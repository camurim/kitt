import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Motor de áudio do KITT:
/// - Reproduz chunks PCM 24 kHz 16-bit mono vindos da Gemini Live API
/// - Calcula amplitude RMS normalizada (0.0..1.0) para animar o KittVisualizer
/// - Toca efeitos sonoros locais (MP3) quando disponíveis em `assets/audio/`
class AudioEngineManager {
  static const int outputSampleRate = 24000;

  final ValueNotifier<double> voiceLevel = ValueNotifier<double>(0.0);
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _pcmInitialized = false;
  Timer? _decayTimer;

  Future<void> init() async {
    if (_pcmInitialized) return;
    try {
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      await FlutterPcmSound.setup(
        sampleRate: outputSampleRate,
        channelCount: 1,
      );
      await FlutterPcmSound.setFeedThreshold(outputSampleRate ~/ 10);
      _pcmInitialized = true;
    } catch (_) {
      // Em plataformas sem suporte nativo a PCM (ex.: testes), mantém fallback seguro.
      _pcmInitialized = false;
    }
  }

  /// Calcula o nível sonoro normalizado (0.0 a 1.0) de um buffer PCM 16-bit little-endian.
  static double computeNormalizedRms(Uint8List pcm16LittleEndian) {
    final int sampleCount = pcm16LittleEndian.lengthInBytes ~/ 2;
    if (sampleCount == 0) return 0.0;

    final ByteData data = ByteData.sublistView(pcm16LittleEndian);
    double sumSquares = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final int sample = data.getInt16(i * 2, Endian.little);
      final double norm = sample / 32768.0;
      sumSquares += norm * norm;
    }

    final double rms = math.sqrt(sumSquares / sampleCount);
    // Ganho suave para deixar a resposta visual do voicebox expressiva na fala.
    return (rms * 3.2).clamp(0.0, 1.0);
  }

  /// Recebe um chunk PCM 24 kHz do Gemini, atualiza o voicebox e envia ao alto-falante.
  Future<void> enqueuePcmChunk(Uint8List pcm24kBytes) async {
    if (pcm24kBytes.isEmpty) return;

    final double level = computeNormalizedRms(pcm24kBytes);
    voiceLevel.value = level;
    _scheduleLevelDecay();

    if (!_pcmInitialized) {
      await init();
    }
    if (!_pcmInitialized) return;

    final int sampleCount = pcm24kBytes.lengthInBytes ~/ 2;
    final ByteData data = ByteData.sublistView(pcm24kBytes);
    final List<int> samples = List<int>.generate(
      sampleCount,
      (int i) => data.getInt16(i * 2, Endian.little),
      growable: false,
    );

    try {
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
    } catch (_) {
      // Evita interromper a sessão caso o buffer nativo oscile.
    }
  }

  /// Toca um efeito sonoro local opcional (ex.: `audio/pursuit.mp3`).
  /// Falha silenciosamente caso você ainda não tenha adicionado os arquivos MP3.
  Future<void> playSfxAsset(String relativeAssetPath) async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(relativeAssetPath));
    } catch (_) {
      // Asset opcional ausente — segue normalmente sem erro.
    }
  }

  void _scheduleLevelDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 60), (Timer t) {
      final double next = voiceLevel.value * 0.72;
      if (next < 0.03) {
        voiceLevel.value = 0.0;
        t.cancel();
      } else {
        voiceLevel.value = next;
      }
    });
  }

  Future<void> dispose() async {
    _decayTimer?.cancel();
    voiceLevel.dispose();
    await _sfxPlayer.dispose();
    if (_pcmInitialized) {
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
      _pcmInitialized = false;
    }
  }
}
