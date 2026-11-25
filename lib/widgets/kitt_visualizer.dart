import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Voicebox clássico do KITT com 3 colunas de segmentos LED vermelhos.
///
/// - Normal: resposta suave conforme o nível sonoro PCM (`0.0..1.0`).
/// - Pursuit Mode (`pursuitMode: true`): frequência mais alta, amplitude amplificada
///   e brilho pulsante vermelho/âmbar nas bordas.
/// - Compact (`compact: true`): versão reduzida usada abaixo do radar em Surveillance Mode.
class KittVisualizer extends StatefulWidget {
  const KittVisualizer({
    super.key,
    required this.levelListenable,
    this.segmentsPerColumn = 11,
    this.pursuitMode = false,
    this.compact = false,
  });

  final ValueListenable<double> levelListenable;
  final int segmentsPerColumn;
  final bool pursuitMode;
  final bool compact;

  @override
  State<KittVisualizer> createState() => _KittVisualizerState();
}

class _KittVisualizerState extends State<KittVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pursuitPulse;

  @override
  void initState() {
    super.initState();
    _pursuitPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    if (widget.pursuitMode) {
      _pursuitPulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant KittVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pursuitMode && !_pursuitPulse.isAnimating) {
      _pursuitPulse.repeat(reverse: true);
    } else if (!widget.pursuitMode && _pursuitPulse.isAnimating) {
      _pursuitPulse.stop();
      _pursuitPulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pursuitPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int segCount = widget.compact ? 5 : widget.segmentsPerColumn;
    final double segW = widget.compact ? 22 : 30;
    final double segH = widget.compact ? 6 : 11;

    return AnimatedBuilder(
      animation: _pursuitPulse,
      builder: (BuildContext context, _) {
        final double pulse = widget.pursuitMode ? _pursuitPulse.value : 0.0;
        final Color borderColor = widget.pursuitMode
            ? Color.lerp(
                const Color(0xFFFF1744),
                const Color(0xFFFFAB00),
                pulse,
              )!
            : const Color(0xFF2B2B33);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 14 : 18,
            vertical: widget.compact ? 8 : 16,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0C),
            borderRadius: BorderRadius.circular(widget.compact ? 10 : 14),
            border: Border.all(
              color: borderColor,
              width: widget.pursuitMode ? 2.4 : 2.0,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.pursuitMode
                    ? Color.fromRGBO(255, 30, 10, 0.42 + pulse * 0.35)
                    : const Color(0x55FF1111),
                blurRadius: widget.pursuitMode ? 24 : 18,
                spreadRadius: widget.pursuitMode ? 2.5 : 1,
              ),
            ],
          ),
          child: ValueListenableBuilder<double>(
            valueListenable: widget.levelListenable,
            builder: (BuildContext context, double level, _) {
              double effective = level.clamp(0.0, 1.0);
              if (widget.pursuitMode) {
                // Aumenta amplitude e adiciona vibração tática de alta frequência
                final double jitter =
                    0.16 + 0.14 * math.sin(pulse * math.pi);
                effective = (effective * 1.38 + jitter).clamp(0.0, 1.0);
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _buildColumn(effective * 0.70, segCount, segW, segH),
                  SizedBox(width: widget.compact ? 10 : 14),
                  _buildColumn(effective, segCount, segW, segH),
                  SizedBox(width: widget.compact ? 10 : 14),
                  _buildColumn(effective * 0.70, segCount, segW, segH),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildColumn(
    double intensity,
    int segCount,
    double segW,
    double segH,
  ) {
    final int centerIndex = segCount ~/ 2;
    final double activeRadius =
        intensity <= 0.02 ? 0.5 : (intensity * centerIndex) + 0.5;
    final Duration animDur = Duration(
      milliseconds: widget.pursuitMode ? 28 : 55,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(segCount, (int index) {
        final double dist = (index - centerIndex).abs().toDouble();
        final double opacity = dist <= activeRadius
            ? (1.0 - (dist / (segCount * 0.85))).clamp(0.35, 1.0)
            : 0.10;
        final bool isLit = dist <= activeRadius && intensity > 0.02;
        final bool isPeakAmber =
            widget.pursuitMode && isLit && dist >= centerIndex - 1;

        final Color ledColor = isPeakAmber
            ? Color.fromRGBO(255, 171, 0, opacity)
            : Color.fromRGBO(255, 24, 24, opacity);

        return AnimatedContainer(
          duration: animDur,
          margin: EdgeInsets.symmetric(vertical: widget.compact ? 1.8 : 2.5),
          width: segW,
          height: segH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            color: ledColor,
            boxShadow: isLit
                ? <BoxShadow>[
                    BoxShadow(
                      color: isPeakAmber
                          ? const Color(0xCCFFAB00)
                          : const Color(0xAAFF1717),
                      blurRadius: widget.pursuitMode ? 11 : 8,
                      spreadRadius: widget.pursuitMode ? 1.0 : 0.5,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
