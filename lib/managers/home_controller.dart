import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/kitt_persona.dart';
import '../models/aux_slot_config.dart';
import '../models/kitt_state.dart';
import 'android_auto_bridge_service.dart';
import 'audio_engine_manager.dart';
import 'aux_apps_manager.dart';
import 'flag_dossier_service.dart';
import 'flag_mission_service.dart';
import 'gemini_live_client.dart';
import 'kitt_backup_service.dart';
import 'mic_stream_manager.dart';
import 'notification_filter_manager.dart';
import 'phone_call_manager.dart';
import 'vehicle_telemetry_service.dart';

/// Instância compartilhada do [HomeController] para sobreviver ao ciclo de vida
/// entre a UI mobile (`HomePage`) e o modo headless do Android Auto.
class KittAppSession {
  KittAppSession._();

  static HomeController? _sharedController;

  static HomeController get controller =>
      _sharedController ??= HomeController();

  static Future<void> ensureStarted() async {
    await controller.initAndConnect();
  }
}

/// Controlador principal do painel KITT.
///
/// Orquestra:
/// - Sessão Gemini Live API
/// - Captura de microfone PCM 16 kHz
/// - Reprodução PCM 24 kHz + nível do Voicebox
/// - Modos de direção, telemetria RPM/velocidade e execução dos gadgets clássicos
class HomeController extends ChangeNotifier {
  HomeController({
    GeminiLiveClient? liveClient,
    AudioEngineManager? audioEngine,
    MicStreamManager? micManager,
    PhoneCallManager? phoneCallManager,
    AuxAppsManager? auxAppsManager,
    VehicleTelemetryService? telemetryService,
    AndroidAutoBridgeService? androidAutoBridge,
    NotificationFilterManager? notificationFilterManager,
    FlagDossierService? flagDossierService,
    FlagMissionService? flagMissionService,
    KittBackupService? backupService,
    KittPersonaConfig initialPersona = const KittPersonaConfig(),
  })  : _liveClient = liveClient ?? GeminiLiveClient(),
        _audioEngine = audioEngine ?? AudioEngineManager(),
        _micManager = micManager ?? MicStreamManager(),
        _phoneCallManager = phoneCallManager ?? PhoneCallManager(),
        _auxAppsManager = auxAppsManager ?? AuxAppsManager(),
        _telemetryService = telemetryService ?? VehicleTelemetryService(),
        _androidAutoBridge = androidAutoBridge ?? AndroidAutoBridgeService(),
        _notificationFilter =
            notificationFilterManager ?? NotificationFilterManager(),
        _dossierService = flagDossierService ?? FlagDossierService(),
        _missionService = flagMissionService ?? FlagMissionService(),
        _backupService = backupService ??
            KittBackupService(dossierService: flagDossierService),
        _persona = initialPersona {
    _transmissionQueue = FlagTransmissionQueue(
      isBusySpeaking: () => _audioEngine.isSpeaking,
      onDeliver: _deliverFlagTransmission,
    );
    _bindStreams();
    _androidAutoBridge.attach(onCommand: handleAndroidAutoCommand);
  }

  final GeminiLiveClient _liveClient;
  final AudioEngineManager _audioEngine;
  final MicStreamManager _micManager;
  final PhoneCallManager _phoneCallManager;
  final AuxAppsManager _auxAppsManager;
  final VehicleTelemetryService _telemetryService;
  final AndroidAutoBridgeService _androidAutoBridge;
  final NotificationFilterManager _notificationFilter;
  final FlagDossierService _dossierService;
  final FlagMissionService _missionService;
  final KittBackupService _backupService;
  Timer? _missionProximityTimer;
  bool _initialBriefingDoneThisSession = false;
  late final FlagTransmissionQueue _transmissionQueue;
  Timer? _transmissionDelayTimer;
  Timer? _turnDrainTimer;

  List<AuxSlotConfig> _auxSlots = AuxSlotConfig.defaultSlots();
  String _flagDossiersMarkdown = FlagDossierService.initialTemplate;

  KittPersonaConfig _persona;
  DriveMode _driveMode = DriveMode.normalCruise;
  LiveConnectionState _connectionState = LiveConnectionState.disconnected;
  bool _isMicActive = false;
  String? _errorMessage;
  String _lastTranscript = '';
  KittActionEvent? _activeAction;
  Timer? _actionClearTimer;

  // Estado dos gadgets clássicos + telemetria de RPM/velocidade
  GadgetType? _activeGadget;
  int _gadgetRunId = 0;
  Timer? _gadgetTimer;
  Timer? _telemetryTimer;
  double _rpmNormalized = 0.22; // 0.0..1.0 (0..10.000 RPM)
  int _speedMph = 55;

  // Proteção anti-repetição / anti-cacofonia de botões do painel
  String? _activeDashboardButton;
  Timer? _dashboardButtonTimer;
  bool _micToggleBusy = false;
  final Map<String, DateTime> _buttonLockUntil = <String, DateTime>{};

  // Preferência persistida de tela sempre ligada (Wakelock)
  static const String keepScreenOnPrefKey = 'kitt_keep_screen_on';
  bool _keepScreenOn = true;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  KittPersonaConfig get persona => _persona;
  DriveMode get driveMode => _driveMode;
  LiveConnectionState get connectionState => _connectionState;
  bool get isMicActive => _isMicActive;
  String? get errorMessage => _errorMessage;
  String get lastTranscript => _lastTranscript;
  KittActionEvent? get activeAction => _activeAction;
  GadgetType? get activeGadget => _activeGadget;
  int get gadgetRunId => _gadgetRunId;
  bool get keepScreenOn => _keepScreenOn;
  bool get missionsEnabled => _missionService.enabled;
  Set<String> get missionSelectedCalendarIds =>
      _missionService.selectedCalendarIds;
  bool get missionsRequireTag => _missionService.requireTag;
  String get missionsTag => _missionService.tag;
  bool isDashboardButtonActive(String code) =>
      _activeDashboardButton == code.toLowerCase();

