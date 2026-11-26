import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitturbo/main.dart';
import 'package:kitturbo/managers/aux_apps_manager.dart';
import 'package:kitturbo/managers/home_controller.dart';
import 'package:kitturbo/models/aux_slot_config.dart';
import 'package:kitturbo/models/kitt_state.dart';
import 'package:kitturbo/pages/comms_filter_page.dart';
import 'package:kitturbo/pages/flag_dossier_page.dart';
import 'package:kitturbo/pages/home_page.dart';
import 'package:kitturbo/widgets/aux_buttons_bar.dart';
import 'package:kitturbo/widgets/gadget_overlay.dart';
import 'package:kitturbo/widgets/gadget_panel.dart';
import 'package:kitturbo/widgets/kitt_dialer_modal.dart';
import 'package:kitturbo/widgets/kitt_scanner_overlay.dart';
import 'package:kitturbo/widgets/kitt_visualizer.dart';
import 'package:kitturbo/widgets/listening_waveform_icon.dart';
import 'package:kitturbo/widgets/side_button.dart';
import 'package:kitturbo/widgets/surveillance_radar.dart';

void main() {
  testWidgets('KittGeminiApp renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const KittGeminiApp());

    expect(find.text('K.i.t.Turbo'), findsOneWidget);
    expect(find.text('SYSTEMS ACTIVATED • GEMINI LIVE'), findsOneWidget);

    // Desmonta a SplashPage para cancelar o Timer de navegação antes do fim do teste.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('KittVisualizer and SideButton render and handle taps', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<double> level = ValueNotifier<double>(0.6);
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              KittVisualizer(levelListenable: level),
              SideButton(
                label: 'PURSUIT',
                accentColor: Colors.red,
                isActive: true,
                onPressed: () => tapped = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('PURSUIT'), findsOneWidget);
    await tester.tap(find.text('PURSUIT'));
    await tester.pump();
    expect(tapped, isTrue);

    level.dispose();
  });

  testWidgets('GadgetPanel displays compact telemetry and toggles sensors', (
    WidgetTester tester,
  ) async {
    bool telemetryToggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              GadgetPanel(
                activeGadget: GadgetType.turboBoost,
                rpmNormalized: 0.96,
                rpmValue: 9600,
                speedKmh: 285,
                isGpsLive: true,
                currentGForce: 0.55,
                telemetryEnabled: true,
                onToggleTelemetry: () => telemetryToggled = true,
              ),
              const GadgetOverlay(
                gadget: GadgetType.oilSlick,
                runId: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('OIL SLICK'), findsNothing);
    expect(find.text('SMOKE SCREEN'), findsNothing);
    expect(find.text('TURBO BOOST'), findsNothing);
    expect(find.text('285 KM/H'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);
    expect(find.text('TELEMETRIA / SENSORES'), findsOneWidget);
    expect(find.text(GadgetType.oilSlick.hudAlert), findsOneWidget);

    await tester.tap(find.text('TELEMETRIA / SENSORES'));
    await tester.pump();
    expect(telemetryToggled, isTrue);
  });

  testWidgets('GadgetOverlay renders Micro Jam, Ski Mode and Scanner animations', (
    WidgetTester tester,
  ) async {
    for (final GadgetType gadget in <GadgetType>[
      GadgetType.microJam,
      GadgetType.skiMode,
      GadgetType.scanner,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                GadgetOverlay(gadget: gadget, runId: 1),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(gadget.hudAlert), findsOneWidget);
      if (gadget == GadgetType.scanner) {
        expect(find.text('GRID SCAN // TACTICAL TELEMETRY'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('KittDialerSheet accepts keypad digits and triggers dial', (
    WidgetTester tester,
  ) async {
    String? dialedNumber;
    bool? dialedDirect;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KittDialerSheet(
              onDial: (String num, bool direct) async {
                dialedNumber = num;
                dialedDirect = direct;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('9'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('190'), findsOneWidget);

    await tester.tap(find.text('LIGAR DIRETO'));
    await tester.pump();
    expect(dialedNumber, '190');
    expect(dialedDirect, isTrue);
  });

  testWidgets('AuxButtonsBar handles tap and long-press on configurable slots', (
    WidgetTester tester,
  ) async {
    int? tappedSlot;
    int? longPressedSlot;

    final List<AuxSlotConfig> slots = <AuxSlotConfig>[
      const AuxSlotConfig(
        slotNumber: 1,
        label: 'NAVEGAÇÃO',
        packageName: 'com.waze',
        appName: 'Waze',
        iconId: 'navigation',
      ),
      const AuxSlotConfig(slotNumber: 2),
      const AuxSlotConfig(slotNumber: 3),
      const AuxSlotConfig(slotNumber: 4),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuxButtonsBar(
            slots: slots,
            onTapSlot: (AuxSlotConfig s) => tappedSlot = s.slotNumber,
            onLongPressSlot: (AuxSlotConfig s) =>
                longPressedSlot = s.slotNumber,
          ),
        ),
      ),
    );

    expect(find.text('NAVEGAÇÃO'), findsOneWidget);
    expect(find.text('AUX 2'), findsOneWidget);

    await tester.tap(find.text('NAVEGAÇÃO'));
    await tester.pump();
    expect(tappedSlot, 1);

    await tester.longPress(find.text('AUX 2'));
    await tester.pump();
    expect(longPressedSlot, 2);
  });

  testWidgets('SurveillanceRadar and Pursuit KittVisualizer render cleanly', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<double> level = ValueNotifier<double>(0.4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const SurveillanceRadar(size: 140, enableCompass: false),
              KittVisualizer(
                levelListenable: level,
                pursuitMode: true,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('PERIMETER SCAN'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    level.dispose();
  });

  testWidgets('KittScannerOverlay renders 8 LED segments and wakes on tap', (
    WidgetTester tester,
  ) async {
    bool woke = false;
    bool wokeWithMic = false;

    await tester.pumpWidget(
      MaterialApp(
        home: KittScannerOverlay(
          enableAudio: false,
          onWake: () => woke = true,
          onWakeWithMic: () => wokeWithMic = true,
        ),
      ),
    );

    for (int i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey<String>('kitt_scanner_seg_$i')), findsOneWidget);
    }

    await tester.tap(find.text('TOQUE NA TELA PARA ATIVAR O PAINEL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(woke, isTrue);
    expect(wokeWithMic, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ListeningWaveformIcon renders 5 animated bars reacting to mic level', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<double> micLevel = ValueNotifier<double>(0.0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ListeningWaveformIcon(levelListenable: micLevel),
          ),
        ),
      ),
    );

    for (int i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey<String>('listening_wave_bar_$i')), findsOneWidget);
    }

    micLevel.value = 0.85;
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey<String>('listening_wave_bar_2')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    micLevel.dispose();
  });

  testWidgets('HomePage renders PageView, switches to gadgets and triggers overlays cleanly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Simula a sequência real: motor iniciado antes (main/headless) e HomePage montada depois.
    KittAppSession.controller.initAndConnect();

    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Página 1: 5 botões na esquerda (sem OIL duplicado) e 6 na direita
    expect(find.text('NORMAL'), findsOneWidget);
    expect(find.text('PURSUIT'), findsOneWidget);
    expect(find.text('AIR'), findsOneWidget);
    expect(find.text('OIL'), findsNothing);
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);

    // Alterna para Página 2 pelo dot indicador
    await tester.tap(find.byKey(const ValueKey<String>('panel_page_dot_1')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('OIL SLICK'), findsOneWidget);
    expect(find.text('SMOKE SCREEN'), findsOneWidget);
    expect(find.text('TURBO BOOST'), findsOneWidget);
    expect(find.text('MICRO JAM'), findsOneWidget);
    expect(find.text('SKI MODE'), findsOneWidget);
    expect(find.text('SCANNER'), findsOneWidget);

    // Dispara um novo gadget (MICRO JAM) e verifica overlay sem exceções
    await tester.tap(find.text('MICRO JAM'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(GadgetType.microJam.hudAlert), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('CommsFilterPage checks permission, toggles master switch and per-app switches', (
    WidgetTester tester,
  ) async {
    bool openedSettings = false;
    bool? masterValue;
    String? toggledPkg;
    bool? toggledState;

    await tester.pumpWidget(
      MaterialApp(
        home: CommsFilterPage(
          initialAllowedPackages: const <String>{'com.whatsapp'},
          initialAutoReadEnabled: true,
          checkPermission: () async => false,
          openPermissionSettings: () async {
            openedSettings = true;
            return true;
          },
          loadInstalledApps: ({bool includeSystemApps = false}) async =>
              const <InstalledAppEntry>[
            InstalledAppEntry(name: 'Waze', packageName: 'com.waze'),
            InstalledAppEntry(name: 'WhatsApp', packageName: 'com.whatsapp'),
            InstalledAppEntry(
              name: 'Telegram',
              packageName: 'org.telegram.messenger',
            ),
          ],
          onToggleAutoRead: (bool enabled) async => masterValue = enabled,
          onTogglePackage: (String pkg, bool allowed) async {
            toggledPkg = pkg;
            toggledState = allowed;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COMUNICAÇÕES / FILTRO F.L.A.G.'), findsOneWidget);
    expect(find.text('ACESSO A NOTIFICAÇÕES: DESATIVADO'), findsOneWidget);
    expect(find.text('LEITURA AUTOMÁTICA DE MENSAGENS'), findsOneWidget);
    expect(find.text('MENSAGENS'), findsNWidgets(2));

    await tester.tap(find.text('ATIVAR ACESSO A NOTIFICAÇÕES'));
    await tester.pump();
    expect(openedSettings, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('flag_master_auto_read_switch')));
    await tester.pump();
    expect(masterValue, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('flag_app_switch_org.telegram.messenger')));
    await tester.pump();
    expect(toggledPkg, 'org.telegram.messenger');
    expect(toggledState, isTrue);
  });

  testWidgets('FlagDossierPage renders active cards tab and raw markdown terminal tab', (
    WidgetTester tester,
  ) async {
    String? savedRaw;
    String? upsertedName;

    await tester.pumpWidget(
      MaterialApp(
        home: FlagDossierPage(
          initialMarkdown:
              '# ARQUIVOS CONFIDENCIAIS F.L.A.G.\n\n## Alvo: Devon Miles\n- Diretor da Fundação.\n',
          onSaveRawMarkdown: (String raw) async {
            savedRaw = raw;
            return raw;
          },
          onUpsertEntry: ({
            required String targetName,
            required String details,
            String? previousTargetName,
          }) async {
            upsertedName = targetName;
            return '# ARQUIVOS CONFIDENCIAIS F.L.A.G.\n\n## Alvo: $targetName\n- $details\n';
          },
          onDeleteEntry: (String targetName) async =>
              '# ARQUIVOS CONFIDENCIAIS F.L.A.G.\n',
          onImportMarkdown: (String raw, {bool merge = true}) async => raw,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FICHAS ATIVAS'), findsOneWidget);
    expect(find.text('TERMINAL RAW (.MD)'), findsOneWidget);
    expect(find.text('ALVO: DEVON MILES'), findsOneWidget);

    // Testa criação de ficha via modal + NOVO REGISTRO
    await tester.tap(find.byKey(const ValueKey<String>('dossier_new_record_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('dossier_name_field')),
      'Bigode',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('dossier_details_field')),
      'Controla o porto.',
    );
    await tester.tap(find.text('SALVAR FICHA'));
    await tester.pumpAndSettle();
    expect(upsertedName, 'Bigode');

    // Aguarda o SnackBar de confirmação sair da base da tela antes de trocar de aba
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Troca para a aba TERMINAL RAW (.MD) e salva
    await tester.tap(find.text('TERMINAL RAW (.MD)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dossier_save_sync_btn')));
    await tester.pumpAndSettle();
    expect(savedRaw, isNotNull);
  });
}
