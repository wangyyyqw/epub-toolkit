import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

/// 列出字体加密目标。
///
/// 对齐 Wails/Python 版 `list_epub_font_encrypt_targets`：
/// - HTML/XHTML 文件按大小写无关排序。
/// - 字体族只列出 `@font-face src` 真正指向 EPUB 内字体文件的项。
class ListFontTargetsOperation {
  ListFontTargetsOperation._();

  static Future<String> execute({required String epubPath}) async {
    final targets = await scan(epubPath: epubPath);

    final log = StringBuffer();
    log.writeln('扫描 EPUB 字体目标...');
    log.writeln('\n=== 字体族 (${targets.fontFamilies.length}) ===');
    for (final family in targets.fontFamilies) {
      log.writeln('  $family');
    }
    log.writeln('\n=== HTML/XHTML 文件 (${targets.xhtmlFiles.length}) ===');
    for (final htmlFile in targets.xhtmlFiles) {
      log.writeln('  $htmlFile');
    }
    if (targets.fontFamilies.isEmpty) {
      log.writeln('\n提示: 未找到 @font-face 字体定义');
    }
    return log.toString();
  }

  /// 扫描并返回可供字体加密页面直接选择的结构化目标。
  static Future<FontEncryptTargets> scan({required String epubPath}) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    return collectTargets(archive);
  }

  static FontEncryptTargets collectTargets(Archive archive) {
    final names = archive.files
        .where((f) => f.name.isNotEmpty)
        .map((f) => f.name)
        .toList();
    final xhtmlFiles = names.where((name) {
      final lower = name.toLowerCase();
      return lower.endsWith('.html') || lower.endsWith('.xhtml');
    }).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final fontFileNames = names
        .where((name) {
          final lower = name.toLowerCase();
          // 字体加密器当前只支持包含 glyf 表的 TTF 文件。
          return lower.endsWith('.ttf');
        })
        .map((name) => p.basename(name).toLowerCase())
        .toSet();

    final fontFamilies = <String>{};
    for (final file in archive.files) {
      if (file.name.isEmpty || !file.name.toLowerCase().endsWith('.css')) {
        continue;
      }
      final css = utf8.decode(file.content as List<int>, allowMalformed: true);
      for (final match in RegExp(
        r'@font-face\s*\{([\s\S]*?)\}',
        caseSensitive: false,
      ).allMatches(css)) {
        final body = match.group(1) ?? '';
        final family = _firstFontFamily(body);
        final src = _declarationValue(body, 'src') ?? '';
        if (family == null || src.isEmpty) continue;
        for (final urlMatch in RegExp(
          r'url\((.*?)\)',
          caseSensitive: false,
        ).allMatches(src)) {
          final cleaned = (urlMatch.group(1) ?? '')
              .trim()
              .replaceAll(RegExp(r'''^['"]|['"]$'''), '')
              .split('#')
              .first
              .split('?')
              .first;
          if (fontFileNames.contains(p.basename(cleaned).toLowerCase())) {
            fontFamilies.add(family);
            break;
          }
        }
      }
    }

    final sortedFamilies = fontFamilies.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return FontEncryptTargets(sortedFamilies, xhtmlFiles);
  }

  static String? _firstFontFamily(String body) {
    final value = _declarationValue(body, 'font-family');
    if (value == null) return null;
    for (final part in _splitCssComma(value)) {
      final cleaned = part.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      if (cleaned.isNotEmpty) return cleaned;
    }
    return null;
  }

  static String? _declarationValue(String body, String name) {
    return RegExp(
      '$name\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(body)?.group(1)?.trim();
  }

  static List<String> _splitCssComma(String value) {
    final result = <String>[];
    final buf = StringBuffer();
    String? quote;
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      if (quote != null) {
        if (ch == quote) quote = null;
        buf.write(ch);
      } else if (ch == '"' || ch == "'") {
        quote = ch;
        buf.write(ch);
      } else if (ch == ',') {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString());
    return result;
  }
}

class FontEncryptTargets {
  const FontEncryptTargets(this.fontFamilies, this.xhtmlFiles);

  final List<String> fontFamilies;
  final List<String> xhtmlFiles;
}
