import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Ícone animado de ondas sonoras (5 barras equalizadoras) que reage em tempo real
/// ao nível de áudio do microfone e mantém uma ondulação suave enquanto o KITT
/// está escutando o motorista.
class ListeningWaveformIcon extends StatefulWidget {
  const ListeningWaveformIcon({
    super.key,
    required this.levelListenable,
    this.width = 24,
    this.height = 20,
    this.color = Colors.white,
    this.barCount = 5,
  });

  final ValueListenable<double> levelListenable;
  final double width;
  final double height;
  final Color color;
  final int barCount;

  @override
  State<ListeningWaveformIcon> createState() => _ListeningWaveformIconState();
}

class _ListeningWaveformIconState extends State<ListeningWaveformIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _waveController,
          widget.levelListenable,
        ]),
        builder: (BuildContext context, _) {
          final double phase = _waveController.value * math.pi * 2;
          final double mic = widget.levelListenable.value.clamp(0.0, 1.0);
          final int count = widget.barCount;
          final double centerIdx = (count - 1) / 2.0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List<Widget>.generate(count, (int i) {
              // Perfil simétrico: barras centrais mais altas que as laterais.
              final double distNorm =
                  centerIdx == 0 ? 0.0 : (i - centerIdx).abs() / centerIdx;
              final double profile = 1.0 - (distNorm * 0.38);

              // Ondulação suave contínua (mostra que está escutando mesmo em silêncio)
              // somada ao pico real capturado pelo microfone.
              final double idleWave =
                  0.24 + 0.16 * (math.sin(phase + i * 1.15) * 0.5 + 0.5);
              final double voiceBoost =
                  mic * (0.62 + 0.20 * math.sin(phase * 1.7 + i * 0.9).abs());
              final double factor =
                  ((idleWave + voiceBoost) * profile).clamp(0.18, 1.0);

              return Container(
                key: ValueKey<String>('listening_wave_bar_$i'),
                width: 3.0,
                height: widget.height * factor,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2.0),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45 + mic * 0.4),
                      blurRadius: 4 + mic * 4,
                    ),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
