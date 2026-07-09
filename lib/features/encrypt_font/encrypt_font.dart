import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';
import 'ttf_font_encryptor.dart';

/// 字体加密操作。
///
/// 行为按 Wails/Python 版 `encrypt_font.py` 对齐：
/// - `@font-face src` 按 CSS 文件位置解析为 EPUB 内部路径。
/// - 字体族比较会去引号、压缩空白并忽略大小写。
/// - 只处理目标 XHTML 中被 CSS 选择器或 inline style 命中的文本。
/// - 正文写入真实韩文混淆字符，而不是 `&#x....;` 实体。
/// - 未参与混淆的 HTML/字体保持原样。
class EncryptFontOperation {
  EncryptFontOperation._();

  static const _allFontExts = ['.ttf', '.otf', '.woff'];
  static const _encryptableExts = ['.ttf'];

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    List<String>? targetFontFamilies,
    List<String>? targetXhtmlFiles,
  }) async {
    var archive = await EpubImageHelper.readArchive(epubPath);
    final log = StringBuffer()..writeln('开始字体加密...');

    final targetFamilies = _normalizeTargetSet(targetFontFamilies);
    final targetHtmls = _normalizePathTargetSet(targetXhtmlFiles);
    if (targetFamilies != null) {
      log.writeln('目标字体族: ${targetFontFamilies!.join(", ")}');
    }
    if (targetHtmls != null) {
      log.writeln('目标文件: ${targetXhtmlFiles!.join(", ")}');
    }

    final files = archive.files.where((f) => f.name.isNotEmpty).toList();
    final fonts = files
        .where((f) => _allFontExts.contains(p.extension(f.name).toLowerCase()))
        .toList();
    if (fonts.isEmpty) {
      log.writeln('未找到字体文件，无需加密。直接复制原 EPUB。');
      await File(outputPath).writeAsBytes(await File(epubPath).readAsBytes());
      return log.toString();
    }
    log.writeln('找到 ${fonts.length} 个字体文件');

    final fontPaths = fonts.map((f) => f.name).toSet();
    final fontNameToFile = _buildFontNameToFileMapping(fonts);
    final fontFileToFamily = <String, String>{};
    final selectorToFont = <String, String>{};
    _parseCssFiles(
      archive,
      fontPaths,
      fontNameToFile,
      fontFileToFamily,
      selectorToFont,
      targetFamilies,
    );
    final orderedSelectorToFont = SplayTreeMap<String, String>(
      (a, b) =>
          b.length == a.length ? a.compareTo(b) : b.length.compareTo(a.length),
    )..addAll(selectorToFont);

    log.writeln('解析到 ${fontNameToFile.length} 个字体别名');
    log.writeln('解析到 ${orderedSelectorToFont.length} 个选择器→字体映射');

    final fontToText = _collectFontText(
      archive,
      orderedSelectorToFont,
      fontNameToFile,
      targetHtmls,
      targetFamilies,
    );
    if (fontToText.isEmpty) {
      log.writeln('未找到匹配的字体使用文本，无需加密。直接复制原 EPUB。');
      await File(outputPath).writeAsBytes(await File(epubPath).readAsBytes());
      return log.toString();
    }

    final fontToReplacement = <String, Map<int, int>>{};
    var encryptCount = 0;
    var skipCount = 0;

    for (final entry in fontToText.entries) {
      final fontPath = entry.key;
      final text = entry.value;
      final fontFile = archive.findFile(fontPath);
      if (fontFile == null || text.isEmpty) {
        skipCount++;
        continue;
      }

      final ext = p.extension(fontPath).toLowerCase();
      if (!_encryptableExts.contains(ext)) {
        log.writeln('  跳过（不支持的格式 $ext）: $fontPath');
        skipCount++;
        continue;
      }

      final fontData = EpubImageHelper.readBytes(fontFile);
      final chars = LinkedHashSet<int>.of(text.runes);
      final result = TtfFontEncryptor.encrypt(fontData, chars);
      if (result.fontData == null || result.charToShadow.isEmpty) {
        log.writeln('  加密失败，保留原字体: $fontPath');
        skipCount++;
        continue;
      }

      archive = EpubImageHelper.addOrReplaceFileSafe(
        archive,
        ArchiveFile(fontPath, result.fontData!.length, result.fontData!),
      );
      fontToReplacement[fontPath] = result.charToShadow;
      encryptCount++;
      log.writeln(
        '  加密: $fontPath '
        '${EpubImageHelper.sizeStr(fontData.length)} → '
        '${EpubImageHelper.sizeStr(result.fontData!.length)} '
        '混淆 ${result.charToShadow.length} 字符',
      );
    }

    if (fontToReplacement.isNotEmpty) {
      archive = _replaceHtmlText(
        archive,
        orderedSelectorToFont,
        fontNameToFile,
        fontFileToFamily,
        fontToReplacement,
        targetHtmls,
        targetFamilies,
      );
    }

    await EpubImageHelper.saveArchive(archive, outputPath);
    log.writeln('\n字体加密完成: 加密 $encryptCount 个, 跳过 $skipCount 个');
    log.writeln('输出文件: $outputPath');
    return log.toString();
  }

  static Set<String>? _normalizeTargetSet(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    final set = values
        .map(_normalizeFontName)
        .where((value) => value.isNotEmpty)
        .toSet();
    return set.isEmpty ? null : set;
  }

  static Set<String>? _normalizePathTargetSet(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    final set = values
        .map(
          (value) => value
              .replaceAll('\\', '/')
              .trim()
              .replaceAll('"', '')
              .replaceAll("'", '')
              .toLowerCase(),
        )
        .where((value) => value.isNotEmpty)
        .toSet();
    return set.isEmpty ? null : set;
  }

  static bool _isTargetHtml(String path, Set<String>? targets) {
    if (targets == null) return true;
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return targets.contains(normalized) ||
        targets.contains(p.posix.basename(normalized));
  }

  static String _normalizeFontName(String? name) {
    return (name ?? '')
        .trim()
        .replaceAll(RegExp(r'''^['"]|['"]$'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  static String _resolveBookPath(String basePath, String href) {
    var cleaned = href.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    cleaned = cleaned.split('#').first.split('?').first;
    if (cleaned.isEmpty || cleaned.contains('://')) return '';
    return p.posix.normalize(p.posix.join(p.posix.dirname(basePath), cleaned));
  }

  static Map<String, String> _buildFontNameToFileMapping(
    List<ArchiveFile> fonts,
  ) {
    final mapping = <String, String>{};
    for (final font in fonts) {
      final aliases = <String>{
        _normalizeFontName(p.basenameWithoutExtension(font.name)),
      };
      aliases.addAll(_readFontNameAliases(EpubImageHelper.readBytes(font)));
      for (final alias in aliases) {
        mapping.putIfAbsent(alias, () => font.name);
      }
    }
    return mapping;
  }

  static Set<String> _readFontNameAliases(Uint8List data) {
    final aliases = <String>{};
    try {
      if (data.length < 12) return aliases;
      final bd = ByteData.sublistView(data);
      final numTables = bd.getUint16(4);
      int? nameOffset;
      int? nameLength;
      var offset = 12;
      for (var i = 0; i < numTables; i++, offset += 16) {
        final tag = ascii.decode(
          data.sublist(offset, offset + 4),
          allowInvalid: true,
        );
        if (tag == 'name') {
          nameOffset = bd.getUint32(offset + 8);
          nameLength = bd.getUint32(offset + 12);
          break;
        }
      }
      if (nameOffset == null ||
          nameLength == null ||
          nameOffset + nameLength > data.length) {
        return aliases;
      }
      final count = bd.getUint16(nameOffset + 2);
      final stringBase = nameOffset + bd.getUint16(nameOffset + 4);
      for (var i = 0; i < count; i++) {
        final rec = nameOffset + 6 + i * 12;
        final platformId = bd.getUint16(rec);
        final nameId = bd.getUint16(rec + 6);
        if (nameId != 1 && nameId != 4 && nameId != 6) continue;
        final len = bd.getUint16(rec + 8);
        final strOff = stringBase + bd.getUint16(rec + 10);
        if (strOff < 0 || strOff + len > data.length) continue;
        final raw = data.sublist(strOff, strOff + len);
        final value = platformId == 0 || platformId == 3
            ? _decodeUtf16Be(raw)
            : utf8.decode(raw, allowMalformed: true);
        final normalized = _normalizeFontName(value);
        if (normalized.isNotEmpty) aliases.add(normalized);
      }
    } catch (_) {
      // 字体 name 表无法解析时仅使用文件名别名。
    }
    return aliases;
  }

  static String _decodeUtf16Be(Uint8List bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static void _parseCssFiles(
    Archive archive,
    Set<String> fontPaths,
    Map<String, String> fontNameToFile,
    Map<String, String> fontFileToFamily,
    Map<String, String> selectorToFont,
    Set<String>? targetFamilies,
  ) {
    for (final file in archive.files) {
      if (file.name.isEmpty || !file.name.toLowerCase().endsWith('.css')) {
        continue;
      }
      final css = utf8.decode(file.content as List<int>, allowMalformed: true);
      _parseFontFaces(
        css,
        file.name,
        fontPaths,
        fontNameToFile,
        fontFileToFamily,
      );
      _parseSelectorFonts(css, fontNameToFile, selectorToFont, targetFamilies);
    }
  }

  static void _parseFontFaces(
    String css,
    String cssPath,
    Set<String> fontPaths,
    Map<String, String> fontNameToFile,
    Map<String, String> fontFileToFamily,
  ) {
    for (final match in RegExp(
      r'@font-face\s*\{([\s\S]*?)\}',
      caseSensitive: false,
    ).allMatches(css)) {
      final body = match.group(1) ?? '';
      final family = _firstFontCandidate(
        _declarationValue(body, 'font-family'),
      );
      if (family == null) continue;
      final normalized = _normalizeFontName(family);
      final src = _declarationValue(body, 'src') ?? '';
      for (final urlMatch in RegExp(
        r'url\((.*?)\)',
        caseSensitive: false,
      ).allMatches(src)) {
        final fontPath = _resolveBookPath(cssPath, urlMatch.group(1) ?? '');
        if (fontPaths.contains(fontPath)) {
          fontNameToFile[normalized] = fontPath;
          fontFileToFamily[fontPath] = family;
          break;
        }
      }
    }
  }

  static void _parseSelectorFonts(
    String css,
    Map<String, String> fontNameToFile,
    Map<String, String> selectorToFont,
    Set<String>? targetFamilies,
  ) {
    final withoutComments = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final withoutFontFace = withoutComments.replaceAll(
      RegExp(r'@font-face\s*\{[\s\S]*?\}', caseSensitive: false),
      '',
    );
    for (final match in RegExp(
      r'([^{}]+)\{([\s\S]*?)\}',
    ).allMatches(withoutFontFace)) {
      final selectors = match.group(1)!.trim();
      final body = match.group(2) ?? '';
      final candidates = _fontCandidatesFromDeclarations(body);
      final font = _pickFontFile(candidates, fontNameToFile, targetFamilies);
      if (font == null) continue;
      for (final selector in selectors.split(',')) {
        final trimmed = selector.trim();
        if (trimmed.isNotEmpty) selectorToFont[trimmed] = font;
      }
    }
  }

  static String? _declarationValue(String body, String name) {
    final match = RegExp(
      '$name\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(body);
    return match?.group(1)?.trim();
  }

  static List<String> _fontCandidatesFromDeclarations(String body) {
    final candidates = <String>[];
    for (final match in RegExp(
      r'([\w-]+)\s*:\s*([^;]+)',
      caseSensitive: false,
    ).allMatches(body)) {
      final name = match.group(1)!.toLowerCase();
      final value = match.group(2)!.trim();
      if (name == 'font-family') {
        candidates.addAll(
          _splitCssComma(
            value,
          ).map((v) => v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '')),
        );
      } else if (name == 'font') {
        candidates.addAll(_fontShorthandCandidates(value));
      }
    }
    return _dedupeFontCandidates(candidates);
  }

  static String? _firstFontCandidate(String? value) {
    if (value == null) return null;
    final candidates = _dedupeFontCandidates(
      _splitCssComma(value)
          .map((v) => v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
          .toList(),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  static List<String> _fontShorthandCandidates(String value) {
    final parts = _splitCssComma(value);
    if (parts.isEmpty) return const [];
    final result = <String>[];
    final first = parts.first.replaceFirst(
      RegExp(r'^.*?(\d[^ ]*(\s*/\s*[^ ]+)?)\s+'),
      '',
    );
    result.add(first);
    result.addAll(parts.skip(1));
    return result
        .map((v) => v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
        .toList();
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

  static List<String> _dedupeFontCandidates(List<String> candidates) {
    const generic = {
      'serif',
      'sans-serif',
      'monospace',
      'cursive',
      'fantasy',
      'system-ui',
      'emoji',
      'math',
      'fangsong',
      'inherit',
      'initial',
      'unset',
      'normal',
    };
    final seen = <String>{};
    final result = <String>[];
    for (final candidate in candidates) {
      final normalized = _normalizeFontName(candidate);
      if (normalized.isEmpty ||
          generic.contains(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      result.add(candidate);
    }
    return result;
  }

  static String? _pickFontFile(
    List<String> candidates,
    Map<String, String> fontNameToFile,
    Set<String>? targetFamilies,
  ) {
    for (final candidate in candidates) {
      final normalized = _normalizeFontName(candidate);
      if (targetFamilies != null && !targetFamilies.contains(normalized)) {
        continue;
      }
      final font = fontNameToFile[normalized];
      if (font != null) return font;
    }
    return null;
  }

  static Map<String, String> _collectFontText(
    Archive archive,
    SplayTreeMap<String, String> selectorToFont,
    Map<String, String> fontNameToFile,
    Set<String>? targetHtmls,
    Set<String>? targetFamilies,
  ) {
    final builders = <String, StringBuffer>{};
    final seen = <String, Set<int>>{};

    void append(String font, String text) {
      final fontSeen = seen.putIfAbsent(font, () => <int>{});
      final buffer = builders.putIfAbsent(font, StringBuffer.new);
      for (final rune in text.runes) {
        if (_skipTextRune(rune) || !fontSeen.add(rune)) continue;
        buffer.writeCharCode(rune);
      }
    }

    for (final file in archive.files) {
      if (file.name.isEmpty ||
          !_isHtml(file.name) ||
          !_isTargetHtml(file.name, targetHtmls)) {
        continue;
      }
      final html = utf8.decode(file.content as List<int>, allowMalformed: true);
      for (final entry in selectorToFont.entries) {
        final text = _extractTextBySelector(html, entry.key);
        if (text.isNotEmpty) append(entry.value, text);
      }
      for (final match in _styledElementPattern.allMatches(html)) {
        final style = match.group(4) ?? '';
        final font = _pickFontFile(
          _fontCandidatesFromDeclarations(style),
          fontNameToFile,
          targetFamilies,
        );
        if (font == null) continue;
        append(font, _stripTags(match.group(3) ?? ''));
      }
    }

    return builders.map((key, value) => MapEntry(key, value.toString()))
      ..removeWhere((_, value) => value.isEmpty);
  }

  static bool _skipTextRune(int rune) {
    if (rune <= 0x20 || (rune >= 0x7F && rune <= 0x9F)) return true;
    return String.fromCharCode(rune).trim().isEmpty;
  }

  static bool _isHtml(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.html') ||
        lower.endsWith('.xhtml') ||
        lower.endsWith('.htm');
  }

  static final _styledElementPattern = RegExp(
    r'''<([A-Za-z][\w:-]*)\b([^>]*)\bstyle\s*=\s*(["'])(.*?)\3([^>]*)>([\s\S]*?)</\1>''',
    caseSensitive: false,
  );

  static String _extractTextBySelector(String html, String selector) {
    final pattern = _selectorPattern(selector);
    if (pattern == null) return '';
    final buffer = StringBuffer();
    for (final match in pattern.allMatches(html)) {
      buffer.write(_stripTags(match.group(match.groupCount) ?? ''));
    }
    return buffer.toString();
  }

  static RegExp? _selectorPattern(String selector) {
    final s = selector.trim();
    if (RegExp(r'^[A-Za-z][\w:-]*$').hasMatch(s)) {
      return RegExp('<$s\\b[^>]*>([\\s\\S]*?)</$s>', caseSensitive: false);
    }
    final classMatch = RegExp(
      r'^(?:([A-Za-z][\w:-]*)\s*)?\.([\w-]+)$',
    ).firstMatch(s);
    if (classMatch != null) {
      final tag = classMatch.group(1) ?? r'[A-Za-z][\w:-]*';
      final cls = RegExp.escape(classMatch.group(2)!);
      return RegExp(
        "<($tag)\\b(?=[^>]*\\bclass\\s*=\\s*[\"'][^\"']*\\b$cls\\b[^\"']*[\"'])[^>]*>([\\s\\S]*?)</\\1>",
        caseSensitive: false,
      );
    }
    final idMatch = RegExp(
      r'^(?:([A-Za-z][\w:-]*)\s*)?#([\w-]+)$',
    ).firstMatch(s);
    if (idMatch != null) {
      final tag = idMatch.group(1) ?? r'[A-Za-z][\w:-]*';
      final id = RegExp.escape(idMatch.group(2)!);
      return RegExp(
        "<($tag)\\b(?=[^>]*\\bid\\s*=\\s*[\"']$id[\"'])[^>]*>([\\s\\S]*?)</\\1>",
        caseSensitive: false,
      );
    }
    return null;
  }

  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  static Archive _replaceHtmlText(
    Archive archive,
    SplayTreeMap<String, String> selectorToFont,
    Map<String, String> fontNameToFile,
    Map<String, String> fontFileToFamily,
    Map<String, Map<int, int>> fontToReplacement,
    Set<String>? targetHtmls,
    Set<String>? targetFamilies,
  ) {
    var working = archive;
    for (final file in archive.files.toList()) {
      if (file.name.isEmpty || !_isHtml(file.name)) continue;
      final original = utf8.decode(
        file.content as List<int>,
        allowMalformed: true,
      );
      var html = original;

      if (_isTargetHtml(file.name, targetHtmls)) {
        for (final entry in selectorToFont.entries) {
          final replacements = fontToReplacement[entry.value];
          if (replacements == null || replacements.isEmpty) continue;
          html = _replaceTextBySelector(
            html,
            entry.key,
            replacements,
            fontFileToFamily[entry.value],
          );
        }
        html = _replaceInlineStyledText(
          html,
          fontNameToFile,
          fontFileToFamily,
          fontToReplacement,
          targetFamilies,
        );
      }

      if (html != original) {
        final bytes = utf8.encode(html);
        working = EpubImageHelper.addOrReplaceFileSafe(
          working,
          ArchiveFile(file.name, bytes.length, bytes),
        );
      }
    }
    return working;
  }

  static String _replaceTextBySelector(
    String html,
    String selector,
    Map<int, int> replacements,
    String? fontFamily,
  ) {
    final pattern = _selectorPattern(selector);
    if (pattern == null) return html;
    return html.replaceAllMapped(pattern, (match) {
      final whole = match.group(0)!;
      final inner = match.group(match.groupCount) ?? '';
      final replaced = _replaceTextNodes(inner, replacements, fontFamily);
      return replaced == inner ? whole : whole.replaceFirst(inner, replaced);
    });
  }

  static String _replaceInlineStyledText(
    String html,
    Map<String, String> fontNameToFile,
    Map<String, String> fontFileToFamily,
    Map<String, Map<int, int>> fontToReplacement,
    Set<String>? targetFamilies,
  ) {
    return html.replaceAllMapped(_styledElementPattern, (match) {
      final style = match.group(4) ?? '';
      final font = _pickFontFile(
        _fontCandidatesFromDeclarations(style),
        fontNameToFile,
        targetFamilies,
      );
      final replacements = font == null ? null : fontToReplacement[font];
      if (replacements == null || replacements.isEmpty) return match.group(0)!;
      final inner = match.group(6) ?? '';
      final replaced = _replaceTextNodes(
        inner,
        replacements,
        fontFileToFamily[font],
      );
      return replaced == inner
          ? match.group(0)!
          : match.group(0)!.replaceFirst(inner, replaced);
    });
  }

  static String _replaceTextNodes(
    String htmlFragment,
    Map<int, int> replacements,
    String? fontFamily,
  ) {
    final protected = <String>[];
    String protect(String value) {
      protected.add(value);
      return String.fromCharCode(0xE000 + protected.length - 1);
    }

    var content = htmlFragment.replaceAllMapped(
      RegExp(
        r'<(?:script|style)\b[^>]*>[\s\S]*?</(?:script|style)>',
        caseSensitive: false,
      ),
      (match) => protect(match.group(0)!),
    );
    content = content.replaceAllMapped(
      RegExp(r'&(?:#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);'),
      (match) => protect(match.group(0)!),
    );
    final replaced = StringBuffer();
    var cursor = 0;
    for (final tag in RegExp(r'<[^>]+>').allMatches(content)) {
      if (tag.start > cursor) {
        replaced.write(
          _replaceRunes(
            content.substring(cursor, tag.start),
            replacements,
            fontFamily,
          ),
        );
      }
      replaced.write(tag.group(0)!);
      cursor = tag.end;
    }
    if (cursor < content.length) {
      replaced.write(
        _replaceRunes(content.substring(cursor), replacements, fontFamily),
      );
    }
    content = replaced.toString();

    for (var i = 0; i < protected.length; i++) {
      content = content.replaceAll(
        String.fromCharCode(0xE000 + i),
        protected[i],
      );
    }
    return content;
  }

  static String _replaceRunes(
    String text,
    Map<int, int> replacements,
    String? fontFamily,
  ) {
    final buffer = StringBuffer();
    var changed = false;
    for (final rune in text.runes) {
      final shadow = replacements[rune];
      if (shadow == null) {
        buffer.writeCharCode(rune);
      } else {
        buffer.writeCharCode(shadow);
        changed = true;
      }
    }
    if (!changed) return text;
    final result = buffer.toString();
    if (fontFamily == null || fontFamily.trim().isEmpty) return result;
    final escapedFamily = _escapeHtmlAttr(fontFamily);
    return '<span style="font-family: &quot;$escapedFamily&quot;;">$result</span>';
  }

  static String _escapeHtmlAttr(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
