import 'package:flutter/material.dart';

import '../managers/aux_apps_manager.dart';
import '../managers/notification_filter_manager.dart';

/// Tela de opções 'COMUNICAÇÕES / FILTRO F.L.A.G.' para leitura seletiva de
/// notificações pelo K.I.T.T. durante a direção.
class CommsFilterPage extends StatefulWidget {
  const CommsFilterPage({
    super.key,
    required this.initialAllowedPackages,
    required this.initialAutoReadEnabled,
    required this.checkPermission,
    required this.openPermissionSettings,
    required this.loadInstalledApps,
    required this.onToggleAutoRead,
    required this.onTogglePackage,
  });

  final Set<String> initialAllowedPackages;
  final bool initialAutoReadEnabled;
  final Future<bool> Function() checkPermission;
  final Future<bool> Function() openPermissionSettings;
  final Future<List<InstalledAppEntry>> Function({bool includeSystemApps})
      loadInstalledApps;
  final Future<void> Function(bool enabled) onToggleAutoRead;
  final Future<void> Function(String packageName, bool allowed) onTogglePackage;

  @override
  State<CommsFilterPage> createState() => _CommsFilterPageState();
}

class _CommsFilterPageState extends State<CommsFilterPage>
    with WidgetsBindingObserver {
  late final TextEditingController _searchCtrl;
  late Set<String> _allowedPackages;
  late bool _autoReadEnabled;

  bool _permissionGranted = false;
  bool _checkingPermission = true;
  bool _includeSystemApps = true;
  bool _loadingApps = true;
  List<InstalledAppEntry> _allApps = const <InstalledAppEntry>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchCtrl = TextEditingController();
    _allowedPackages = Set<String>.from(widget.initialAllowedPackages);
    _autoReadEnabled = widget.initialAutoReadEnabled;
    _refreshPermission();
    _fetchApps();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
    }
  }

  Future<void> _refreshPermission() async {
    setState(() => _checkingPermission = true);
    final bool granted = await widget.checkPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _checkingPermission = false;
    });
  }

  Future<void> _fetchApps() async {
    setState(() => _loadingApps = true);
    final List<InstalledAppEntry> apps = await widget.loadInstalledApps(
      includeSystemApps: _includeSystemApps,
    );
    if (!mounted) return;
    setState(() {
      _allApps = NotificationFilterManager.sortAppsHighlightingMessaging(apps);
      _loadingApps = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<InstalledAppEntry> get _filteredApps {
    final String q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _allApps;
    return _allApps
        .where(
          (InstalledAppEntry a) =>
              a.name.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _handleAutoReadChanged(bool value) async {
    setState(() => _autoReadEnabled = value);
    await widget.onToggleAutoRead(value);
  }

  Future<void> _handlePackageToggled(String pkg, bool value) async {
    setState(() {
      if (value) {
        _allowedPackages.add(pkg);
      } else {
        _allowedPackages.remove(pkg);
      }
    });
    await widget.onTogglePackage(pkg, value);
  }

  @override
  Widget build(BuildContext context) {
    final List<InstalledAppEntry> visibleApps = _filteredApps;

    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        title: const Text(
          'COMUNICAÇÕES / FILTRO F.L.A.G.',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFFFF5252),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
            letterSpacing: 1.4,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Atualizar status da permissão',
            onPressed: _refreshPermission,
            icon: const Icon(Icons.refresh, color: Color(0xFFD0D0DC), size: 20),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            _buildPermissionStatusCard(),
            const SizedBox(height: 10),
            _buildMasterAutoReadCard(),
            const SizedBox(height: 12),
            _buildSearchAndFilterBar(),
            const SizedBox(height: 8),
            Expanded(
              child: _loadingApps
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF2424),
                      ),
                    )
                  : visibleApps.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum aplicativo encontrado.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: visibleApps.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (BuildContext context, int idx) {
                            return _buildAppTile(visibleApps[idx]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionStatusCard() {
    final Color accent = _permissionGranted
        ? const Color(0xFF00E676)
        : const Color(0xFFFFAB00);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: 0.7),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _permissionGranted
                    ? Icons.verified_user
                    : Icons.notifications_off_outlined,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _checkingPermission
                      ? 'VERIFICANDO ACESSO A NOTIFICAÇÕES...'
                      : _permissionGranted
                          ? 'ACESSO A NOTIFICAÇÕES: ATIVO'
                          : 'ACESSO A NOTIFICAÇÕES: DESATIVADO',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _permissionGranted
                ? 'O K.I.T.T. está autorizado pelo Android a interceptar apenas os apps marcados abaixo.'
                : 'Autorize o serviço "K.I.T.T. • Filtro F.L.A.G." nas configurações do Android para ler mensagens.',
            style: const TextStyle(color: Color(0xFFB5B5C2), fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () async {
                await widget.openPermissionSettings();
              },
              icon: const Icon(Icons.settings_applications, size: 18),
              label: Text(
                _permissionGranted
                    ? 'GERENCIAR PERMISSÃO NO ANDROID'
                    : 'ATIVAR ACESSO A NOTIFICAÇÕES',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterAutoReadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _autoReadEnabled
            ? const Color(0x22FF2424)
            : const Color(0xFF101018),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _autoReadEnabled
              ? const Color(0xFFFF5252)
              : const Color(0xFF343444),
          width: 1.3,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _autoReadEnabled ? Icons.record_voice_over : Icons.voice_over_off,
            color: _autoReadEnabled
                ? const Color(0xFFFF5252)
                : const Color(0xFF8A8A9E),
            size: 22,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'LEITURA AUTOMÁTICA DE MENSAGENS',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ativa ou silencia a leitura em voz alta durante a direção',
                  style: TextStyle(color: Color(0xFFA0A0B2), fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey<String>('flag_master_auto_read_switch'),
            value: _autoReadEnabled,
            activeColor: const Color(0xFFFF2424),
            onChanged: _handleAutoReadChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filtrar apps (WhatsApp, Telegram, SMS...)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
              filled: true,
              fillColor: const Color(0xFF12121A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF2E2E3C)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF2E2E3C)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text(
            'SISTEMA',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          selected: _includeSystemApps,
          selectedColor: const Color(0x44FF5252),
          checkmarkColor: const Color(0xFFFF5252),
          backgroundColor: const Color(0xFF14141E),
          labelStyle: TextStyle(
            color: _includeSystemApps ? const Color(0xFFFF8A80) : Colors.white60,
          ),
          onSelected: (bool v) {
            setState(() => _includeSystemApps = v);
            _fetchApps();
          },
        ),
      ],
    );
  }

  Widget _buildAppTile(InstalledAppEntry app) {
    final bool allowed = _allowedPackages.contains(app.packageName);
    final bool isMessaging = NotificationFilterManager.isMessagingApp(app);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: allowed
            ? const Color(0x2000E676)
            : isMessaging
                ? const Color(0x16FFB300)
                : const Color(0xFF0E0E15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: allowed
              ? const Color(0xFF00E676)
              : isMessaging
                  ? const Color(0x88FFB300)
                  : const Color(0xFF262634),
          width: allowed || isMessaging ? 1.2 : 0.9,
        ),
      ),
      child: Row(
        children: <Widget>[
          if (app.icon != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                app.icon!,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C28),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isMessaging ? Icons.chat_bubble_outline : Icons.apps,
                color: isMessaging
                    ? const Color(0xFFFFD54F)
                    : Colors.white54,
                size: 18,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isMessaging) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x33FFB300),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFFB300)),
                        ),
                        child: const Text(
                          'MENSAGENS',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFFFD54F),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A8A9E),
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: ValueKey<String>('flag_app_switch_${app.packageName}'),
            value: allowed,
            activeColor: const Color(0xFF00E676),
            onChanged: (bool value) =>
                _handlePackageToggled(app.packageName, value),
          ),
        ],
      ),
    );
  }
}
