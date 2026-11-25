import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Captura áudio contínuo do microfone em PCM 16 kHz 16-bit mono
/// para envio direto à Gemini Live API.
class MicStreamManager {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

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
      onChunk,
      onDone: () => _isRecording = false,
      onError: (_) => _isRecording = false,
    );
    return true;
  }

  Future<void> stopStreaming() async {
    await _streamSub?.cancel();
    _streamSub = null;
    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _isRecording = false;
    }
  }

  Future<void> dispose() async {
    await stopStreaming();
    await _recorder.dispose();
  }
}
