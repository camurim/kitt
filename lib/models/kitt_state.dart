/// Estados centrais do painel do KITT e da sessão Gemini Live.

enum DriveMode {
  normalCruise,
  autoCruise,
  surveillance,
  pursuit;

  String get label => switch (this) {
        DriveMode.normalCruise => 'NORMAL CRUISE',
        DriveMode.autoCruise => 'AUTO CRUISE',
        DriveMode.surveillance => 'SURVEILLANCE MODE',
        DriveMode.pursuit => 'PURSUIT MODE',
      };

  String get apiValue => switch (this) {
        DriveMode.normalCruise => 'normal',
        DriveMode.autoCruise => 'auto_cruise',
        DriveMode.surveillance => 'surveillance',
        DriveMode.pursuit => 'pursuit',
      };

  static DriveMode fromApiValue(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'auto_cruise':
      case 'auto':
        return DriveMode.autoCruise;
      case 'surveillance':
      case 'vigilancia':
      case 'vigilância':
      case 'radar':
        return DriveMode.surveillance;
      case 'pursuit':
      case 'perseguicao':
      case 'perseguição':
        return DriveMode.pursuit;
      default:
        return DriveMode.normalCruise;
    }
  }
}

enum LiveConnectionState {
  disconnected,
  connecting,
  ready,
  error;

  String get label => switch (this) {
        LiveConnectionState.disconnected => 'OFFLINE',
        LiveConnectionState.connecting => 'CONECTANDO',
        LiveConnectionState.ready => 'ONLINE',
        LiveConnectionState.error => 'OFFLINE',
      };
}

class KittActionEvent {
  const KittActionEvent({
    required this.code,
    required this.title,
    required this.detail,
    required this.timestamp,
  });

  final String code;
  final String title;
  final String detail;
  final DateTime timestamp;
}

class GeminiToolCall {
  const GeminiToolCall({
    required this.id,
    required this.name,
    required this.args,
  });

  final String id;
  final String name;
  final Map<String, dynamic> args;
}

/// Gadgets clássicos do KITT com animação em tela cheia e integração Gemini Live.
enum GadgetType {
  oilSlick,
  smokeScreen,
  turboBoost,
  microJam,
  skiMode,
  scanner;

  String get toolName => switch (this) {
        GadgetType.oilSlick => 'deploy_oil_slick',
        GadgetType.smokeScreen => 'activate_smoke_screen',
        GadgetType.turboBoost => 'trigger_turbo_boost',
        GadgetType.microJam => 'trigger_micro_jam',
        GadgetType.skiMode => 'activate_ski_mode',
        GadgetType.scanner => 'run_structural_scan',
      };

  String get label => switch (this) {
        GadgetType.oilSlick => 'OIL SLICK',
        GadgetType.smokeScreen => 'SMOKE SCREEN',
        GadgetType.turboBoost => 'TURBO BOOST',
        GadgetType.microJam => 'MICRO JAM',
        GadgetType.skiMode => 'SKI MODE',
        GadgetType.scanner => 'SCANNER',
      };

  String get hudAlert => switch (this) {
        GadgetType.oilSlick => 'OIL SLICK DEPLOYED • TRACTION HAZARD',
        GadgetType.smokeScreen => 'SMOKE SCREEN ACTIVE • VISIBILITY 0%',
        GadgetType.turboBoost => 'TURBO BOOST ENGAGED • MAX THRUST',
        GadgetType.microJam => 'MICRO JAM ACTIVE • EMP INTERFERENCE',
        GadgetType.skiMode => 'SKI MODE ENGAGED • 45° TWO-WHEEL BALANCE',
        GadgetType.scanner => 'STRUCTURAL SCAN • TACTICAL TELEMETRY',
      };

  String get sfxAsset => switch (this) {
        GadgetType.oilSlick => 'audio/oil_slick.mp3',
        GadgetType.smokeScreen => 'audio/smoke_screen.mp3',
        GadgetType.turboBoost => 'audio/turbo_boost.mp3',
        GadgetType.microJam => 'audio/micro_jam.mp3',
        GadgetType.skiMode => 'audio/ski_mode.mp3',
        GadgetType.scanner => 'audio/scanner.mp3',
      };

  Duration get duration => switch (this) {
        GadgetType.oilSlick => const Duration(milliseconds: 3600),
        GadgetType.smokeScreen => const Duration(milliseconds: 3900),
        GadgetType.turboBoost => const Duration(milliseconds: 3500),
        GadgetType.microJam => const Duration(milliseconds: 3600),
        GadgetType.skiMode => const Duration(milliseconds: 3800),
        GadgetType.scanner => const Duration(milliseconds: 3900),
      };
}
