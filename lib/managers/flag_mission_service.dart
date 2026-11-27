import 'dart:collection';

import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadados de um calendário encontrado no dispositivo para seleção na UI.
class CalendarAccountInfo {
  const CalendarAccountInfo({
    required this.id,
    required this.name,
    required this.accountName,
    this.isReadOnly = false,
  });

  final String id;
  final String name;
  final String accountName;
  final bool isReadOnly;
}

/// Compromisso filtrado e limpo pronto para narração tática pelo K.I.T.T.
class FlagMissionItem {
  const FlagMissionItem({
    required this.eventId,
    required this.rawTitle,
    required this.cleanTitle,
    required this.description,
    required this.startTime,
    this.endTime,
    required this.calendarId,
    required this.calendarName,
  });

  final String eventId;
  final String rawTitle;
  final String cleanTitle;
  final String description;
  final DateTime startTime;
  final DateTime? endTime;
  final String calendarId;
  final String calendarName;

  int get startTimeMillis => startTime.millisecondsSinceEpoch;

  String get briefedKey => '${eventId}_${startTimeMillis}_briefed';
  String get upcomingKey => '${eventId}_${startTimeMillis}_upcoming';

  String get formattedTime {
    final DateTime local = startTime.toLocal();
    final String h = local.hour.toString().padLeft(2, '0');
    final String m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Resultado estruturado da criação de uma nova missão no calendário.
class MissionCreateResult {
  const MissionCreateResult({
    required this.success,
    required this.message,
    this.eventId = '',
    this.cleanTitle = '',
    this.storedTitle = '',
    this.startTime,
    this.endTime,
    this.calendarName = '',
    this.recurrence = 'NONE',
  });

  static const String hudConfirmation = 'MISSION LOGGED // F.L.A.G. DATABASE';

  final bool success;
  final String message;
  final String eventId;
  final String cleanTitle;
  final String storedTitle;
  final DateTime? startTime;
  final DateTime? endTime;
  final String calendarName;
  final String recurrence;

  Map<String, dynamic> toToolResponse() => <String, dynamic>{
        'status': success ? 'ok' : 'error',
        'event_id': eventId,
        'title': cleanTitle,
        'start_iso': startTime?.toIso8601String() ?? '',
        'end_iso': endTime?.toIso8601String() ?? '',
        'calendar': calendarName,
        'recurrence': recurrence,
        'message': message,
      };
}

/// Serviço 'DIRETRIZES E MISSÕES F.L.A.G.':
/// - Lê eventos das próximas 24h (incluindo recorrências expandidas) via `device_calendar`
/// - Aplica estratégia mista (todos os eventos da agenda selecionada OU apenas com tag `#flag`)
/// - Remove a tag do título antes de enviar à Gemini Live API
/// - Persiste chaves `{eventId}_{startTimeMillis}_briefed` e `_upcoming` no `SharedPreferences`
///   com limpeza automática de registros com mais de 48h.
class FlagMissionService {
  FlagMissionService({
    DeviceCalendarPlugin? calendarPlugin,
  }) : _calendarPlugin = calendarPlugin ?? DeviceCalendarPlugin();

  static const String _prefEnabled = 'kitt_missions_enabled';
  static const String _prefSelectedCalendars = 'kitt_missions_selected_calendars';
  static const String _prefRequireTag = 'kitt_missions_require_tag';
  static const String _prefTag = 'kitt_missions_tag';

  static const String defaultTag = '#flag';
  static const Duration dedupRetention = Duration(hours: 48);
  static const Duration proximityWindow = Duration(minutes: 15);

  final DeviceCalendarPlugin _calendarPlugin;

  bool _enabled = true;
  Set<String> _selectedCalendarIds = <String>{};
  bool _requireTag = false;
  String _tag = defaultTag;

  bool get enabled => _enabled;
  Set<String> get selectedCalendarIds =>
      Set<String>.unmodifiable(_selectedCalendarIds);
  bool get requireTag => _requireTag;
  String get tag => _tag;

  Future<void> init() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefEnabled) ?? true;
      _selectedCalendarIds =
          (prefs.getStringList(_prefSelectedCalendars) ?? const <String>[])
              .toSet();
      _requireTag = prefs.getBool(_prefRequireTag) ?? false;
      final String savedTag = (prefs.getString(_prefTag) ?? defaultTag).trim();
      _tag = savedTag.isEmpty ? defaultTag : savedTag;
      await cleanupExpiredDedupKeys(prefsOverride: prefs);
    } catch (_) {
      // Fallback seguro em ambientes sem SharedPreferences nativo.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, value);
    } catch (_) {}
  }

  Future<void> setCalendarSelected(String calendarId, bool selected) async {
    if (selected) {
      _selectedCalendarIds.add(calendarId);
    } else {
      _selectedCalendarIds.remove(calendarId);
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefSelectedCalendars,
        _selectedCalendarIds.toList(),
      );
    } catch (_) {}
  }

  Future<void> setRequireTag(bool value) async {
    _requireTag = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefRequireTag, value);
    } catch (_) {}
  }

  Future<void> setTag(String value) async {
    final String cleaned = value.trim().isEmpty ? defaultTag : value.trim();
    _tag = cleaned;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTag, cleaned);
    } catch (_) {}
  }

  /// Regra de filtragem mista (pura e testável).
  static bool matchesHybridFilter({
    required String title,
    String? description,
    required bool requireTag,
    required String tag,
  }) {
    if (title.trim().isEmpty) return false;
    if (!requireTag) return true;
    final String needle = tag.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final String haystackTitle = title.toLowerCase();
    final String haystackDesc = (description ?? '').toLowerCase();
    return haystackTitle.contains(needle) || haystackDesc.contains(needle);
  }

  /// Remove a tag (ex.: `#flag`, case-insensitive) do título para narração natural.
  static String cleanTitleForSpeech(String rawTitle, String tag) {
    final String needle = tag.trim();
    if (needle.isEmpty) return rawTitle.trim();
    final RegExp re = RegExp(RegExp.escape(needle), caseSensitive: false);
    final String stripped = rawTitle
        .replaceAll(re, ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s\-:|]+|[\s\-:|]+$'), '')
        .trim();
    return stripped.isEmpty ? rawTitle.trim() : stripped;
  }

  /// Retorna true quando a missão inicia entre agora e os próximos 15 minutos.
  static bool isWithinProximityWindow(
    DateTime startTime,
    DateTime now, {
    Duration window = proximityWindow,
  }) {
    final Duration diff = startTime.difference(now);
    return diff >= Duration.zero && diff <= window;
  }

  /// Aplica a tag discretamente ao final do título quando `requireTag` está ativo
  /// e o título ainda não contém a tag configurada.
  static String formatTitleForStorage(
    String title, {
    required bool requireTag,
    required String tag,
  }) {
    final String trimmed = title.trim();
    if (!requireTag) return trimmed;
    final String needle = tag.trim();
    if (needle.isEmpty) return trimmed;
    if (trimmed.toLowerCase().contains(needle.toLowerCase())) {
      return trimmed;
    }
    return '$trimmed $needle';
  }

  /// Converte `recurrenceType` (`DAILY`, `WEEKLY`, `MONTHLY`, `NONE`) em [RecurrenceRule].
  static RecurrenceRule? parseRecurrenceRule(String? recurrenceType) {
    switch (recurrenceType?.trim().toUpperCase()) {
      case 'DAILY':
        return RecurrenceRule(RecurrenceFrequency.Daily);
      case 'WEEKLY':
        return RecurrenceRule(RecurrenceFrequency.Weekly);
      case 'MONTHLY':
        return RecurrenceRule(RecurrenceFrequency.Monthly);
      default:
        return null;
    }
  }

  /// Gera a linha de referência de data/hora/dia da semana para a Gemini Live API
  /// calcular expressões relativas ("amanhã", "próxima segunda", "daqui a 2 horas").
  static String buildCurrentDateTimeContext([DateTime? now]) {
    final DateTime dt = (now ?? DateTime.now()).toLocal();
    const List<String> weekdaysPt = <String>[
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    final String weekday = weekdaysPt[(dt.weekday - 1).clamp(0, 6)];
    final String dd = dt.day.toString().padLeft(2, '0');
    final String mm = dt.month.toString().padLeft(2, '0');
    final String yyyy = dt.year.toString().padLeft(4, '0');
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String min = dt.minute.toString().padLeft(2, '0');
    return 'Referência temporal atual: $weekday, $dd/$mm/$yyyy às $hh:$min '
        '(ISO local: $yyyy-$mm-${dd}T$hh:$min:00).';
  }

  /// Cria uma nova missão no calendário selecionado (ou no padrão gravável),
  /// com suporte a tag híbrida, recorrência e marcação `_briefed` imediata.
  Future<MissionCreateResult> createMissionEvent({
    required String title,
    required DateTime startTime,
    int durationMinutes = 60,
    String? description,
    String? recurrenceType,
  }) async {
    final String rawCleanTitle = cleanTitleForSpeech(title, _tag);
    if (rawCleanTitle.isEmpty) {
      return const MissionCreateResult(
        success: false,
        message: 'Título da missão vazio.',
      );
    }

    bool granted = await hasCalendarPermission();
    if (!granted) {
      granted = await requestCalendarPermission();
    }
    if (!granted) {
      return const MissionCreateResult(
        success: false,
        message: 'Permissão de leitura/escrita de calendário não concedida.',
      );
    }

    try {
      final Result<UnmodifiableListView<Calendar>> calsRes =
          await _calendarPlugin.retrieveCalendars();
      final List<Calendar> allCals =
          calsRes.data?.toList() ?? const <Calendar>[];
      final List<Calendar> writableCals = allCals
          .where((Calendar c) => (c.id ?? '').isNotEmpty && c.isReadOnly != true)
          .toList();

      if (writableCals.isEmpty) {
        return const MissionCreateResult(
          success: false,
          message: 'Nenhuma agenda gravável encontrada no dispositivo.',
        );
      }

      // Prioriza a primeira agenda selecionada pelo usuário que seja gravável;
      // caso contrário, usa a agenda padrão gravável do aparelho.
      Calendar? targetCal;
      for (final Calendar c in writableCals) {
        if (_selectedCalendarIds.contains(c.id)) {
          targetCal = c;
          break;
        }
      }
      targetCal ??= writableCals.firstWhere(
        (Calendar c) => c.isDefault == true,
        orElse: () => writableCals.first,
      );

      final int safeDuration = durationMinutes > 0 ? durationMinutes : 60;
      final DateTime endTime =
          startTime.add(Duration(minutes: safeDuration));
      final String storedTitle = formatTitleForStorage(
        rawCleanTitle,
        requireTag: _requireTag,
        tag: _tag,
      );
      final RecurrenceRule? rule = parseRecurrenceRule(recurrenceType);
      final String normalizedRecurrence =
          (recurrenceType ?? 'NONE').trim().toUpperCase();

      final Event event = Event(
        targetCal.id,
        title: storedTitle,
        description: description?.trim(),
        start: TZDateTime.from(startTime, local),
        end: TZDateTime.from(endTime, local),
        recurrenceRule: rule,
      );

      final Result<String>? created =
          await _calendarPlugin.createOrUpdateEvent(event);
      final String eventId = created?.data?.trim() ?? '';
      if (created == null || !created.isSuccess || eventId.isEmpty) {
        return const MissionCreateResult(
          success: false,
          message: 'Não foi possível gravar a diretriz na agenda do dispositivo.',
        );
      }

      // Marca _briefed imediatamente para não repetir o briefing na sessão atual,
      // mantendo _upcoming livre para disparar o alerta de proximidade (15 min antes).
      final int startMs = startTime.millisecondsSinceEpoch;
      await markKey('${eventId}_${startMs}_briefed', startMs);

      final String calName =
          (targetCal.name ?? '').trim().isNotEmpty ? targetCal.name!.trim() : targetCal.id!;
      return MissionCreateResult(
        success: true,
        eventId: eventId,
        cleanTitle: rawCleanTitle,
        storedTitle: storedTitle,
        startTime: startTime,
        endTime: endTime,
        calendarName: calName,
        recurrence: rule != null ? normalizedRecurrence : 'NONE',
        message: 'Diretriz "$rawCleanTitle" registrada com sucesso.',
      );
    } catch (e) {
      return MissionCreateResult(
        success: false,
        message: 'Falha ao agendar diretriz: $e',
      );
    }
  }

  /// Monta o contexto silencioso / diretriz de briefing inicial das próximas 24h.
  static String buildInitialBriefingPrompt(List<FlagMissionItem> missions) {
    final StringBuffer list = StringBuffer();
    for (final FlagMissionItem m in missions) {
      list.writeln('- ${m.formattedTime}: ${m.cleanTitle}');
    }
    return '[SISTEMA — DIRETRIZES E MISSÕES F.L.A.G. (PRÓXIMAS 24H)]:\n'
        '${list.toString().trim()}\n'
        'Apresente brevemente estas diretrizes do dia em voz alta no personagem do K.I.T.T. '
        '(como um briefing tático da Fundação F.L.A.G. para o motorista). '
        'NUNCA mencione Google Calendar, agenda do celular, eventos ou tags.';
  }

  /// Monta o alerta de proximidade (15 minutos antes do início).
  static String buildUpcomingAlertPrompt(
    FlagMissionItem mission,
    int minutesRemaining,
  ) {
    final int clamped = minutesRemaining.clamp(0, 15);
    final String timePhrase = clamped <= 1
        ? 'agora mesmo'
        : 'em aproximadamente $clamped minutos (às ${mission.formattedTime})';
    return '[ALERTA TÁTICO F.L.A.G. — MISSÃO IMINENTE]: '
        'A diretriz "${mission.cleanTitle}" começa $timePhrase. '
        'Avise o motorista imediatamente em voz alta no personagem do K.I.T.T., '
        'de forma concisa e imersiva, sem mencionar calendário, celular ou tags.';
  }

  Future<bool> hasCalendarPermission() async {
    try {
      final Result<bool> pluginRes = await _calendarPlugin.hasPermissions();
      if (pluginRes.data == true) return true;
    } catch (_) {}
    try {
      final PermissionStatus status =
          await Permission.calendarFullAccess.status;
      if (status.isGranted) return true;
    } catch (_) {}
    // Fallback: em alguns aparelhos onde apenas READ_CALENDAR foi concedido,
    // tenta consultar as agendas diretamente.
    try {
      final Result<UnmodifiableListView<Calendar>> probe =
          await _calendarPlugin.retrieveCalendars();
      if (probe.isSuccess && probe.data != null) return true;
    } catch (_) {}
    return false;
  }

  Future<bool> requestCalendarPermission() async {
    try {
      final Result<bool> pluginRes = await _calendarPlugin.requestPermissions();
      if (pluginRes.data == true) return true;
    } catch (_) {}
    try {
      final PermissionStatus status =
          await Permission.calendarFullAccess.request();
      if (status.isGranted) return true;
    } catch (_) {}
    return hasCalendarPermission();
  }

  Future<List<CalendarAccountInfo>> listDeviceCalendars() async {
    final bool granted = await hasCalendarPermission();
    if (!granted) return const <CalendarAccountInfo>[];
    try {
      final Result<UnmodifiableListView<Calendar>> res =
          await _calendarPlugin.retrieveCalendars();
      final List<Calendar> cals = res.data?.toList() ?? const <Calendar>[];
      return cals
          .where((Calendar c) => (c.id ?? '').isNotEmpty)
          .map(
            (Calendar c) => CalendarAccountInfo(
              id: c.id!,
              name: (c.name ?? '').trim().isNotEmpty ? c.name!.trim() : c.id!,
              accountName: (c.accountName ?? '').trim(),
              isReadOnly: c.isReadOnly ?? false,
            ),
          )
          .toList()
        ..sort(
          (CalendarAccountInfo a, CalendarAccountInfo b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    } catch (_) {
      return const <CalendarAccountInfo>[];
    }
  }

  /// Busca os eventos das próximas 24 horas nos calendários selecionados,
  /// aplicando a filtragem mista e limpeza de tag para voz.
  Future<List<FlagMissionItem>> fetchNext24hMissions({DateTime? now}) async {
    if (_selectedCalendarIds.isEmpty) return const <FlagMissionItem>[];
    final bool granted = await hasCalendarPermission();
    if (!granted) return const <FlagMissionItem>[];

    final DateTime start = now ?? DateTime.now();
    final DateTime end = start.add(const Duration(hours: 24));

    final Map<String, String> calNames = <String, String>{};
    for (final CalendarAccountInfo c in await listDeviceCalendars()) {
      calNames[c.id] = c.name;
    }

    final List<FlagMissionItem> missions = <FlagMissionItem>[];
    for (final String calId in _selectedCalendarIds) {
      try {
        final Result<UnmodifiableListView<Event>> res =
            await _calendarPlugin.retrieveEvents(
          calId,
          RetrieveEventsParams(startDate: start, endDate: end),
        );
        final List<Event> events = res.data?.toList() ?? const <Event>[];
        for (final Event ev in events) {
          final String eventId = (ev.eventId ?? '').trim();
          final String rawTitle = (ev.title ?? '').trim();
          final DateTime? evStart = ev.start;
          if (eventId.isEmpty || rawTitle.isEmpty || evStart == null) continue;
          if (evStart.isBefore(start) || evStart.isAfter(end)) continue;

          if (!matchesHybridFilter(
            title: rawTitle,
            description: ev.description,
            requireTag: _requireTag,
            tag: _tag,
          )) {
            continue;
          }

          missions.add(
            FlagMissionItem(
              eventId: eventId,
              rawTitle: rawTitle,
              cleanTitle: cleanTitleForSpeech(rawTitle, _tag),
              description: (ev.description ?? '').trim(),
              startTime: evStart,
              endTime: ev.end,
              calendarId: calId,
              calendarName: calNames[calId] ?? calId,
            ),
          );
        }
      } catch (_) {
        // Ignora falha pontual em uma agenda e continua nas demais.
      }
    }

    missions.sort(
      (FlagMissionItem a, FlagMissionItem b) =>
          a.startTime.compareTo(b.startTime),
    );
    return missions;
  }

  /// Remove automaticamente chaves `_briefed` / `_upcoming` de eventos com mais de 48h.
  Future<int> cleanupExpiredDedupKeys({
    DateTime? now,
    SharedPreferences? prefsOverride,
  }) async {
    try {
      final SharedPreferences prefs =
          prefsOverride ?? await SharedPreferences.getInstance();
      final int cutoffMs =
          (now ?? DateTime.now()).subtract(dedupRetention).millisecondsSinceEpoch;
      int removed = 0;
      for (final String key in prefs.getKeys().toList()) {
        if (!key.endsWith('_briefed') && !key.endsWith('_upcoming')) continue;
        final int? eventTs = prefs.getInt(key);
        if (eventTs == null || eventTs < cutoffMs) {
          await prefs.remove(key);
          removed++;
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> isKeyMarked(
    String key, {
    SharedPreferences? prefsOverride,
  }) async {
    try {
      final SharedPreferences prefs =
          prefsOverride ?? await SharedPreferences.getInstance();
      return prefs.containsKey(key);
    } catch (_) {
      return false;
    }
  }

  Future<void> markKey(
    String key,
    int startTimeMillis, {
    SharedPreferences? prefsOverride,
  }) async {
    try {
      final SharedPreferences prefs =
          prefsOverride ?? await SharedPreferences.getInstance();
      await prefs.setInt(key, startTimeMillis);
    } catch (_) {}
  }

  /// Retorna as missões das próximas 24h pendentes de briefing (ou todas se `ignoreBriefedLock`).
  Future<List<FlagMissionItem>> getMissionsForBriefing({
    bool ignoreBriefedLock = false,
    DateTime? now,
    SharedPreferences? prefsOverride,
  }) async {
    if (!_enabled && !ignoreBriefedLock) return const <FlagMissionItem>[];
    await cleanupExpiredDedupKeys(now: now, prefsOverride: prefsOverride);
    final List<FlagMissionItem> all = await fetchNext24hMissions(now: now);
    if (ignoreBriefedLock) return all;

    final List<FlagMissionItem> pending = <FlagMissionItem>[];
    for (final FlagMissionItem m in all) {
      if (!await isKeyMarked(m.briefedKey, prefsOverride: prefsOverride)) {
        pending.add(m);
      }
    }
    return pending;
  }

  /// Marca todas as missões fornecidas como `_briefed`.
  Future<void> markBriefed(
    List<FlagMissionItem> missions, {
    SharedPreferences? prefsOverride,
  }) async {
    for (final FlagMissionItem m in missions) {
      await markKey(m.briefedKey, m.startTimeMillis, prefsOverride: prefsOverride);
    }
  }

  /// Retorna missões que estão a <= 15 minutos de iniciar e ainda não foram alertadas (`_upcoming`).
  Future<List<FlagMissionItem>> getDueUpcomingMissions({
    DateTime? now,
    SharedPreferences? prefsOverride,
  }) async {
    if (!_enabled) return const <FlagMissionItem>[];
    final DateTime ts = now ?? DateTime.now();
    await cleanupExpiredDedupKeys(now: ts, prefsOverride: prefsOverride);
    final List<FlagMissionItem> all = await fetchNext24hMissions(now: ts);

    final List<FlagMissionItem> due = <FlagMissionItem>[];
    for (final FlagMissionItem m in all) {
      if (!isWithinProximityWindow(m.startTime, ts)) continue;
      if (!await isKeyMarked(m.upcomingKey, prefsOverride: prefsOverride)) {
        due.add(m);
      }
    }
    return due;
  }

  Future<void> markUpcoming(
    FlagMissionItem mission, {
    SharedPreferences? prefsOverride,
  }) async {
    await markKey(
      mission.upcomingKey,
      mission.startTimeMillis,
      prefsOverride: prefsOverride,
    );
  }
}