  bool _isLocked(String key) {
    final DateTime? until = _buttonLockUntil[key];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _lockButton(String key, Duration duration) {
    _buttonLockUntil[key] = DateTime.now().add(duration);
  }
  double get rpmNormalized => _rpmNormalized;
  int get rpmValue => (_rpmNormalized * 10000).round();
  int get speedMph => _speedMph;
  int get displaySpeedKmh {
    if (_activeGadget == GadgetType.turboBoost) {
      return (_speedMph * 1.609).round();
    }
    if (_telemetryService.hasGpsLock) {
      return _telemetryService.speedKmh.round();
    }
    return (_speedMph * 1.609).round();
  }

  bool get isGpsLive => _telemetryService.hasGpsLock;
  double get currentGForce => _telemetryService.currentGForce;
  bool get telemetryAutoCommentsEnabled =>
      _telemetryService.autoCommentsEnabled;
  Set<String> get allowedNotificationPackages =>
      _notificationFilter.allowedPackages;
  bool get autoReadMessagesEnabled => _notificationFilter.autoReadEnabled;
  String get flagDossiersMarkdown => _flagDossiersMarkdown;
  List<AuxSlotConfig> get auxSlots => List<AuxSlotConfig>.unmodifiable(_auxSlots);
  ValueListenable<double> get voiceLevel => _audioEngine.voiceLevel;
  ValueListenable<double> get micLevel => _micManager.micLevel;

  void _bindStreams() {
    _subs.add(
      _liveClient.connectionState.listen((LiveConnectionState state) {
        _connectionState = state;
        if (state == LiveConnectionState.ready) {
          _errorMessage = null;
          _liveClient.sendSilentContext(
            '[SINCRONIZAÇÃO TEMPORAL]: ${FlagMissionService.buildCurrentDateTimeContext()}',
          );
          if (!_initialBriefingDoneThisSession) {
            _initialBriefingDoneThisSession = true;
            _runInitialMissionBriefing();
          }
        }
        notifyListeners();
      }),
    );

    _subs.add(
      _liveClient.audioChunks.listen((Uint8List chunk) {
        _audioEngine.enqueuePcmChunk(chunk);
      }),
    );

    _subs.add(
      _liveClient.transcripts.listen((String text) {
        _lastTranscript = text;
        notifyListeners();
      }),
    );

    _subs.add(
      _liveClient.errors.listen((String err) {
        _errorMessage = err;
        notifyListeners();
      }),
    );

    _subs.add(
      _liveClient.toolCalls.listen(_handleToolCall),
    );

    _subs.add(
      _liveClient.turnCompleted.listen((_) {
        _turnDrainTimer?.cancel();
        // Aguarda um breve respiro após turnComplete para finalizar o buffer PCM.
        _turnDrainTimer = Timer(const Duration(milliseconds: 650), () {
          _transmissionQueue.notifySpeechCompleted();
        });
      }),
    );

    _subs.add(
      _telemetryService.telemetryUpdates.listen((_) => notifyListeners()),
    );

    _subs.add(
      _telemetryService.maneuverReactions.listen(_handleHarshManeuver),
    );

    _subs.add(
      _notificationFilter.incomingNotifications
          .listen(_handleIncomingNotification),
    );
  }

  void _handleIncomingNotification(IncomingNotificationEvent event) {
    _transmissionQueue.enqueue(event);
  }

  void _deliverFlagTransmission(IncomingNotificationEvent event) {
    _audioEngine.playCommsBeepSfx();
    _setTransientAction(
      code: 'comms_flag_${event.packageName}',
      title: IncomingNotificationEvent.hudBannerTitle,
      detail: '${event.appName.toUpperCase()} • ${event.title}',
    );

    if (_connectionState != LiveConnectionState.ready) {
      _transmissionQueue.notifySpeechCompleted();
      return;
    }

    _transmissionDelayTimer?.cancel();
    _transmissionDelayTimer = Timer(const Duration(milliseconds: 280), () {
      if (_connectionState == LiveConnectionState.ready) {
        _liveClient.sendTextMessage(event.toGeminiPrompt());
      } else {
        _transmissionQueue.notifySpeechCompleted();
      }
    });
  }

  Future<bool> isNotificationAccessGranted() =>
      _notificationFilter.isPermissionGranted();

  Future<bool> openNotificationAccessSettings() =>
      _notificationFilter.openPermissionSettings();

  Future<void> setAutoReadMessagesEnabled(bool enabled) async {
    await _notificationFilter.setAutoReadEnabled(enabled);
    notifyListeners();
  }

  Future<void> setNotificationPackageAllowed(
    String packageName,
    bool allowed,
  ) async {
    await _notificationFilter.setPackageAllowed(packageName, allowed);
    notifyListeners();
  }

  void _handleHarshManeuver(ManeuverEvent event) {
    HapticFeedback.heavyImpact();
    _setTransientAction(
      code: 'g_force_alert',
      title: 'FORÇA G • ${event.gForce.toStringAsFixed(2)}G',
      detail:
          '${event.kind.toUpperCase()} (${event.peakMs2.toStringAsFixed(1)} m/s²)',
    );
    if (_connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(event.toGeminiSystemEvent());
    }
  }

  Future<void> toggleTelemetrySensors() async {
    final bool next = !_telemetryService.autoCommentsEnabled;
    _telemetryService.setAutoCommentsEnabled(next);
    if (next && !_telemetryService.isRunning) {
      await _telemetryService.start();
    }
    HapticFeedback.selectionClick();
    _setTransientAction(
      code: 'telemetry_toggle',
      title: next ? 'TELEMETRIA / SENSORES: ATIVO' : 'TELEMETRIA / SENSORES: MUDO',
      detail: next
          ? 'Monitoramento de força G e reações espontâneas do KITT ativados.'
          : 'Comentários automáticos de manobras bruscas silenciados.',
    );
    notifyListeners();
  }

  bool _initialized = false;

  Future<void> initAndConnect() async {
    if (_initialized) {
      // Já inicializado (ex.: motor headless do Android Auto) — ressincroniza
      // apenas o Android Auto sem disparar notifyListeners() durante initState/build.
      _syncAndroidAutoState();
      return;
    }
    _initialized = true;
    _auxSlots = await _auxAppsManager.loadSlots();
    _flagDossiersMarkdown = await _dossierService.readRawMarkdown();
    await _loadKeepScreenOnPref();
    await _missionService.init();
    _startMissionProximityMonitor();
    await _notificationFilter.init();
    notifyListeners();
    await _audioEngine.init();
    await _telemetryService.start();
    await connect();
  }

  void _startMissionProximityMonitor() {
    _missionProximityTimer?.cancel();
    _missionProximityTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkUpcomingMissions(),
    );
  }

