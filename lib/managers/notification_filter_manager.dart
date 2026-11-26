import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aux_apps_manager.dart';

/// Notificação filtrada pelo sistema F.L.A.G. pronta para leitura pelo K.I.T.T.
class IncomingNotificationEvent {
  const IncomingNotificationEvent({
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.timestamp,
    this.notificationKey = '',
    this.canReply = false,
  });

  final String packageName;
  final String appName;
  final String title;
  final String text;
  final DateTime timestamp;
  final String notificationKey;
  final bool canReply;

  static const String hudBannerTitle =
      'INCOMING TRANSMISSION // F.L.A.G. ENCRYPTED CHANNEL';

  String toGeminiPrompt() {
    return '[TRANSMISSÃO F.L.A.G. RECEBIDA | Canal: $appName | Remetente: $title | Conteúdo: $text]. '
        'Instrução: Avise imediatamente que há uma transmissão recebida na frequência da F.L.A.G. '
        'vinda de $title e leia ou resuma o conteúdo de forma natural, tática e 100% dentro do '
        'personagem KITT, sem mencionar celulares, Android ou notificações.';
  }
}

/// Fila simples (FIFO) de transmissões F.L.A.G. para evitar atropelar falas do KITT.
/// Se uma nova mensagem chegar enquanto o KITT está falando, fica na fila até a
/// conclusão do turno atual.
class FlagTransmissionQueue {
  FlagTransmissionQueue({
    required this.isBusySpeaking,
    required this.onDeliver,
    this.maxInFlightDuration = const Duration(seconds: 12),
  });

  final bool Function() isBusySpeaking;
  final void Function(IncomingNotificationEvent event) onDeliver;
  final Duration maxInFlightDuration;

  final Queue<IncomingNotificationEvent> _pending =
      Queue<IncomingNotificationEvent>();
  bool _inFlight = false;
  Timer? _safetyTimer;

  int get pendingCount => _pending.length;
  bool get hasInFlight => _inFlight;

  void enqueue(IncomingNotificationEvent event) {
    if (_inFlight || isBusySpeaking()) {
      _pending.addLast(event);
      return;
    }
    _deliverNow(event);
  }

  /// Deve ser chamado quando o KITT concluir a fala atual (`turnComplete` / fim do áudio).
  void notifySpeechCompleted() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _inFlight = false;
    if (_pending.isNotEmpty && !isBusySpeaking()) {
      _deliverNow(_pending.removeFirst());
    }
  }

  void _deliverNow(IncomingNotificationEvent event) {
    _inFlight = true;
    _safetyTimer?.cancel();
    _safetyTimer = Timer(maxInFlightDuration, notifySpeechCompleted);
    onDeliver(event);
  }

  void clear() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _inFlight = false;
    _pending.clear();
  }
}

