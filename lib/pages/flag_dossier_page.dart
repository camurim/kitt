import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../managers/flag_dossier_service.dart';

/// Terminal retrô anos 80 do 'BANCO DE DADOS TÁTICO / DOSSIÊS F.L.A.G.'
/// com duas abas:
/// - FICHAS ATIVAS: cards táticos editáveis/excluíveis + botão '+ NOVO REGISTRO'
/// - TERMINAL RAW (.MD): editor monoespaçado do `flag_dossiers.md` com 'SALVAR E SINCRONIZAR'
class FlagDossierPage extends StatefulWidget {
  const FlagDossierPage({
    super.key,
    required this.initialMarkdown,
    required this.onSaveRawMarkdown,
    required this.onUpsertEntry,
    required this.onDeleteEntry,
    required this.onImportMarkdown,
  });

  final String initialMarkdown;
  final Future<String> Function(String rawMarkdown) onSaveRawMarkdown;
  final Future<String> Function({
    required String targetName,
    required String details,
    String? previousTargetName,
  }) onUpsertEntry;
  final Future<String> Function(String targetName) onDeleteEntry;
  final Future<String> Function(String rawMarkdown, {bool merge})
      onImportMarkdown;

  @override
  State<FlagDossierPage> createState() => _FlagDossierPageState();
}

class _FlagDossierPageState extends State<FlagDossierPage> {
  late String _rawMarkdown;
  late List<FlagDossierEntry> _entries;
  late final TextEditingController _rawEditorCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rawMarkdown = widget.initialMarkdown;
    _entries = FlagDossierService.parseEntries(_rawMarkdown);
    _rawEditorCtrl = TextEditingController(text: _rawMarkdown);
  }

  @override
  void dispose() {
    _rawEditorCtrl.dispose();
    super.dispose();
  }

  void _applyUpdatedMarkdown(String updated, {String? snackMessage}) {
    if (!mounted) return;
    setState(() {
      _rawMarkdown = updated;
      _entries = FlagDossierService.parseEntries(updated);
      _rawEditorCtrl.text = updated;
      _saving = false;
    });
    if (snackMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF14141E),
          content: Text(
            snackMessage,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF69F0AE),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveRaw() async {
    setState(() => _saving = true);
    final String updated = await widget.onSaveRawMarkdown(_rawEditorCtrl.text);
    _applyUpdatedMarkdown(
      updated,
      snackMessage: 'DOSSIÊS F.L.A.G. SALVOS E SINCRONIZADOS COM O K.I.T.T.',
    );
  }

  Future<void> _openEntryModal({FlagDossierEntry? existing}) async {
    final ({String name, String details})? result =
        await showDialog<({String name, String details})>(
      context: context,
      builder: (_) => _DossierEntryDialog(existing: existing),
    );

    if (result != null) {
      setState(() => _saving = true);
      final String updated = await widget.onUpsertEntry(
        targetName: result.name,
        details: result.details,
        previousTargetName: existing?.targetName,
      );
      _applyUpdatedMarkdown(
        updated,
        snackMessage: 'FICHA "${result.name.toUpperCase()}" SINCRONIZADA.',
      );
    }
  }

  Future<void> _deleteEntry(FlagDossierEntry entry) async {
    setState(() => _saving = true);
    final String updated = await widget.onDeleteEntry(entry.targetName);
    _applyUpdatedMarkdown(
      updated,
      snackMessage: 'FICHA "${entry.targetName.toUpperCase()}" REMOVIDA.',
    );
  }

  Future<void> _exportToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _rawMarkdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF14141E),
        content: Text(
          'flag_dossiers.md COPIADO PARA A ÁREA DE TRANSFERÊNCIA.',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFFFFD54F),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _openImportDialog() async {
    final ({String raw, bool merge})? payload =
        await showDialog<({String raw, bool merge})>(
      context: context,
      builder: (_) => const _ImportMarkdownDialog(),
    );

    if (payload != null) {
      setState(() => _saving = true);
      final String updated = await widget.onImportMarkdown(
        payload.raw,
        merge: payload.merge,
      );
      _applyUpdatedMarkdown(
        updated,
        snackMessage: 'DOSSIÊS IMPORTADOS E SINCRONIZADOS.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF050507),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E0E14),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'DOSSIÊS F.L.A.G. // DATABASE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                'BANCO DE DADOS TÁTICO • flag_dossiers.md',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFFFD54F),
                  fontSize: 9.5,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Exportar (copiar .md)',
              onPressed: _exportToClipboard,
              icon: const Icon(
                Icons.copy_all_outlined,
                color: Color(0xFFFFD54F),
                size: 20,
              ),
            ),
            IconButton(
              tooltip: 'Importar (.md)',
              onPressed: _openImportDialog,
              icon: const Icon(
                Icons.download_for_offline_outlined,
                color: Color(0xFF00E5FF),
                size: 20,
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF2424),
            labelColor: Color(0xFFFFD54F),
            unselectedLabelColor: Color(0xFF8A8A9E),
            labelStyle: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 1.2,
            ),
            tabs: <Widget>[
              Tab(text: 'FICHAS ATIVAS'),
              Tab(text: 'TERMINAL RAW (.MD)'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _buildActiveCardsTab(),
            _buildRawTerminalTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCardsTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('dossier_new_record_btn'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF2424),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _saving ? null : () => _openEntryModal(),
              icon: const Icon(Icons.add_box_outlined, size: 18),
              label: const Text(
                '+ NOVO REGISTRO',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0E15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'NENHUMA FICHA ATIVA NO BANCO F.L.A.G.\n\n'
                        'Toque em "+ NOVO REGISTRO" ou dite por voz:\n'
                        '"KITT, registre no banco de dados que..."',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFB5B5C2),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int idx) {
                      final FlagDossierEntry entry = _entries[idx];
                      return _buildDossierCard(entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDossierCard(FlagDossierEntry entry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF5252).withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF2424).withValues(alpha: 0.12),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.folder_special_outlined,
                color: Color(0xFFFFB300),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ALVO: ${entry.targetName.toUpperCase()}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Editar ficha',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                onPressed: _saving ? null : () => _openEntryModal(existing: entry),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF40C4FF),
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Excluir ficha',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                onPressed: _saving ? null : () => _deleteEntry(entry),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFFF5252),
                  size: 18,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF282836), height: 14),
          Text(
            entry.details,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFFD8D8E4),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawTerminalTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF080A0E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.6),
                  width: 1.2,
                ),
              ),
              child: TextField(
                key: const ValueKey<String>('dossier_raw_md_editor'),
                controller: _rawEditorCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFFFD54F),
                  fontSize: 12.5,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '# ARQUIVOS CONFIDENCIAIS F.L.A.G.',
                  hintStyle: TextStyle(color: Colors.white24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('dossier_save_sync_btn'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _saving ? null : _saveRaw,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text(
                'SALVAR E SINCRONIZAR',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DossierEntryDialog extends StatefulWidget {
  const _DossierEntryDialog({this.existing});

  final FlagDossierEntry? existing;

  @override
  State<_DossierEntryDialog> createState() => _DossierEntryDialogState();
}

class _DossierEntryDialogState extends State<_DossierEntryDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _detailsCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.targetName ?? '');
    _detailsCtrl = TextEditingController(text: widget.existing?.details ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101018),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFFF5252), width: 1.4),
      ),
      title: Text(
        widget.existing == null
            ? 'NOVO REGISTRO F.L.A.G.'
            : 'EDITAR FICHA TÁTICA',
        style: const TextStyle(
          fontFamily: 'monospace',
          color: Color(0xFFFF5252),
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 1.4,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('dossier_name_field'),
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nome / Apelido',
                labelStyle: TextStyle(color: Color(0xFFFFD54F)),
                hintText: 'Ex.: Bigode, Devon Miles...',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('dossier_details_field'),
              controller: _detailsCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Histórico / Perfil',
                labelStyle: TextStyle(color: Color(0xFFFFD54F)),
                hintText: 'Ex.: Controla o porto. Evitar rota sul à noite.',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'CANCELAR',
            style: TextStyle(color: Colors.white60),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF2424),
          ),
          onPressed: () {
            final String n = _nameCtrl.text.trim();
            final String d = _detailsCtrl.text.trim();
            if (n.isEmpty || d.isEmpty) return;
            Navigator.of(context).pop((name: n, details: d));
          },
          child: const Text('SALVAR FICHA'),
        ),
      ],
    );
  }
}

