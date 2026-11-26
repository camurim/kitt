import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitturbo/config/kitt_persona.dart';
import 'package:kitturbo/managers/android_auto_bridge_service.dart';
import 'package:kitturbo/managers/audio_engine_manager.dart';
import 'package:kitturbo/managers/aux_apps_manager.dart';
import 'package:kitturbo/managers/flag_dossier_service.dart';
import 'package:kitturbo/managers/notification_filter_manager.dart';
import 'package:kitturbo/managers/phone_call_manager.dart';
import 'package:kitturbo/managers/vehicle_telemetry_service.dart';
import 'package:kitturbo/models/aux_slot_config.dart';
import 'package:kitturbo/models/kitt_state.dart';

void main() {
  group('KittPersonaConfig', () {
    test('builds PT-BR system instruction with driver name and drive mode', () {
      const KittPersonaConfig persona = KittPersonaConfig(
        driverName: 'Carlos',
        languageCode: 'pt-BR',
        sarcasmLevel: 0.8,
      );

      final String prompt = persona.buildSystemInstruction(
        DriveMode.pursuit,
        flagDossiersMarkdown: '# ARQUIVOS CONFIDENCIAIS F.L.A.G.\n\n## Alvo: Bigode\n- Controla o porto.',
      );
      expect(prompt, contains('Carlos'));
      expect(prompt, contains('PURSUIT'));
      expect(prompt, contains('Português do Brasil'));
      expect(prompt, contains('send_flag_transmission_reply'));
      expect(prompt, contains('Confirma o envio?'));
      expect(prompt, contains('[BANCO DE DADOS DE INTELIGÊNCIA DA F.L.A.G.]'));
      expect(prompt, contains('Bigode'));
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
          'trigger_micro_jam',
          'activate_ski_mode',
          'run_structural_scan',
          'launch_aux_app',
          'make_phone_call',
          'add_flag_dossier_entry',
          'send_flag_transmission_reply',
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

    test('synthesizes valid WAV buffer for Micro Jam interference SFX', () {
      final Uint8List wav = AudioEngineManager.buildInterferenceWavBytes();
      expect(wav.length, greaterThan(44));
      // RIFF....WAVE header
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });

    test('synthesizes valid WAV buffer for F.L.A.G. commlink beep SFX', () {
      final Uint8List wav = AudioEngineManager.buildCommsBeepWavBytes();
      expect(wav.length, greaterThan(44));
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });

    test('synthesizes valid WAV buffer for F.L.A.G. transmission sent beep SFX', () {
      final Uint8List wav = AudioEngineManager.buildTransmissionSentBeepWavBytes();
      expect(wav.length, greaterThan(44));
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
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

  group('AndroidAutoBridgeService', () {
    test('computes dynamic status subtitles for online, pursuit, mic and gadgets', () {
      expect(
        AndroidAutoBridgeService.computeStatusSubtitle(
          connectionState: LiveConnectionState.ready,
          driveMode: DriveMode.normalCruise,
          isMicActive: false,
          activeGadget: null,
        ),
        'ONLINE - AGUARDANDO COMANDO',
      );
      expect(
        AndroidAutoBridgeService.computeStatusSubtitle(
          connectionState: LiveConnectionState.ready,
          driveMode: DriveMode.pursuit,
          isMicActive: false,
          activeGadget: null,
        ),
        'PURSUIT MODE ENGAGED',
      );
      expect(
        AndroidAutoBridgeService.computeStatusSubtitle(
          connectionState: LiveConnectionState.ready,
          driveMode: DriveMode.normalCruise,
          isMicActive: true,
          activeGadget: null,
        ),
        'OUVINDO... (GEMINI LIVE)',
      );
      expect(
        AndroidAutoBridgeService.computeStatusSubtitle(
          connectionState: LiveConnectionState.ready,
          driveMode: DriveMode.pursuit,
          isMicActive: false,
          activeGadget: GadgetType.turboBoost,
        ),
        'TURBO BOOST ENGAGED',
      );
    });
  });

  group('NotificationFilterManager (F.L.A.G. Comms Filter)', () {
    test('highlights messaging apps and filters only authorized packages when auto-read is on', () async {
      final NotificationFilterManager mgr = NotificationFilterManager();
      final List<IncomingNotificationEvent> received = <IncomingNotificationEvent>[];
      final sub = mgr.incomingNotifications.listen(received.add);

      const InstalledAppEntry wa = InstalledAppEntry(
        name: 'WhatsApp',
        packageName: 'com.whatsapp',
      );
      const InstalledAppEntry maps = InstalledAppEntry(
        name: 'Maps',
        packageName: 'com.google.android.apps.maps',
      );
      const InstalledAppEntry tg = InstalledAppEntry(
        name: 'Telegram',
        packageName: 'org.telegram.messenger',
      );

      expect(NotificationFilterManager.isMessagingApp(wa), isTrue);
      expect(NotificationFilterManager.isMessagingApp(tg), isTrue);
      expect(NotificationFilterManager.isMessagingApp(maps), isFalse);

      final List<InstalledAppEntry> sorted =
          NotificationFilterManager.sortAppsHighlightingMessaging(
        <InstalledAppEntry>[maps, wa, tg],
      );
      expect(sorted.last.packageName, 'com.google.android.apps.maps');

      await mgr.setPackageAllowed('com.whatsapp', true);

      // App não autorizado: ignorado
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.google.android.apps.maps',
          appName: 'Maps',
          title: 'Trânsito',
          text: 'Rota atualizada',
        ),
        isFalse,
      );

      // App autorizado: encaminhado
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: 'Devon',
          text: 'Michael, volte à Fundação.',
        ),
        isTrue,
      );

      // Chave geral silenciada: bloqueado mesmo se autorizado
      await mgr.setAutoReadEnabled(false);
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: 'Bonnie',
          text: 'Diagnóstico pronto.',
        ),
        isFalse,
      );

      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(
        received.first.toGeminiPrompt(),
        contains('[TRANSMISSÃO F.L.A.G. RECEBIDA | Canal: WhatsApp | Remetente: Devon | Conteúdo: Michael, volte à Fundação.]'),
      );
      expect(
        IncomingNotificationEvent.hudBannerTitle,
        'INCOMING TRANSMISSION // F.L.A.G. ENCRYPTED CHANNEL',
      );

      // Rejeita resumo de grupo, texto/título vazio e duplicata dentro da janela
      await mgr.setAutoReadEnabled(true);
      final DateTime t0 = DateTime(2026, 11, 25, 21, 20, 0);
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: 'Grupo F.L.A.G.',
          text: '3 novas mensagens',
          timestamp: t0,
        ),
        isFalse,
      );
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: '',
          text: 'Mensagem sem remetente',
          timestamp: t0,
        ),
        isFalse,
      );
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: 'April',
          text: 'Relatório enviado',
          timestamp: t0,
        ),
        isTrue,
      );
      // Duplicata 2s depois: bloqueada
      expect(
        mgr.processIncomingNotification(
          packageName: 'com.whatsapp',
          appName: 'WhatsApp',
          title: 'April',
          text: 'Relatório enviado',
          timestamp: t0.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );

      await sub.cancel();
      mgr.dispose();
    });

    test('FlagTransmissionQueue queues second message while KITT is speaking and delivers after turnComplete', () {
      bool speaking = false;
      final List<String> deliveredSenders = <String>[];
      final FlagTransmissionQueue queue = FlagTransmissionQueue(
        isBusySpeaking: () => speaking,
        onDeliver: (IncomingNotificationEvent ev) {
          deliveredSenders.add(ev.title);
          speaking = true;
        },
      );

      final IncomingNotificationEvent msg1 = IncomingNotificationEvent(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Devon',
        text: 'Primeira transmissão.',
        timestamp: DateTime(2026, 11, 25, 21, 20, 0),
      );
      final IncomingNotificationEvent msg2 = IncomingNotificationEvent(
        packageName: 'org.telegram.messenger',
        appName: 'Telegram',
        title: 'Bonnie',
        text: 'Segunda transmissão.',
        timestamp: DateTime(2026, 11, 25, 21, 20, 1),
      );

      queue.enqueue(msg1);
      expect(deliveredSenders, <String>['Devon']);
      expect(queue.pendingCount, 0);

      // Chega a segunda enquanto KITT ainda fala -> entra na fila
      queue.enqueue(msg2);
      expect(deliveredSenders, <String>['Devon']);
      expect(queue.pendingCount, 1);

      // KITT termina de falar -> entrega automaticamente a segunda
      speaking = false;
      queue.notifySpeechCompleted();
      expect(deliveredSenders, <String>['Devon', 'Bonnie']);
      expect(queue.pendingCount, 0);

      queue.clear();
    });
  });

  group('FlagDossierService (Persistent Markdown Database)', () {
    test('initializes flag_dossiers.md, upserts, appends, parses and deletes entries', () async {
      final Directory tmpDir =
          await Directory.systemTemp.createTemp('kitt_flag_dossiers_test_');
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });

      final FlagDossierService svc = FlagDossierService(
        directoryProvider: () async => tmpDir,
      );

      final String initial = await svc.readRawMarkdown();
      expect(initial, contains('# ARQUIVOS CONFIDENCIAIS F.L.A.G.'));
      expect(FlagDossierService.parseEntries(initial), isEmpty);

      await svc.upsertEntry(
        targetName: 'Bigode',
        details: 'Controla o porto.',
      );
      await svc.upsertEntry(
        targetName: 'Bigode',
        details: 'Usa um sedã preto blindado.',
        appendIfExists: true,
      );

      final String afterUpsert = await svc.readRawMarkdown();
      final List<FlagDossierEntry> entries =
          FlagDossierService.parseEntries(afterUpsert);
      expect(entries.length, 1);
      expect(entries.first.targetName, 'Bigode');
      expect(entries.first.details, contains('Controla o porto.'));
      expect(entries.first.details, contains('sedã preto blindado'));

      final String afterDelete = await svc.deleteEntry('Bigode');
      expect(FlagDossierService.parseEntries(afterDelete), isEmpty);
    });
  });
}
