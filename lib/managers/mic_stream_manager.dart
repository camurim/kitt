import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Captura áudio contínuo do microfone em PCM 16 kHz 16-bit mono
/// para envio direto à Gemini Live API e expõe o nível RMS normalizado (0.0..1.0)
/// para feedback visual de ondas sonoras.
class MicStreamManager {
  final AudioRecorder _recorder = AudioRecorder();
  final ValueNotifier<double> micLevel = ValueNotifier<double>(0.0);
  StreamSubscription<Uint8List>? _streamSub;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Calcula o nível sonoro normalizado (0.0 a 1.0) de um chunk PCM 16-bit LE.
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
    return (rms * 4.2).clamp(0.0, 1.0);
  }

  Future<bool> startStreaming(void Function(Uint8List pcm16kChunk) onChunk) async {
    if (_isRecording) return true;

    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      return false;
    }

    if (!await _recorder.hasPermission()) {
      return false;
    }

    final Stream<Uint8List> stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _isRecording = true;
    _streamSub = stream.listen(
      (Uint8List chunk) {
        final double rawLevel = computeNormalizedRms(chunk);
        // Suavização leve para evitar tremulação brusca nas barras de onda.
        micLevel.value = (micLevel.value * 0.45 + rawLevel * 0.55).clamp(0.0, 1.0);
        onChunk(chunk);
      },
      onDone: () {
        _isRecording = false;
        micLevel.value = 0.0;
      },
      onError: (_) {
        _isRecording = false;
        micLevel.value = 0.0;
      },
    );
    return true;
  }

  Future<void> stopStreaming() async {
    await _streamSub?.cancel();
    _streamSub = null;
    micLevel.value = 0.0;
    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _isRecording = false;
    }
  }

  Future<void> dispose() async {
    await stopStreaming();
    micLevel.dispose();
    await _recorder.dispose();
  }
}
