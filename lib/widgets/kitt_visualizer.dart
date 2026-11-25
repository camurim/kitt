import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Voicebox clássico do KITT com 3 colunas de segmentos LED vermelhos.
///
/// Expande simetricamente a partir do centro conforme o nível sonoro PCM (`0.0..1.0`):
/// - Coluna central: resposta completa (`100%`)
/// - Colunas laterais: resposta modulada (`68%`)
class KittVisualizer extends StatelessWidget {
  const KittVisualizer({
    super.key,
    required this.levelListenable,
    this.segmentsPerColumn = 11,
  });

  final ValueListenable<double> levelListenable;
  final int segmentsPerColumn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B2B33), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x55FF1111),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: levelListenable,
        builder: (BuildContext context, double level, _) {
          final double clamped = level.clamp(0.0, 1.0);
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildColumn(clamped * 0.68),
              const SizedBox(width: 14),
              _buildColumn(clamped),
              const SizedBox(width: 14),
              _buildColumn(clamped * 0.68),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColumn(double intensity) {
    final int centerIndex = segmentsPerColumn ~/ 2;
    // Garante o segmento central suavemente aceso em standby para o visual clássico.
    final double activeRadius =
        intensity <= 0.02 ? 0.5 : (intensity * centerIndex) + 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(segmentsPerColumn, (int index) {
        final double dist = (index - centerIndex).abs().toDouble();
        final double opacity = dist <= activeRadius
            ? (1.0 - (dist / (segmentsPerColumn * 0.85))).clamp(0.35, 1.0)
            : 0.10;
        final bool isLit = dist <= activeRadius && intensity > 0.02;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 55),
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          width: 30,
          height: 11,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            color: Color.fromRGBO(255, 24, 24, opacity),
            boxShadow: isLit
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0xAAFF1717),
                      blurRadius: 8,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
