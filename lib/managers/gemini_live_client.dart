import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/kitt_persona.dart';
import '../models/aux_slot_config.dart';
import '../models/kitt_state.dart';

/// Cliente WebSocket para a Gemini Live API (BidiGenerateContent).
///
/// Envia áudio PCM 16 kHz mono do microfone em tempo real e recebe:
/// - chunks de áudio PCM 24 kHz 16-bit mono
/// - chamadas de ferramentas (`toolCall.functionCalls`)
/// - transcrições/texto quando presentes
class GeminiLiveClient {
  static const String _wsBaseUrl =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

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

  Stream<Uint8List> get audioChunks => _audioController.stream;
  Stream<GeminiToolCall> get toolCalls => _toolCallController.stream;
  Stream<String> get transcripts => _transcriptController.stream;
  Stream<LiveConnectionState> get connectionState => _stateController.stream;
  Stream<String> get errors => _errorController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({
    required String apiKey,
    required String model,
    required KittPersonaConfig persona,
    required DriveMode currentMode,
    List<AuxSlotConfig> auxSlots = const <AuxSlotConfig>[],
  }) async {
    await disconnect();

    if (apiKey.trim().isEmpty) {
      _stateController.add(LiveConnectionState.error);
      _errorController.add(
        'GEMINI_API_KEY não configurada. Execute com --dart-define=GEMINI_API_KEY=SUA_CHAVE.',
      );
      return;
    }

    _stateController.add(LiveConnectionState.connecting);

    final Uri uri = Uri.parse('$_wsBaseUrl?key=${Uri.encodeQueryComponent(apiKey)}');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (Object err) {
          _stateController.add(LiveConnectionState.error);
          _errorController.add(
            'Erro WebSocket Gemini Live: ${_sanitizeError(err)}',
          );
        },
        onDone: () {
          final int? code = _channel?.closeCode;
          final String? reason = _channel?.closeReason;
          if (code != null && code != 1000) {
            _stateController.add(LiveConnectionState.error);
            _errorController.add(
              'Conexão encerrada pelo Gemini (código $code): '
              '${(reason != null && reason.isNotEmpty) ? reason : "sem detalhes"}',
            );
          } else {
            _stateController.add(LiveConnectionState.disconnected);
          }
        },
      );

      final String normalizedModel =
          model.startsWith('models/') ? model : 'models/$model';

      final Map<String, dynamic> setupPayload = <String, dynamic>{
        'setup': <String, dynamic>{
          'model': normalizedModel,
          'generationConfig': <String, dynamic>{
            'responseModalities': <String>['AUDIO'],
            'speechConfig': <String, dynamic>{
              'voiceConfig': <String, dynamic>{
                'prebuiltVoiceConfig': <String, dynamic>{
                  'voiceName': persona.voiceName,
                },
              },
            },
          },
          'systemInstruction': <String, dynamic>{
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{
                'text': persona.buildSystemInstruction(
                  currentMode,
                  auxSlots: auxSlots,
                ),
              },
            ],
          },
          'tools': buildKittToolDeclarations(),
        },
      };

      _sendJson(setupPayload);
    } catch (e) {
      _stateController.add(LiveConnectionState.error);
      _errorController.add(
        'Falha ao conectar na Gemini Live API: ${_sanitizeError(e)}',
      );
      await disconnect();
    }
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
        _stateController.add(LiveConnectionState.ready);
        return;
      }

      // 1. Áudio PCM e texto devolvidos pelo modelo
      final Map<String, dynamic>? serverContent =
          json['serverContent'] as Map<String, dynamic>?;
      if (serverContent != null) {
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

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_stateController.isClosed) {
      _stateController.add(LiveConnectionState.disconnected);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _audioController.close();
    await _toolCallController.close();
    await _transcriptController.close();
    await _stateController.close();
    await _errorController.close();
  }
}
