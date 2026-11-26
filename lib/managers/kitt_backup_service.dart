import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flag_dossier_service.dart';

/// Resultado estruturado de uma operação de restauração de backup.
class KittBackupRestoreResult {
  const KittBackupRestoreResult({
    required this.restoredMarkdown,
    required this.restoredPrefsCount,
    required this.isFullJsonBackup,
    required this.fileName,
  });

  final String restoredMarkdown;
  final int restoredPrefsCount;
  final bool isFullJsonBackup;
  final String fileName;

  static const String hudConfirmation =
      'BACKUP RESTORED // DATABASE SYNCHRONIZED';
}

/// Serviço de Backup e Restauração Completa do K.i.t.Turbo:
/// - Exporta `flag_dossiers.md` + todas as chaves tipadas do `SharedPreferences`
///   (botões auxiliares, filtro de notificações e preferências gerais) em um
///   arquivo `kitturbo_backup_YYYYMMDD.json` compartilhado via `share_plus`.
/// - Restaura tanto `.json` completo quanto `.md` avulso via `file_picker`.
class KittBackupService {
  KittBackupService({
    FlagDossierService? dossierService,
    Future<Directory> Function()? tempDirectoryProvider,
  })  : _dossierService = dossierService ?? FlagDossierService(),
        _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory;

  static const int currentSchemaVersion = 1;

  final FlagDossierService _dossierService;
  final Future<Directory> Function() _tempDirectoryProvider;

  /// Gera o nome padronizado `kitturbo_backup_YYYYMMDD.json`.
  static String buildBackupFilename([DateTime? now]) {
    final DateTime dt = now ?? DateTime.now();
    final String y = dt.year.toString().padLeft(4, '0');
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    return 'kitturbo_backup_$y$m$d.json';
  }

  /// Serializa `flag_dossiers.md` e todas as chaves do `SharedPreferences`
  /// preservando o tipo exato de cada valor (`bool`, `int`, `double`, `string`, `stringList`).
  static String buildBackupJson({
    required String flagDossiersMarkdown,
    required Map<String, Object?> rawPreferences,
    DateTime? now,
  }) {
    final Map<String, Map<String, dynamic>> typedPrefs =
        <String, Map<String, dynamic>>{};

    final List<String> sortedKeys = rawPreferences.keys.toList()..sort();
    for (final String key in sortedKeys) {
      final Object? val = rawPreferences[key];
      if (val is bool) {
        typedPrefs[key] = <String, dynamic>{'type': 'bool', 'value': val};
      } else if (val is int) {
        typedPrefs[key] = <String, dynamic>{'type': 'int', 'value': val};
      } else if (val is double) {
        typedPrefs[key] = <String, dynamic>{'type': 'double', 'value': val};
      } else if (val is String) {
        typedPrefs[key] = <String, dynamic>{'type': 'string', 'value': val};
      } else if (val is List) {
        typedPrefs[key] = <String, dynamic>{
          'type': 'stringList',
          'value': val.map((dynamic e) => e.toString()).toList(),
        };
      }
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'app': 'K.i.t.Turbo',
      'packageId': 'net.carlosamorim.kitturbo',
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'flagDossiersMarkdown': flagDossiersMarkdown,
      'preferences': typedPrefs,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Lê `flag_dossiers.md` + `SharedPreferences`, grava `kitturbo_backup_YYYYMMDD.json`
  /// em pasta temporária e abre o menu nativo de compartilhamento (`share_plus`).
  Future<String> exportAndShareBackup() async {
    final String markdown = await _dossierService.readRawMarkdown();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, Object?> rawPrefs = <String, Object?>{
      for (final String k in prefs.getKeys()) k: prefs.get(k),
    };

    final String fileName = buildBackupFilename();
    final String jsonContent = buildBackupJson(
      flagDossiersMarkdown: markdown,
      rawPreferences: rawPrefs,
    );

    final Directory tmpDir = await _tempDirectoryProvider();
    final File outFile = File('${tmpDir.path}${Platform.pathSeparator}$fileName');
    await outFile.writeAsString('$jsonContent\n', encoding: utf8);

    await Share.shareXFiles(
      <XFile>[XFile(outFile.path, mimeType: 'application/json', name: fileName)],
      subject: 'K.i.t.Turbo — Backup Completo ($fileName)',
      text: 'Backup completo dos Dossiês F.L.A.G. e configurações do K.i.t.Turbo.',
    );
    return fileName;
  }

  /// Abre o seletor de arquivos (`file_picker`) aceitando `.json` ou `.md`
  /// e aplica a restauração completa (ou apenas dossiês para `.md`).
  Future<KittBackupRestoreResult?> pickAndRestoreBackup() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json', 'md'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final PlatformFile file = picked.files.first;
    String content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null && file.path!.isNotEmpty) {
      content = await File(file.path!).readAsString(encoding: utf8);
    } else {
      return null;
    }

    return restoreFromContent(
      content: content,
      fileName: file.name,
    );
  }

