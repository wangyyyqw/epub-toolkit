import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';
import 'ttf_subsetter.dart';

/// 字体子集化操作
///
/// 分析 EPUB 中的 CSS @font-face 规则和字体引用关系，
/// 提取每个字体实际使用的字符，对 TTF 字体进行子集化以减小体积。
/// 未被任何选择器引用的字体会从 OPF manifest 中移除。
class FontSubsetOperation {
  FontSubsetOperation._();

  /// 支持子集化的字体扩展名
  static const _subsettableExts = ['.ttf', '.otf'];

  /// 所有字体扩展名（含不支持的格式）
  static const _allFontExts = ['.ttf', '.otf', '.woff', '.woff2'];

  /// 执行字体子集化
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) async {
    var archive = await EpubImageHelper.readArchive(epubPath);

    final log = StringBuffer();
    log.writeln('开始字体子集化...');

    // 1. 查找所有字体文件
    final fontFiles = <ArchiveFile>[];
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      final ext = p.extension(file.name).toLowerCase();
      if (_allFontExts.contains(ext)) {
        fontFiles.add(file);
      }
    }

    if (fontFiles.isEmpty) {
      log.writeln('未找到字体文件，无需子集化。直接复制原 EPUB。');
      // 仍输出原 EPUB 的拷贝（保证调用方拿到有效输出）
      final bytes = await File(epubPath).readAsBytes();
      await File(outputPath).writeAsBytes(bytes);
      return log.toString();
    }

    log.writeln('找到 ${fontFiles.length} 个字体文件');

    // 2. 解析 CSS，建立字体名→字体文件、选择器→字体文件映射
    final fontNameToFile = <String, String>{}; // font-family → 字体文件路径
    final selectorToFontFile = <String, String>{}; // CSS选择器 → 字体文件路径

    _parseCssFiles(archive, fontNameToFile, selectorToFontFile);

    log.writeln('解析到 ${fontNameToFile.length} 个 @font-face 规则');
    log.writeln('解析到 ${selectorToFontFile.length} 个选择器→字体映射');

    // 3. 收集每个字体使用的字符
    final fontToChars = <String, Set<int>>{}; // 字体文件路径 → 字符集合

    // 初始化所有字体的字符集合
    for (final fontFile in fontFiles) {
      fontToChars[fontFile.name] = <int>{};
    }

    // 遍历 HTML 文件，按选择器提取文本
    _collectCharsFromHtml(
      archive,
      selectorToFontFile,
      fontToChars,
      fontNameToFile,
    );

    // 4. 子集化字体文件
    var subsetCount = 0;
    var skipCount = 0;
    var removeCount = 0;
    final removedFonts = <String>{}; // 被移除的字体路径

    for (final fontFile in fontFiles) {
      final fontPath = fontFile.name;
      final ext = p.extension(fontPath).toLowerCase();
      final chars = fontToChars[fontPath] ?? <int>{};

      if (chars.isEmpty) {
        // 未被任何选择器引用，移除该字体
        removedFonts.add(fontPath);
        removeCount++;
        log.writeln('  移除未引用字体: $fontPath');
        continue;
      }

      if (!_subsettableExts.contains(ext)) {
        // 不支持的格式（woff/woff2），跳过
        skipCount++;
        log.writeln('  跳过不支持的格式: $fontPath ($ext)');
        continue;
      }

      // 子集化 TTF/OTF 字体
      final fontData = EpubImageHelper.readBytes(fontFile);
      final subsetData = TtfSubsetter.subset(fontData, chars);

      if (subsetData != null) {
        final ratio = subsetData.length / fontData.length;
        log.writeln(
          '  子集化: $fontPath '
          '${EpubImageHelper.sizeStr(fontData.length)} → '
          '${EpubImageHelper.sizeStr(subsetData.length)} '
          '(${(ratio * 100).toStringAsFixed(1)}%) '
          '保留 ${chars.length} 字符',
        );

        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile(fontPath, subsetData.length, subsetData),
        );
        subsetCount++;
      } else {
        log.writeln('  子集化失败，保留原字体: $fontPath');
        skipCount++;
      }
    }

    // 5. 从 OPF manifest 中移除未引用的字体
    if (removedFonts.isNotEmpty) {
      _removeFromOpfManifest(archive, removedFonts);
      // 安全移除字体文件（archive 包 removeFile 有索引损坏 bug）
      archive = EpubImageHelper.removeFiles(archive, removedFonts.toSet());
    }

    // 6. 保存
    await EpubImageHelper.saveArchive(archive, outputPath);

    log.writeln(
      '\n字体子集化完成: '
      '子集化 $subsetCount 个, 移除 $removeCount 个, 跳过 $skipCount 个',
    );
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 解析 CSS 文件，建立字体映射关系
  ///
  /// [fontNameToFile] 输出：font-family 名称 → 字体文件路径
  /// [selectorToFontFile] 输出：CSS 选择器 → 字体文件路径
  static void _parseCssFiles(
    Archive archive,
    Map<String, String> fontNameToFile,
    Map<String, String> selectorToFontFile,
  ) {
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      if (!file.name.toLowerCase().endsWith('.css')) continue;

      final content = utf8.decode(file.content as List<int>);

      // 解析 @font-face 规则
      _parseFontFace(content, fontNameToFile);

      // 解析选择器中的 font-family 声明
      _parseSelectorFonts(content, fontNameToFile, selectorToFontFile);
    }
  }

  /// 解析 @font-face 规则
  ///
  /// 提取 font-family 名称和 src 中的 url
  static void _parseFontFace(String css, Map<String, String> fontNameToFile) {
    final fontFacePattern = RegExp(
      r'@font-face\s*\{([^}]*)\}',
      caseSensitive: false,
    );

    for (final match in fontFacePattern.allMatches(css)) {
      final body = match.group(1)!;

      // 提取 font-family
      final familyMatch = RegExp(
        r"""font-family\s*:\s*["']?([^"';\s]+)["']?""",
        caseSensitive: false,
      ).firstMatch(body);
      if (familyMatch == null) continue;
      final familyName = familyMatch.group(1)!.trim();

      // 提取 src url
      final srcMatch = RegExp(
        r"""url\s*\(\s*["']?([^"')\s]+)["']?""",
        caseSensitive: false,
      ).firstMatch(body);
      if (srcMatch == null) continue;
      final url = srcMatch.group(1)!.trim();

      // 提取文件名（CSS 中的 url 可能是相对路径或绝对路径）
      final fileName = p.basename(url);

      fontNameToFile[familyName] = fileName;
    }
  }

  /// 解析 CSS 选择器中的 font-family 声明
  ///
  /// 将使用特定 font-family 的 CSS 选择器映射到字体文件
  static void _parseSelectorFonts(
    String css,
    Map<String, String> fontNameToFile,
    Map<String, String> selectorToFontFile,
  ) {
    // 匹配 CSS 规则块：selector { declarations }
    final rulePattern = RegExp(r'([^{}]+)\{([^}]*)\}');

    for (final match in rulePattern.allMatches(css)) {
      final selectors = match.group(1)!.trim();
      final declarations = match.group(2)!;

      // 跳过 @font-face（已单独处理）
      if (selectors.contains('@font-face')) continue;

      // 提取 font-family 声明
      final familyMatch = RegExp(
        r"""font-family\s*:\s*["']?([^"';\s]+)["']?""",
        caseSensitive: false,
      ).firstMatch(declarations);
      if (familyMatch == null) continue;

      final familyName = familyMatch.group(1)!.trim();
      final fontFile = fontNameToFile[familyName];
      if (fontFile == null) continue;

      // 按逗号分割多个选择器
      for (final selector in selectors.split(',')) {
        final trimmed = selector.trim();
        if (trimmed.isNotEmpty) {
          selectorToFontFile[trimmed] = fontFile;
        }
      }
    }
  }

  /// 从 HTML 文件中收集每个字体使用的字符
  ///
  /// [selectorToFontFile] CSS 选择器 → 字体文件映射
  /// [fontToChars] 输出：字体文件路径 → 字符集合
  /// [fontNameToFile] font-family 名称 → 字体文件映射
  static void _collectCharsFromHtml(
    Archive archive,
    Map<String, String> selectorToFontFile,
    Map<String, Set<int>> fontToChars,
    Map<String, String> fontNameToFile,
  ) {
    // 如果没有选择器映射，则所有文本都可能是字体使用的字符
    final noSelectors = selectorToFontFile.isEmpty;

    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.html') &&
          !lowerName.endsWith('.xhtml') &&
          !lowerName.endsWith('.htm')) {
        continue;
      }

      final content = utf8.decode(file.content as List<int>);

      if (noSelectors) {
        // 无选择器映射时，将所有文本字符加入所有字体
        final chars = _extractAllChars(content);
        for (final fontPath in fontToChars.keys) {
          fontToChars[fontPath]!.addAll(chars);
        }
      } else {
        // 按选择器提取文本
        _collectCharsBySelectors(content, selectorToFontFile, fontToChars);

        // 同时处理内联 style 中的 font-family
        _collectCharsFromInlineStyle(content, fontNameToFile, fontToChars);
      }
    }
  }

  /// 提取 HTML 中的所有字符
  ///
  /// 去除标签和 script/style 内容
  static Set<int> _extractAllChars(String html) {
    final chars = <int>{};

    // 移除 script 和 style 内容
    final cleaned = html
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        );

    // 提取标签之间的文本
    for (final match in RegExp(r'>([^<]+)<').allMatches(cleaned)) {
      final text = match.group(1)!;
      for (final rune in text.runes) {
        if (rune > 0x20) {
          chars.add(rune);
        }
      }
    }

    return chars;
  }

  /// 按选择器提取文本中的字符
  ///
  /// 简化实现：通过正则匹配 class/id 选择器对应的元素文本
  static void _collectCharsBySelectors(
    String html,
    Map<String, String> selectorToFontFile,
    Map<String, Set<int>> fontToChars,
  ) {
    for (final entry in selectorToFontFile.entries) {
      final selector = entry.key;
      final fontFile = entry.value;
      final charSet = fontToChars[fontFile];
      if (charSet == null) continue;

      final chars = _extractTextBySelector(html, selector);
      charSet.addAll(chars);
    }
  }

  /// 根据 CSS 选择器提取 HTML 中的文本
  ///
  /// 支持标签选择器、class 选择器、id 选择器
  static Set<int> _extractTextBySelector(String html, String selector) {
    final chars = <int>{};

    // 标签选择器（如 body, p, div）
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9]*$').hasMatch(selector)) {
      final pattern = RegExp(
        r'<' + selector + r'\b[^>]*>([\s\S]*?)</' + selector + r'>',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(html)) {
        final text = _stripTags(match.group(1)!);
        for (final rune in text.runes) {
          if (rune > 0x20) chars.add(rune);
        }
      }
    }
    // class 选择器（如 .content, .chapter）
    else if (selector.startsWith('.')) {
      final className = selector.substring(1);
      // 匹配 class 属性包含该类名的元素
      final pattern = RegExp(
        r"""<(\w+)\b[^>]*\bclass\s*=\s*["'][^"']*""" +
            RegExp.escape(className) +
            r"""[^"']*["'][^>]*>([\s\S]*?)</\1>""",
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(html)) {
        final text = _stripTags(match.group(2)!);
        for (final rune in text.runes) {
          if (rune > 0x20) chars.add(rune);
        }
      }
    }
    // id 选择器（如 #content, #chapter）
    else if (selector.startsWith('#')) {
      final idName = selector.substring(1);
      final pattern = RegExp(
        r"""<(\w+)\b[^>]*\bid\s*=\s*["']""" +
            RegExp.escape(idName) +
            r"""["'][^>]*>([\s\S]*?)</\1>""",
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(html)) {
        final text = _stripTags(match.group(2)!);
        for (final rune in text.runes) {
          if (rune > 0x20) chars.add(rune);
        }
      }
    }

    return chars;
  }

  /// 从内联 style 属性中提取 font-family 并收集对应文本
  ///
  /// 处理 style="font-family: xxx" 的元素
  static void _collectCharsFromInlineStyle(
    String html,
    Map<String, String> fontNameToFile,
    Map<String, Set<int>> fontToChars,
  ) {
    // 匹配带有 style="font-family: xxx" 的元素
    final pattern = RegExp(
      r"""<(\w+)\b[^>]*\bstyle\s*=\s*["'][^"']*font-family\s*:\s*["']?([^"';\s]+)["']?[^"']*["'][^>]*>([\s\S]*?)</\1>""",
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(html)) {
      final familyName = match.group(2)!.trim();
      final content = match.group(3)!;
      final fontFile = fontNameToFile[familyName];
      if (fontFile == null) continue;

      final charSet = fontToChars[fontFile];
      if (charSet == null) continue;

      final text = _stripTags(content);
      for (final rune in text.runes) {
        if (rune > 0x20) charSet.add(rune);
      }
    }
  }

  /// 去除 HTML 标签，保留纯文本
  static String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 从 OPF manifest 中移除未引用的字体项
  ///
  /// [removedFonts] 被移除的字体文件路径集合
  static void _removeFromOpfManifest(
    Archive archive,
    Set<String> removedFonts,
  ) {
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) return;

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) return;

    try {
      final opfContent = utf8.decode(opfFile.content as List<int>);
      final document = xml.XmlDocument.parse(opfContent);

      // 收集被移除字体的文件名
      final removedBasenames = removedFonts.map(p.basename).toSet();

      // 查找并移除匹配的 manifest item
      final items = document.findAllElements('item', namespace: '*').toList();

      for (final item in items) {
        final href = item.getAttribute('href');
        if (href == null) continue;

        final hrefBasename = p.basename(href);

        // 按文件名匹配
        if (removedBasenames.contains(hrefBasename)) {
          // 检查 media-type 是否为字体类型
          final mediaType = item.getAttribute('media-type') ?? '';
          if (mediaType.startsWith('application/font') ||
              mediaType.startsWith('font/') ||
              mediaType.contains('font')) {
            item.parentElement?.children.remove(item);
          }
        }
      }

      // 写回修改后的 OPF
      final updatedOpf = document.toXmlString(pretty: true);
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile(opfPath, updatedOpf.length, utf8.encode(updatedOpf)),
      );
    } catch (e) {
      // OPF 解析失败，跳过清理
    }
  }
}
