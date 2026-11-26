import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Registro estruturado de um alvo/contato no Banco de Dados Tático F.L.A.G.
class FlagDossierEntry {
  const FlagDossierEntry({
    required this.targetName,
    required this.details,
  });

  final String targetName;
  final String details;
}

/// Serviço de memória persistente em Markdown (`flag_dossiers.md`) para o K.I.T.T.
///
/// Salva e lê o arquivo local no diretório de documentos do app via `path_provider`,
/// suportando edição estruturada (`## Alvo: [Nome]\n- [Detalhes]`), edição bruta
/// em Markdown e importação/exportação via copiar/colar.
class FlagDossierService {
  FlagDossierService({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider =
            directoryProvider ?? getApplicationDocumentsDirectory;

  static const String fileName = 'flag_dossiers.md';

  static const String defaultHeader = '# ARQUIVOS CONFIDENCIAIS F.L.A.G.';

  static const String initialTemplate = '''# ARQUIVOS CONFIDENCIAIS F.L.A.G.

<!--
Exemplo de registro tático:
## Alvo: Devon Miles
- Diretor da Fundação para a Lei e o Governo. Exige cautela extrema com o chassi do K.I.T.T.
-->
''';

  final Future<Directory> Function() _directoryProvider;

  Future<File> _resolveFile() async {
    final Directory dir = await _directoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  /// Garante que `flag_dossiers.md` existe e retorna seu conteúdo completo.
  Future<String> readRawMarkdown() async {
    try {
      final File file = await _resolveFile();
      if (!await file.exists()) {
        await file.create(recursive: true);
        await file.writeAsString(initialTemplate);
        return initialTemplate;
      }
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        await file.writeAsString(initialTemplate);
        return initialTemplate;
      }
      return content;
    } catch (_) {
      return initialTemplate;
    }
  }

  /// Salva diretamente o conteúdo bruto em `flag_dossiers.md`.
  Future<String> saveRawMarkdown(String rawMarkdown) async {
    final String normalized = rawMarkdown.trim().isEmpty
        ? initialTemplate
        : '${rawMarkdown.trimRight()}\n';
    try {
      final File file = await _resolveFile();
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(normalized);
    } catch (_) {
      // Ignora em ambientes sem filesystem gravável.
    }
    return normalized;
  }

  /// Faz o parse das fichas estruturadas (`## Alvo: [Nome]`) do Markdown.
  static List<FlagDossierEntry> parseEntries(String rawMarkdown) {
    final String withoutComments = stripHtmlComments(rawMarkdown);
    final RegExp headerRegex = RegExp(
      r'^##\s*Alvo:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    );
    final List<RegExpMatch> matches =
        headerRegex.allMatches(withoutComments).toList();
    if (matches.isEmpty) return const <FlagDossierEntry>[];

    final List<FlagDossierEntry> entries = <FlagDossierEntry>[];
    for (int i = 0; i < matches.length; i++) {
      final RegExpMatch m = matches[i];
      final String name = (m.group(1) ?? '').trim();
      final int bodyStart = m.end;
      final int bodyEnd =
          (i + 1 < matches.length) ? matches[i + 1].start : withoutComments.length;
      final String rawBody = withoutComments.substring(bodyStart, bodyEnd).trim();
      final List<String> lines = rawBody
          .split('\n')
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty)
          .map((String line) => line.startsWith('- ') ? line.substring(2).trim() : line)
          .toList();
      if (name.isNotEmpty) {
        entries.add(
          FlagDossierEntry(
            targetName: name,
            details: lines.join('\n'),
          ),
        );
      }
    }
    return entries;
  }

  /// Remove comentários HTML (`<!-- ... -->`) antes de injetar no prompt ou listar fichas.
  static String stripHtmlComments(String rawMarkdown) {
    return rawMarkdown.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
  }

  /// Formata uma lista de fichas estruturadas de volta para Markdown limpo.
  static String formatMarkdown(List<FlagDossierEntry> entries) {
    if (entries.isEmpty) return initialTemplate;
    final StringBuffer buf = StringBuffer('$defaultHeader\n\n');
    for (final FlagDossierEntry entry in entries) {
      buf.writeln('## Alvo: ${entry.targetName.trim()}');
      final List<String> lines = entry.details
          .split('\n')
          .map((String l) => l.trim())
          .where((String l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        buf.writeln('- Sem detalhes registrados.');
      } else {
        for (final String line in lines) {
          final String clean =
              line.startsWith('- ') ? line.substring(2).trim() : line;
          buf.writeln('- $clean');
        }
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// Adiciona ou atualiza um registro no `flag_dossiers.md` e retorna o novo Markdown.
  Future<String> upsertEntry({
    required String targetName,
    required String details,
    String? previousTargetName,
    bool appendIfExists = false,
  }) async {
    final String cleanName = targetName.trim();
    final String cleanDetails = details.trim();
    if (cleanName.isEmpty || cleanDetails.isEmpty) {
      return readRawMarkdown();
    }

    final String current = await readRawMarkdown();
    final List<FlagDossierEntry> entries =
        List<FlagDossierEntry>.from(parseEntries(current));
    final String matchKey = (previousTargetName ?? cleanName).trim().toLowerCase();
    final int idx = entries.indexWhere(
      (FlagDossierEntry e) => e.targetName.trim().toLowerCase() == matchKey,
    );

    if (idx >= 0) {
      final FlagDossierEntry existing = entries[idx];
      final String mergedDetails = appendIfExists && existing.details.isNotEmpty
          ? '${existing.details}\n$cleanDetails'
          : cleanDetails;
      entries[idx] = FlagDossierEntry(
        targetName: cleanName,
        details: mergedDetails,
      );
    } else {
      entries.add(
        FlagDossierEntry(targetName: cleanName, details: cleanDetails),
      );
    }

    return saveRawMarkdown(formatMarkdown(entries));
  }

  /// Remove uma ficha pelo nome do alvo e retorna o novo Markdown salvo.
  Future<String> deleteEntry(String targetName) async {
    final String current = await readRawMarkdown();
    final String key = targetName.trim().toLowerCase();
    final List<FlagDossierEntry> remaining = parseEntries(current)
        .where((FlagDossierEntry e) => e.targetName.trim().toLowerCase() != key)
        .toList();
    return saveRawMarkdown(formatMarkdown(remaining));
  }

  /// Importa conteúdo Markdown (substituindo ou mesclando com o banco atual).
  Future<String> importMarkdown(
    String importedRaw, {
    bool merge = false,
  }) async {
    final String trimmed = importedRaw.trim();
    if (trimmed.isEmpty) return readRawMarkdown();

    if (!merge) {
      final String withHeader = trimmed.startsWith('#')
          ? trimmed
          : '$defaultHeader\n\n$trimmed';
      return saveRawMarkdown(withHeader);
    }

    final String current = await readRawMarkdown();
    final List<FlagDossierEntry> currentEntries =
        List<FlagDossierEntry>.from(parseEntries(current));
    final List<FlagDossierEntry> incoming = parseEntries(trimmed);
    for (final FlagDossierEntry entry in incoming) {
      final int idx = currentEntries.indexWhere(
        (FlagDossierEntry e) =>
            e.targetName.toLowerCase() == entry.targetName.toLowerCase(),
      );
      if (idx >= 0) {
        currentEntries[idx] = entry;
      } else {
        currentEntries.add(entry);
      }
    }
    return saveRawMarkdown(formatMarkdown(currentEntries));
  }
}
