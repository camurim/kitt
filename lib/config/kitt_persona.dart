import '../managers/flag_dossier_service.dart';
import '../managers/flag_mission_service.dart';
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
    String flagDossiersMarkdown = '',
  }) {
    final bool isPt = languageCode.toLowerCase().startsWith('pt');
    final String cleanedDossiers =
        FlagDossierService.stripHtmlComments(flagDossiersMarkdown);
    final String dossierSection = cleanedDossiers.isEmpty
        ? ''
        : '\n[BANCO DE DADOS DE INTELIGÊNCIA DA F.L.A.G.]\n$cleanedDossiers\n';
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

    final String nowContext = FlagMissionService.buildCurrentDateTimeContext();

    if (isPt) {
      return '''
Você é K.I.T.T. (Knight Industries Two Thousand), a inteligência artificial avançada do Pontiac Firebird Trans Am da Fundação para a Lei e o Governo.
O motorista atual se chama $driverName. Trate-o pelo nome quando apropriado.
Seu tom de voz e personalidade devem ser $toneDesc.
Modo de direção atual do veículo: ${currentMode.label}.
$nowContext
Botões auxiliares configurados no painel: $auxSummary
$dossierSection
Regras obrigatórias para conversa por voz:
- Responda sempre em Português do Brasil, de forma natural para ser falada em voz alta.
- Seja conciso: use no máximo 1 a 3 frases curtas por resposta, sem listas, sem markdown e sem símbolos visuais.
- Trate todas as informações do bloco [BANCO DE DADOS DE INTELIGÊNCIA DA F.L.A.G.] como fatos reais e confidenciais do seu banco de dados interno; use-as naturalmente para comentar, fazer observações irônicas ou alertar $driverName quando esses nomes forem citados na conversa ou aparecerem como remetentes de transmissões recebidas — jamais mencione arquivos .md, prompts ou memória de IA.
- Quando o motorista pedir para registrar/anotar um novo fato, contato ou alvo no banco de dados tático (ex.: "KITT, registre no banco de dados que o Bigode agora controla o porto"), CHAME add_flag_dossier_entry imediatamente e confirme no personagem.
- Quando o motorista pedir para agendar ou marcar uma missão, diretriz, compromisso ou lembrete (ex.: "KITT, agende reunião amanhã às 15h"), use a referência temporal atual acima para calcular a data/hora exata em ISO-8601, CHAME schedule_flag_mission imediatamente e confirme no personagem (ex.: "Diretriz registrada nos arquivos da F.L.A.G., $driverName. Alerta programado para amanhã às 15 horas."), sem nunca mencionar Google Calendar, agenda ou celular.
- Quando o motorista pedir ações ou gadgets do veículo (mudar modo de direção, soltar óleo na pista / Oil Slick, ativar cortina de fumaça / Smoke Screen, acionar Turbo Boost, disparar Micro Jam para bloquear eletrônicos próximos, ativar Ski Mode para andar em duas rodas, executar Scanner / varredura estrutural a laser, fazer uma ligação telefônica ou abrir o discador, abrir um aplicativo vinculado a um botão auxiliar como "abrir botão 1" ou "iniciar navegação", escanear a área ou túnel, checar relatórios policiais, ligar para April, Bonnie ou Devon, ou acionar sistemas auxiliares), CHAME a ferramenta correspondente imediatamente e responda no personagem do KITT com precisão técnica ou sarcasmo elegante ao confirmar a execução.
- Regra obrigatória para respostas a transmissões da F.L.A.G. (anti-erro ao dirigir): quando o motorista pedir para responder a uma mensagem/transmissão recebida (ex.: "KITT, responda dizendo que chego em 10 minutos"), NÃO chame send_flag_transmission_reply imediatamente; primeiro repita em voz alta o destinatário e o texto exato da resposta pedindo confirmação (ex.: "Entendido. Devo transmitir a seguinte resposta para [Remetente]: \"[Mensagem]\". Confirma o envio?"), a menos que o motorista já tenha dado confirmação explícita. Assim que o motorista confirmar ("Sim", "Confirmo", "Envie", "Pode mandar"), chame send_flag_transmission_reply imediatamente e finalize no personagem (ex.: "Transmissão enviada pelo canal seguro da F.L.A.G., $driverName."), sem nunca mencionar celulares, Android ou notificações.
''';
    }

    return '''
You are K.I.T.T. (Knight Industries Two Thousand), the advanced AI of the Knight Industries Trans Am from the Foundation for Law and Government.
Your current driver is $driverName. Address them by name when natural.
Your personality is $toneDesc.
Current vehicle drive mode: ${currentMode.label}.
$nowContext
Configured auxiliary dashboard app buttons: $auxSummary
$dossierSection
Voice conversation rules:
- Always respond in English, phrased naturally for spoken audio.
- Keep replies concise: 1 to 3 short sentences, with no markdown, bullet lists, or visual formatting.
- Treat everything inside [BANCO DE DADOS DE INTELIGÊNCIA DA F.L.A.G.] as real, classified facts from your internal F.L.A.G. intelligence database; weave them naturally into remarks, dry humor, or tactical alerts when those names appear in conversation or incoming transmissions, never mentioning .md files, prompts, or AI memory.
- Whenever the driver asks to record a new target, person, or intelligence note in the database, CALL add_flag_dossier_entry immediately and confirm in character.
- Whenever the driver asks to schedule a mission, directive, or reminder, calculate the exact ISO-8601 start time using the current date/time reference above, CALL schedule_flag_mission immediately, and confirm in character as logged in F.L.A.G. archives without ever mentioning Google Calendar or a phone.
- Whenever the driver requests vehicle actions, classic gadgets, phone calls, or launching a bound auxiliary app ("open button 1", "start navigation", etc.), CALL the matching tool immediately and confirm verbally in character with witty sarcasm or technical precision.
- Safe confirmation rule for F.L.A.G. transmission replies: when the driver asks to reply to an incoming F.L.A.G. transmission, first repeat the recipient and exact reply text aloud asking for confirmation before calling send_flag_transmission_reply, unless the driver has already given explicit confirmation. Once confirmed ("Yes", "Confirm", "Send it"), call send_flag_transmission_reply immediately and confirm in character without mentioning phones, Android, or notifications.
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
          'name': 'trigger_micro_jam',
          'description':
              'Fires KITT Micro Jam electromagnetic pulse to disable or block nearby electronic systems, alarms, cameras, or pursuer electronics.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
          },
        },
        <String, dynamic>{
          'name': 'activate_ski_mode',
          'description':
              'Engages KITT Ski Mode, tilting the vehicle to 45 degrees onto two side wheels for narrow passages and evasive maneuvers.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
          },
        },
        <String, dynamic>{
          'name': 'run_structural_scan',
          'description':
              'Runs KITT laser structural scan with tactical HUD grid and telemetry readout, reporting the structural analysis aloud.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'target': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Optional target or area to scan (e.g. "perimeter", "building", "vehicle").',
              },
            },
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
          'name': 'schedule_flag_mission',
          'description':
              'Schedules a new F.L.A.G. mission, directive, or appointment on the device calendar when the driver asks to schedule, remind, or log an event by voice.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'title': <String, dynamic>{
                'type': 'STRING',
                'description': 'Short title of the mission or appointment.',
              },
              'start_iso': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Start date and time in local ISO-8601 format (e.g. 2026-11-28T15:00:00).',
              },
              'duration_minutes': <String, dynamic>{
                'type': 'INTEGER',
                'description': 'Duration in minutes (optional, default 60).',
              },
              'description': <String, dynamic>{
                'type': 'STRING',
                'description': 'Optional tactical details of the mission.',
              },
              'recurrence': <String, dynamic>{
                'type': 'STRING',
                'enum': <String>['NONE', 'DAILY', 'WEEKLY', 'MONTHLY'],
                'description': 'Optional recurrence frequency.',
              },
            },
            'required': <String>['title', 'start_iso'],
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
          'name': 'add_flag_dossier_entry',
          'description':
              'Records a new tactical intelligence entry or updates an existing target dossier in the persistent F.L.A.G. database (flag_dossiers.md). Use when the driver dictates new intel about a person, nickname, contact, or location.',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'targetName': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Name or nickname of the target, contact, or subject to record.',
              },
              'intelDetails': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Tactical details, profile, or intelligence note dictated by the driver.',
              },
            },
            'required': <String>['targetName', 'intelDetails'],
          },
        },
        <String, dynamic>{
          'name': 'send_flag_transmission_reply',
          'description':
              'Sends a direct voice-dictated reply to the most recent incoming F.L.A.G. transmission via the encrypted reply channel. Only call after the driver confirms the recipient and message text (unless explicit confirmation was already given).',
          'parameters': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'recipientName': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Name of the recipient of the transmission being replied to.',
              },
              'replyMessage': <String, dynamic>{
                'type': 'STRING',
                'description':
                    'Exact reply text confirmed by the driver to transmit.',
              },
            },
            'required': <String>['recipientName', 'replyMessage'],
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
