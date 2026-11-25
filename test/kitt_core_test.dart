import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt_gemini/config/kitt_persona.dart';
import 'package:kitt_gemini/managers/audio_engine_manager.dart';
import 'package:kitt_gemini/managers/aux_apps_manager.dart';
import 'package:kitt_gemini/managers/phone_call_manager.dart';
import 'package:kitt_gemini/managers/vehicle_telemetry_service.dart';
import 'package:kitt_gemini/models/aux_slot_config.dart';
import 'package:kitt_gemini/models/kitt_state.dart';

void main() {
  group('KittPersonaConfig', () {
    test('builds PT-BR system instruction with driver name and drive mode', () {
      const KittPersonaConfig persona = KittPersonaConfig(
        driverName: 'Carlos',
        languageCode: 'pt-BR',
        sarcasmLevel: 0.8,
      );

      final String prompt = persona.buildSystemInstruction(DriveMode.pursuit);
      expect(prompt, contains('Carlos'));
      expect(prompt, contains('PURSUIT'));
      expect(prompt, contains('Português do Brasil'));
    });

    test('exposes all expected Gemini Live function declarations', () {
      final List<Map<String, dynamic>> tools = buildKittToolDeclarations();
      final List<dynamic> decls =
          tools.first['functionDeclarations'] as List<dynamic>;
      final Set<String> names = decls
          .map((dynamic e) => (e as Map<String, dynamic>)['name'] as String)
          .toSet();

      expect(
        names,
        containsAll(<String>[
          'set_operation_mode',
          'set_drive_mode',
          'deploy_oil_slick',
          'activate_smoke_screen',
          'trigger_turbo_boost',
          'launch_aux_app',
          'make_phone_call',
          'scan_environment',
          'call_contact',
          'trigger_system_effect',
        ]),
      );
    });
  });

  group('AudioEngineManager.computeNormalizedRms', () {
    test('returns 0.0 for silence', () {
      final Uint8List silence = Uint8List(200);
      expect(AudioEngineManager.computeNormalizedRms(silence), 0.0);
    });

    test('returns elevated normalized level for loud PCM16 signal', () {
      final ByteData buf = ByteData(200);
      for (int i = 0; i < 100; i++) {
        buf.setInt16(i * 2, i.isEven ? 16000 : -16000, Endian.little);
      }
      final double level =
          AudioEngineManager.computeNormalizedRms(buf.buffer.asUint8List());
      expect(level, greaterThan(0.8));
      expect(level, lessThanOrEqualTo(1.0));
    });
  });

  group('PhoneCallManager', () {
    test('sanitizes formatted phone numbers preserving +, * and #', () {
      expect(
        PhoneCallManager.sanitizePhoneNumber('+55 (11) 98765-4321'),
        '+5511987654321',
      );
      expect(PhoneCallManager.sanitizePhoneNumber('*123#'), '*123#');
    });
  });

  group('AuxSlotConfig & AuxAppsManager', () {
    test('serializes and resolves auxiliary slots by number and label', () {
      const AuxSlotConfig navSlot = AuxSlotConfig(
        slotNumber: 1,
        label: 'NAVEGAÇÃO',
        packageName: 'com.waze',
        appName: 'Waze',
        iconId: 'navigation',
      );
      final AuxSlotConfig restored = AuxSlotConfig.fromJson(navSlot.toJson());
      expect(restored.isConfigured, isTrue);
      expect(restored.packageName, 'com.waze');
      expect(restored.hudIcon, AuxHudIcon.navigation);

      final List<AuxSlotConfig> slots = <AuxSlotConfig>[
        restored,
        const AuxSlotConfig(slotNumber: 2),
        const AuxSlotConfig(slotNumber: 3),
        const AuxSlotConfig(slotNumber: 4),
      ];

      expect(AuxAppsManager.resolveSlot(slots, slotNumber: 1)?.packageName, 'com.waze');
      expect(AuxAppsManager.resolveSlot(slots, query: 'iniciar navegacao')?.slotNumber, 1);
      expect(AuxAppsManager.resolveSlot(slots, query: 'Waze')?.slotNumber, 1);
    });
  });

  group('DriveMode operational modes', () {
    test('parses surveillance, pursuit and normal modes', () {
      expect(DriveMode.fromApiValue('surveillance'), DriveMode.surveillance);
      expect(DriveMode.fromApiValue('pursuit'), DriveMode.pursuit);
      expect(DriveMode.fromApiValue('normal'), DriveMode.normalCruise);
    });
  });

  group('VehicleTelemetryService', () {
    test('detects harsh lateral/longitudinal maneuvers above 4.5 m/s2', () {
      expect(
        VehicleTelemetryService.evaluateLinearAcceleration(
          x: 1.2,
          y: 0.8,
          z: 0.5,
        ),
        isNull,
      );

      final ({String kind, double peakMs2, double gForce})? turn =
          VehicleTelemetryService.evaluateLinearAcceleration(
        x: 5.4,
        y: 0.6,
        z: 0.2,
      );
      expect(turn, isNotNull);
      expect(turn!.kind, 'curva fechada');
      expect(turn.peakMs2, greaterThanOrEqualTo(5.4));

      final ({String kind, double peakMs2, double gForce})? brake =
          VehicleTelemetryService.evaluateLinearAcceleration(
        x: 0.4,
        y: -6.1,
        z: 0.3,
      );
      expect(brake, isNotNull);
      expect(brake!.kind, 'freada ou aceleração brusca');
    });

    test('enforces 45-second cooldown and respects mute toggle', () {
      final VehicleTelemetryService svc = VehicleTelemetryService();
      final DateTime t0 = DateTime(2026, 11, 25, 16, 0, 0);

      final ManeuverEvent? first = svc.processAccelerationSample(
        x: 5.8,
        y: 0.0,
        z: 0.0,
        now: t0,
      );
      expect(first, isNotNull);
      expect(first!.toGeminiSystemEvent(), contains('Manobra brusca detectada'));

      // 20s depois: bloqueado pelo cooldown de 45s
      final ManeuverEvent? blocked = svc.processAccelerationSample(
        x: 6.2,
        y: 0.0,
        z: 0.0,
        now: t0.add(const Duration(seconds: 20)),
      );
      expect(blocked, isNull);

      // 46s depois: permitido novamente
      final ManeuverEvent? allowed = svc.processAccelerationSample(
        x: 6.2,
        y: 0.0,
        z: 0.0,
        now: t0.add(const Duration(seconds: 46)),
      );
      expect(allowed, isNotNull);

      // Silenciado pelo usuário: bloqueado mesmo após 120s
      svc.setAutoCommentsEnabled(false);
      final ManeuverEvent? muted = svc.processAccelerationSample(
        x: 7.0,
        y: 0.0,
        z: 0.0,
        now: t0.add(const Duration(seconds: 120)),
      );
      expect(muted, isNull);
    });
  });
}
