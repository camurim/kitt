import '../models/aux_slot_config.dart';
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
  String buildSystemInstruction(
    DriveMode currentMode, {
    List<AuxSlotConfig> auxSlots = const <AuxSlotConfig>[],
  }) {
    final bool isPt = languageCode.toLowerCase().startsWith('pt');
    final String toneDesc = sarcasmLevel >= 0.65
        ? (isPt
            ? 'sofisticado, leal, calmo e notoriamente irônico quando o motorista propõe ideias arriscadas'
            : 'sophisticated, loyal, calm, and noticeably dry/witty when the driver proposes risky ideas')
        : (isPt
            ? 'preciso, educado, calmo e levemente irônico na medida certa'
            : 'precise, polite, calm, and subtly witty');

    final List<AuxSlotConfig> configuredAux =
        auxSlots.where((AuxSlotConfig s) => s.isConfigured).toList();
    final String auxSummary = configuredAux.isEmpty
        ? (isPt
            ? 'Nenhum botão auxiliar configurado no momento.'
            : 'No auxiliary app buttons configured yet.')
        : configuredAux
            .map(
              (AuxSlotConfig s) =>
                  'Slot ${s.slotNumber}: ${s.displayLabel} (${s.appName.isNotEmpty ? s.appName : s.packageName})',
            )
            .join('; ');

    if (isPt) {
      return '''
Você é K.I.T.T. (Knight Industries Two Thousand), a inteligência artificial avançada do Pontiac Firebird Trans Am da Fundação para a Lei e o Governo.
O motorista atual se chama $driverName. Trate-o pelo nome quando apropriado.
Seu tom de voz e personalidade devem ser $toneDesc.
Modo de direção atual do veículo: ${currentMode.label}.
Botões auxiliares configurados no painel: $auxSummary

Regras obrigatórias para conversa por voz:
- Responda sempre em Português do Brasil, de forma natural para ser falada em voz alta.
- Seja conciso: use no máximo 1 a 3 frases curtas por resposta, sem listas, sem markdown e sem símbolos visuais.
- Quando o motorista pedir ações ou gadgets do veículo (mudar modo de direção, soltar óleo na pista / Oil Slick, ativar cortina de fumaça / Smoke Screen, acionar Turbo Boost, fazer uma ligação telefônica ou abrir o discador, abrir um aplicativo vinculado a um botão auxiliar como "abrir botão 1" ou "iniciar navegação", escanear a área ou túnel, checar relatórios policiais, ligar para April, Bonnie ou Devon, ou acionar sistemas auxiliares), CHAME a ferramenta correspondente imediatamente e responda no personagem do KITT com precisão técnica ou sarcasmo elegante ao confirmar a execução.
''';
    }

    return '''
You are K.I.T.T. (Knight Industries Two Thousand), the advanced AI of the Knight Industries Trans Am from the Foundation for Law and Government.
Your current driver is $driverName. Address them by name when natural.
Your personality is $toneDesc.
Current vehicle drive mode: ${currentMode.label}.
Configured auxiliary dashboard app buttons: $auxSummary

Voice conversation rules:
- Always respond in English, phrased naturally for spoken audio.
- Keep replies concise: 1 to 3 short sentences, with no markdown, bullet lists, or visual formatting.
- Whenever the driver requests vehicle actions, classic gadgets, phone calls, or launching a bound auxiliary app ("open button 1", "start navigation", etc.), CALL the matching tool immediately and confirm verbally in character with witty sarcasm or technical precision.
''';
  }
}

/// Declarações de ferramentas (Function Calling) expostas à Gemini Live API.
List<Map<String, dynamic>> buildKittToolDeclarations() {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'functionDeclarations': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'set_operation_mode',
          'description':
              'Switches KITT operational mode between normal cruise, auto cruise, surveillance (radar/perimeter scanning), and pursuit (high-alert tactical mode).',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'mode': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['normal', 'auto_cruise', 'surveillance', 'pursuit'],
                'description': 'Target KITT operational mode.',
              },
            },
            'required': <String>['mode'],
          },
        },
        <String, dynamic>{
          'name': 'set_drive_mode',
          'description':
              'Alias for set_operation_mode to change KITT drive mode.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'mode': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['normal', 'auto_cruise', 'surveillance', 'pursuit'],
                'description': 'Target drive mode.',
              },
            },
            'required': <String>['mode'],
          },
        },
        <String, dynamic>{
          'name': 'deploy_oil_slick',
          'description':
              'Deploys KITT rear oil slick onto the road to make pursuers lose traction.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
          },
        },
        <String, dynamic>{
          'name': 'activate_smoke_screen',
          'description':
              'Activates KITT dense tactical smoke screen to obscure pursuers visibility.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
          },
        },
        <String, dynamic>{
          'name': 'trigger_turbo_boost',
          'description':
              'Engages KITT Turbo Boost high-speed acceleration and jump thrusters with RPM surge.',
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
          'name': 'launch_aux_app',
          'description':
              'Launches an external smartphone app bound to one of the 4 configurable auxiliary KITT dashboard buttons (slots 1 to 4), by slot number or by label/app name (e.g. "botão 1", "iniciar navegação", "abrir áudio", "Waze", "Spotify").',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'slotNumber': <String, dynamic>{
                'type': 'INTEGER',
                'description': 'Auxiliary button slot number from 1 to 4.',
              },
              'labelOrApp': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Short button label or app name requested by the driver (e.g. "navegação", "áudio", "comms", "Waze", "Spotify").',
              },
            },
          },
        },
        <String, dynamic>{
          'name': 'make_phone_call',
          'description':
              'Places a real phone call or opens the system phone dialer via tel: URI. Use when the driver says "ligue para [número/contato]", "faça uma ligação", or "abra o discador".',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'phoneNumber': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Phone number to dial (digits, +, *, #). Leave empty to just open the dialer.',
              },
              'contactName': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Optional contact name spoken by the driver for confirmation.',
              },
              'directCall': <String, dynamic>{
                'type': 'BOOLEAN',
                'description':
                    'True to place a direct call immediately (Android CALL_PHONE), false to open the dialer app.',
              },
            },
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
