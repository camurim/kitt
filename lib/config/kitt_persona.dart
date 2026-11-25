import '../models/kitt_state.dart';

/// Configurações de runtime injetadas via `--dart-define`.
class KittConfig {
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const String geminiLiveModel = String.fromEnvironment(
    'GEMINI_LIVE_MODEL',
    defaultValue: 'gemini-2.5-flash-native-audio-preview-12-2025',
  );

  static const List<String> availableVoices = <String>[
    'Charon',
    'Fenrir',
    'Orus',
    'Puck',
    'Kore',
  ];
}

/// Parâmetros configuráveis da personalidade do KITT.
class KittPersonaConfig {
  const KittPersonaConfig({
    this.driverName = 'Michael',
    this.languageCode = 'pt-BR',
    this.voiceName = 'Charon',
    this.sarcasmLevel = 0.6,
  });

  final String driverName;
  final String languageCode;
  final String voiceName;

  /// Intensidade de ironia/sarcasmo clássico do KITT (0.0 = estritamente técnico, 1.0 = bem irônico).
  final double sarcasmLevel;

  KittPersonaConfig copyWith({
    String? driverName,
    String? languageCode,
    String? voiceName,
    double? sarcasmLevel,
  }) {
    return KittPersonaConfig(
      driverName: driverName ?? this.driverName,
      languageCode: languageCode ?? this.languageCode,
      voiceName: voiceName ?? this.voiceName,
      sarcasmLevel: sarcasmLevel ?? this.sarcasmLevel,
    );
  }

  /// Gera a `systemInstruction` enviada no handshake `setup` da Gemini Live API.
  String buildSystemInstruction(DriveMode currentMode) {
    final bool isPt = languageCode.toLowerCase().startsWith('pt');
    final String toneDesc = sarcasmLevel >= 0.65
        ? (isPt
            ? 'sofisticado, leal, calmo e notoriamente irônico quando o motorista propõe ideias arriscadas'
            : 'sophisticated, loyal, calm, and noticeably dry/witty when the driver proposes risky ideas')
        : (isPt
            ? 'preciso, educado, calmo e levemente irônico na medida certa'
            : 'precise, polite, calm, and subtly witty');

    if (isPt) {
      return '''
Você é K.I.T.T. (Knight Industries Two Thousand), a inteligência artificial avançada do Pontiac Firebird Trans Am da Fundação para a Lei e o Governo.
O motorista atual se chama $driverName. Trate-o pelo nome quando apropriado.
Seu tom de voz e personalidade devem ser $toneDesc.
Modo de direção atual do veículo: ${currentMode.label}.

Regras obrigatórias para conversa por voz:
- Responda sempre em Português do Brasil, de forma natural para ser falada em voz alta.
- Seja conciso: use no máximo 1 a 3 frases curtas por resposta, sem listas, sem markdown e sem símbolos visuais.
- Quando o motorista pedir ações do veículo (como mudar modo de direção, ativar Turbo Boost, escanear a área ou túnel, checar relatórios policiais, ligar para April, Bonnie ou Devon, ou acionar sistemas como óleo/ar), CHAME a ferramenta correspondente imediatamente e confirme a ação na voz do KITT.
''';
    }

    return '''
You are K.I.T.T. (Knight Industries Two Thousand), the advanced AI of the Knight Industries Trans Am from the Foundation for Law and Government.
Your current driver is $driverName. Address them by name when natural.
Your personality is $toneDesc.
Current vehicle drive mode: ${currentMode.label}.

Voice conversation rules:
- Always respond in English, phrased naturally for spoken audio.
- Keep replies concise: 1 to 3 short sentences, with no markdown, bullet lists, or visual formatting.
- Whenever the driver requests vehicle actions (drive mode changes, Turbo Boost, scanning area/tunnel, police reports, calling April/Bonnie/Devon, or system effects), CALL the matching tool immediately and confirm verbally in character.
''';
  }
}

/// Declarações de ferramentas (Function Calling) expostas à Gemini Live API.
List<Map<String, dynamic>> buildKittToolDeclarations() {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'functionDeclarations': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'set_drive_mode',
          'description':
              'Changes KITT drive mode between normal cruise, auto cruise, and pursuit.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'mode': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['normal', 'auto_cruise', 'pursuit'],
                'description': 'Target drive mode.',
              },
            },
            'required': <String>['mode'],
          },
        },
        <String, dynamic>{
          'name': 'activate_turbo_boost',
          'description':
              'Engages KITT Turbo Boost jump/acceleration sequence.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
          },
        },
        <String, dynamic>{
          'name': 'scan_environment',
          'description':
              'Runs KITT front scanner or police report diagnostics.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'target': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['area', 'tunnel', 'police_reports'],
                'description': 'What to scan or inspect.',
              },
            },
            'required': <String>['target'],
          },
        },
        <String, dynamic>{
          'name': 'call_contact',
          'description':
              'Opens a simulated commlink video/voice call with Foundation team members.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'contact': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['april', 'bonnie', 'devon'],
                'description': 'Foundation contact name.',
              },
            },
            'required': <String>['contact'],
          },
        },
        <String, dynamic>{
          'name': 'trigger_system_effect',
          'description':
              'Triggers an auxiliary dashboard system effect (oil slick, air, P1-P4, S1-S2).',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'effect': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>[
                  'oil',
                  'air',
                  'p1',
                  'p2',
                  'p3',
                  'p4',
                  's1',
                  's2',
                ],
                'description': 'Auxiliary system identifier.',
              },
            },
            'required': <String>['effect'],
          },
        },
      ],
    },
  ];
}
