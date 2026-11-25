import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/kitt_state.dart';

/// Overlay em tela cheia (3–4s) para os gadgets clássicos do KITT:
/// - Oil Slick: óleo viscoso escorrendo com reflexos metálicos/iridescentes
/// - Smoke Screen: sistema de partículas de fumaça densa subindo e dissipando
/// - Turbo Boost: linhas de velocidade nas bordas e brilho de propulsão
/// - Micro Jam: pulsos eletromagnéticos circulares e distorção/estática retrô
/// - Ski Mode: horizonte artificial inclinando a 45° com barras de equilíbrio âmbar/vermelho
/// - Scanner: feixe laser horizontal varrendo de cima a baixo com grades táticas e telemetria
class GadgetOverlay extends StatefulWidget {
  const GadgetOverlay({
    super.key,
    required this.gadget,
    required this.runId,
  });

  final GadgetType gadget;
  final int runId;

  @override
  State<GadgetOverlay> createState() => _GadgetOverlayState();
}

class _GadgetOverlayState extends State<GadgetOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.gadget.duration,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant GadgetOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runId != widget.runId || oldWidget.gadget != widget.gadget) {
      _controller
        ..duration = widget.gadget.duration
        ..forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final double p = _controller.value;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: switch (widget.gadget) {
                  GadgetType.oilSlick => _OilSlickPainter(progress: p),
                  GadgetType.smokeScreen => _SmokeScreenPainter(progress: p),
                  GadgetType.turboBoost => _TurboBoostPainter(progress: p),
                  GadgetType.microJam => _MicroJamPainter(progress: p),
                  GadgetType.skiMode => _SkiModePainter(progress: p),
                  GadgetType.scanner => _StructuralScanPainter(progress: p),
                },
              ),
              _buildHudAlertBanner(p),
              if (widget.gadget == GadgetType.scanner)
                _buildScannerTelemetryReadout(p),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScannerTelemetryReadout(double p) {
    final double opacity = p < 0.12
        ? (p / 0.12)
        : p > 0.85
            ? ((1.0 - p) / 0.15)
            : 1.0;
    final int pct = (p * 100).round().clamp(0, 100);
    final String integrity = p < 0.45 ? 'ANALYZING...' : '94.2% NOMINAL';
    final String thermal = p < 0.60 ? 'SWEEPING IR' : '02 SIGNATURES';
    final String alloy = p < 0.75 ? 'SAMPLING...' : 'FE-C / COMPOSITE';

    return Positioned(
      left: 20,
      right: 20,
      bottom: 112,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC041014),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.75),
              width: 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.28),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'GRID SCAN // TACTICAL TELEMETRY',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF69F0AE),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'STRUCTURAL INTEGRITY : $integrity\n'
                'THERMAL CONTACTS     : $thermal\n'
                'DENSITY / ALLOY      : $alloy',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFB2EBF2),
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudAlertBanner(double p) {
    // Fade-in rápido no início, mantém visível e faz fade-out suave no final.
    final double opacity = p < 0.12
        ? (p / 0.12)
        : p > 0.82
            ? ((1.0 - p) / 0.18)
            : 1.0;

    final Color accent = switch (widget.gadget) {
      GadgetType.oilSlick => const Color(0xFFFF9100),
      GadgetType.smokeScreen => const Color(0xFFB0BEC5),
      GadgetType.turboBoost => const Color(0xFFFF2424),
      GadgetType.microJam => const Color(0xFFE040FB),
      GadgetType.skiMode => const Color(0xFFFFAB00),
      GadgetType.scanner => const Color(0xFF00E5FF),
    };

    final IconData icon = switch (widget.gadget) {
      GadgetType.oilSlick => Icons.water_drop,
      GadgetType.smokeScreen => Icons.cloud,
      GadgetType.turboBoost => Icons.speed,
      GadgetType.microJam => Icons.wifi_tethering_off,
      GadgetType.skiMode => Icons.screen_rotation_alt,
      GadgetType.scanner => Icons.radar,
    };

    // Piscada retrô de alerta HUD
    final bool blink = ((p * 18).floor()).isEven;

    return Positioned(
      top: 72,
      left: 20,
      right: 20,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xDD08080C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: blink ? accent : accent.withValues(alpha: 0.45),
              width: 2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: blink ? 0.55 : 0.2),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.gadget.hudAlert,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 1.6,
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

/// 1. Oil Slick: óleo escuro viscoso escorrendo pela tela com reflexos metálicos.
class _OilSlickPainter extends CustomPainter {
  _OilSlickPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double fadeOut = progress > 0.76 ? ((1.0 - progress) / 0.24) : 1.0;
    final double flow = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );

    if (fadeOut <= 0.01) return;

    // Camada principal de óleo viscoso escorrendo do topo com 9 gotas/filetes
    const int dripCount = 9;
    final double segW = size.width / dripCount;
    final Path oilPath = Path()..moveTo(0, 0);

    for (int i = 0; i < dripCount; i++) {
      final double x0 = i * segW;
      final double xMid = x0 + segW * 0.5;
      final double x1 = (i + 1) * segW;

      final double seed = math.sin(i * 2.17 + 0.6) * 0.5 + 0.5;
      final double baseDepth = size.height * (0.28 + 0.52 * seed) * flow;
      final double wobble = math.sin(progress * 10 + i * 1.4) * 14 * flow;
      final double dripY = (baseDepth + wobble).clamp(0.0, size.height * 0.92);
      final double valleyY =
          (size.height * (0.14 + 0.16 * (1 - seed)) * flow).clamp(0.0, dripY);

      if (i == 0) {
        oilPath.lineTo(0, valleyY);
      }
      oilPath.cubicTo(
        x0 + segW * 0.18,
        valleyY + (dripY - valleyY) * 0.75,
        xMid - segW * 0.16,
        dripY,
        xMid,
        dripY,
      );
      oilPath.cubicTo(
        xMid + segW * 0.16,
        dripY,
        x1 - segW * 0.18,
        valleyY + (dripY - valleyY) * 0.75,
        x1,
        valleyY,
      );
    }

    oilPath
      ..lineTo(size.width, 0)
      ..close();

    final Paint oilPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFF030407).withValues(alpha: 0.94 * fadeOut),
          const Color(0xFF0E111A).withValues(alpha: 0.88 * fadeOut),
          const Color(0xFF1A1426).withValues(alpha: 0.80 * fadeOut),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(oilPath, oilPaint);

    // Reflexos metálicos/iridescentes típicos de óleo no asfalto
    final Paint sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          const Color(0xFF00E5FF).withValues(alpha: 0.42 * fadeOut),
          const Color(0xFFAA00FF).withValues(alpha: 0.45 * fadeOut),
          const Color(0xFFFFD54F).withValues(alpha: 0.35 * fadeOut),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(oilPath, sheenPaint);

    // Poças e respingos metálicos brilhantes espalhados na tela
    for (int i = 0; i < 6; i++) {
      final double appear = ((progress - i * 0.06) / 0.25).clamp(0.0, 1.0);
      if (appear <= 0) continue;
      final double cx = size.width * (0.14 + (i * 0.15) % 0.76);
      final double cy = size.height * (0.42 + (i % 3) * 0.16) + appear * 26;
      final double rx = (22 + (i % 3) * 14) * appear;
      final double ry = rx * 0.62;

      final Rect puddleRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      );
      final Paint puddlePaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFF28354A).withValues(alpha: 0.65 * fadeOut),
            const Color(0xFF07080D).withValues(alpha: 0.85 * fadeOut),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.65, 1.0],
        ).createShader(puddleRect);
      canvas.drawOval(puddleRect, puddlePaint);

      // Brilho especular metálico
      final Paint highlightPaint = Paint()
        ..color = (i.isEven ? const Color(0xFF40C4FF) : const Color(0xFFE040FB))
            .withValues(alpha: 0.32 * fadeOut);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - rx * 0.25, cy - ry * 0.22),
          width: rx * 0.65,
          height: ry * 0.3,
        ),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OilSlickPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 2. Smoke Screen: sistema de partículas de fumaça densa subindo e dissipando.
