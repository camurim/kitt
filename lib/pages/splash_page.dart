import 'dart:async';

import 'package:flutter/material.dart';

import 'home_page.dart';

/// Tela de inicialização ("K.I.T.T. Systems Activated").
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scannerController;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _navTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'K.i.t.Turbo',
                style: TextStyle(
                  color: Color(0xFFFF2424),
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'SYSTEMS ACTIVATED • GEMINI LIVE',
                style: TextStyle(
                  color: Color(0xFFB8B8C4),
                  fontSize: 12,
                  letterSpacing: 2.8,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 240,
                height: 10,
                child: AnimatedBuilder(
                  animation: _scannerController,
                  builder: (BuildContext context, _) {
                    return Align(
                      alignment: Alignment(
                        (_scannerController.value * 2) - 1,
                        0,
                      ),
                      child: Container(
                        width: 54,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1E1E),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0xCCFF1E1E),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
