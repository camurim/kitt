import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Overlay em tela cheia do Modo Stand-by / Scanner Frontal clássico do KITT:
/// - Barra de 8 segmentos retangulares com brilho neon vermelho (`BoxShadow`)
///   e rastro gradual de decaimento (efeito lâmpada halógena 1982)
/// - Loop suave do efeito sonoro do scanner (`audio/scanner_loop.mp3`) com controle de volume
/// - Recolhe suavemente ao tocar na tela, clicar no microfone ou quando o KITT começa a falar
class KittScannerOverlay extends StatefulWidget {
  const KittScannerOverlay({
    super.key,
    required this.onWake,
    required this.onWakeWithMic,
    this.voiceLevelListenable,
    this.enableAudio = true,
  });

  final VoidCallback onWake;
  final VoidCallback onWakeWithMic;
  final ValueListenable<double>? voiceLevelListenable;
  final bool enableAudio;

  @override
  State<KittScannerOverlay> createState() => _KittScannerOverlayState();
}

class _KittScannerOverlayState extends State<KittScannerOverlay>
    with TickerProviderStateMixin {
  static const int _segmentCount = 8;

  late final AnimationController _sweepController;
  late final AnimationController _exitController;
  final AudioPlayer _scannerPlayer = AudioPlayer();

  /// Intensidade individual (0.0..1.0) de cada um dos 8 segmentos para o rastro gradual.
  final List<double> _intensities = List<double>.filled(_segmentCount, 0.0);
  double _volume = 0.55;
  bool _muted = false;
  bool _exiting = false;
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )
      ..addListener(_updateTrail)
      ..repeat(reverse: true);

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0,
    );

    widget.voiceLevelListenable?.addListener(_onVoiceActivity);

    if (widget.enableAudio) {
      _startScannerAudio();
    }
  }

  void _onVoiceActivity() {
    final double level = widget.voiceLevelListenable?.value ?? 0.0;
    if (level > 0.12 && !_exiting) {
      _dismiss(activateMic: false);
    }
  }

  Future<void> _startScannerAudio() async {
    try {
      await _scannerPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const <AVAudioSessionOptions>{
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      await _scannerPlayer.setReleaseMode(ReleaseMode.loop);
      await _scannerPlayer.setVolume(_muted ? 0.0 : _volume);
      await _scannerPlayer.play(AssetSource('audio/scanner_loop.mp3'));
      _audioPlaying = true;
    } catch (_) {
      // Asset opcional ausente — animação visual segue normalmente.
      _audioPlaying = false;
    }
  }

  Future<void> _applyVolume() async {
    if (!_audioPlaying) return;
    try {
      await _scannerPlayer.setVolume(_muted ? 0.0 : _volume);
    } catch (_) {}
  }

  void _updateTrail() {
    final double pos = _sweepController.value * (_segmentCount - 1);
    for (int i = 0; i < _segmentCount; i++) {
      final double dist = (i - pos).abs();
      // Segmento sob o foco atinge brilho máximo; vizinhos imediatos recebem halo suave
      final double target = dist < 0.55
          ? 1.0
          : dist < 1.35
              ? (1.0 - (dist - 0.55) / 0.80) * 0.55
              : 0.0;
      // Decaimento gradual para reproduzir o rastro clássico das luzes anteriores
      final double decayed = _intensities[i] * 0.86;
      _intensities[i] = target > decayed ? target : decayed;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _dismiss({required bool activateMic}) async {
    if (_exiting) return;
    _exiting = true;
    _sweepController.stop();
    HapticFeedback.lightImpact();

    if (_audioPlaying) {
      try {
        await _scannerPlayer.stop();
      } catch (_) {}
      _audioPlaying = false;
    }

    await _exitController.reverse();
    if (!mounted) return;
    if (activateMic) {
      widget.onWakeWithMic();
    } else {
      widget.onWake();
    }
  }

  @override
  void dispose() {
    widget.voiceLevelListenable?.removeListener(_onVoiceActivity);
    _sweepController.removeListener(_updateTrail);
    _sweepController.dispose();
    _exitController.dispose();
    _scannerPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> fade = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeInOutCubic,
    );
    final Animation<double> scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: scale,
        child: Material(
          color: const Color(0xF8030305),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                // Cabeçalho discreto Stand-by
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'K.i.t.Turbo • STAND-BY SCANNER',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF8E2428),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                        ),
                      ),
                      IconButton(
                        tooltip: _muted ? 'Ativar som do scanner' : 'Silenciar scanner',
                        onPressed: () {
                          setState(() => _muted = !_muted);
                          _applyVolume();
                        },
                        icon: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: const Color(0xFFFF5252),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                // Área central clicável com a barra de 8 segmentos LED
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _dismiss(activateMic: false),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _buildScannerBar(),
                            const SizedBox(height: 28),
                            const Text(
                              'TOQUE NA TELA PARA ATIVAR O PAINEL',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: Color(0xFF7A7A8C),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Controle de volume do scanner + botão rápido de voz
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.graphic_eq,
                            color: Color(0xFF7A282C),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'SCANNER VOL',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFF7A7A8C),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _muted ? 0.0 : _volume,
                              activeColor: const Color(0xFFFF1744),
                              inactiveColor: const Color(0xFF2B1215),
                              onChanged: (double v) {
                                setState(() {
                                  _volume = v;
                                  _muted = v <= 0.01;
                                });
                                _applyVolume();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _dismiss(activateMic: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                            side: const BorderSide(
                              color: Color(0xAAFF1744),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.mic),
                          label: const Text(
                            'ATIVAR MICROFONE E CONVERSAR COM O KITT',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScannerBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0406),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D1216), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x44FF1111),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: List<Widget>.generate(_segmentCount, (int i) {
          final double intensity = _intensities[i].clamp(0.0, 1.0);
          final bool isLit = intensity > 0.06;

          return Expanded(
            child: Container(
              key: ValueKey<String>('kitt_scanner_seg_$i'),
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: isLit
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color.fromRGBO(255, 20, 20, 0.25 + intensity * 0.75),
                          Color.fromRGBO(
                            255,
                            (45 + intensity * 75).round(),
                            (20 + intensity * 35).round(),
                            0.35 + intensity * 0.65,
                          ),
                          Color.fromRGBO(220, 0, 0, 0.25 + intensity * 0.75),
                        ],
                      )
                    : null,
                color: isLit ? null : const Color(0xFF1A0607),
                boxShadow: isLit
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Color.fromRGBO(
                            255,
                            18,
                            18,
                            (intensity * 0.90).clamp(0.0, 0.90),
                          ),
                          blurRadius: 10 + intensity * 16,
                          spreadRadius: intensity * 2.2,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}
