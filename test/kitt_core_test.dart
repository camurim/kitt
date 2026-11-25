import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt_gemini/config/kitt_persona.dart';
import 'package:kitt_gemini/managers/audio_engine_manager.dart';
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
          'set_drive_mode',
          'activate_turbo_boost',
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
}
