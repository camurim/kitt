import 'package:flutter/services.dart';

import '../models/kitt_state.dart';

/// Ponte Flutter ↔ Android Auto via MethodChannel (`net.carlosamorim.kitturbo/android_auto`).
///
/// Escuta comandos disparados na tela do carro (`KittMainScreen`) e sincroniza
/// o estado/subtítulo dinâmico do K.I.T.T. de volta para o Android Auto sempre
/// que o modo operacional, microfone, conexão ou gadget mudar.
class AndroidAutoBridgeService {
  AndroidAutoBridgeService({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'net.carlosamorim.kitturbo/android_auto';

  final MethodChannel _channel;
  Future<void> Function(String command)? _onCommand;
  String? _lastPayloadSignature;

  /// Registra o handler de comandos vindos do Android Auto.
  void attach({
    required Future<void> Function(String command) onCommand,
  }) {
    _onCommand = onCommand;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAutoCommand') {
      final Map<Object?, Object?>? args =
          call.arguments as Map<Object?, Object?>?;
      final String? command = args?['command'] as String?;
      if (command != null && command.isNotEmpty && _onCommand != null) {
        await _onCommand!(command);
      }
      return true;
    }
    return null;
  }

  /// Gera o subtítulo dinâmico exibido no cabeçalho do Android Auto.
  static String computeStatusSubtitle({
    required LiveConnectionState connectionState,
    required DriveMode driveMode,
    required bool isMicActive,
    required GadgetType? activeGadget,
  }) {
    if (activeGadget != null) {
      return switch (activeGadget) {
        GadgetType.turboBoost => 'TURBO BOOST ENGAGED',
        GadgetType.oilSlick => 'OIL SLICK DEPLOYED',
        GadgetType.smokeScreen => 'SMOKE SCREEN ACTIVE',
        GadgetType.microJam => 'MICRO JAM ACTIVE',
        GadgetType.skiMode => 'SKI MODE ENGAGED',
        GadgetType.scanner => 'STRUCTURAL SCAN ACTIVE',
      };
    }

    if (isMicActive) {
      return 'OUVINDO... (GEMINI LIVE)';
    }

    if (driveMode == DriveMode.pursuit) {
      return 'PURSUIT MODE ENGAGED';
    }
    if (driveMode == DriveMode.surveillance) {
      return 'SURVEILLANCE MODE ATIVO';
    }
    if (driveMode == DriveMode.autoCruise) {
      return 'AUTO CRUISE ENGAGED';
    }

    return switch (connectionState) {
      LiveConnectionState.ready => 'ONLINE - AGUARDANDO COMANDO',
      LiveConnectionState.connecting => 'CONECTANDO GEMINI LIVE...',
      LiveConnectionState.error => 'ERRO DE CONEXÃO GEMINI',
      LiveConnectionState.disconnected => 'OFFLINE - AGUARDANDO LINK',
    };
  }

  /// Sincroniza o estado atual do K.I.T.T. com o Android Auto (com deduplicação).
  Future<void> syncState({
    required LiveConnectionState connectionState,
    required DriveMode driveMode,
    required bool isMicActive,
    required GadgetType? activeGadget,
  }) async {
    final String subtitle = computeStatusSubtitle(
      connectionState: connectionState,
      driveMode: driveMode,
      isMicActive: isMicActive,
      activeGadget: activeGadget,
    );

    final String? gadgetCode = switch (activeGadget) {
      GadgetType.turboBoost => 'turbo_boost',
      GadgetType.oilSlick => 'oil_slick',
      GadgetType.smokeScreen => 'smoke_screen',
      GadgetType.microJam => 'micro_jam',
      GadgetType.skiMode => 'ski_mode',
      GadgetType.scanner => 'scanner',
      null => null,
    };

    final String signature =
        '$subtitle|$isMicActive|${driveMode.apiValue}|$gadgetCode|${connectionState == LiveConnectionState.ready}';
    if (signature == _lastPayloadSignature) {
      return;
    }
    _lastPayloadSignature = signature;

    try {
      await _channel.invokeMethod<void>('updateState', <String, dynamic>{
        'statusSubtitle': subtitle,
        'isListening': isMicActive,
        'driveMode': driveMode.apiValue,
        'activeGadget': gadgetCode,
        'isConnected': connectionState == LiveConnectionState.ready,
      });
    } catch (_) {
      // Ignora em plataformas sem canal nativo Android Auto (ex.: testes/iOS).
    }
  }

  void dispose() {
    _onCommand = null;
    _channel.setMethodCallHandler(null);
  }
}