/// Gerencia o filtro seletivo de notificações (F.L.A.G.) via MethodChannel nativo
/// (`com.kitt.project/notifications`) e persistência local (`shared_preferences`).
class NotificationFilterManager {
  NotificationFilterManager({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.kitt.project/notifications';
  static const String _allowedPackagesKey = 'kitt_flag_allowed_packages_v1';
  static const String _autoReadEnabledKey = 'kitt_flag_auto_read_enabled_v1';

  static const Set<String> _knownMessagingPackages = <String>{
    'com.whatsapp',
    'com.whatsapp.w4b',
    'org.telegram.messenger',
    'org.telegram.messenger.web',
    'com.google.android.apps.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
    'com.facebook.orca',
    'org.thoughtcrime.securesms',
    'com.discord',
    'com.Slack',
    'com.microsoft.teams',
    'com.instagram.android',
  };

  final MethodChannel _channel;
  final StreamController<IncomingNotificationEvent> _incomingController =
      StreamController<IncomingNotificationEvent>.broadcast();

  Set<String> _allowedPackages = <String>{};
  bool _autoReadEnabled = true;
  bool _attached = false;
  final Map<String, DateTime> _recentSignatures = <String, DateTime>{};
  static const Duration _dedupWindow = Duration(seconds: 8);

  static final List<RegExp> _groupSummaryPatterns = <RegExp>[
    RegExp(r'^\d+\s+(novas?\s+mensagens?|new\s+messages?)', caseSensitive: false),
    RegExp(r'^\d+\s+mensagens?\s+de\s+\d+\s+conversas?', caseSensitive: false),
    RegExp(r'^\d+\s+messages?\s+from\s+\d+\s+chats?', caseSensitive: false),
    RegExp(r'^(verificando|checking\s+for)\s+(novas?\s+mensagens?|new\s+messages?)', caseSensitive: false),
  ];

  /// Retorna `true` se o texto parecer um resumo genérico de grupo/contagem sem conteúdo real.
  static bool isEmptyOrGroupSummaryText(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    for (final RegExp pattern in _groupSummaryPatterns) {
      if (pattern.hasMatch(trimmed)) return true;
    }
    return false;
  }

  Set<String> get allowedPackages => Set<String>.unmodifiable(_allowedPackages);
  bool get autoReadEnabled => _autoReadEnabled;
  Stream<IncomingNotificationEvent> get incomingNotifications =>
      _incomingController.stream;

  /// Retorna `true` se o app for um mensageiro conhecido (WhatsApp, SMS, Telegram, etc.).
  static bool isMessagingApp(InstalledAppEntry app) {
    final String pkg = app.packageName.toLowerCase();
    if (_knownMessagingPackages.contains(app.packageName) ||
        _knownMessagingPackages.contains(pkg)) {
      return true;
    }
    final String name = app.name.toLowerCase();
    return pkg.contains('whatsapp') ||
        pkg.contains('telegram') ||
        pkg.contains('messaging') ||
        pkg.contains('sms') ||
        name.contains('whatsapp') ||
        name.contains('telegram') ||
        name.contains('mensagen') ||
        name.contains('messages') ||
        name.contains('sms') ||
        name.contains('signal') ||
        name.contains('messenger');
  }

  /// Ordena os apps colocando mensageiros conhecidos em destaque no topo.
  static List<InstalledAppEntry> sortAppsHighlightingMessaging(
    List<InstalledAppEntry> apps,
  ) {
    final List<InstalledAppEntry> copy = List<InstalledAppEntry>.from(apps);
    copy.sort((InstalledAppEntry a, InstalledAppEntry b) {
      final bool aMsg = isMessagingApp(a);
      final bool bMsg = isMessagingApp(b);
      if (aMsg != bMsg) return aMsg ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }

  /// Carrega as preferências salvas e conecta o listener nativo de notificações.
  Future<void> init() async {
    await loadSettings();
    if (!_attached) {
      _attached = true;
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<void> loadSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? savedPkgs = prefs.getStringList(_allowedPackagesKey);
      if (savedPkgs != null) {
        _allowedPackages = savedPkgs.toSet();
      }
      _autoReadEnabled = prefs.getBool(_autoReadEnabledKey) ?? true;
    } catch (_) {
      // Mantém defaults seguros em ambientes sem SharedPreferences nativo.
    }
    await _syncAllowedPackagesToNative();
  }

  Future<void> _syncAllowedPackagesToNative() async {
    try {
      await _channel.invokeMethod<void>(
        'syncAllowedPackages',
        <String, dynamic>{'packages': _allowedPackages.toList()},
      );
    } catch (_) {
      // Ignora em ambientes de teste sem canal nativo.
    }
  }

  Future<void> setAutoReadEnabled(bool enabled) async {
    _autoReadEnabled = enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoReadEnabledKey, enabled);
    } catch (_) {}
  }

  Future<void> setPackageAllowed(String packageName, bool allowed) async {
    final String pkg = packageName.trim();
    if (pkg.isEmpty) return;
    final Set<String> next = Set<String>.from(_allowedPackages);
    if (allowed) {
      next.add(pkg);
    } else {
      next.remove(pkg);
    }
    _allowedPackages = next;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_allowedPackagesKey, _allowedPackages.toList());
    } catch (_) {}
    await _syncAllowedPackagesToNative();
  }

