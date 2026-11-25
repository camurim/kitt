import 'package:flutter/material.dart';

import '../config/kitt_persona.dart';
import '../managers/home_controller.dart';
import '../models/kitt_state.dart';
import '../widgets/kitt_visualizer.dart';
import '../widgets/side_button.dart';

/// Painel principal do KITT (retrato e paisagem) integrado à Gemini Live API.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomeController();
    _controller.initAndConnect();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF050507),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: <Widget>[
                  _buildTopStatusBar(),
                  const SizedBox(height: 12),
                  if (_controller.errorMessage != null) _buildErrorBanner(),
                  if (_controller.activeAction != null) _buildActiveActionBar(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        final bool isWide = c.maxWidth >= 600;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            SizedBox(
                              width: isWide ? 140 : 94,
                              child: _buildLeftColumn(),
                            ),
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    KittVisualizer(
                                      levelListenable: _controller.voiceLevel,
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _controller.driveMode.label,
                                      style: const TextStyle(
                                        color: Color(0xFFFFD54F),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                    if (_controller.lastTranscript.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          left: 12,
                                          right: 12,
                                        ),
                                        child: Text(
                                          _controller.lastTranscript,
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFB5B5C2),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: isWide ? 140 : 94,
                              child: _buildRightColumn(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBottomControlBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopStatusBar() {
    final Color dotColor = switch (_controller.connectionState) {
      LiveConnectionState.ready => const Color(0xFF00E676),
      LiveConnectionState.connecting => const Color(0xFFFFCA28),
      LiveConnectionState.error => const Color(0xFFFF1744),
      LiveConnectionState.disconnected => const Color(0xFF757575),
    };

    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(color: dotColor.withValues(alpha: 0.7), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_controller.connectionState.label} • ${_controller.persona.driverName.toUpperCase()}',
            style: const TextStyle(
              color: Color(0xFFD0D0DC),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Reconectar Gemini Live',
          onPressed: _controller.connect,
          icon: const Icon(Icons.refresh, color: Color(0xFFD0D0DC), size: 20),
        ),
        IconButton(
          tooltip: 'Configurar Persona do KITT',
          onPressed: _openPersonaSettings,
          icon: const Icon(Icons.tune, color: Color(0xFFFF5252), size: 20),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FF1744),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF1744)),
      ),
      child: Text(
        _controller.errorMessage!,
        style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
      ),
    );
  }

  Widget _buildActiveActionBar() {
    final KittActionEvent ev = _controller.activeAction!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x28FFD54F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt, color: Color(0xFFFFD54F), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${ev.title} — ${ev.detail}',
              style: const TextStyle(
                color: Color(0xFFFFECB3),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SideButton(
          label: 'NORMAL',
          accentColor: const Color(0xFFFFEB3B),
          isActive: _controller.driveMode == DriveMode.normalCruise,
          onPressed: () => _controller.setDriveMode(
            DriveMode.normalCruise,
            announceToGemini: true,
          ),
        ),
        const SizedBox(height: 10),
        SideButton(
          label: 'AUTO\nCRUISE',
          accentColor: const Color(0xFFFFB300),
          isActive: _controller.driveMode == DriveMode.autoCruise,
          onPressed: () => _controller.setDriveMode(
            DriveMode.autoCruise,
            announceToGemini: true,
          ),
        ),
        const SizedBox(height: 10),
        SideButton(
          label: 'PURSUIT',
          accentColor: const Color(0xFFFF2424),
          isActive: _controller.driveMode == DriveMode.pursuit,
          onPressed: () => _controller.setDriveMode(
            DriveMode.pursuit,
            announceToGemini: true,
          ),
        ),
        const SizedBox(height: 10),
        SideButton(
          label: 'AIR',
          accentColor: const Color(0xFF40C4FF),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('air'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'OIL',
          accentColor: const Color(0xFFFF9100),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('oil'),
        ),
      ],
    );
  }

  Widget _buildRightColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SideButton(
          label: 'P1',
          accentColor: const Color(0xFFFF5252),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('p1'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'P2',
          accentColor: const Color(0xFFFF5252),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('p2'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'P3',
          accentColor: const Color(0xFFFFB300),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('p3'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'P4',
          accentColor: const Color(0xFFFFB300),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('p4'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'S1',
          accentColor: const Color(0xFFFFEB3B),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('s1'),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'S2',
          accentColor: const Color(0xFFFFEB3B),
          compact: true,
          onPressed: () => _controller.triggerDashboardButton('s2'),
        ),
      ],
    );
  }

  Widget _buildBottomControlBar() {
    final bool micOn = _controller.isMicActive;

    return Row(
      children: <Widget>[
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _controller.toggleMic,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  micOn ? const Color(0xFFFF1744) : const Color(0xFF1A1A22),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                color: micOn
                    ? const Color(0xFFFF5252)
                    : const Color(0xFF3A3A48),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(micOn ? Icons.mic : Icons.mic_none),
            label: Text(
              micOn ? 'OUVINDO... (TOQUE P/ PAUSAR)' : 'FALAR COM O KITT',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: 'Enviar comando de texto de teste',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A22),
            foregroundColor: const Color(0xFFFFD54F),
            padding: const EdgeInsets.all(14),
          ),
          onPressed: _openQuickTextDialog,
          icon: const Icon(Icons.keyboard),
        ),
      ],
    );
  }

  Future<void> _openQuickTextDialog() async {
    final TextEditingController textCtrl = TextEditingController();
    final String? prompt = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14141A),
          title: const Text(
            'Comando rápido para o KITT',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: textCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Ex.: KITT, ativa o Turbo Boost!',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            onSubmitted: (String value) => Navigator.of(ctx).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(textCtrl.text),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
    textCtrl.dispose();
    if (prompt != null && prompt.trim().isNotEmpty) {
      _controller.sendQuickTextPrompt(prompt.trim());
    }
  }

  Future<void> _openPersonaSettings() async {
    final KittPersonaConfig current = _controller.persona;
    final TextEditingController nameCtrl =
        TextEditingController(text: current.driverName);
    String lang = current.languageCode;
    String voice = current.voiceName;
    double sarcasm = current.sarcasmLevel;

    final KittPersonaConfig? result = await showModalBottomSheet<KittPersonaConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121218),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'PARÂMETROS DA PERSONA KITT',
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nome do motorista',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: lang,
                          dropdownColor: const Color(0xFF1C1C24),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Idioma',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'pt-BR',
                              child: Text('Português (BR)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'en-US',
                              child: Text('English (US)'),
                            ),
                          ],
                          onChanged: (String? v) {
                            if (v != null) setModalState(() => lang = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: voice,
                          dropdownColor: const Color(0xFF1C1C24),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Voz Gemini',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                          items: KittConfig.availableVoices
                              .map(
                                (String v) => DropdownMenuItem<String>(
                                  value: v,
                                  child: Text(v),
                                ),
                              )
                              .toList(),
                          onChanged: (String? v) {
                            if (v != null) setModalState(() => voice = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Nível de ironia/sarcasmo: ${(sarcasm * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Slider(
                    value: sarcasm,
                    activeColor: const Color(0xFFFF2424),
                    onChanged: (double v) => setModalState(() => sarcasm = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2424),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop(
                          current.copyWith(
                            driverName: nameCtrl.text.trim().isEmpty
                                ? 'Michael'
                                : nameCtrl.text.trim(),
                            languageCode: lang,
                            voiceName: voice,
                            sarcasmLevel: sarcasm,
                          ),
                        );
                      },
                      child: const Text('SALVAR E RECONECTAR'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    if (result != null) {
      await _controller.updatePersona(result);
    }
  }
}
