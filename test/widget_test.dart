import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt_gemini/main.dart';
import 'package:kitt_gemini/widgets/kitt_visualizer.dart';
import 'package:kitt_gemini/widgets/side_button.dart';

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
}
