import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt_gemini/main.dart';
import 'package:kitt_gemini/models/aux_slot_config.dart';
import 'package:kitt_gemini/models/kitt_state.dart';
import 'package:kitt_gemini/widgets/aux_buttons_bar.dart';
import 'package:kitt_gemini/widgets/gadget_overlay.dart';
import 'package:kitt_gemini/widgets/gadget_panel.dart';
import 'package:kitt_gemini/widgets/kitt_dialer_modal.dart';
import 'package:kitt_gemini/widgets/kitt_scanner_overlay.dart';
import 'package:kitt_gemini/widgets/kitt_visualizer.dart';
import 'package:kitt_gemini/widgets/listening_waveform_icon.dart';
import 'package:kitt_gemini/widgets/side_button.dart';
import 'package:kitt_gemini/widgets/surveillance_radar.dart';

void main() {
  testWidgets('KittGeminiApp renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const KittGeminiApp());

    expect(find.text('K.I.T.T.'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(woke, isTrue);
    expect(wokeWithMic, isFalse);
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
}
