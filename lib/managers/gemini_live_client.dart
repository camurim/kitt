import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/kitt_persona.dart';
import '../models/aux_slot_config.dart';
import '../models/kitt_state.dart';

class _LiveConnectionParams {
  const _LiveConnectionParams({
    required this.apiKey,
    required this.model,
    required this.persona,
    required this.currentMode,
    required this.auxSlots,
    required this.flagDossiersMarkdown,
  });

  final String apiKey;
  final String model;
  final KittPersonaConfig persona;
  final DriveMode currentMode;
  final List<AuxSlotConfig> auxSlots;
  final String flagDossiersMarkdown;
}

/// Cliente WebSocket para a Gemini Live API (BidiGenerateContent) com:
/// - Reconexão automática segura com exponential backoff (`2s -> 4s -> 8s -> 16s -> 30s`)
/// - Limite de tentativas consecutivas e bloqueio em erros de chave/cota/política
/// - Suporte a `sessionResumption` e `goAway` para preservar contexto hands-free
class GeminiLiveClient {
  static const String _wsBaseUrl =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  static const int maxAutoReconnectAttempts = 5;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  _LiveConnectionParams? _lastParams;
  String? _resumptionHandle;
  bool _autoReconnectEnabled = true;
  bool _manualDisconnect = false;
  bool _isConnecting = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  final StreamController<Uint8List> _audioController =
      StreamController<Uint8List>.broadcast();
  final StreamController<GeminiToolCall> _toolCallController =
      StreamController<GeminiToolCall>.broadcast();
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();
  final StreamController<LiveConnectionState> _stateController =
      StreamController<LiveConnectionState>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<void> _turnCompleteController =
      StreamController<void>.broadcast();

  Stream<Uint8List> get audioChunks => _audioController.stream;
  Stream<GeminiToolCall> get toolCalls => _toolCallController.stream;
  Stream<String> get transcripts => _transcriptController.stream;
  Stream<LiveConnectionState> get connectionState => _stateController.stream;
  Stream<String> get errors => _errorController.stream;
  Stream<void> get turnCompleted => _turnCompleteController.stream;

  bool get isConnected => _channel != null;
  bool get autoReconnectEnabled => _autoReconnectEnabled;

  /// Ativa ou pausa a reconexão automática (ex.: pausar quando o app vai para
  /// segundo plano sem Android Auto, economizando bateria e evitando conexões ociosas).
  void setAutoReconnectEnabled(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  /// Calcula o atraso de backoff exponencial (`2s, 4s, 8s, 16s, 30s`) para evitar
  /// excesso de requisições / HTTP 429.
  static Duration computeBackoffDelay(int attempt) {
    final int clamped = attempt.clamp(0, 6);
    final int seconds = math.min(30, 2 * (1 << clamped));
    return Duration(seconds: seconds);
  }

  /// Identifica erros permanentes (chave inválida, política, cota) onde NÃO se deve
  /// tentar reconectar automaticamente.
  static bool isNonRecoverableCloseCode(int? code, String? reason) {
    if (code == 1007 || code == 1008) return true;
    final String r = (reason ?? '').toLowerCase();
    return r.contains('api key') ||
        r.contains('permission') ||
        r.contains('not found') ||
        r.contains('quota') ||
        r.contains('billing') ||
        r.contains('invalid argument') ||
        r.contains('unauthorized');
  }

  Future<void> connect({
    required String apiKey,
    required String model,
    required KittPersonaConfig persona,
    required DriveMode currentMode,
    List<AuxSlotConfig> auxSlots = const <AuxSlotConfig>[],
    String flagDossiersMarkdown = '',
    bool resetResumption = false,
  }) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _manualDisconnect = false;
    if (resetResumption) {
      _resumptionHandle = null;
    }

    _lastParams = _LiveConnectionParams(
      apiKey: apiKey,
      model: model,
      persona: persona,
      currentMode: currentMode,
      auxSlots: auxSlots,
      flagDossiersMarkdown: flagDossiersMarkdown,
    );

    await _openSocket(_lastParams!);
  }

