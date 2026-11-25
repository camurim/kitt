import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Radar circular animado estilo KITT Surveillance Mode:
/// - Usa `flutter_compass` para rotacionar o Norte real (com fallback seguro em emuladores)
/// - Varredura sonar contínua em 360° com rastro fosforescente
/// - Pontos de varredura (blips) simulados que piscam quando o feixe passa por eles
class SurveillanceRadar extends StatefulWidget {
  const SurveillanceRadar({
    super.key,
    this.size = 176,
    this.enableCompass = true,
  });

  final double size;
  final bool enableCompass;

  @override
  State<SurveillanceRadar> createState() => _SurveillanceRadarState();
}

class _SurveillanceRadarState extends State<SurveillanceRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  StreamSubscription<CompassEvent>? _compassSub;
  double _headingDegrees = 0.0;
  bool _compassLive = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    if (widget.enableCompass) {
      _subscribeCompass();
    }
  }

  void _subscribeCompass() {
    try {
      final Stream<CompassEvent>? events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (CompassEvent event) {
          final double? h = event.heading;
          if (h != null && mounted) {
            setState(() {
              _headingDegrees = (h % 360 + 360) % 360;
              _compassLive = true;
            });
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Fallback silencioso em emuladores/testes sem magnetômetro.
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _sweepController.dispose();
    super.dispose();
  }

  String _cardinalLabel(double deg) {
    const List<String> dirs = <String>['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final int idx = (((deg + 22.5) % 360) / 45).floor() % 8;
    return dirs[idx];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _sweepController,
            builder: (BuildContext context, _) {
              return CustomPaint(
                painter: _SurveillanceRadarPainter(
                  sweepProgress: _sweepController.value,
                  headingDegrees: _headingDegrees,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'HDG ${_headingDegrees.round().toString().padLeft(3, '0')}° '
          '${_cardinalLabel(_headingDegrees)} • '
          '${_compassLive ? "COMPASS LOCK" : "PERIMETER SCAN"}',
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF4DD0E1),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
      ],
    );
  }
}

class _RadarBlip {
  const _RadarBlip({
    required this.angleRad,
    required this.distanceFactor,
    required this.isHostile,
  });

  final double angleRad;
  final double distanceFactor;
  final bool isHostile;
}

class _SurveillanceRadarPainter extends CustomPainter {
  _SurveillanceRadarPainter({
    required this.sweepProgress,
    required this.headingDegrees,
  });

  final double sweepProgress;
  final double headingDegrees;

  static const List<_RadarBlip> _blips = <_RadarBlip>[
    _RadarBlip(angleRad: 0.75, distanceFactor: 0.62, isHostile: true),
    _RadarBlip(angleRad: 2.10, distanceFactor: 0.44, isHostile: false),
    _RadarBlip(angleRad: 3.65, distanceFactor: 0.76, isHostile: true),
    _RadarBlip(angleRad: 4.85, distanceFactor: 0.35, isHostile: false),
    _RadarBlip(angleRad: 5.70, distanceFactor: 0.68, isHostile: false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) * 0.46;

    // Fundo circular do radar
    final Paint bgPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFF062426),
          const Color(0xFF041418),
          const Color(0xFF02080A),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Anéis concêntricos e mira
    final Paint gridPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final double factor in const <double>[0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, radius * factor, gridPaint);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    // Rótulos da bússola rotacionados pelo Norte real
    final double northOffsetRad = -headingDegrees * math.pi / 180.0;
    const List<MapEntry<String, double>> cardinals = <MapEntry<String, double>>[
      MapEntry<String, double>('N', -math.pi / 2),
      MapEntry<String, double>('E', 0.0),
      MapEntry<String, double>('S', math.pi / 2),
      MapEntry<String, double>('W', math.pi),
    ];

    for (final MapEntry<String, double> entry in cardinals) {
      final double a = entry.value + northOffsetRad;
      final Offset pos = Offset(
        center.dx + math.cos(a) * (radius + 9),
        center.dy + math.sin(a) * (radius + 9),
      );
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            fontFamily: 'monospace',
            color: entry.key == 'N'
                ? const Color(0xFFFF5252)
                : const Color(0xFF80DEEA),
            fontSize: entry.key == 'N' ? 10.5 : 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
    }

    // Feixe de varredura sonar com rastro fosforescente
    final double sweepAngle = sweepProgress * math.pi * 2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sweepAngle);

    final Paint sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: <Color>[
          Colors.transparent,
          Colors.transparent,
          const Color(0xFF00E5FF).withValues(alpha: 0.14),
          const Color(0xFF00E676).withValues(alpha: 0.45),
        ],
        stops: const <double>[0.0, 0.72, 0.90, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, sweepPaint);

    // Linha líder brilhante do sonar
    final Paint beamLinePaint = Paint()
      ..color = const Color(0xFF69F0AE)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(radius, 0), beamLinePaint);
    canvas.restore();

    // Pontos de varredura (blips) que acendem quando o feixe passa por eles
    for (final _RadarBlip blip in _blips) {
      final double worldAngle = (blip.angleRad + northOffsetRad) % (math.pi * 2);
      final double diff =
          ((sweepAngle - worldAngle) % (math.pi * 2) + math.pi * 2) %
              (math.pi * 2);
      // Brilho máximo logo após o feixe passar, dissipando gradualmente
      final double glow = (1.0 - (diff / (math.pi * 1.4))).clamp(0.0, 1.0);
      if (glow <= 0.05) continue;

      final Offset pos = Offset(
        center.dx + math.cos(worldAngle) * (radius * blip.distanceFactor),
        center.dy + math.sin(worldAngle) * (radius * blip.distanceFactor),
      );
      final Color blipColor =
          blip.isHostile ? const Color(0xFFFF5252) : const Color(0xFF69F0AE);

      // Anel sonar expandindo no blip
      final Paint ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = blipColor.withValues(alpha: glow * 0.6);
      canvas.drawCircle(pos, 4 + (1.0 - glow) * 10, ringPaint);

      // Núcleo do blip
      final Paint dotPaint = Paint()
        ..color = blipColor.withValues(alpha: glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(pos, 3.2, dotPaint);
    }

    // Ponto central (veículo KITT)
    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = const Color(0xFFFFD54F),
    );

    // Borda externa brilhante
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(covariant _SurveillanceRadarPainter oldDelegate) =>
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.headingDegrees != headingDegrees;
}
