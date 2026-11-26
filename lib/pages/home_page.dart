import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/kitt_persona.dart';
import '../managers/home_controller.dart';
import '../models/aux_slot_config.dart';
import '../models/kitt_state.dart';
import '../widgets/aux_buttons_bar.dart';
import '../widgets/gadget_overlay.dart';
import '../widgets/gadget_panel.dart';
import '../widgets/kitt_dialer_modal.dart';
import '../widgets/kitt_scanner_overlay.dart';
import '../widgets/kitt_visualizer.dart';
import '../widgets/listening_waveform_icon.dart';
import '../widgets/side_button.dart';
import '../widgets/surveillance_radar.dart';
import 'aux_slot_config_page.dart';
import 'comms_filter_page.dart';
import 'flag_dossier_page.dart';

/// Painel principal do KITT (retrato e paisagem) integrado à Gemini Live API.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final HomeController _controller;
  late final AnimationController _alertPulseController;
  late final PageController _pageController;
  int _currentPage = 0;
  bool _standbyScannerActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setWakelock(true);
    _controller = KittAppSession.controller;
    _pageController = PageController();
    _alertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
    _controller.initAndConnect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setWakelock(true);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setWakelock(false);
    }
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Ignora em ambientes de teste sem canal nativo.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setWakelock(false);
    _pageController.dispose();
    _alertPulseController.dispose();
    // Não descarta _controller aqui pois ele é compartilhado com o Android Auto
    // via KittAppSession e permanece ativo mesmo com a tela do celular apagada.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _controller,
        _alertPulseController,
      ]),
      builder: (BuildContext context, _) {
        final bool isPursuit = _controller.driveMode == DriveMode.pursuit;
        final bool isSurveillance =
            _controller.driveMode == DriveMode.surveillance;
        final double pulse = _alertPulseController.value;

        final Color scaffoldBg = isPursuit
            ? Color.lerp(
                const Color(0xFF0E0305),
                const Color(0xFF1D0608),
                pulse,
              )!
            : isSurveillance
                ? const Color(0xFF040B0D)
                : const Color(0xFF050507);

        return Scaffold(
          backgroundColor: scaffoldBg,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Borda pulsante vermelho/âmbar em Pursuit Mode
              if (isPursuit)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Color.lerp(
                          const Color(0xFFFF1744),
                          const Color(0xFFFFAB00),
                          pulse,
                        )!
                            .withValues(alpha: 0.65 + pulse * 0.35),
                        width: 4.0,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFFFF1744)
                              .withValues(alpha: 0.16 + pulse * 0.18),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      _buildTopStatusBar(),
                      if (isPursuit) _buildPursuitHudBadge(pulse),
                      const SizedBox(height: 8),
                      if (_controller.errorMessage != null) _buildErrorBanner(),
                      if (_controller.activeAction != null)
                        _buildActiveActionBar(),
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                onPageChanged: (int idx) {
                                  if (_currentPage != idx) {
                                    setState(() => _currentPage = idx);
                                  }
                                },
                                children: <Widget>[
                                  _buildMainPanelPage(
                                    isPursuit: isPursuit,
                                    isSurveillance: isSurveillance,
                                  ),
                                  _buildGadgetArsenalPage(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildPageIndicator(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      GadgetPanel(
                        activeGadget: _controller.activeGadget,
                        rpmNormalized: _controller.rpmNormalized,
                        rpmValue: _controller.rpmValue,
                        speedKmh: _controller.displaySpeedKmh,
                        isGpsLive: _controller.isGpsLive,
                        currentGForce: _controller.currentGForce,
                        telemetryEnabled:
                            _controller.telemetryAutoCommentsEnabled,
                        onToggleTelemetry: _controller.toggleTelemetrySensors,
                      ),
                      const SizedBox(height: 8),
                      AuxButtonsBar(
                        slots: _controller.auxSlots,
                        onTapSlot: _handleAuxTap,
                        onLongPressSlot: _openAuxSlotConfig,
                      ),
                      const SizedBox(height: 10),
                      _buildBottomControlBar(),
                    ],
                  ),
                ),
              ),
              if (_controller.activeGadget != null)
                GadgetOverlay(
                  gadget: _controller.activeGadget!,
                  runId: _controller.gadgetRunId,
                ),
              if (_standbyScannerActive)
                KittScannerOverlay(
                  voiceLevelListenable: _controller.voiceLevel,
                  onWake: () => setState(() => _standbyScannerActive = false),
                  onWakeWithMic: () {
                    setState(() => _standbyScannerActive = false);
                    if (!_controller.isMicActive) {
                      _controller.toggleMic();
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPursuitHudBadge(double pulse) {
    final bool bright = pulse >= 0.45;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bright ? const Color(0x55FF1744) : const Color(0x22FFAB00),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: bright ? const Color(0xFFFF1744) : const Color(0xFFFFAB00),
          width: 1.6,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: bright ? const Color(0xFFFFEA00) : const Color(0xFFFF5252),
          ),
          const SizedBox(width: 8),
          Text(
            'PURSUIT ENGAGED',
            style: TextStyle(
              fontFamily: 'monospace',
              color: bright ? Colors.white : const Color(0xFFFFAB00),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 3.0,
            ),
          ),
        ],
      ),
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
          tooltip: 'Dossiês / Database F.L.A.G.',
          onPressed: _openFlagDossiersPage,
          icon: const Icon(
            Icons.folder_special_outlined,
            color: Color(0xFFFFB300),
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Comunicações / Filtro F.L.A.G.',
          onPressed: _openCommsFilterPage,
          icon: Icon(
            _controller.autoReadMessagesEnabled
                ? Icons.mark_chat_unread_outlined
                : Icons.comments_disabled_outlined,
            color: _controller.autoReadMessagesEnabled
                ? const Color(0xFFFFD54F)
                : const Color(0xFF8A8A9E),
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Modo Stand-by / Scanner Frontal',
          onPressed: () => setState(() => _standbyScannerActive = true),
          icon: const Icon(
            Icons.linear_scale,
            color: Color(0xFFFF2424),
            size: 20,
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

  Widget _buildMainPanelPage({
    required bool isPursuit,
    required bool isSurveillance,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool isWide = c.maxWidth >= 600;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: isWide ? 140 : 94,
              child: SingleChildScrollView(
                child: _buildLeftColumn(),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (isSurveillance) ...<Widget>[
                        const SurveillanceRadar(size: 162),
                        const SizedBox(height: 8),
                        KittVisualizer(
                          levelListenable: _controller.voiceLevel,
                          compact: true,
                        ),
                      ] else
                        KittVisualizer(
                          levelListenable: _controller.voiceLevel,
                          pursuitMode: isPursuit,
                        ),
                      const SizedBox(height: 10),
                      Text(
                        _controller.driveMode.label,
                        style: TextStyle(
                          color: isPursuit
                              ? const Color(0xFFFF5252)
                              : isSurveillance
                                  ? const Color(0xFF4DD0E1)
                                  : const Color(0xFFFFD54F),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 2.0,
                        ),
                      ),
                      if (_controller.lastTranscript.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 6,
                            left: 10,
                            right: 10,
                          ),
                          child: Text(
                            _controller.lastTranscript,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB5B5C2),
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: isWide ? 140 : 94,
              child: SingleChildScrollView(
                child: _buildRightColumn(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGadgetArsenalPage() {
    final GadgetType? active = _controller.activeGadget;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'ARSENAL DE GADGETS',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SideButton(
                        label: 'OIL SLICK',
                        accentColor: const Color(0xFFFF9100),
                        isActive: active == GadgetType.oilSlick,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.oilSlick),
                      ),
                      const SizedBox(height: 12),
                      SideButton(
                        label: 'SMOKE SCREEN',
                        accentColor: const Color(0xFF80DEEA),
                        isActive: active == GadgetType.smokeScreen,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.smokeScreen),
                      ),
                      const SizedBox(height: 12),
                      SideButton(
                        label: 'TURBO BOOST',
                        accentColor: const Color(0xFFFF2424),
                        isActive: active == GadgetType.turboBoost,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.turboBoost),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SideButton(
                        label: 'MICRO JAM',
                        accentColor: const Color(0xFFE040FB),
                        isActive: active == GadgetType.microJam,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.microJam),
                      ),
                      const SizedBox(height: 12),
                      SideButton(
                        label: 'SKI MODE',
                        accentColor: const Color(0xFFFFAB00),
                        isActive: active == GadgetType.skiMode,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.skiMode),
                      ),
                      const SizedBox(height: 12),
                      SideButton(
                        label: 'SCANNER',
                        accentColor: const Color(0xFF00E5FF),
                        isActive: active == GadgetType.scanner,
                        onPressed: () =>
                            _controller.activateGadget(GadgetType.scanner),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(2, (int idx) {
        final bool selected = _currentPage == idx;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _pageController.animateToPage(
              idx,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: AnimatedContainer(
              key: ValueKey<String>('panel_page_dot_$idx'),
              duration: const Duration(milliseconds: 180),
              width: selected ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: selected
                    ? const Color(0xFFFF2424)
                    : const Color(0xFF3E3E4E),
                boxShadow: selected
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0xAAFF2424),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
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
          onPressed: () => _controller.setOperationMode(
            DriveMode.autoCruise,
            announceToGemini: true,
          ),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'SURVEIL-\nLANCE',
          accentColor: const Color(0xFF00E5FF),
          compact: true,
          isActive: _controller.driveMode == DriveMode.surveillance,
          onPressed: () => _controller.setOperationMode(
            DriveMode.surveillance,
            announceToGemini: true,
          ),
        ),
        const SizedBox(height: 8),
        SideButton(
          label: 'PURSUIT',
          accentColor: const Color(0xFFFF2424),
          isActive: _controller.driveMode == DriveMode.pursuit,
          onPressed: () => _controller.setOperationMode(
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
            icon: micOn
                ? ListeningWaveformIcon(
                    levelListenable: _controller.micLevel,
                    color: Colors.white,
                  )
                : const Icon(Icons.mic_none),
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
          tooltip: 'Commlink • Discador telefônico KITT',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A22),
            foregroundColor: const Color(0xFF00E676),
            padding: const EdgeInsets.all(14),
            side: const BorderSide(color: Color(0xFF1B5E20)),
          ),
          onPressed: _openDialerModal,
          icon: const Icon(Icons.call),
        ),
        const SizedBox(width: 8),
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

  Future<void> _handleAuxTap(AuxSlotConfig slot) async {
    if (!slot.isConfigured) {
      await _openAuxSlotConfig(slot);
      return;
    }
    await _controller.launchAuxApp(slotNumber: slot.slotNumber);
  }

  Future<void> _openAuxSlotConfig(AuxSlotConfig slot) async {
    final AuxSlotConfig? updated =
        await Navigator.of(context).push<AuxSlotConfig>(
      MaterialPageRoute<AuxSlotConfig>(
        builder: (_) => AuxSlotConfigPage(
          initialConfig: slot,
          loadInstalledApps: _controller.listInstalledApps,
        ),
      ),
    );
    if (updated != null) {
      await _controller.saveAuxSlot(updated);
    }
  }

  Future<void> _openCommsFilterPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CommsFilterPage(
          initialAllowedPackages: _controller.allowedNotificationPackages,
          initialAutoReadEnabled: _controller.autoReadMessagesEnabled,
          checkPermission: _controller.isNotificationAccessGranted,
          openPermissionSettings: _controller.openNotificationAccessSettings,
          loadInstalledApps: _controller.listInstalledApps,
          onToggleAutoRead: _controller.setAutoReadMessagesEnabled,
          onTogglePackage: _controller.setNotificationPackageAllowed,
        ),
      ),
    );
  }

  Future<void> _openFlagDossiersPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FlagDossierPage(
          initialMarkdown: _controller.flagDossiersMarkdown,
          onSaveRawMarkdown: _controller.saveFlagDossiersRaw,
          onUpsertEntry: ({
            required String targetName,
            required String details,
            String? previousTargetName,
          }) =>
              _controller.upsertFlagDossierEntry(
            targetName: targetName,
            details: details,
            previousTargetName: previousTargetName,
          ),
          onDeleteEntry: _controller.deleteFlagDossierEntry,
          onImportMarkdown: _controller.importFlagDossiers,
        ),
      ),
    );
  }

  Future<void> _openDialerModal() async {
    await showKittDialerModal(
      context: context,
      onDial: (String phoneNumber, bool directCall) async {
        await _controller.makePhoneCall(
          phoneNumber: phoneNumber,
          directCall: directCall,
        );
      },
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
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD54F),
                        side: const BorderSide(color: Color(0xFFFFB300)),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openFlagDossiersPage();
                      },
                      icon: const Icon(Icons.folder_special_outlined, size: 18),
                      label: const Text('DOSSIÊS / DATABASE F.L.A.G.'),
                    ),
                  ),
                  const SizedBox(height: 10),
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