  Future<void> _openSocket(_LiveConnectionParams params) async {
    if (_disposed || _isConnecting) return;
    _isConnecting = true;

    await _closeCurrentSocket(notifyDisconnected: false);

    if (params.apiKey.trim().isEmpty) {
      _isConnecting = false;
      _stateController.add(LiveConnectionState.error);
      _errorController.add(
        'GEMINI_API_KEY não configurada. Execute com --dart-define=GEMINI_API_KEY=SUA_CHAVE.',
      );
      return;
    }

    _stateController.add(LiveConnectionState.connecting);

    final Uri uri = Uri.parse(
      '$_wsBaseUrl?key=${Uri.encodeQueryComponent(params.apiKey)}',
    );

    try {
      final WebSocketChannel channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;

      _subscription = channel.stream.listen(
        _handleIncomingMessage,
        onError: (Object err) {
          final String msg = _sanitizeError(err);
          _stateController.add(LiveConnectionState.error);
          _errorController.add('Erro WebSocket Gemini Live: $msg');
          if (!isNonRecoverableCloseCode(null, msg)) {
            _scheduleAutoReconnect();
          }
        },
        onDone: () {
          final int? code = _channel?.closeCode;
          final String? reason = _channel?.closeReason;
          _channel = null;

          if (_manualDisconnect || _disposed) {
            _stateController.add(LiveConnectionState.disconnected);
            return;
          }

          if (isNonRecoverableCloseCode(code, reason)) {
            _resumptionHandle = null;
            _stateController.add(LiveConnectionState.error);
            _errorController.add(
              'Conexão encerrada pelo Gemini (código $code): '
              '${(reason != null && reason.isNotEmpty) ? reason : "erro de configuração/autorização"}',
            );
            return;
          }

          // Timeout de inatividade (1000/1001/1006/1011) ou reinício do servidor:
          // tenta reconectar automaticamente de forma segura se habilitado.
          if (_autoReconnectEnabled &&
              _reconnectAttempts < maxAutoReconnectAttempts) {
            _stateController.add(LiveConnectionState.connecting);
            _scheduleAutoReconnect();
          } else if (code != null && code != 1000) {
            _stateController.add(LiveConnectionState.error);
            _errorController.add(
              'Conexão encerrada pelo Gemini (código $code): '
              '${(reason != null && reason.isNotEmpty) ? reason : "limite de reconexões atingido"}',
            );
          } else {
            _stateController.add(LiveConnectionState.disconnected);
          }
        },
      );

      final String normalizedModel = params.model.startsWith('models/')
          ? params.model
          : 'models/${params.model}';

      final Map<String, dynamic> setupBody = <String, dynamic>{
        'model': normalizedModel,
        'generationConfig': <String, dynamic>{
          'responseModalities': <String>['AUDIO'],
          'speechConfig': <String, dynamic>{
            'voiceConfig': <String, dynamic>{
              'prebuiltVoiceConfig': <String, dynamic>{
                'voiceName': params.persona.voiceName,
              },
            },
          },
        },
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text': params.persona.buildSystemInstruction(
                params.currentMode,
                auxSlots: params.auxSlots,
                flagDossiersMarkdown: params.flagDossiersMarkdown,
              ),
            },
          ],
        },
        'tools': buildKittToolDeclarations(),
        'sessionResumption': _resumptionHandle != null
            ? <String, dynamic>{'handle': _resumptionHandle}
            : <String, dynamic>{},
      };

      _sendJson(<String, dynamic>{'setup': setupBody});
    } catch (e) {
      final String sanitized = _sanitizeError(e);
      _stateController.add(LiveConnectionState.error);
      _errorController.add(
        'Falha ao conectar na Gemini Live API: $sanitized',
      );
      await _closeCurrentSocket(notifyDisconnected: false);
      if (!isNonRecoverableCloseCode(null, sanitized)) {
        _scheduleAutoReconnect();
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _scheduleAutoReconnect() {
    if (_disposed ||
        _manualDisconnect ||
        !_autoReconnectEnabled ||
        _lastParams == null) {
      return;
    }
    if (_reconnectAttempts >= maxAutoReconnectAttempts) {
      return;
    }
    if (_reconnectTimer?.isActive == true) {
      return;
    }

    final Duration delay = computeBackoffDelay(_reconnectAttempts);
    _reconnectAttempts++;

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed ||
          _manualDisconnect ||
          !_autoReconnectEnabled ||
          _lastParams == null) {
        return;
      }
      _openSocket(_lastParams!);
    });
  }

  String _sanitizeError(Object err) {
    return err.toString().replaceAll(RegExp(r'key=[^&\s\x27"]+'), 'key=***');
  }

  /// Envia um chunk PCM 16-bit mono 16 kHz capturado do microfone.
  void sendPcmAudioChunk(Uint8List pcm16kBytes) {
    if (_channel == null || pcm16kBytes.isEmpty) return;
    _sendJson(<String, dynamic>{
      'realtimeInput': <String, dynamic>{
        'mediaChunks': <Map<String, dynamic>>[
          <String, dynamic>{
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(pcm16kBytes),
          },
        ],
      },
    });
  }

  /// Envia um turno de texto (útil para testes sem microfone ou botões rápidos).
  void sendTextMessage(String text, {bool turnComplete = true}) {
    if (_channel == null || text.trim().isEmpty) return;
    _sendJson(<String, dynamic>{
      'clientContent': <String, dynamic>{
        'turns': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{'text': text},
            ],
          },
        ],
        'turnComplete': turnComplete,
      },
    });
  }

  /// Injeta contexto silencioso na sessão ativa da Gemini Live API (`turnComplete: false`)
  /// para ajustar o tom/comportamento do KITT sem disparar uma resposta imediata.
  void sendSilentContext(String contextInstruction) {
    sendTextMessage(contextInstruction, turnComplete: false);
  }

  /// Devolve o resultado de uma chamada de função para o Gemini continuar a fala.
  void sendToolResponse({
    required String callId,
    required String name,
    required Map<String, dynamic> response,
  }) {
    if (_channel == null) return;
    _sendJson(<String, dynamic>{
      'toolResponse': <String, dynamic>{
        'functionResponses': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': callId,
            'name': name,
            'response': response,
          },
        ],
      },
    });
  }

  void _sendJson(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _handleIncomingMessage(dynamic raw) {
    try {
      final String text = raw is String
          ? raw
          : raw is List<int>
              ? utf8.decode(raw)
              : raw.toString();

      final Map<String, dynamic> json =
          jsonDecode(text) as Map<String, dynamic>;

      if (json.containsKey('setupComplete')) {
        _reconnectAttempts = 0;
        _stateController.add(LiveConnectionState.ready);
        return;
      }

      // Token de retomada de sessão emitido periodicamente pelo Gemini Live
      final Map<String, dynamic>? resumptionUpdate =
          json['sessionResumptionUpdate'] as Map<String, dynamic>?;
      if (resumptionUpdate != null) {
        final bool resumable = resumptionUpdate['resumable'] == true;
        final String? handle = resumptionUpdate['newHandle'] as String?;
        if (resumable && handle != null && handle.isNotEmpty) {
          _resumptionHandle = handle;
        }
      }

      // Aviso proativo do servidor de que a conexão será encerrada em breve
      if (json.containsKey('goAway') && _autoReconnectEnabled) {
        _scheduleAutoReconnect();
      }

      // 1. Áudio PCM e texto devolvidos pelo modelo
      final Map<String, dynamic>? serverContent =
          json['serverContent'] as Map<String, dynamic>?;
      if (serverContent != null) {
        if (serverContent['turnComplete'] == true ||
            serverContent['interrupted'] == true) {
          if (!_turnCompleteController.isClosed) {
            _turnCompleteController.add(null);
          }
        }
        final Map<String, dynamic>? modelTurn =
            serverContent['modelTurn'] as Map<String, dynamic>?;
        final List<dynamic>? parts = modelTurn?['parts'] as List<dynamic>?;
        if (parts != null) {
          for (final dynamic part in parts) {
            if (part is! Map<String, dynamic>) continue;

            final String? partText = part['text'] as String?;
            if (partText != null && partText.trim().isNotEmpty) {
              _transcriptController.add(partText.trim());
            }

            final Map<String, dynamic>? inlineData =
                part['inlineData'] as Map<String, dynamic>?;
            if (inlineData != null) {
              final String mime = (inlineData['mimeType'] as String? ?? '');
              final String? b64 = inlineData['data'] as String?;
              if (b64 != null && mime.startsWith('audio/pcm')) {
                _audioController.add(base64Decode(b64));
              }
            }
          }
        }
      }

      // 2. Function Calling solicitado pelo Gemini
      final Map<String, dynamic>? toolCall =
          json['toolCall'] as Map<String, dynamic>?;
      if (toolCall != null) {
        final List<dynamic>? calls =
            toolCall['functionCalls'] as List<dynamic>?;
        if (calls != null) {
          for (final dynamic item in calls) {
            if (item is! Map<String, dynamic>) continue;
            final String id = item['id'] as String? ?? '';
            final String name = item['name'] as String? ?? '';
            final Map<String, dynamic> args =
                (item['args'] as Map<String, dynamic>?) ?? <String, dynamic>{};
            if (name.isNotEmpty) {
              _toolCallController.add(
                GeminiToolCall(id: id, name: name, args: args),
              );
            }
          }
        }
      }
    } catch (e) {
      _errorController.add('Erro ao decodificar mensagem do Gemini Live: $e');
    }
  }

  Future<void> _closeCurrentSocket({required bool notifyDisconnected}) async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (notifyDisconnected && !_stateController.isClosed) {
      _stateController.add(LiveConnectionState.disconnected);
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeCurrentSocket(notifyDisconnected: true);
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _audioController.close();
    await _toolCallController.close();
    await _transcriptController.close();
    await _stateController.close();
    await _errorController.close();
    await _turnCompleteController.close();
  }
}