class _ImportMarkdownDialog extends StatefulWidget {
  const _ImportMarkdownDialog();

  @override
  State<_ImportMarkdownDialog> createState() => _ImportMarkdownDialogState();
}

class _ImportMarkdownDialogState extends State<_ImportMarkdownDialog> {
  final TextEditingController _importCtrl = TextEditingController();
  bool _merge = true;

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101018),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFFFB300), width: 1.4),
      ),
      title: const Text(
        'IMPORTAR MARKDOWN (.MD)',
        style: TextStyle(
          fontFamily: 'monospace',
          color: Color(0xFFFFD54F),
          fontWeight: FontWeight.w900,
          fontSize: 13.5,
          letterSpacing: 1.2,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final ClipboardData? clip =
                      await Clipboard.getData(Clipboard.kTextPlain);
                  if (clip?.text != null) {
                    _importCtrl.text = clip!.text!;
                  }
                },
                icon: const Icon(
                  Icons.content_paste,
                  size: 16,
                  color: Color(0xFFFFD54F),
                ),
                label: const Text(
                  'COLAR DA ÁREA DE TRANSFERÊNCIA',
                  style: TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            TextField(
              controller: _importCtrl,
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                hintText: '## Alvo: Nome\n- Detalhes...',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _merge,
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFFFF2424),
              title: const Text(
                'Mesclar com fichas existentes',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              onChanged: (bool? v) {
                if (v != null) setState(() => _merge = v);
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            if (_importCtrl.text.trim().isEmpty) return;
            Navigator.of(context)
                .pop((raw: _importCtrl.text.trim(), merge: _merge));
          },
          child: const Text('IMPORTAR'),
        ),
      ],
    );
  }
}
