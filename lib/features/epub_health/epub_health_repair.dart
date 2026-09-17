import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/epub_image_helper.dart';
import '../../core/epub_packer.dart';
import 'epub_health.dart';
import 'epub_health_report.dart';

class EpubHealthRepairOperation {
  EpubHealthRepairOperation._();

  static Future<Map<String, Object?>> execute({
    required String epubPath,
    required String outputPath,
    required List<String> selectedFixIds,
    String? reportDirectory,
  }) async {
    final input = File(epubPath).absolute;
    final output = File(outputPath).absolute;
    if (input.path == output.path) {
      throw ArgumentError('输出路径不能覆盖输入 EPUB');
    }
    if (!await input.exists()) throw ArgumentError('输入 EPUB 不存在');
    await output.parent.create(recursive: true);

    final before = await EpubHealthInspector.scan(input.path);
    final selected = before.fixes
        .where((fix) => selectedFixIds.contains(fix.id))
        .toList();
    if (selected.isEmpty) {
      throw ArgumentError('没有选择可执行的安全修复项');
    }

    final archive = ZipDecoder().decodeBytes(
      await input.readAsBytes(),
      verify: true,
    );
    var working = archive;
    var canonicalMimetype = false;
    final applied = <String>[];
    final opfFixes = <EpubHealthFix>[];

    for (final fix in selected) {
      switch (fix.kind) {
        case 'canonicalMimetype':
          canonicalMimetype = true;
          applied.add(fix.label);
        case 'repairContainer':
          final opfPath = fix.data['opfPath'] as String?;
          if (opfPath == null || working.findFile(opfPath) == null) {
            throw StateError('无法重建 container.xml：目标 OPF 不存在');
          }
          final xml = _containerXml(opfPath);
          working = EpubImageHelper.addOrReplaceFileSafe(
            working,
            ArchiveFile(
              'META-INF/container.xml',
              utf8.encode(xml).length,
              utf8.encode(xml),
            ),
          );
          applied.add(fix.label);
        case 'correctMediaType':
        case 'addNavProperty':
        case 'declareCover':
          opfFixes.add(fix);
      }
    }

    if (opfFixes.isNotEmpty) {
      working = _applyOpfFixes(working, opfFixes, applied);
    }

    final tempDirectory = await output.parent.createTemp('.epub-health-');
    final staged = File(p.join(tempDirectory.path, p.basename(output.path)));
    try {
      if (canonicalMimetype) {
        await EpubPacker.pack(archive: working, outputPath: staged.path);
      } else {
        final bytes = ZipEncoder().encode(working);
        if (bytes == null) throw StateError('ZIP 编码失败');
        await staged.writeAsBytes(bytes, flush: true);
      }

      final stagedReport = await EpubHealthInspector.scan(staged.path);
      if (stagedReport.issues.any((issue) => issue.code == 'zip-invalid')) {
        throw StateError('修复产物未通过 ZIP 完整性复检');
      }
      await _replaceOutput(staged, output);
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }

    final after = await EpubHealthInspector.scan(output.path);
    final reportDir = Directory(
      reportDirectory == null || reportDirectory.trim().isEmpty
          ? output.parent.path
          : reportDirectory,
    );
    await reportDir.create(recursive: true);
    final base = p.basenameWithoutExtension(output.path);
    final reportPaths = await writeReports(
      directory: reportDir.path,
      baseName: base,
      before: before,
      after: after,
    );

    return {
      'before': before.toJson(),
      'after': after.toJson(),
      'appliedFixes': applied.toSet().toList(),
      'outputPath': output.path,
      ...reportPaths,
    };
  }

  static Future<Map<String, Object?>> exportReport({
    required EpubHealthReport report,
    required String directory,
    required String baseName,
  }) async {
    final target = Directory(directory);
    await target.create(recursive: true);
    final safeBase = baseName.trim().isEmpty ? 'epub_health' : baseName.trim();
    final jsonPath = p.join(target.path, '$safeBase.json');
    final htmlPath = p.join(target.path, '$safeBase.html');
    await File(jsonPath).writeAsString(report.toPrettyJson(), flush: true);
    await File(htmlPath).writeAsString(report.toHtml(), flush: true);
    return {'jsonReportPath': jsonPath, 'htmlReportPath': htmlPath};
  }

