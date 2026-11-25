import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/kitt_persona.dart';
import '../models/aux_slot_config.dart';
import '../models/kitt_state.dart';
import 'audio_engine_manager.dart';
import 'aux_apps_manager.dart';
import 'gemini_live_client.dart';
import 'mic_stream_manager.dart';
import 'phone_call_manager.dart';
import 'vehicle_telemetry_service.dart';

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
    KittPersonaConfig initialPersona = const KittPersonaConfig(),
  })  : _liveClient = liveClient ?? GeminiLiveClient(),
        _audioEngine = audioEngine ?? AudioEngineManager(),
        _micManager = micManager ?? MicStreamManager(),
        _phoneCallManager = phoneCallManager ?? PhoneCallManager(),
        _auxAppsManager = auxAppsManager ?? AuxAppsManager(),
        _telemetryService = telemetryService ?? VehicleTelemetryService(),
        _persona = initialPersona {
    _bindStreams();
  }

  final GeminiLiveClient _liveClient;
  final AudioEngineManager _audioEngine;
  final MicStreamManager _micManager;
  final PhoneCallManager _phoneCallManager;
  final AuxAppsManager _auxAppsManager;
  final VehicleTelemetryService _telemetryService;

  List<AuxSlotConfig> _auxSlots = AuxSlotConfig.defaultSlots();

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
  List<AuxSlotConfig> get auxSlots => List<AuxSlotConfig>.unmodifiable(_auxSlots);
  ValueListenable<double> get voiceLevel => _audioEngine.voiceLevel;

  void _bindStreams() {
    _subs.add(
      _liveClient.connectionState.listen((LiveConnectionState state) {
        _connectionState = state;
        if (state == LiveConnectionState.ready) {
          _errorMessage = null;
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
      _telemetryService.telemetryUpdates.listen((_) => notifyListeners()),
    );

    _subs.add(
      _telemetryService.maneuverReactions.listen(_handleHarshManeuver),
    );
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

  Future<void> initAndConnect() async {
    _auxSlots = await _auxAppsManager.loadSlots();
    notifyListeners();
    await _audioEngine.init();
    await _telemetryService.start();
    await connect();
  }

  Future<void> connect() async {
    _errorMessage = null;
    notifyListeners();
    await _liveClient.connect(
      apiKey: KittConfig.geminiApiKey,
      model: KittConfig.geminiLiveModel,
      persona: _persona,
      currentMode: _driveMode,
      auxSlots: _auxSlots,
    );
  }

  Future<void> disconnect() async {
    await stopMic();
    await _liveClient.disconnect();
  }

  Future<void> toggleMic() async {
    if (_isMicActive) {
      await stopMic();
      return;
    }

    if (_connectionState != LiveConnectionState.ready) {
      await connect();
      if (_connectionState == LiveConnectionState.error) return;
    }

    final bool started = await _micManager.startStreaming(
      _liveClient.sendPcmAudioChunk,
    );
    if (!started) {
      _errorMessage = 'Permissão de microfone negada.';
      notifyListeners();
      return;
    }
    _isMicActive = true;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> stopMic() async {
    await _micManager.stopStreaming();
    if (_isMicActive) {
      _isMicActive = false;
      notifyListeners();
    }
  }

  void setOperationMode(DriveMode mode, {bool announceToGemini = false}) {
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
    _gadgetTimer?.cancel();
    _telemetryTimer?.cancel();

    _activeGadget = gadget;
    _gadgetRunId++;

    // Efeito sonoro opcional (falha silenciosamente se o MP3 não existir)
    _audioEngine.playSfxAsset(gadget.sfxAsset);

    // Feedback háptico e telemetria específicos do gadget
    if (gadget == GadgetType.turboBoost) {
      _runTurboBoostTelemetryAndHaptics();
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
    };

    _setTransientAction(
      code: gadget.toolName,
      title: gadget.label,
      detail: gadget.hudAlert,
    );

    if (announceToGemini && _connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        'O motorista acionou manualmente o gadget ${gadget.label} no painel '
        '(telemetria: $telemetry). Reaja brevemente como KITT com sarcasmo ou precisão técnica.',
      );
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

  @override
  void dispose() {
    _actionClearTimer?.cancel();
    _gadgetTimer?.cancel();
    _telemetryTimer?.cancel();
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
