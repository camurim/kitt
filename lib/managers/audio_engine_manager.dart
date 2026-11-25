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