class _SmokeScreenPainter extends CustomPainter {
  _SmokeScreenPainter({required this.progress});

  final double progress;

  static final List<_SmokeParticle> _particles = _generateParticles();

  static List<_SmokeParticle> _generateParticles() {
    final math.Random rng = math.Random(1982);
    return List<_SmokeParticle>.generate(46, (int i) {
      return _SmokeParticle(
        startX: rng.nextDouble(),
        startY: 0.88 + rng.nextDouble() * 0.26,
        riseSpeed: 0.55 + rng.nextDouble() * 0.65,
        swayAmp: 0.03 + rng.nextDouble() * 0.07,
        swayFreq: 1.5 + rng.nextDouble() * 2.5,
        phase: rng.nextDouble() * math.pi * 2,
        baseRadius: 54 + rng.nextDouble() * 76,
        delay: rng.nextDouble() * 0.28,
        shade: 165 + rng.nextInt(65),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Névoa de fundo que sobe de intensidade e depois dissipa suavemente
    final double veilAlpha = progress < 0.45
        ? (progress / 0.45) * 0.62
        : progress < 0.70
            ? 0.62
            : ((1.0 - progress) / 0.30) * 0.62;

    if (veilAlpha > 0.01) {
      final Paint veilPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            Color.fromRGBO(195, 202, 210, veilAlpha.clamp(0.0, 0.72)),
            Color.fromRGBO(140, 148, 158, (veilAlpha * 0.72).clamp(0.0, 0.55)),
            Color.fromRGBO(90, 96, 106, (veilAlpha * 0.28).clamp(0.0, 0.25)),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRect(Offset.zero & size, veilPaint);
    }

    for (final _SmokeParticle p in _particles) {
      final double localT =
          ((progress - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
      if (localT <= 0.0) continue;

      final double x = (p.startX +
              math.sin(localT * math.pi * p.swayFreq + p.phase) * p.swayAmp) *
          size.width;
      final double y = (p.startY - localT * p.riseSpeed * 1.18) * size.height;
      final double radius = p.baseRadius * (0.65 + localT * 1.15);

      final double alpha = localT < 0.22
          ? (localT / 0.22) * 0.48
          : localT > 0.65
              ? ((1.0 - localT) / 0.35) * 0.48
              : 0.48;

      if (alpha <= 0.01) continue;

      final Offset center = Offset(x, y);
      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Color.fromRGBO(p.shade, p.shade + 4, p.shade + 10, alpha),
            Color.fromRGBO(p.shade - 25, p.shade - 22, p.shade - 16, alpha * 0.5),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmokeScreenPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SmokeParticle {
  const _SmokeParticle({
    required this.startX,
    required this.startY,
    required this.riseSpeed,
    required this.swayAmp,
    required this.swayFreq,
    required this.phase,
    required this.baseRadius,
    required this.delay,
    required this.shade,
  });

  final double startX;
  final double startY;
  final double riseSpeed;
  final double swayAmp;
  final double swayFreq;
  final double phase;
  final double baseRadius;
  final double delay;
  final int shade;
}

/// 3. Turbo Boost: linhas de velocidade radiais nas bordas + brilho de propulsão.
class _TurboBoostPainter extends CustomPainter {
  _TurboBoostPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double intensity = progress < 0.14
        ? (progress / 0.14)
        : progress > 0.78
            ? ((1.0 - progress) / 0.22)
            : 1.0;

    if (intensity <= 0.01) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.58;

    // Brilho radial quente nas bordas da tela
    final Paint vignettePaint = Paint()
      ..shader = RadialGradient(
        radius: 0.92,
        colors: <Color>[
          Colors.transparent,
          Colors.transparent,
          const Color(0xFFFF3D00).withValues(alpha: 0.22 * intensity),
          const Color(0xFFFF1744).withValues(alpha: 0.48 * intensity),
        ],
        stops: const <double>[0.0, 0.52, 0.80, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignettePaint);

    // 52 linhas de velocidade saindo em direção às bordas da tela
    const int lineCount = 52;
    for (int i = 0; i < lineCount; i++) {
      final double angle = (i / lineCount) * math.pi * 2;
      final double speedPhase = (progress * 5.2 + (i * 0.37)) % 1.0;

      final double rStart = maxRadius * (0.40 + speedPhase * 0.34);
      final double lineLen = maxRadius * (0.14 + (i % 4) * 0.055);
      final double rEnd = math.min(rStart + lineLen, maxRadius * 1.05);

      final Offset p1 = Offset(
        center.dx + math.cos(angle) * rStart,
        center.dy + math.sin(angle) * rStart,
      );
      final Offset p2 = Offset(
        center.dx + math.cos(angle) * rEnd,
        center.dy + math.sin(angle) * rEnd,
      );

      final Color lineColor = i % 3 == 0
          ? const Color(0xFFFFEA00)
          : i % 3 == 1
              ? const Color(0xFFFF5252)
              : const Color(0xFFFFFFFF);

      final Paint linePaint = Paint()
        ..color = lineColor.withValues(alpha: (0.82 * intensity).clamp(0.0, 1.0))
        ..strokeWidth = i % 4 == 0 ? 3.0 : 1.7
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TurboBoostPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 4. Micro Jam: pulsos eletromagnéticos circulares e distorção/estática retrô.
class _MicroJamPainter extends CustomPainter {
  _MicroJamPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double intensity = progress < 0.10
        ? (progress / 0.10)
        : progress > 0.80
            ? ((1.0 - progress) / 0.20)
            : 1.0;

    if (intensity <= 0.01) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.62;

    // Halo eletromagnético sutil no fundo
    final Paint bgGlow = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFE040FB).withValues(alpha: 0.24 * intensity),
          const Color(0xFF00E5FF).withValues(alpha: 0.12 * intensity),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawRect(Offset.zero & size, bgGlow);

    // 4 ondas de pulso eletromagnético (EMP) expandindo ciclicamente do centro
    for (int i = 0; i < 4; i++) {
      final double waveT = (progress * 2.4 + i * 0.25) % 1.0;
      final double radius = maxRadius * (0.08 + waveT * 0.96);
      final double ringAlpha = ((1.0 - waveT) * 0.9 * intensity).clamp(0.0, 1.0);
      final Color ringColor =
          i.isEven ? const Color(0xFFE040FB) : const Color(0xFF00E5FF);

      final Paint glowRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0 - waveT * 3.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = ringColor.withValues(alpha: ringAlpha * 0.65);
      canvas.drawCircle(center, radius, glowRing);

      final Paint sharpRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: ringAlpha * 0.85);
      canvas.drawCircle(center, radius, sharpRing);
    }

    // Distorção / estática retrô CRT (faixas horizontais e blocos de ruído)
    final int frameSeed = (progress * 28).floor();
    final math.Random rng = math.Random(1982 + frameSeed * 73);

    // Linhas de interferência horizontal
    for (int i = 0; i < 26; i++) {
      final double y = rng.nextDouble() * size.height;
      final double h = 1.2 + rng.nextDouble() * 4.5;
      final double xOffset = (rng.nextDouble() - 0.5) * 32;
      final Color bandColor = i % 3 == 0
          ? const Color(0xFF00E5FF)
          : i % 3 == 1
              ? const Color(0xFFE040FB)
              : Colors.white;
      final Paint bandPaint = Paint()
        ..color = bandColor.withValues(
          alpha: (0.14 + rng.nextDouble() * 0.34) * intensity,
        );
      canvas.drawRect(
        Rect.fromLTWH(xOffset, y, size.width, h),
        bandPaint,
      );
    }

    // Blocos de glitch estático
    for (int i = 0; i < 18; i++) {
      final double bx = rng.nextDouble() * size.width;
      final double by = rng.nextDouble() * size.height;
      final double bw = 18 + rng.nextDouble() * 64;
      final double bh = 3 + rng.nextDouble() * 10;
      final Paint glitchPaint = Paint()
        ..color = (i.isEven ? const Color(0xFFFFEA00) : const Color(0xFF00E5FF))
            .withValues(alpha: (0.22 + rng.nextDouble() * 0.32) * intensity);
      canvas.drawRect(Rect.fromLTWH(bx, by, bw, bh), glitchPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MicroJamPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 5. Ski Mode: horizonte artificial inclinando a 45° no HUD com barras laterais âmbar/vermelho.
class _SkiModePainter extends CustomPainter {
  _SkiModePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double opacity = progress < 0.12
        ? (progress / 0.12)
        : progress > 0.82
            ? ((1.0 - progress) / 0.18)
            : 1.0;

    if (opacity <= 0.01) return;

    // Curva de inclinação: sobe suave até 45°, mantém equilíbrio e retorna
    final double tiltFactor = progress < 0.25
        ? Curves.easeOutBack.transform(progress / 0.25).clamp(0.0, 1.08)
        : progress < 0.78
            ? 1.0 + math.sin(progress * 26) * 0.03
            : Curves.easeInCubic.transform((1.0 - progress) / 0.22);

    final double angleRad = (45.0 * tiltFactor) * (math.pi / 180.0);
    final Offset center = Offset(size.width / 2, size.height / 2);

    // 1. Horizonte artificial rotacionado a 45°
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-angleRad);

    final double span = math.max(size.width, size.height) * 1.4;

    // Preenchimento sutil acima/abaixo do horizonte
    final Paint upperTint = Paint()
      ..color = const Color(0xFFFFAB00).withValues(alpha: 0.07 * opacity);
    canvas.drawRect(Rect.fromLTWH(-span, -span, span * 2, span), upperTint);

    final Paint lowerTint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.14 * opacity);
    canvas.drawRect(Rect.fromLTWH(-span, 0, span * 2, span), lowerTint);

    // Linha principal do horizonte artificial
    final Paint horizonGlow = Paint()
      ..color = const Color(0xFFFFAB00).withValues(alpha: 0.55 * opacity)
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(Offset(-span, 0), Offset(span, 0), horizonGlow);

    final Paint horizonLine = Paint()
      ..color = const Color(0xFFFFEA00).withValues(alpha: 0.92 * opacity)
      ..strokeWidth = 2.2;
    canvas.drawLine(Offset(-span, 0), Offset(span, 0), horizonLine);

    // Escada de pitch / inclinação
    final Paint pitchPaint = Paint()
      ..color = const Color(0xFFFFAB00).withValues(alpha: 0.65 * opacity)
      ..strokeWidth = 1.6;
    for (int step = -3; step <= 3; step++) {
      if (step == 0) continue;
      final double y = step * 34.0;
      final double halfW = step.abs() == 1 ? 64.0 : 42.0;
      canvas.drawLine(Offset(-halfW, y), Offset(-18, y), pitchPaint);
      canvas.drawLine(Offset(18, y), Offset(halfW, y), pitchPaint);
    }

    // Silhueta central do chassi inclinado
    final Paint reticlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFFFF2424).withValues(alpha: 0.9 * opacity);
    canvas.drawCircle(Offset.zero, 24, reticlePaint);
    canvas.drawLine(const Offset(-48, 0), const Offset(-26, 0), reticlePaint);
    canvas.drawLine(const Offset(26, 0), const Offset(48, 0), reticlePaint);
    canvas.drawLine(const Offset(0, -34), const Offset(0, -24), reticlePaint);

    canvas.restore();

    // 2. Arco superior de referência de 45°
    final Rect arcRect = Rect.fromCircle(center: center, radius: 118);
    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFFAB00).withValues(alpha: 0.55 * opacity);
    canvas.drawArc(arcRect, -math.pi * 0.85, math.pi * 0.70, false, arcPaint);

    // 3. Barras de equilíbrio laterais (esquerda e direita) em âmbar/vermelho
    const int barSegments = 14;
    final double barHeight = size.height * 0.44;
    final double barTop = (size.height - barHeight) / 2;
    final double segH = (barHeight - (barSegments - 1) * 4) / barSegments;
    final int leftLit = ((0.25 + 0.68 * tiltFactor) * barSegments)
        .round()
        .clamp(1, barSegments);
    final int rightLit = ((0.75 - 0.52 * tiltFactor) * barSegments)
        .round()
        .clamp(1, barSegments);

    _drawBalanceBar(
      canvas: canvas,
      x: 16,
      top: barTop,
      width: 14,
      segH: segH,
      segments: barSegments,
      litCount: leftLit,
      opacity: opacity,
    );
    _drawBalanceBar(
      canvas: canvas,
      x: size.width - 30,
      top: barTop,
      width: 14,
      segH: segH,
      segments: barSegments,
      litCount: rightLit,
      opacity: opacity,
    );
  }

  void _drawBalanceBar({
    required Canvas canvas,
    required double x,
    required double top,
    required double width,
    required double segH,
    required int segments,
    required int litCount,
    required double opacity,
  }) {
    for (int i = 0; i < segments; i++) {
      // Preenche de baixo para cima
      final int idxFromBottom = segments - 1 - i;
      final bool lit = idxFromBottom < litCount;
      final bool isRedZone = idxFromBottom >= segments - 4;
      final Color baseColor =
          isRedZone ? const Color(0xFFFF1744) : const Color(0xFFFFAB00);
      final double y = top + i * (segH + 4);
      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, segH),
        const Radius.circular(2),
      );

      final Paint segPaint = Paint()
        ..color = baseColor.withValues(alpha: (lit ? 0.92 : 0.16) * opacity);
      canvas.drawRRect(rrect, segPaint);

      if (lit) {
        final Paint glowPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.42 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawRRect(rrect, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkiModePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 6. Scanner: feixe laser horizontal varrendo a tela de cima a baixo com grades táticas.
class _StructuralScanPainter extends CustomPainter {
  _StructuralScanPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double opacity = progress < 0.10
        ? (progress / 0.10)
        : progress > 0.85
            ? ((1.0 - progress) / 0.15)
            : 1.0;

    if (opacity <= 0.01) return;

    // 1. Grade tática HUD em ciano
    final Paint gridPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.16 * opacity)
      ..strokeWidth = 1.0;

    const double step = 36.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Cantoneiras táticas (retículo de enquadramento)
    final Paint bracketPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.72 * opacity)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    const double m = 22.0;
    const double len = 26.0;
    // Top-left
    canvas.drawLine(const Offset(m, m + len), const Offset(m, m), bracketPaint);
    canvas.drawLine(const Offset(m, m), const Offset(m + len, m), bracketPaint);
    // Top-right
    canvas.drawLine(Offset(size.width - m - len, m), Offset(size.width - m, m), bracketPaint);
    canvas.drawLine(Offset(size.width - m, m), Offset(size.width - m, m + len), bracketPaint);
    // Bottom-left
    canvas.drawLine(Offset(m, size.height - m - len), Offset(m, size.height - m), bracketPaint);
    canvas.drawLine(Offset(m, size.height - m), Offset(m + len, size.height - m), bracketPaint);
    // Bottom-right
    canvas.drawLine(
      Offset(size.width - m - len, size.height - m),
      Offset(size.width - m, size.height - m),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - m, size.height - m - len),
      Offset(size.width - m, size.height - m),
      bracketPaint,
    );

    // 2. Feixe laser horizontal varrendo de cima para baixo (e retornando suavemente)
    final double sweepT = progress < 0.72
        ? (progress / 0.72)
        : 1.0 - ((progress - 0.72) / 0.28);
    final double laserY = size.height * (0.06 + sweepT * 0.88);
    final bool goingDown = progress < 0.72;

    // Rastro luminoso do feixe
    const double trailHeight = 90.0;
    final Rect trailRect = goingDown
        ? Rect.fromLTWH(0, laserY - trailHeight, size.width, trailHeight)
        : Rect.fromLTWH(0, laserY, size.width, trailHeight);
    final Paint trailPaint = Paint()
      ..shader = LinearGradient(
        begin: goingDown ? Alignment.topCenter : Alignment.bottomCenter,
        end: goingDown ? Alignment.bottomCenter : Alignment.topCenter,
        colors: <Color>[
          Colors.transparent,
          const Color(0xFF00E5FF).withValues(alpha: 0.18 * opacity),
          const Color(0xFFFF1744).withValues(alpha: 0.36 * opacity),
        ],
      ).createShader(trailRect);
    canvas.drawRect(trailRect, trailPaint);

    // Glow vermelho/ciano do laser
    final Paint laserGlow = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.75 * opacity)
      ..strokeWidth = 9.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(Offset(0, laserY), Offset(size.width, laserY), laserGlow);

    // Núcleo branco/vermelho brilhante do feixe laser
    final Paint laserCore = Paint()
      ..color = const Color(0xFFFFEBEE).withValues(alpha: 0.96 * opacity)
      ..strokeWidth = 2.4;
    canvas.drawLine(Offset(0, laserY), Offset(size.width, laserY), laserCore);

    // Pontos de detecção tática piscando conforme o laser passa
    final List<Offset> markers = <Offset>[
      Offset(size.width * 0.28, size.height * 0.32),
      Offset(size.width * 0.70, size.height * 0.48),
      Offset(size.width * 0.44, size.height * 0.66),
    ];
    for (int i = 0; i < markers.length; i++) {
      final Offset pt = markers[i];
      final double dist = (laserY - pt.dy).abs();
      final bool revealed = laserY >= pt.dy || !goingDown;
      if (!revealed) continue;

      final double pulse = dist < 48 ? 1.0 : 0.65;
      final Paint markerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xFF69F0AE).withValues(alpha: pulse * opacity);
      canvas.drawCircle(pt, 10 + (dist < 48 ? 4 : 0), markerPaint);
      canvas.drawLine(pt + const Offset(-16, 0), pt + const Offset(16, 0), markerPaint);
      canvas.drawLine(pt + const Offset(0, -16), pt + const Offset(0, 16), markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StructuralScanPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