  static Future<Map<String, Object?>> writeReports({
    required String directory,
    required String baseName,
    required EpubHealthReport before,
    required EpubHealthReport after,
  }) async {
    final beforePaths = await exportReport(
      report: before,
      directory: directory,
      baseName: '${baseName}_before',
    );
    final afterPaths = await exportReport(
      report: after,
      directory: directory,
      baseName: '${baseName}_after',
    );
    return {
      'beforeJsonReportPath': beforePaths['jsonReportPath'],
      'beforeHtmlReportPath': beforePaths['htmlReportPath'],
      'afterJsonReportPath': afterPaths['jsonReportPath'],
      'afterHtmlReportPath': afterPaths['htmlReportPath'],
    };
  }

  static Archive _applyOpfFixes(
    Archive archive,
    List<EpubHealthFix> fixes,
    List<String> applied,
  ) {
    final byOpf = <String, List<EpubHealthFix>>{};
    for (final fix in fixes) {
      final opfPath = fix.data['opfPath'] as String?;
      if (opfPath == null) throw StateError('修复项缺少 OPF 路径：${fix.label}');
      byOpf.putIfAbsent(opfPath, () => []).add(fix);
    }

    var result = archive;
    for (final entry in byOpf.entries) {
      final opfFile = result.findFile(entry.key);
      if (opfFile == null) throw StateError('找不到 OPF：${entry.key}');
      final document = XmlDocument.parse(
        utf8.decode(opfFile.content as List<int>, allowMalformed: true),
      );
      for (final fix in entry.value) {
        final itemId = fix.data['itemId'] as String?;
        final item = document.descendants
            .whereType<XmlElement>()
            .where(
              (element) =>
                  element.name.local == 'item' &&
                  element.getAttribute('id') == itemId,
            )
            .firstOrNull;
        if (item == null) {
          throw StateError('找不到 manifest item：$itemId');
        }
        switch (fix.kind) {
          case 'correctMediaType':
            item.setAttribute('media-type', fix.data['mediaType'] as String);
          case 'addNavProperty':
            final tokens =
                (item.getAttribute('properties') ?? '')
                    .split(RegExp(r'\s+'))
                    .where((token) => token.isNotEmpty)
                    .toSet()
                  ..add('nav');
            item.setAttribute('properties', tokens.join(' '));
          case 'declareCover':
            if (fix.data['epub3'] == true) {
              final tokens =
                  (item.getAttribute('properties') ?? '')
                      .split(RegExp(r'\s+'))
                      .where((token) => token.isNotEmpty)
                      .toSet()
                    ..add('cover-image');
              item.setAttribute('properties', tokens.join(' '));
            } else {
              final metadata = document.descendants
                  .whereType<XmlElement>()
                  .where((element) => element.name.local == 'metadata')
                  .firstOrNull;
              if (metadata == null) throw StateError('OPF 缺少 metadata');
              final existing = metadata.childElements.where(
                (element) =>
                    element.name.local == 'meta' &&
                    element.getAttribute('name') == 'cover',
              );
              if (existing.isEmpty) {
                metadata.children.add(
                  XmlElement(XmlName('meta'), [
                    XmlAttribute(XmlName('name'), 'cover'),
                    XmlAttribute(XmlName('content'), itemId ?? ''),
                  ]),
                );
              }
            }
        }
        applied.add(fix.label);
      }

      final bytes = utf8.encode(
        document.toXmlString(pretty: true, indent: '  '),
      );
      result = EpubImageHelper.addOrReplaceFileSafe(
        result,
        ArchiveFile(entry.key, bytes.length, bytes),
      );
    }
    return result;
  }

  static Future<void> _replaceOutput(File staged, File output) async {
    File? backup;
    if (await output.exists()) {
      backup = File('${output.path}.health-backup');
      if (await backup.exists()) await backup.delete();
      await output.rename(backup.path);
    }
    try {
      await staged.rename(output.path);
      if (backup != null && await backup.exists()) await backup.delete();
    } catch (_) {
      if (backup != null && await backup.exists() && !await output.exists()) {
        await backup.rename(output.path);
      }
      rethrow;
    }
  }

  static String _containerXml(String opfPath) =>
      '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="${_escapeXml(opfPath)}" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
