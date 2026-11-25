import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'managers/home_controller.dart';
import 'pages/splash_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF050507),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // Inicia o HomeController + AndroidAutoBridgeService + Gemini Live imediatamente,
  // garantindo funcionamento mesmo quando o FlutterEngine sobe em modo headless
  // pelo Android Auto com a tela do celular apagada.
  KittAppSession.ensureStarted();
  runApp(const KittGeminiApp());
}

class KittGeminiApp extends StatelessWidget {
  const KittGeminiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K.I.T.T. Gemini',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF050507),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2424),
          secondary: Color(0xFFFFD54F),
          surface: Color(0xFF121218),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
