import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Evento gerado quando uma manobra brusca ultrapassa o limiar de aceleração linear.
class ManeuverEvent {
  const ManeuverEvent({
    required this.kind,
    required this.peakMs2,
    required this.gForce,
    required this.speedKmh,
    required this.timestamp,
  });

  /// Ex.: 'curva fechada' ou 'freada ou aceleração brusca'
  final String kind;
  final double peakMs2;
  final double gForce;
  final double speedKmh;
  final DateTime timestamp;

  /// Mensagem estruturada enviada em tempo real para a sessão Gemini Live.
  String toGeminiSystemEvent() {
    return '[SISTEMA: Manobra brusca detectada ($kind), força G elevada '
        '(${gForce.toStringAsFixed(2)}G / ${peakMs2.toStringAsFixed(1)} m/s²), '
        'velocidade GPS atual: ${speedKmh.round()} km/h]. '
        'Comente espontaneamente em voz alta no personagem do KITT.';
  }
}

/// Serviço de telemetria real do veículo:
/// - Velocímetro real em km/h via GPS (`geolocator`)
/// - Monitoramento de aceleração linear sem gravidade (`sensors_plus`) para detectar
///   freadas bruscas ou curvas fechadas (> 4.5 m/s²)
/// - Cooldown mínimo de 45 segundos entre reações automáticas do KITT
class VehicleTelemetryService {
  VehicleTelemetryService({
    this.maneuverThresholdMs2 = 4.5,
    this.reactionCooldown = const Duration(seconds: 45),
  });

  static const double standardGravity = 9.80665;

  final double maneuverThresholdMs2;
  final Duration reactionCooldown;

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _gpsSub;

  double _speedKmh = 0.0;
  bool _hasGpsLock = false;
  double _currentGForce = 0.0;
  bool _autoCommentsEnabled = true;
  bool _running = false;
  DateTime? _lastReactionAt;

  final StreamController<ManeuverEvent> _maneuverController =
      StreamController<ManeuverEvent>.broadcast();
  final StreamController<void> _updateController =
      StreamController<void>.broadcast();

  double get speedKmh => _speedKmh;
  bool get hasGpsLock => _hasGpsLock;
  double get currentGForce => _currentGForce;
  bool get autoCommentsEnabled => _autoCommentsEnabled;
  bool get isRunning => _running;

  Stream<ManeuverEvent> get maneuverReactions => _maneuverController.stream;
  Stream<void> get telemetryUpdates => _updateController.stream;

  void setAutoCommentsEnabled(bool enabled) {
    _autoCommentsEnabled = enabled;
    _updateController.add(null);
  }

  /// Avalia aceleração linear (já sem gravidade) e retorna o tipo/pico se exceder o limiar.
  static ({String kind, double peakMs2, double gForce})?
      evaluateLinearAcceleration({
    required double x,
    required double y,
    required double z,
    double thresholdMs2 = 4.5,
  }) {
    final double absX = x.abs();
    final double absY = y.abs();
    final double absZ = z.abs();
    final double horizontalPeak = math.max(absX, math.max(absY, absZ));
    final double magnitude = math.sqrt(x * x + y * y + z * z);

    if (horizontalPeak < thresholdMs2 && magnitude < thresholdMs2) {
      return null;
    }

    final String kind = absX >= math.max(absY, absZ)
        ? 'curva fechada'
        : 'freada ou aceleração brusca';
    final double peak = math.max(horizontalPeak, magnitude);
    return (
      kind: kind,
      peakMs2: peak,
      gForce: peak / standardGravity,
    );
  }

  /// Verifica se o cooldown mínimo de 45s já foi respeitado.
  bool canEmitAutoComment(DateTime now) {
    if (!_autoCommentsEnabled) return false;
    if (_lastReactionAt == null) return true;
    return now.difference(_lastReactionAt!) >= reactionCooldown;
  }

  /// Registra uma amostra de aceleração linear (útil também para testes).
  ManeuverEvent? processAccelerationSample({
    required double x,
    required double y,
    required double z,
    DateTime? now,
  }) {
    final double magnitude = math.sqrt(x * x + y * y + z * z);
    _currentGForce = magnitude / standardGravity;

    final ({String kind, double peakMs2, double gForce})? detected =
        evaluateLinearAcceleration(
      x: x,
      y: y,
      z: z,
      thresholdMs2: maneuverThresholdMs2,
    );

    if (detected == null) return null;

    final DateTime ts = now ?? DateTime.now();
    if (!canEmitAutoComment(ts)) return null;

    _lastReactionAt = ts;
    final ManeuverEvent event = ManeuverEvent(
      kind: detected.kind,
      peakMs2: detected.peakMs2,
      gForce: detected.gForce,
      speedKmh: _speedKmh,
      timestamp: ts,
    );
    if (!_maneuverController.isClosed) {
      _maneuverController.add(event);
    }
    return event;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _startAccelerometer();
    await _startGps();
    _updateController.add(null);
  }

  void _startAccelerometer() {
    try {
      _accelSub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (UserAccelerometerEvent e) {
          final double prevG = _currentGForce;
          processAccelerationSample(x: e.x, y: e.y, z: e.z);
          if ((_currentGForce - prevG).abs() >= 0.04) {
            _updateController.add(null);
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Fallback silencioso em emuladores/testes sem acelerômetro.
    }
  }

  Future<void> _startGps() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen(
        (Position pos) {
          final double rawKmh = pos.speed > 0 ? pos.speed * 3.6 : 0.0;
          _speedKmh = rawKmh < 1.5 ? 0.0 : rawKmh;
          _hasGpsLock = true;
          _updateController.add(null);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Fallback silencioso caso o GPS não esteja disponível.
    }
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    _accelSub = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    await _maneuverController.close();
    await _updateController.close();
  }
}
