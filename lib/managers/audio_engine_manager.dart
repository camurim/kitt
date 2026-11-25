import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Motor de áudio do KITT com gerenciamento de foco de áudio (ducking):
/// - Usa `audio_session` (`gainTransientMayDuck`) para reduzir suavemente o volume
///   do Spotify/rádio enquanto o KITT fala e restaurar automaticamente ao terminar.
/// - Reproduz chunks PCM 24 kHz 16-bit mono vindos da Gemini Live API.
/// - Calcula amplitude RMS normalizada (0.0..1.0) para animar o KittVisualizer.
/// - Toca efeitos sonoros locais (MP3) também em modo ducking.
class AudioEngineManager {
  static const int outputSampleRate = 24000;

  final ValueNotifier<double> voiceLevel = ValueNotifier<double>(0.0);
  final ap.AudioPlayer _sfxPlayer = ap.AudioPlayer();

  AudioSession? _audioSession;
  bool _pcmInitialized = false;
  bool _focusActive = false;
  Timer? _decayTimer;
  Timer? _focusReleaseTimer;

  Future<void> init() async {
    await _configureAudioSession();
    await _configureSfxPlayer();

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

  Future<void> _configureAudioSession() async {
    if (_audioSession != null) return;
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers |
                  AVAudioSessionCategoryOptions.defaultToSpeaker |
                  AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistant,
            flags: AndroidAudioFlags.none,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      _audioSession = session;
    } catch (_) {
      // Ignora em ambientes sem suporte nativo (ex.: testes unitários).
    }
  }

  Future<void> _configureSfxPlayer() async {
    try {
      await _sfxPlayer.setAudioContext(
        ap.AudioContext(
          android: const ap.AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: ap.AndroidContentType.sonification,
            usageType: ap.AndroidUsageType.assistanceSonification,
            audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: ap.AudioContextIOS(
            category: ap.AVAudioSessionCategory.playback,
            options: const <ap.AVAudioSessionOptions>{
              ap.AVAudioSessionOptions.duckOthers,
              ap.AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _acquireDuckingFocus() async {
    _focusReleaseTimer?.cancel();
    if (_focusActive) return;
    try {
      if (_audioSession == null) {
        await _configureAudioSession();
      }
      final bool granted = await _audioSession?.setActive(true) ?? false;
      _focusActive = granted;
    } catch (_) {}
  }

  void _scheduleFocusRelease() {
    _focusReleaseTimer?.cancel();
    _focusReleaseTimer = Timer(const Duration(milliseconds: 650), () async {
      if (!_focusActive) return;
      try {
        await _audioSession?.setActive(false);
      } catch (_) {}
      _focusActive = false;
    });
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
    return (rms * 3.2).clamp(0.0, 1.0);
  }

  /// Recebe um chunk PCM 24 kHz do Gemini, ativa ducking, atualiza o voicebox e reproduz.
  Future<void> enqueuePcmChunk(Uint8List pcm24kBytes) async {
    if (pcm24kBytes.isEmpty) return;

    await _acquireDuckingFocus();

    final double level = computeNormalizedRms(pcm24kBytes);
    voiceLevel.value = level;
    _scheduleLevelDecay();
    _scheduleFocusRelease();

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

  /// Toca um efeito sonoro local opcional (ex.: `audio/pursuit.mp3`) com ducking.
  Future<void> playSfxAsset(String relativeAssetPath) async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(ap.AssetSource(relativeAssetPath));
    } catch (_) {
      // Asset opcional ausente — segue normalmente sem erro.
    }
  }

  /// Toca o efeito sonoro de interferência eletromagnética do MICRO JAM.
  /// Tenta primeiro o asset MP3 opcional e, na ausência, sintetiza um burst
  /// retrô de estática/pulso EMP em memória (WAV PCM 16-bit).
  Future<void> playMicroJamInterferenceSfx() async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(ap.AssetSource('audio/micro_jam.mp3'));
      return;
    } catch (_) {
      // Fallback para síntese de interferência eletromagnética em memória.
    }

    try {
      final Uint8List wavBytes = buildInterferenceWavBytes();
      await _sfxPlayer.stop();
      await _sfxPlayer.play(ap.BytesSource(wavBytes, mimeType: 'audio/wav'));
    } catch (_) {
      // Ignora em ambientes de teste sem canal nativo de áudio.
    }
  }

  /// Gera um buffer WAV 16-bit mono (16 kHz, ~1.1s) com pulso EMP e estática retrô.
  static Uint8List buildInterferenceWavBytes() {
    const int sampleRate = 16000;
    const int durationMs = 1100;
    const int numSamples = (sampleRate * durationMs) ~/ 1000;
    const int dataBytes = numSamples * 2;
    final ByteData wav = ByteData(44 + dataBytes);

    // Header RIFF/WAVE
    wav.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    wav.setUint32(4, 36 + dataBytes, Endian.little);
    wav.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    wav.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    wav.setUint32(16, 16, Endian.little); // PCM chunk size
    wav.setUint16(20, 1, Endian.little); // PCM format
    wav.setUint16(22, 1, Endian.little); // Mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    wav.setUint16(32, 2, Endian.little); // Block align
    wav.setUint16(34, 16, Endian.little); // Bits per sample
    wav.setUint32(36, 0x64617461, Endian.big); // "data"
    wav.setUint32(40, dataBytes, Endian.little);

    final math.Random rng = math.Random(19820926);
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double norm = i / numSamples;
      final double env = norm < 0.08
          ? norm / 0.08
          : norm > 0.72
              ? (1.0 - norm) / 0.28
              : 1.0;

      // Varredura descendente de frequência EMP + modulação quadrada + estática
      final double sweepFreq = 980.0 - 740.0 * norm;
      final double empTone = math.sin(2 * math.pi * sweepFreq * t);
      final double pulseMod =
          math.sin(2 * math.pi * (14.0 + 18.0 * norm) * t) > 0 ? 1.0 : 0.35;
      final double staticNoise = (rng.nextDouble() * 2.0 - 1.0) * 0.48;
      final double mixed = ((empTone * 0.55 * pulseMod) + staticNoise) * env;
      final int sample = (mixed * 18000).round().clamp(-32767, 32767);
      wav.setInt16(44 + i * 2, sample, Endian.little);
    }

    return wav.buffer.asUint8List();
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
    _focusReleaseTimer?.cancel();
    if (_focusActive) {
      try {
        await _audioSession?.setActive(false);
      } catch (_) {}
      _focusActive = false;
    }
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
