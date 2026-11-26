import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aux_slot_config.dart';

/// Representação leve de um app instalado para o seletor do painel.
class InstalledAppEntry {
  const InstalledAppEntry({
    required this.name,
    required this.packageName,
    this.icon,
  });

  final String name;
  final String packageName;
  final Uint8List? icon;
}

/// Gerencia persistência local (`shared_preferences`) e integração nativa Android
/// via `MethodChannel` para listar e abrir aplicativos instalados sem plugins
/// incompatíveis com Android SDK 35+/Kotlin 2.
class AuxAppsManager {
  static const String _prefsKey = 'kitt_aux_slots_v1';
  static const MethodChannel _channel =
      MethodChannel('net.carlosamorim.kitturbo/aux_apps');

  Future<List<AuxSlotConfig>> loadSlots() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        return AuxSlotConfig.defaultSlots();
      }
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final Map<int, AuxSlotConfig> bySlot = <int, AuxSlotConfig>{};
      for (final dynamic item in decoded) {
        if (item is Map<String, dynamic>) {
          final AuxSlotConfig cfg = AuxSlotConfig.fromJson(item);
          if (cfg.slotNumber >= 1 && cfg.slotNumber <= 4) {
            bySlot[cfg.slotNumber] = cfg;
          }
        }
      }
      return List<AuxSlotConfig>.generate(
        4,
        (int i) => bySlot[i + 1] ?? AuxSlotConfig(slotNumber: i + 1),
      );
    } catch (_) {
      return AuxSlotConfig.defaultSlots();
    }
  }

  Future<void> saveSlots(List<AuxSlotConfig> slots) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(
        slots.map((AuxSlotConfig s) => s.toJson()).toList(),
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // Ignora erro silenciosamente caso prefs não esteja disponível em testes.
    }
  }

  Future<List<InstalledAppEntry>> listInstalledApps({
    bool includeSystemApps = false,
  }) async {
    try {
      final List<dynamic>? rawList = await _channel.invokeListMethod<dynamic>(
        'getInstalledApps',
        <String, dynamic>{'includeSystemApps': includeSystemApps},
      );
      if (rawList == null) return const <InstalledAppEntry>[];

      final List<InstalledAppEntry> entries = <InstalledAppEntry>[];
      for (final dynamic item in rawList) {
        if (item is! Map<dynamic, dynamic>) continue;
        final String pkg = item['packageName'] as String? ?? '';
        if (pkg.isEmpty) continue;
        final String name = item['name'] as String? ?? pkg;
        final Object? rawIcon = item['icon'];
        final Uint8List? icon = rawIcon is Uint8List ? rawIcon : null;
        entries.add(
          InstalledAppEntry(name: name, packageName: pkg, icon: icon),
        );
      }
      entries.sort(
        (InstalledAppEntry a, InstalledAppEntry b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return entries;
    } catch (_) {
      return const <InstalledAppEntry>[];
    }
  }

  Future<bool> launchPackage(String packageName) async {
    if (packageName.trim().isEmpty) return false;
    try {
      final bool? started = await _channel.invokeMethod<bool>(
        'launchApp',
        <String, dynamic>{'packageName': packageName.trim()},
      );
      return started ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Resolve qual slot corresponde a um pedido por número (1..4) ou rótulo/nome de app.
  static AuxSlotConfig? resolveSlot(
    List<AuxSlotConfig> slots, {
    int? slotNumber,
    String? query,
  }) {
    if (slotNumber != null && slotNumber >= 1 && slotNumber <= slots.length) {
      return slots[slotNumber - 1];
    }

    final String q = _normalize(query ?? '');
    if (q.isEmpty) return null;

    for (final AuxSlotConfig slot in slots) {
      if (!slot.isConfigured) continue;
      final String label = _normalize(slot.label);
      final String appName = _normalize(slot.appName);
      final String pkg = _normalize(slot.packageName);
      if (label.isNotEmpty &&
          (label == q || label.contains(q) || q.contains(label))) {
        return slot;
      }
      if (appName.isNotEmpty && (appName.contains(q) || q.contains(appName))) {
        return slot;
      }
      if (pkg.isNotEmpty && pkg.contains(q)) {
        return slot;
      }
    }
    return null;
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }
}
