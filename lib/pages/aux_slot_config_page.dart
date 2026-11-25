import 'package:flutter/material.dart';

import '../managers/aux_apps_manager.dart';
import '../models/aux_slot_config.dart';

/// Tela de configuração de um slot auxiliar do painel do KITT.
///
/// Permite:
/// - Escolher um aplicativo instalado no dispositivo (com busca)
/// - Definir um rótulo curto estilo HUD (ex.: 'NAVEGAÇÃO', 'ÁUDIO', 'COMMS')
/// - Selecionar um ícone HUD
/// - Limpar o vínculo do slot
class AuxSlotConfigPage extends StatefulWidget {
  const AuxSlotConfigPage({
    super.key,
    required this.initialConfig,
    required this.loadInstalledApps,
  });

  final AuxSlotConfig initialConfig;
  final Future<List<InstalledAppEntry>> Function({bool includeSystemApps})
      loadInstalledApps;

  @override
  State<AuxSlotConfigPage> createState() => _AuxSlotConfigPageState();
}

class _AuxSlotConfigPageState extends State<AuxSlotConfigPage> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _manualPkgCtrl;

  late String _selectedIconId;
  String _selectedPackage = '';
  String _selectedAppName = '';
  bool _includeSystemApps = false;
  bool _loadingApps = true;
  List<InstalledAppEntry> _allApps = const <InstalledAppEntry>[];

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialConfig.label);
    _searchCtrl = TextEditingController();
    _manualPkgCtrl =
        TextEditingController(text: widget.initialConfig.packageName);
    _selectedIconId = widget.initialConfig.iconId;
    _selectedPackage = widget.initialConfig.packageName;
    _selectedAppName = widget.initialConfig.appName;
    _fetchApps();
  }

  Future<void> _fetchApps() async {
    setState(() => _loadingApps = true);
    final List<InstalledAppEntry> apps = await widget.loadInstalledApps(
      includeSystemApps: _includeSystemApps,
    );
    if (!mounted) return;
    setState(() {
      _allApps = apps;
      _loadingApps = false;
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _manualPkgCtrl.dispose();
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

  void _save() {
    final String pkg = _selectedPackage.trim().isNotEmpty
        ? _selectedPackage.trim()
        : _manualPkgCtrl.text.trim();
    final AuxHudIcon icon = AuxHudIcon.fromId(_selectedIconId);
    final String label = _labelCtrl.text.trim().isNotEmpty
        ? _labelCtrl.text.trim().toUpperCase()
        : icon.defaultLabel;

    Navigator.of(context).pop(
      widget.initialConfig.copyWith(
        label: label,
        packageName: pkg,
        appName: _selectedAppName.isNotEmpty ? _selectedAppName : pkg,
        iconId: _selectedIconId,
      ),
    );
  }

  void _clearSlot() {
    Navigator.of(context).pop(widget.initialConfig.cleared());
  }

  @override
  Widget build(BuildContext context) {
    final List<InstalledAppEntry> visibleApps = _filteredApps;

    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        title: Text(
          'CONFIGURAR SLOT AUX 0${widget.initialConfig.slotNumber}',
          style: const TextStyle(
            color: Color(0xFFFF5252),
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.6,
          ),
        ),
        actions: <Widget>[
          if (widget.initialConfig.isConfigured)
            TextButton(
              onPressed: _clearSlot,
              child: const Text(
                'LIMPAR',
                style: TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 1. Rótulo curto HUD
              TextField(
                controller: _labelCtrl,
                maxLength: 12,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rótulo curto no HUD (ex.: NAVEGAÇÃO, ÁUDIO, COMMS)',
                  labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                  counterStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),

              // 2. Seletor de ícone HUD
              const Text(
                'ÍCONE ESTILO HUD',
                style: TextStyle(
                  color: Color(0xFF9E9EB2),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AuxHudIcon.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int i) {
                    final AuxHudIcon item = AuxHudIcon.values[i];
                    final bool selected = item.id == _selectedIconId;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIconId = item.id;
                          if (_labelCtrl.text.trim().isEmpty) {
                            _labelCtrl.text = item.defaultLabel;
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 68,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? item.accentColor.withValues(alpha: 0.25)
                              : const Color(0xFF12121A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? item.accentColor
                                : const Color(0xFF2B2B38),
                            width: selected ? 1.8 : 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(item.iconData, color: item.accentColor, size: 18),
                            const SizedBox(height: 2),
                            Text(
                              item.defaultLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),

              // 3. Busca de aplicativos instalados
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Buscar app instalado (Waze, Spotify...)',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Sistema', style: TextStyle(fontSize: 11)),
                    selected: _includeSystemApps,
                    onSelected: (bool v) {
                      setState(() => _includeSystemApps = v);
                      _fetchApps();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 4. Lista de aplicativos ou fallback manual
              Expanded(
                child: _loadingApps
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF2424),
                        ),
                      )
                    : visibleApps.isEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Nenhum aplicativo listado. Você pode informar o packageName manualmente (ex.: com.waze, com.spotify.music):',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _manualPkgCtrl,
                                onChanged: (String v) {
                                  setState(() {
                                    _selectedPackage = v.trim();
                                    _selectedAppName = v.trim();
                                  });
                                },
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Package Name Android',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: visibleApps.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: Color(0xFF1C1C26)),
                            itemBuilder: (BuildContext context, int i) {
                              final InstalledAppEntry app = visibleApps[i];
                              final bool selected =
                                  app.packageName == _selectedPackage;
                              return ListTile(
                                dense: true,
                                selected: selected,
                                selectedTileColor: const Color(0x28FF2424),
                                leading: app.icon != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.memory(
                                          app.icon!,
                                          width: 34,
                                          height: 34,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.android,
                                        color: Color(0xFF69F0AE),
                                      ),
                                title: Text(
                                  app.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  app.packageName,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Color(0xFFFF2424),
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedPackage = app.packageName;
                                    _selectedAppName = app.name;
                                    _manualPkgCtrl.text = app.packageName;
                                    if (_labelCtrl.text.trim().isEmpty) {
                                      _labelCtrl.text = app.name
                                          .split(' ')
                                          .first
                                          .toUpperCase();
                                    }
                                  });
                                },
                              );
                            },
                          ),
              ),
              const SizedBox(height: 10),

              // 5. Botão salvar
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedPackage.trim().isEmpty &&
                          _manualPkgCtrl.text.trim().isEmpty
                      ? null
                      : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'SALVAR NO PAINEL KITT',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
