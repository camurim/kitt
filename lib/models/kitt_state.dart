/// Estados centrais do painel do KITT e da sessão Gemini Live.

enum DriveMode {
  normalCruise,
  autoCruise,
  pursuit;

  String get label => switch (this) {
        DriveMode.normalCruise => 'NORMAL CRUISE',
        DriveMode.autoCruise => 'AUTO CRUISE',
        DriveMode.pursuit => 'PURSUIT',
      };

  String get apiValue => switch (this) {
        DriveMode.normalCruise => 'normal',
        DriveMode.autoCruise => 'auto_cruise',
        DriveMode.pursuit => 'pursuit',
      };

  static DriveMode fromApiValue(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'auto_cruise':
      case 'auto':
        return DriveMode.autoCruise;
      case 'pursuit':
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
        LiveConnectionState.connecting => 'CONNECTING...',
        LiveConnectionState.ready => 'ONLINE • GEMINI LIVE',
        LiveConnectionState.error => 'LINK ERROR',
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