  /// Dispara a resposta direta (`RemoteInput` + `PendingIntent.send`) para a
  /// última transmissão autorizada armazenada em `LastNotificationCache`.
  Future<Map<String, dynamic>> replyToLastNotification(String messageText) async {
    final String clean = messageText.trim();
    if (clean.isEmpty) {
      return const <String, dynamic>{
        'success': false,
        'error': 'empty_message',
        'message': 'O texto da resposta não pode estar vazio.',
      };
    }
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'replyToLastNotification',
        <String, dynamic>{'messageText': clean},
      );
      if (raw == null) {
        return const <String, dynamic>{
          'success': false,
          'error': 'no_response',
          'message': 'Sem resposta do serviço nativo de notificações.',
        };
      }
      return raw.map<String, dynamic>(
        (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'channel_error',
        'message': 'Falha ao comunicar com o canal nativo: $e',
      };
    }
  }

  Future<bool> isPermissionGranted() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'isNotificationAccessGranted',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openPermissionSettings() async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openNotificationAccessSettings',
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Processa uma notificação recebida e emite no stream apenas se passar no filtro F.L.A.G.:
  /// (a) leitura automática ativa,
  /// (b) packageName autorizado,
  /// (c) não é resumo de grupo vazio nem duplicada dentro da janela de deduplicação,
  /// (d) possui title (remetente) e text (conteúdo) válidos.
  bool processIncomingNotification({
    required String packageName,
    required String appName,
    required String title,
    required String text,
    DateTime? timestamp,
    String notificationKey = '',
    bool canReply = false,
  }) {
    if (!_autoReadEnabled) return false;
    if (!_allowedPackages.contains(packageName)) return false;

    final String cleanTitle = title.trim();
    final String cleanText = text.trim();
    if (cleanTitle.isEmpty || isEmptyOrGroupSummaryText(cleanText)) {
      return false;
    }

    final DateTime now = timestamp ?? DateTime.now();
    final String sig = '$packageName|$cleanTitle|$cleanText';
    final DateTime? previous = _recentSignatures[sig];
    if (previous != null && now.difference(previous).abs() < _dedupWindow) {
      return false;
    }
    _recentSignatures[sig] = now;
    if (_recentSignatures.length > 40) {
      _recentSignatures.removeWhere(
        (_, DateTime ts) => now.difference(ts).abs() >= _dedupWindow,
      );
    }

    if (!_incomingController.isClosed) {
      _incomingController.add(
        IncomingNotificationEvent(
          packageName: packageName,
          appName: appName.isNotEmpty ? appName : packageName,
          title: cleanTitle,
          text: cleanText,
          timestamp: now,
          notificationKey: notificationKey,
          canReply: canReply,
        ),
      );
    }
    return true;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNotificationPosted') {
      final Map<Object?, Object?>? args =
          call.arguments as Map<Object?, Object?>?;
      if (args == null) return false;
      final String notificationKey = args['notificationKey'] as String? ?? '';
      final String pkg = args['packageName'] as String? ?? '';
      final String appName = args['appName'] as String? ?? pkg;
      final String title = args['title'] as String? ?? '';
      final String text = args['text'] as String? ?? '';
      final int? tsMs = args['timestamp'] as int?;
      final bool canReply = args['canReply'] == true;
      return processIncomingNotification(
        packageName: pkg,
        appName: appName,
        title: title,
        text: text,
        timestamp: tsMs != null
            ? DateTime.fromMillisecondsSinceEpoch(tsMs)
            : DateTime.now(),
        notificationKey: notificationKey,
        canReply: canReply,
      );
    }
    return null;
  }

  void dispose() {
    if (_attached) {
      _channel.setMethodCallHandler(null);
      _attached = false;
    }
    _incomingController.close();
  }
}