  Future<void> _runInitialMissionBriefing() async {
    if (!_missionService.enabled ||
        _connectionState != LiveConnectionState.ready) {
      return;
    }
    final List<FlagMissionItem> pending =
        await _missionService.getMissionsForBriefing();
    if (pending.isEmpty) return;

    await _missionService.markBriefed(pending);
    _setTransientAction(
      code: 'flag_missions_briefing',
      title: 'DIRETRIZES F.L.A.G. • ${pending.length} MISSÃO(ÕES)',
      detail: pending.map((FlagMissionItem m) => '${m.formattedTime} ${m.cleanTitle}').join(' | '),
    );
    _liveClient.sendTextMessage(
      FlagMissionService.buildInitialBriefingPrompt(pending),
    );
  }

  Future<void> _checkUpcomingMissions() async {
    if (!_missionService.enabled) return;
    final DateTime now = DateTime.now();
    final List<FlagMissionItem> due =
        await _missionService.getDueUpcomingMissions(now: now);
    if (due.isEmpty) return;

    for (final FlagMissionItem mission in due) {
      await _missionService.markUpcoming(mission);
      final int mins = mission.startTime.difference(now).inMinutes;
      HapticFeedback.heavyImpact();
      _audioEngine.playCommsBeepSfx();
      _setTransientAction(
        code: 'flag_mission_upcoming_${mission.eventId}',
        title: 'ALERTA F.L.A.G. • EM ${mins.clamp(0, 15)} MIN',
        detail: '${mission.formattedTime} • ${mission.cleanTitle}',
      );
      if (_connectionState == LiveConnectionState.ready) {
        _liveClient.sendTextMessage(
          FlagMissionService.buildUpcomingAlertPrompt(mission, mins),
        );
      }
    }
  }

