import 'package:flutter/material.dart';

import '../managers/flag_mission_service.dart';

/// Tela de opções 'MISSÕES / CALENDÁRIO F.L.A.G.' seguindo o mesmo padrão visual
/// do filtro de comunicações (F.L.A.G. HUD retrô).
class FlagMissionsPage extends StatefulWidget {
  const FlagMissionsPage({
    super.key,
    required this.initialEnabled,
    required this.initialSelectedCalendarIds,
    required this.initialRequireTag,
    required this.initialTag,
    required this.hasPermission,
    required this.requestPermission,
    required this.loadCalendars,
    required this.onToggleEnabled,
    required this.onToggleCalendar,
    required this.onToggleRequireTag,
    required this.onChangeTag,
    required this.onForceBriefingNow,
  });

  final bool initialEnabled;
  final Set<String> initialSelectedCalendarIds;
  final bool initialRequireTag;
  final String initialTag;
  final Future<bool> Function() hasPermission;
  final Future<bool> Function() requestPermission;
  final Future<List<CalendarAccountInfo>> Function() loadCalendars;
  final Future<void> Function(bool enabled) onToggleEnabled;
  final Future<void> Function(String calendarId, bool selected) onToggleCalendar;
  final Future<void> Function(bool requireTag) onToggleRequireTag;
  final Future<void> Function(String tag) onChangeTag;
  final Future<int> Function() onForceBriefingNow;

  @override
  State<FlagMissionsPage> createState() => _FlagMissionsPageState();
}

class _FlagMissionsPageState extends State<FlagMissionsPage>
    with WidgetsBindingObserver {
  late bool _enabled;
  late Set<String> _selectedIds;
  late bool _requireTag;
  late final TextEditingController _tagCtrl;

  bool _hasPermission = false;
  bool _loading = true;
  bool _forcing = false;
  List<CalendarAccountInfo> _calendars = const <CalendarAccountInfo>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enabled = widget.initialEnabled;
    _selectedIds = Set<String>.from(widget.initialSelectedCalendarIds);
    _requireTag = widget.initialRequireTag;
    _tagCtrl = TextEditingController(text: widget.initialTag);
    _refreshState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshState() async {
    setState(() => _loading = true);
    final bool granted = await widget.hasPermission();
    final List<CalendarAccountInfo> cals = granted
        ? await widget.loadCalendars()
        : const <CalendarAccountInfo>[];
    if (!mounted) return;
    setState(() {
      _hasPermission = granted;
      _calendars = cals;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    final bool granted = await widget.requestPermission();
    if (!mounted) return;
    if (granted) {
      await _refreshState();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2B0E12),
          content: Text(
            'PERMISSÃO DE CALENDÁRIO NEGADA. ATIVE NAS CONFIGURAÇÕES DO ANDROID.',
            style: TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFFFF8A80),
              fontSize: 11.5,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _forceBriefing() async {
    setState(() => _forcing = true);
    final int count = await widget.onForceBriefingNow();
    if (!mounted) return;
    setState(() => _forcing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF14141E),
        content: Text(
          count > 0
              ? 'BRIEFING DISPARADO // $count DIRETRIZ(ES) ENVIADA(S) AO K.I.T.T.'
              : 'NENHUMA MISSÃO ENCONTRADA NAS PRÓXIMAS 24H.',
          style: TextStyle(
            fontFamily: 'monospace',
            color: count > 0
                ? const Color(0xFF69F0AE)
                : const Color(0xFFFFD54F),
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'MISSÕES / CALENDÁRIO F.L.A.G.',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              'DIRETRIZES E ALERTAS DE PROXIMIDADE (15 MIN)',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFFFFD54F),
                fontSize: 9.5,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 1. Banner de permissão READ_CALENDAR
              if (!_hasPermission && !_loading) ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x28FF1744),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF5252)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ACESSO AO CALENDÁRIO NECESSÁRIO',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFFF8A80),
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Autorize a leitura das agendas do dispositivo para o K.I.T.T. monitorar diretrizes e missões F.L.A.G.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF1744),
                          ),
                          onPressed: _requestPermission,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text('CONCEDER PERMISSÃO'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 2. Switch geral: ATIVAR BRIEFING DE MISSÕES
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF282836)),
                ),
                child: SwitchListTile(
                  activeThumbColor: const Color(0xFFFF2424),
                  activeTrackColor: const Color(0x66FF2424),
                  title: const Text(
                    'ATIVAR BRIEFING DE MISSÕES',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                  subtitle: const Text(
                    'Briefing inicial (24h) ao conectar + alerta 15 min antes.',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  value: _enabled,
                  onChanged: (bool v) async {
                    setState(() => _enabled = v);
                    await widget.onToggleEnabled(v);
                  },
                ),
              ),
              const SizedBox(height: 10),

              // 3. Filtro híbrido por tag
              Container(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF282836)),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      dense: true,
                      activeThumbColor: const Color(0xFFFFD54F),
                      activeTrackColor: const Color(0x66FFD54F),
                      title: const Text(
                        'EXIGIR TAG NO TÍTULO DO EVENTO',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFFFD54F),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          letterSpacing: 0.8,
                        ),
                      ),
                      subtitle: const Text(
                        'Desativado: lê todos os eventos das agendas marcadas.',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      value: _requireTag,
                      onChanged: (bool v) async {
                        setState(() => _requireTag = v);
                        await widget.onToggleRequireTag(v);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _tagCtrl,
                        enabled: _requireTag,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Tag de filtragem (padrão: #flag)',
                          labelStyle: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (String v) => widget.onChangeTag(v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. Botão de teste: FORÇAR BRIEFING AGORA
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('force_mission_briefing_btn'),
                  onPressed: _forcing ? null : _forceBriefing,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xAA00E5FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: Text(
                    _forcing
                        ? 'CONSULTANDO DIRETRIZES...'
                        : 'FORÇAR BRIEFING AGORA',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 5. Lista de calendários do aparelho
              const Text(
                'AGENDAS MONITORADAS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF9E9EB2),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF2424),
                        ),
                      )
                    : _calendars.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhuma agenda encontrada no dispositivo.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12.5,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _calendars.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFF1C1C26),
                            ),
                            itemBuilder: (BuildContext context, int i) {
                              final CalendarAccountInfo cal = _calendars[i];
                              final bool selected =
                                  _selectedIds.contains(cal.id);
                              return CheckboxListTile(
                                dense: true,
                                activeColor: const Color(0xFFFF2424),
                                checkColor: Colors.white,
                                title: Text(
                                  cal.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  cal.accountName.isNotEmpty
                                      ? cal.accountName
                                      : 'Agenda local',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                value: selected,
                                onChanged: (bool? v) async {
                                  final bool next = v ?? false;
                                  setState(() {
                                    if (next) {
                                      _selectedIds.add(cal.id);
                                    } else {
                                      _selectedIds.remove(cal.id);
                                    }
                                  });
                                  await widget.onToggleCalendar(cal.id, next);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