  /// Aplica a restauração a partir do conteúdo lido (suporta `.json` completo ou `.md`).
  Future<KittBackupRestoreResult> restoreFromContent({
    required String content,
    required String fileName,
    SharedPreferences? prefsOverride,
  }) async {
    final String lowerName = fileName.toLowerCase().trim();
    final String trimmed = content.trim();
    final bool looksJson = lowerName.endsWith('.json') ||
        (trimmed.startsWith('{') && trimmed.endsWith('}'));

    if (looksJson) {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Formato de backup JSON inválido.');
      }

      // 1. Restaura flag_dossiers.md
      final String rawMd = decoded['flagDossiersMarkdown'] as String? ?? '';
      final String savedMd = rawMd.trim().isNotEmpty
          ? await _dossierService.saveRawMarkdown(rawMd)
          : await _dossierService.readRawMarkdown();

      // 2. Restaura todas as chaves do SharedPreferences com tipagem preservada
      final SharedPreferences prefs =
          prefsOverride ?? await SharedPreferences.getInstance();
      int restoredPrefsCount = 0;
      final Object? rawPrefs = decoded['preferences'];
      if (rawPrefs is Map<String, dynamic>) {
        for (final MapEntry<String, dynamic> entry in rawPrefs.entries) {
          final String key = entry.key;
          final dynamic spec = entry.value;
          if (spec is Map<String, dynamic>) {
            final String type = spec['type'] as String? ?? '';
            final dynamic val = spec['value'];
            if (type == 'bool' && val is bool) {
              await prefs.setBool(key, val);
              restoredPrefsCount++;
            } else if (type == 'int' && val is num) {
              await prefs.setInt(key, val.toInt());
              restoredPrefsCount++;
            } else if (type == 'double' && val is num) {
              await prefs.setDouble(key, val.toDouble());
              restoredPrefsCount++;
            } else if (type == 'string' && val is String) {
              await prefs.setString(key, val);
              restoredPrefsCount++;
            } else if (type == 'stringList' && val is List) {
              await prefs.setStringList(
                key,
                val.map((dynamic e) => e.toString()).toList(),
              );
              restoredPrefsCount++;
            }
          } else if (spec is bool) {
            await prefs.setBool(key, spec);
            restoredPrefsCount++;
          } else if (spec is int) {
            await prefs.setInt(key, spec);
            restoredPrefsCount++;
          } else if (spec is double) {
            await prefs.setDouble(key, spec);
            restoredPrefsCount++;
          } else if (spec is String) {
            await prefs.setString(key, spec);
            restoredPrefsCount++;
          } else if (spec is List) {
            await prefs.setStringList(
              key,
              spec.map((dynamic e) => e.toString()).toList(),
            );
            restoredPrefsCount++;
          }
        }
      }

      return KittBackupRestoreResult(
        restoredMarkdown: savedMd,
        restoredPrefsCount: restoredPrefsCount,
        isFullJsonBackup: true,
        fileName: fileName,
      );
    }

    // Arquivo .md avulso — restaura apenas os dossiês F.L.A.G.
    final String savedMd = await _dossierService.saveRawMarkdown(content);
    return KittBackupRestoreResult(
      restoredMarkdown: savedMd,
      restoredPrefsCount: 0,
      isFullJsonBackup: false,
      fileName: fileName,
    );
  }
}
