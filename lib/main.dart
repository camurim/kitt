import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/splash_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF050507),
    ),
  );
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
