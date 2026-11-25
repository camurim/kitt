import 'package:flutter/foundation.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Resultado estruturado de uma tentativa de chamada ou abertura do discador.
class PhoneCallResult {
  const PhoneCallResult({
    required this.success,
    required this.mode,
    required this.message,
    this.phoneNumber = '',
    this.contactName = '',
    this.fallbackToDialer = false,
  });

  final bool success;
  final String mode; // 'direct_call' | 'dialer' | 'error'
  final String message;
  final String phoneNumber;
  final String contactName;
  final bool fallbackToDialer;

  Map<String, dynamic> toToolResponse() => <String, dynamic>{
        'status': success ? 'ok' : 'error',
        'mode': mode,
        'phone_number': phoneNumber,
        'contact_name': contactName,
        'fallback_to_dialer': fallbackToDialer,
        'message': message,
      };
}

/// Gerencia abertura do discador (`url_launcher` via `tel:`) e ligação direta
/// no Android (`flutter_phone_direct_caller` com permissão `CALL_PHONE`).
class PhoneCallManager {
  /// Remove espaços, parênteses e hifens mantendo dígitos, `+`, `*` e `#`.
  static String sanitizePhoneNumber(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9+*#]'), '');
  }

  /// Abre o discador ou inicia chamada direta conforme `directCall`.
  Future<PhoneCallResult> placeCall({
    String? phoneNumber,
    String? contactName,
    bool directCall = false,
  }) async {
    final String cleanNumber = sanitizePhoneNumber(phoneNumber ?? '');
    final String label = (contactName != null && contactName.trim().isNotEmpty)
        ? contactName.trim()
        : cleanNumber;

    // Caso 1: apenas abrir o discador sem número informado
    if (cleanNumber.isEmpty) {
      final bool opened = await _openDialer('');
      return PhoneCallResult(
        success: opened,
        mode: opened ? 'dialer' : 'error',
        contactName: contactName?.trim() ?? '',
        message: opened
            ? 'Discador do sistema aberto.'
            : 'Não foi possível abrir o discador neste dispositivo.',
      );
    }

    // Caso 2: ligação direta (Android) solicitando permissão CALL_PHONE
    if (directCall && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final PermissionStatus status = await Permission.phone.request();
      if (status.isGranted) {
        try {
          final bool? called =
              await FlutterPhoneDirectCaller.callNumber(cleanNumber);
          if (called == true) {
            return PhoneCallResult(
              success: true,
              mode: 'direct_call',
              phoneNumber: cleanNumber,
              contactName: contactName?.trim() ?? '',
              message: 'Chamada direta iniciada para $label.',
            );
          }
        } catch (_) {
          // Segue para fallback no discador abaixo.
        }
      }

      // Fallback seguro para o discador caso permissão CALL_PHONE seja negada
      final bool opened = await _openDialer(cleanNumber);
      return PhoneCallResult(
        success: opened,
        mode: opened ? 'dialer' : 'error',
        phoneNumber: cleanNumber,
        contactName: contactName?.trim() ?? '',
        fallbackToDialer: true,
        message: opened
            ? 'Permissão de chamada direta indisponível; discador aberto com $label.'
            : 'Não foi possível iniciar a chamada para $label.',
      );
    }

    // Caso 3: abrir o discador preenchido via `tel:`
    final bool opened = await _openDialer(cleanNumber);
    return PhoneCallResult(
      success: opened,
      mode: opened ? 'dialer' : 'error',
      phoneNumber: cleanNumber,
      contactName: contactName?.trim() ?? '',
      message: opened
          ? 'Discador aberto com o número $label.'
          : 'Não foi possível abrir o discador para $label.',
    );
  }

  Future<bool> _openDialer(String number) async {
    try {
      final Uri uri = Uri(scheme: 'tel', path: number);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
