import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/kitt_state.dart';

/// Overlay em tela cheia (3–4s) para os gadgets clássicos do KITT:
/// - Oil Slick: óleo viscoso escorrendo com reflexos metálicos/iridescentes
/// - Smoke Screen: sistema de partículas de fumaça densa subindo e dissipando
/// - Turbo Boost: linhas de velocidade nas bordas e brilho de propulsão
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
                },
              ),
              _buildHudAlertBanner(p),
            ],
          );
        },
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
    };

    final IconData icon = switch (widget.gadget) {
      GadgetType.oilSlick => Icons.water_drop,
      GadgetType.smokeScreen => Icons.cloud,
      GadgetType.turboBoost => Icons.speed,
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
