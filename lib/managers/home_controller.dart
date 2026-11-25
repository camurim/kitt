import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/kitt_persona.dart';
import '../models/kitt_state.dart';
import 'audio_engine_manager.dart';
import 'gemini_live_client.dart';
import 'mic_stream_manager.dart';

/// Controlador principal do painel KITT.
///
/// Orquestra:
/// - Sessão Gemini Live API
/// - Captura de microfone PCM 16 kHz
/// - Reprodução PCM 24 kHz + nível do Voicebox
/// - Modos de direção e execução de Function Calling local
class HomeController extends ChangeNotifier {
  HomeController({
    GeminiLiveClient? liveClient,
    AudioEngineManager? audioEngine,
    MicStreamManager? micManager,
    KittPersonaConfig initialPersona = const KittPersonaConfig(),
  })  : _liveClient = liveClient ?? GeminiLiveClient(),
        _audioEngine = audioEngine ?? AudioEngineManager(),
        _micManager = micManager ?? MicStreamManager(),
        _persona = initialPersona {
    _bindStreams();
  }

  final GeminiLiveClient _liveClient;
  final AudioEngineManager _audioEngine;
  final MicStreamManager _micManager;

  KittPersonaConfig _persona;
  DriveMode _driveMode = DriveMode.normalCruise;
  LiveConnectionState _connectionState = LiveConnectionState.disconnected;
  bool _isMicActive = false;
  String? _errorMessage;
  String _lastTranscript = '';
  KittActionEvent? _activeAction;
  Timer? _actionClearTimer;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  KittPersonaConfig get persona => _persona;
  DriveMode get driveMode => _driveMode;
  LiveConnectionState get connectionState => _connectionState;
  bool get isMicActive => _isMicActive;
  String? get errorMessage => _errorMessage;
  String get lastTranscript => _lastTranscript;
  KittActionEvent? get activeAction => _activeAction;
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
  }

  Future<void> initAndConnect() async {
    await _audioEngine.init();
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

  void setDriveMode(DriveMode mode, {bool announceToGemini = false}) {
    _driveMode = mode;
    _audioEngine.playSfxAsset('audio/${mode.apiValue}.mp3');
    _setTransientAction(
      code: mode.apiValue,
      title: mode.label,
      detail: 'Modo de direção alterado para ${mode.label}.',
    );
    if (announceToGemini && _connectionState == LiveConnectionState.ready) {
      _liveClient.sendTextMessage(
        'O motorista pressionou o botão ${mode.label} no painel. Confirme brevemente como KITT.',
      );
    }
    notifyListeners();
  }

  void triggerDashboardButton(String code) {
    final String lower = code.toLowerCase();
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

  void _handleToolCall(GeminiToolCall call) {
    Map<String, dynamic> result;

    switch (call.name) {
      case 'set_drive_mode':
        final DriveMode mode =
            DriveMode.fromApiValue(call.args['mode'] as String?);
        setDriveMode(mode);
        result = <String, dynamic>{
          'status': 'ok',
          'active_mode': mode.label,
        };
        break;

      case 'activate_turbo_boost':
        _audioEngine.playSfxAsset('audio/turbo_boost.mp3');
        _setTransientAction(
          code: 'turbo_boost',
          title: 'TURBO BOOST ENGAGED',
          detail: 'Propulsores Turbo Boost ativados.',
        );
        result = <String, dynamic>{
          'status': 'ok',
          'turbo_boost': 'engaged',
        };
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
    for (final StreamSubscription<dynamic> sub in _subs) {
      sub.cancel();
    }
    _micManager.dispose();
    _audioEngine.dispose();
    _liveClient.dispose();
    super.dispose();
  }
}