  /// Força o briefing imediato ignorando a trava `_briefed` uma única vez (botão de teste).
  Future<int> forceMissionBriefingNow() async {
    final List<FlagMissionItem> missions =
        await _missionService.getMissionsForBriefing(ignoreBriefedLock: true);
    if (missions.isEmpty) {
      _setTransientAction(
        code: 'flag_missions_empty',
        title: 'DIRETRIZES F.L.A.G.',
        detail: 'Nenhuma missão encontrada nas agendas selecionadas para as próximas 24h.',
      );
      return 0;
    }

    HapticFeedback.mediumImpact();
    _audioEngine.playCommsBeepSfx();
    _setTransientAction(
      code: 'flag_missions_forced',
      title: 'BRIEFING F.L.A.G. • ${missions.length} MISSÃO(ÕES)',
      detail: missions.map((FlagMissionItem m) => '${m.formattedTime} ${m.cleanTitle}').join(' | '),
    );

    if (_connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        FlagMissionService.buildInitialBriefingPrompt(missions),
      );
    }
    return missions.length;
  }

  Future<bool> hasCalendarPermission() =>
      _missionService.hasCalendarPermission();

  Future<bool> requestCalendarPermission() =>
      _missionService.requestCalendarPermission();

  Future<List<CalendarAccountInfo>> listDeviceCalendars() =>
      _missionService.listDeviceCalendars();

  Future<void> setMissionsEnabled(bool enabled) async {
    await _missionService.setEnabled(enabled);
    notifyListeners();
  }

  Future<void> setMissionCalendarSelected(
    String calendarId,
    bool selected,
  ) async {
    await _missionService.setCalendarSelected(calendarId, selected);
    notifyListeners();
  }

  Future<void> setMissionsRequireTag(bool requireTag) async {
    await _missionService.setRequireTag(requireTag);
    notifyListeners();
  }

  Future<void> setMissionsTag(String tag) async {
    await _missionService.setTag(tag);
    notifyListeners();
  }

  Future<void> _loadKeepScreenOnPref() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _keepScreenOn = prefs.getBool(keepScreenOnPrefKey) ?? true;
    } catch (_) {
      _keepScreenOn = true;
    }
    await _applyWakelock(_keepScreenOn);
  }

  Future<void> setKeepScreenOn(bool enabled) async {
    if (_keepScreenOn == enabled) return;
    _keepScreenOn = enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keepScreenOnPrefKey, enabled);
    } catch (_) {}
    await _applyWakelock(enabled);
    HapticFeedback.selectionClick();
    _setTransientAction(
      code: 'keep_screen_on',
      title: enabled ? 'MONITOR SEMPRE LIGADO: ATIVO' : 'MONITOR SEMPRE LIGADO: OFF',
      detail: enabled
          ? 'A tela permanecerá acesa enquanto o K.i.t.Turbo estiver aberto.'
          : 'O sistema voltará a respeitar o tempo limite de tela do Android.',
    );
    notifyListeners();
  }

  Future<void> _applyWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } catch (_) {
      // Ignora em testes unitários sem canal nativo.
    }
  }

  Future<void> connect() async {
    _errorMessage = null;
    _flagDossiersMarkdown = await _dossierService.readRawMarkdown();
    notifyListeners();
    await _liveClient.connect(
      apiKey: KittConfig.geminiApiKey,
      model: KittConfig.geminiLiveModel,
      persona: _persona,
      currentMode: _driveMode,
      auxSlots: _auxSlots,
      flagDossiersMarkdown: _flagDossiersMarkdown,
    );
  }

  Future<String> saveFlagDossiersRaw(String rawMarkdown) async {
    _flagDossiersMarkdown = await _dossierService.saveRawMarkdown(rawMarkdown);
    _syncDossiersToLiveSession();
    notifyListeners();
    return _flagDossiersMarkdown;
  }

  Future<String> upsertFlagDossierEntry({
    required String targetName,
    required String details,
    String? previousTargetName,
    bool appendIfExists = false,
  }) async {
    _flagDossiersMarkdown = await _dossierService.upsertEntry(
      targetName: targetName,
      details: details,
      previousTargetName: previousTargetName,
      appendIfExists: appendIfExists,
    );
    _syncDossiersToLiveSession();
    notifyListeners();
    return _flagDossiersMarkdown;
  }

  Future<String> deleteFlagDossierEntry(String targetName) async {
    _flagDossiersMarkdown = await _dossierService.deleteEntry(targetName);
    _syncDossiersToLiveSession();
    notifyListeners();
    return _flagDossiersMarkdown;
  }

  Future<String> importFlagDossiers(
    String rawMarkdown, {
    bool merge = true,
  }) async {
    _flagDossiersMarkdown =
        await _dossierService.importMarkdown(rawMarkdown, merge: merge);
    _syncDossiersToLiveSession();
    notifyListeners();
    return _flagDossiersMarkdown;
  }

  /// Exporta backup completo (`flag_dossiers.md` + `SharedPreferences`) em `.json`
  /// e abre o menu nativo de compartilhamento (`share_plus`).
  Future<String> exportFullBackup() async {
    final String fileName = await _backupService.exportAndShareBackup();
    HapticFeedback.mediumImpact();
    _setTransientAction(
      code: 'backup_exported',
      title: 'BACKUP EXPORTED // F.L.A.G. ARCHIVE',
      detail: 'Arquivo $fileName pronto para compartilhamento.',
    );
    return fileName;
  }

  /// Seleciona um arquivo `.json` (backup completo) ou `.md` (somente dossiês)
  /// via `file_picker`, restaura os dados e sincroniza a sessão Gemini Live.
  Future<KittBackupRestoreResult?> restoreBackupFromFile() async {
    final KittBackupRestoreResult? result =
        await _backupService.pickAndRestoreBackup();
    if (result == null) return null;

    _flagDossiersMarkdown = result.restoredMarkdown;
    if (result.isFullJsonBackup) {
      _auxSlots = await _auxAppsManager.loadSlots();
      await _loadKeepScreenOnPref();
      await _missionService.init();
      await _notificationFilter.init();
    }

    HapticFeedback.heavyImpact();
    _audioEngine.playCommsBeepSfx();
    _setTransientAction(
      code: 'backup_restored',
      title: KittBackupRestoreResult.hudConfirmation,
      detail: result.isFullJsonBackup
          ? '${result.fileName} restaurado (${result.restoredPrefsCount} preferências + Dossiês F.L.A.G.).'
          : '${result.fileName} restaurado nos Dossiês F.L.A.G.',
    );

    if (_connectionState == LiveConnectionState.ready) {
      _syncDossiersToLiveSession();
      _liveClient.sendTextMessage(
        '[SISTEMA: ${KittBackupRestoreResult.hudConfirmation} — '
        'Backup "${result.fileName}" restaurado com sucesso]. '
        'Confirme brevemente no personagem do KITT que o banco de dados F.L.A.G. '
        'e as configurações do painel foram sincronizados.',
      );
    }

    notifyListeners();
    return result;
  }

  void _syncDossiersToLiveSession() {
    if (_connectionState != LiveConnectionState.ready) return;
    final String cleaned =
        FlagDossierService.stripHtmlComments(_flagDossiersMarkdown);
    _liveClient.sendSilentContext(
      '[ATUALIZAÇÃO DO BANCO DE DADOS DE INTELIGÊNCIA DA F.L.A.G.]:\n$cleaned\n'
      'Memorize e passe a considerar estes registros imediatamente como fatos reais '
      'do banco de dados interno da F.L.A.G., sem mencionar arquivos .md ou prompts.',
    );
  }

  Future<void> disconnect() async {
    await stopMic();
    await _liveClient.disconnect();
  }

  /// Controla a reconexão automática conforme o app está em primeiro plano
  /// (economiza bateria/conexões quando minimizado e reconecta ao voltar).
  Future<void> setAppForeground(bool inForeground) async {
    _liveClient.setAutoReconnectEnabled(inForeground);
    if (inForeground &&
        _initialized &&
        _connectionState == LiveConnectionState.disconnected) {
      await connect();
    }
  }

  Future<void> toggleMic() async {
    if (_micToggleBusy || _isLocked('mic_toggle')) return;
    _micToggleBusy = true;
    _lockButton('mic_toggle', const Duration(milliseconds: 450));
    try {
      if (_isMicActive) {
        await stopMic();
        return;
      }

      if (_connectionState != LiveConnectionState.ready) {
        await connect();
        if (_connectionState == LiveConnectionState.error) return;
      }

      await _audioEngine.acquireListeningFocus();
      final bool started = await _micManager.startStreaming(
        _liveClient.sendPcmAudioChunk,
      );
      if (!started) {
        _audioEngine.releaseListeningFocus();
        _errorMessage = 'Permissão de microfone negada.';
        notifyListeners();
        return;
      }
      _isMicActive = true;
      _errorMessage = null;
      notifyListeners();
    } finally {
      _micToggleBusy = false;
    }
  }

  Future<void> stopMic() async {
    await _micManager.stopStreaming();
    _audioEngine.releaseListeningFocus();
    if (_isMicActive) {
      _isMicActive = false;
      notifyListeners();
    }
  }

  void setOperationMode(DriveMode mode, {bool announceToGemini = false}) {
    // Evita reacionamento consecutivo do modo já ativo (previne cacofonia/estado inconsistente)
    if (_driveMode == mode) return;

    _driveMode = mode;
    _applyBaselineTelemetry();
    _audioEngine.playSfxAsset('audio/${mode.apiValue}.mp3');

    if (mode == DriveMode.pursuit) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    _setTransientAction(
      code: mode.apiValue,
      title: mode.label,
      detail: switch (mode) {
        DriveMode.pursuit => 'PURSUIT ENGAGED • Alerta tático máximo.',
        DriveMode.surveillance => 'SURVEILLANCE • Radar de perímetro ativo.',
        DriveMode.autoCruise => 'AUTO CRUISE • Piloto automático engajado.',
        DriveMode.normalCruise => 'NORMAL CRUISE • Sistemas em cruzeiro padrão.',
      },
    );

    if (_connectionState == LiveConnectionState.ready) {
      // Injeta contexto silencioso para moldar o tom do KITT no modo atual
      _liveClient.sendSilentContext(_buildModeContextInstruction(mode));

      if (announceToGemini) {
        _liveClient.sendTextMessage(
          'O motorista ativou o modo ${mode.label} no painel. Confirme brevemente no personagem do KITT.',
        );
      }
    }
    notifyListeners();
  }

  /// Alias mantido para compatibilidade com chamadas existentes.
  void setDriveMode(DriveMode mode, {bool announceToGemini = false}) {
    setOperationMode(mode, announceToGemini: announceToGemini);
  }

  String _buildModeContextInstruction(DriveMode mode) {
    return switch (mode) {
      DriveMode.pursuit =>
        '[CONTEXTO DO SISTEMA — MODO PURSUIT ATIVO]: Adote um tom de voz urgente, tático, focado e extremamente conciso (máximo 1 a 2 frases curtas), priorizando velocidade, manobras evasivas e alertas imediatos.',
      DriveMode.surveillance =>
        '[CONTEXTO DO SISTEMA — MODO SURVEILLANCE ATIVO]: Comporte-se como se estivesse escaneando continuamente o perímetro com radar e sensores infravermelhos, reportando assinaturas térmicas, movimentos e análise tática de ameaças ao redor do veículo.',
      DriveMode.autoCruise =>
        '[CONTEXTO DO SISTEMA — MODO AUTO CRUISE ATIVO]: Você assumiu o controle autônomo da direção; responda de forma confiante, precisa e levemente orgulhosa das suas capacidades.',
      DriveMode.normalCruise =>
        '[CONTEXTO DO SISTEMA — MODO NORMAL CRUISE ATIVO]: Retorne ao seu tom clássico de KITT: calmo, elegante, prestativo e com ironia sutil.',
    };
  }

  /// Aciona um gadget clássico do KITT (overlay 3-4s, SFX opcional, háptico e telemetria).
  Map<String, dynamic> activateGadget(
    GadgetType gadget, {
    bool announceToGemini = true,
  }) {
    // Ignora toques sucessivos no mesmo gadget enquanto ele já está em execução
    if (_activeGadget == gadget) {
      return <String, dynamic>{
        'status': 'already_active',
        'gadget': gadget.toolName,
      };
    }

    _gadgetTimer?.cancel();
    _telemetryTimer?.cancel();

    _activeGadget = gadget;
    _gadgetRunId++;

    // Efeito sonoro opcional (Micro Jam possui fallback sintetizado de interferência)
    if (gadget == GadgetType.microJam) {
      _audioEngine.playMicroJamInterferenceSfx();
    } else {
      _audioEngine.playSfxAsset(gadget.sfxAsset);
    }

    // Feedback háptico e telemetria específicos do gadget
    if (gadget == GadgetType.turboBoost) {
      _runTurboBoostTelemetryAndHaptics();
    } else if (gadget == GadgetType.microJam || gadget == GadgetType.skiMode) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }

    final Map<String, dynamic> telemetry = switch (gadget) {
      GadgetType.oilSlick => <String, dynamic>{
          'status': 'deployed',
          'gadget': 'oil_slick',
          'surface_friction_drop_pct': 92,
          'reservoir_remaining_pct': 74,
          'duration_ms': gadget.duration.inMilliseconds,
        },
      GadgetType.smokeScreen => <String, dynamic>{
          'status': 'active',
          'gadget': 'smoke_screen',
          'rear_visibility_pct': 0,
          'particulate_density': 'maximum',
          'duration_ms': gadget.duration.inMilliseconds,
        },
      GadgetType.turboBoost => <String, dynamic>{
          'status': 'engaged',
          'gadget': 'turbo_boost',
          'peak_rpm': 9800,
          'peak_speed_mph': 285,
          'thruster_temp_c': 640,
          'duration_ms': gadget.duration.inMilliseconds,
        },
      GadgetType.microJam => <String, dynamic>{
          'status': 'jamming',
          'gadget': 'micro_jam',
          'emp_radius_m': 45,
          'blocked_systems': <String>['cameras', 'ignition_ecus', 'radio_links'],
          'frequency_band_mhz': '2.4-5800',
          'duration_ms': gadget.duration.inMilliseconds,
        },
      GadgetType.skiMode => <String, dynamic>{
          'status': 'engaged',
          'gadget': 'ski_mode',
          'tilt_angle_deg': 45,
          'active_wheels': 'right_side_pair',
          'gyro_balance_pct': 99.4,
          'duration_ms': gadget.duration.inMilliseconds,
        },
      GadgetType.scanner => <String, dynamic>{
          'status': 'scan_complete',
          'gadget': 'structural_scanner',
          'structural_integrity_pct': 94,
          'thermal_signatures': 2,
          'material_density': 'reinforced_concrete_steel',
          'perimeter_threat_level': 'low',
          'duration_ms': gadget.duration.inMilliseconds,
        },
    };

    _setTransientAction(
      code: gadget.toolName,
      title: gadget.label,
      detail: gadget.hudAlert,
    );

    if (announceToGemini && _connectionState == LiveConnectionState.ready) {
      final String prompt = switch (gadget) {
        GadgetType.microJam =>
          'O motorista acionou o MICRO JAM no painel (telemetria: $telemetry). '
              'Confirme brevemente no personagem do KITT que os sistemas eletrônicos próximos foram bloqueados pela interferência eletromagnética.',
        GadgetType.skiMode =>
          'O motorista ativou o SKI MODE no painel (telemetria: $telemetry). '
              'Alerte brevemente no personagem do KITT sobre a manobra em duas rodas inclinada a 45 graus.',
        GadgetType.scanner =>
          'O motorista acionou o SCANNER estrutural no painel (telemetria: $telemetry). '
              'Relate brevemente em voz alta no personagem do KITT o resultado da varredura estrutural e tática.',
        _ =>
          'O motorista acionou manualmente o gadget ${gadget.label} no painel '
              '(telemetria: $telemetry). Reaja brevemente como KITT com sarcasmo ou precisão técnica.',
      };
      _liveClient.sendTextMessage(prompt);
    }

    _gadgetTimer = Timer(gadget.duration, () {
      _activeGadget = null;
      _telemetryTimer?.cancel();
      _applyBaselineTelemetry();
      notifyListeners();
    });

    notifyListeners();
    return telemetry;
  }

  void _runTurboBoostTelemetryAndHaptics() {
    HapticFeedback.heavyImpact();
    int tick = 0;
    const int totalTicks = 28; // ~3.5s a cada 125ms

    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 125),
      (Timer timer) {
        tick++;
        if (tick <= 8) {
          // Subida explosiva de RPM e velocidade
          final double t = tick / 8.0;
          _rpmNormalized = (0.35 + (0.63 * t)).clamp(0.0, 0.99);
          _speedMph = (85 + (200 * t)).round();
          if (tick == 2 || tick == 5 || tick == 8) {
            HapticFeedback.heavyImpact();
          }
        } else if (tick <= 20) {
          // Pico sustentado com leve oscilação de turbina
          _rpmNormalized = tick.isEven ? 0.98 : 0.93;
          _speedMph = tick.isEven ? 285 : 278;
          if (tick == 12 || tick == 16) {
            HapticFeedback.heavyImpact();
          }
        } else if (tick <= totalTicks) {
          // Desaceleração controlada
          final double t = (tick - 20) / (totalTicks - 20);
          final double baseRpm = _baselineRpmFor(_driveMode);
          final int baseSpeed = _baselineSpeedFor(_driveMode);
          _rpmNormalized = 0.95 - ((0.95 - baseRpm) * t);
          _speedMph = (280 - ((280 - baseSpeed) * t)).round();
        } else {
          timer.cancel();
          _applyBaselineTelemetry();
        }
        notifyListeners();
      },
    );
  }

  double _baselineRpmFor(DriveMode mode) => switch (mode) {
        DriveMode.normalCruise => 0.22,
        DriveMode.autoCruise => 0.34,
        DriveMode.surveillance => 0.16,
        DriveMode.pursuit => 0.68,
      };

  int _baselineSpeedFor(DriveMode mode) => switch (mode) {
        DriveMode.normalCruise => 55,
        DriveMode.autoCruise => 85,
        DriveMode.surveillance => 15,
        DriveMode.pursuit => 165,
      };

  void _applyBaselineTelemetry() {
    _rpmNormalized = _baselineRpmFor(_driveMode);
    _speedMph = _baselineSpeedFor(_driveMode);
  }

  void triggerDashboardButton(String code) {
    final String lower = code.toLowerCase();
    if (lower == 'oil') {
      activateGadget(GadgetType.oilSlick);
      return;
    }
    // Bloqueia toques repetidos no mesmo botão auxiliar enquanto ativo/em cooldown
    if (_activeDashboardButton == lower || _isLocked('dash_$lower')) {
      return;
    }
    _activeDashboardButton = lower;
    _lockButton('dash_$lower', const Duration(seconds: 4));
    _dashboardButtonTimer?.cancel();
    _dashboardButtonTimer = Timer(const Duration(seconds: 4), () {
      if (_activeDashboardButton == lower) {
        _activeDashboardButton = null;
        notifyListeners();
      }
    });

    _audioEngine.playSfxAsset('audio/$lower.mp3');
    _setTransientAction(
      code: lower,
      title: 'SYSTEM ${code.toUpperCase()}',
      detail: 'Subsistema ${code.toUpperCase()} acionado pelo painel.',
    );
    if (_connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        'O motorista acionou o botão auxiliar ${code.toUpperCase()} no painel. Responda brevemente como KITT.',
      );
    }
    notifyListeners();
  }

  void sendQuickTextPrompt(String prompt) {
    if (_connectionState != LiveConnectionState.ready) {
      _errorMessage = 'Conecte ao Gemini Live antes de enviar comandos.';
      notifyListeners();
      return;
    }
    _liveClient.sendTextMessage(prompt);
  }

  Future<void> updatePersona(KittPersonaConfig updated) async {
    _persona = updated;
    notifyListeners();
    if (_connectionState == LiveConnectionState.ready ||
        _connectionState == LiveConnectionState.connecting) {
      await connect();
    }
  }

  Future<List<InstalledAppEntry>> listInstalledApps({
    bool includeSystemApps = false,
  }) {
    return _auxAppsManager.listInstalledApps(
      includeSystemApps: includeSystemApps,
    );
  }

  Future<void> saveAuxSlot(AuxSlotConfig updated) async {
    final List<AuxSlotConfig> next = List<AuxSlotConfig>.from(_auxSlots);
    final int idx = updated.slotNumber - 1;
    if (idx < 0 || idx >= next.length) return;
    next[idx] = updated;
    _auxSlots = next;
    await _auxAppsManager.saveSlots(_auxSlots);
    _setTransientAction(
      code: 'aux_config_${updated.slotNumber}',
      title: 'SLOT AUX ${updated.slotNumber} ATUALIZADO',
      detail: updated.isConfigured
          ? '${updated.displayLabel} vinculado a ${updated.appName.isNotEmpty ? updated.appName : updated.packageName}.'
          : 'Slot AUX ${updated.slotNumber} limpo.',
    );
    notifyListeners();
  }

  Future<Map<String, dynamic>> launchAuxApp({
    int? slotNumber,
    String? query,
    bool announceToGemini = true,
  }) async {
    final AuxSlotConfig? slot = AuxAppsManager.resolveSlot(
      _auxSlots,
      slotNumber: slotNumber,
      query: query,
    );

    if (slot == null || !slot.isConfigured) {
      final String msg = slotNumber != null
          ? 'O botão auxiliar $slotNumber ainda não tem nenhum aplicativo vinculado.'
          : 'Nenhum botão auxiliar encontrado para "${query ?? ''}".';
      _setTransientAction(
        code: 'aux_empty',
        title: 'AUXILIAR NÃO CONFIGURADO',
        detail: msg,
      );
      return <String, dynamic>{
        'status': 'not_configured',
        'message': msg,
      };
    }

    final String auxLockKey = 'aux_${slot.slotNumber}';
    if (_isLocked(auxLockKey)) {
      return <String, dynamic>{
        'status': 'already_launching',
        'slot_number': slot.slotNumber,
      };
    }
    _lockButton(auxLockKey, const Duration(seconds: 3));

    HapticFeedback.mediumImpact();
    _audioEngine.playSfxAsset('audio/aux_launch.mp3');

    final bool launched =
        await _auxAppsManager.launchPackage(slot.packageName);
    final String appLabel =
        slot.appName.isNotEmpty ? slot.appName : slot.packageName;
    final String detail = launched
        ? 'Abrindo ${slot.displayLabel} ($appLabel)...'
        : 'Falha ao abrir ${slot.displayLabel} ($appLabel).';

    _setTransientAction(
      code: 'aux_launch_${slot.slotNumber}',
      title: 'AUX ${slot.slotNumber} • ${slot.displayLabel}',
      detail: detail,
    );

    if (announceToGemini && _connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        'O motorista acionou o botão auxiliar ${slot.slotNumber} (${slot.displayLabel} - $appLabel). '
        'Confirme brevemente no personagem do KITT.',
      );
    }

    return <String, dynamic>{
      'status': launched ? 'launched' : 'error',
      'slot_number': slot.slotNumber,
      'label': slot.displayLabel,
      'app_name': appLabel,
      'package_name': slot.packageName,
      'message': detail,
    };
  }

  Future<PhoneCallResult> makePhoneCall({
    String? phoneNumber,
    String? contactName,
    bool directCall = false,
    bool announceToGemini = true,
  }) async {
    final PhoneCallResult res = await _phoneCallManager.placeCall(
      phoneNumber: phoneNumber,
      contactName: contactName,
      directCall: directCall,
    );

    _setTransientAction(
      code: 'make_phone_call',
      title: directCall ? 'COMMLINK • CHAMADA DIRETA' : 'COMMLINK • DISCADOR',
      detail: res.message,
    );

    if (!res.success) {
      _errorMessage = res.message;
      notifyListeners();
    }

    if (announceToGemini && _connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        'O motorista acionou o Commlink telefônico (${res.message}). '
        'Confirme brevemente no personagem do KITT.',
      );
    }

    return res;
  }

  Future<void> _handleToolCall(GeminiToolCall call) async {
    Map<String, dynamic> result;

    switch (call.name) {
      case 'set_operation_mode':
      case 'set_drive_mode':
        final DriveMode mode =
            DriveMode.fromApiValue(call.args['mode'] as String?);
        setOperationMode(mode);
        result = <String, dynamic>{
          'status': 'ok',
          'active_mode': mode.label,
          'mode_code': mode.apiValue,
        };
        break;

      case 'deploy_oil_slick':
        result = activateGadget(
          GadgetType.oilSlick,
          announceToGemini: false,
        );
        break;

      case 'activate_smoke_screen':
        result = activateGadget(
          GadgetType.smokeScreen,
          announceToGemini: false,
        );
        break;

      case 'trigger_turbo_boost':
      case 'activate_turbo_boost':
        result = activateGadget(
          GadgetType.turboBoost,
          announceToGemini: false,
        );
        break;

      case 'trigger_micro_jam':
        result = activateGadget(
          GadgetType.microJam,
          announceToGemini: false,
        );
        break;

      case 'activate_ski_mode':
        result = activateGadget(
          GadgetType.skiMode,
          announceToGemini: false,
        );
        break;

      case 'run_structural_scan':
        result = activateGadget(
          GadgetType.scanner,
          announceToGemini: false,
        );
        break;

      case 'schedule_flag_mission':
        final String title = (call.args['title'] as String? ?? '').trim();
        final String startIso =
            (call.args['start_iso'] as String? ?? '').trim();
        final DateTime? parsedStart = DateTime.tryParse(startIso);
        if (title.isEmpty || parsedStart == null) {
          result = <String, dynamic>{
            'status': 'error',
            'message':
                'Parâmetros inválidos: informe título e data/hora em ISO-8601 (ex.: 2026-11-28T15:00:00).',
          };
          break;
        }
        final int durationMin =
            (call.args['duration_minutes'] as num?)?.toInt() ?? 60;
        final MissionCreateResult created =
            await _missionService.createMissionEvent(
          title: title,
          startTime: parsedStart,
          durationMinutes: durationMin,
          description: call.args['description'] as String?,
          recurrenceType: call.args['recurrence'] as String?,
        );
        if (created.success) {
          HapticFeedback.mediumImpact();
          _audioEngine.playTransmissionSentBeepSfx();
          final DateTime localStart = parsedStart.toLocal();
          final String hh = localStart.hour.toString().padLeft(2, '0');
          final String mm = localStart.minute.toString().padLeft(2, '0');
          _setTransientAction(
            code: 'mission_logged_${created.eventId}',
            title: MissionCreateResult.hudConfirmation,
            detail: '$hh:$mm • ${created.cleanTitle}',
          );
        }
        result = created.toToolResponse();
        break;

      case 'launch_aux_app':
        final num? rawSlot = call.args['slotNumber'] as num?;
        result = await launchAuxApp(
          slotNumber: rawSlot?.toInt(),
          query: call.args['labelOrApp'] as String?,
          announceToGemini: false,
        );
        break;

      case 'make_phone_call':
        final PhoneCallResult callRes = await makePhoneCall(
          phoneNumber: call.args['phoneNumber'] as String?,
          contactName: call.args['contactName'] as String?,
          directCall: call.args['directCall'] == true,
          announceToGemini: false,
        );
        result = callRes.toToolResponse();
        break;

      case 'scan_environment':
        final String target = call.args['target'] as String? ?? 'area';
        _setTransientAction(
          code: 'scan_$target',
          title: 'SCANNER: ${target.toUpperCase()}',
          detail: 'Varredura de sensores executada em "$target".',
        );
        result = <String, dynamic>{
          'status': 'ok',
          'target': target,
          'anomalies_detected': 0,
        };
        break;

      case 'add_flag_dossier_entry':
        final String targetName =
            (call.args['targetName'] as String? ?? '').trim();
        final String intelDetails =
            (call.args['intelDetails'] as String? ?? '').trim();
        if (targetName.isEmpty || intelDetails.isEmpty) {
          result = <String, dynamic>{
            'status': 'error',
            'message': 'Nome do alvo e detalhes táticos são obrigatórios.',
          };
        } else {
          await upsertFlagDossierEntry(
            targetName: targetName,
            details: intelDetails,
            appendIfExists: true,
          );
          HapticFeedback.selectionClick();
          _audioEngine.playCommsBeepSfx();
          _setTransientAction(
            code: 'flag_dossier_recorded',
            title: 'BANCO DE DADOS F.L.A.G. ATUALIZADO',
            detail: 'Alvo: $targetName — $intelDetails',
          );
          result = <String, dynamic>{
            'status': 'recorded',
            'target_name': targetName,
            'intel_details': intelDetails,
            'message':
                'Registro de inteligência para $targetName arquivado no banco de dados da F.L.A.G.',
          };
        }
        break;

      case 'send_flag_transmission_reply':
        final String recipientName =
            (call.args['recipientName'] as String? ?? '').trim();
        final String replyMessage =
            (call.args['replyMessage'] as String? ?? '').trim();
        final Map<String, dynamic> replyRes =
            await _notificationFilter.replyToLastNotification(replyMessage);
        final bool sent = replyRes['success'] == true;
        final String resolvedRecipient = recipientName.isNotEmpty
            ? recipientName
            : (replyRes['sender'] as String? ?? 'destinatário');

        if (sent) {
          HapticFeedback.mediumImpact();
          _audioEngine.playTransmissionSentBeepSfx();
          _setTransientAction(
            code: 'flag_transmission_sent',
            title: 'TRANSMISSION SENT // CHANNEL ENCRYPTED',
            detail: '$resolvedRecipient • "$replyMessage"',
          );
          result = <String, dynamic>{
            'status': 'sent',
            'recipient': resolvedRecipient,
            'reply_message': replyMessage,
            'channel': replyRes['appName'] ?? 'F.L.A.G.',
            'hud_alert': 'TRANSMISSION SENT // CHANNEL ENCRYPTED',
          };
        } else {
          _setTransientAction(
            code: 'flag_transmission_failed',
            title: 'TRANSMISSION FAILED // F.L.A.G. CHANNEL',
            detail: replyRes['message'] as String? ??
                'Não foi possível transmitir a resposta.',
          );
          result = <String, dynamic>{
            'status': 'error',
            'error': replyRes['error'] ?? 'reply_failed',
            'message': replyRes['message'] ??
                'Não foi possível transmitir a resposta pelo canal seguro.',
          };
        }
        break;

      case 'call_contact':
        final String contact = call.args['contact'] as String? ?? 'devon';
        _setTransientAction(
          code: 'call_$contact',
          title: 'COMMLINK: ${contact.toUpperCase()}',
          detail: 'Canal de comunicação aberto com ${contact.toUpperCase()}.',
        );
        result = <String, dynamic>{
          'status': 'ok',
          'commlink_connected_to': contact,
        };
        break;

      case 'trigger_system_effect':
        final String effect = call.args['effect'] as String? ?? 'p1';
        if (effect == 'oil') {
          result = activateGadget(
            GadgetType.oilSlick,
            announceToGemini: false,
          );
        } else {
          _audioEngine.playSfxAsset('audio/$effect.mp3');
          _setTransientAction(
            code: effect,
            title: 'SYSTEM ${effect.toUpperCase()}',
            detail: 'Efeito auxiliar ${effect.toUpperCase()} ativado.',
          );
          result = <String, dynamic>{
            'status': 'ok',
            'effect': effect,
          };
        }
        break;

      default:
        result = <String, dynamic>{
          'status': 'unsupported_tool',
          'name': call.name,
        };
    }

    _liveClient.sendToolResponse(
      callId: call.id,
      name: call.name,
      response: result,
    );
  }

  void _setTransientAction({
    required String code,
    required String title,
    required String detail,
  }) {
    _actionClearTimer?.cancel();
    _activeAction = KittActionEvent(
      code: code,
      title: title,
      detail: detail,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    _actionClearTimer = Timer(const Duration(seconds: 6), () {
      _activeAction = null;
      notifyListeners();
    });
  }

  /// Executa um comando acionado na interface nativa do Android Auto.
  Future<void> handleAndroidAutoCommand(String command) async {
    switch (command) {
      case 'toggle_voice':
        await toggleMic();
        break;
      case 'toggle_pursuit':
        final DriveMode next = _driveMode == DriveMode.pursuit
            ? DriveMode.normalCruise
            : DriveMode.pursuit;
        setOperationMode(next, announceToGemini: true);
        break;
      case 'toggle_surveillance':
        final DriveMode next = _driveMode == DriveMode.surveillance
            ? DriveMode.normalCruise
            : DriveMode.surveillance;
        setOperationMode(next, announceToGemini: true);
        break;
      case 'trigger_turbo_boost':
        activateGadget(GadgetType.turboBoost);
        break;
      case 'trigger_oil_slick':
        activateGadget(GadgetType.oilSlick);
        break;
      case 'trigger_smoke_screen':
        activateGadget(GadgetType.smokeScreen);
        break;
      default:
        break;
    }
  }

  void _syncAndroidAutoState() {
    _androidAutoBridge.syncState(
      connectionState: _connectionState,
      driveMode: _driveMode,
      isMicActive: _isMicActive,
      activeGadget: _activeGadget,
    );
  }

  @override
  void notifyListeners() {
    _syncAndroidAutoState();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _androidAutoBridge.dispose();
    _notificationFilter.dispose();
    _transmissionQueue.clear();
    _transmissionDelayTimer?.cancel();
    _turnDrainTimer?.cancel();
    _actionClearTimer?.cancel();
    _gadgetTimer?.cancel();
    _telemetryTimer?.cancel();
    _dashboardButtonTimer?.cancel();
    _missionProximityTimer?.cancel();
    for (final StreamSubscription<dynamic> sub in _subs) {
      sub.cancel();
    }
    _micManager.dispose();
    _audioEngine.dispose();
    _telemetryService.dispose();
    _liveClient.dispose();
    super.dispose();
  }
}
