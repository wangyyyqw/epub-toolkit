import 'dart:typed_data';

import 'duokan_base.dart';

/// 掌阅转多看操作（B13）
///
/// 将掌阅（iReader）格式的散落 `<aside>` 脚注转换为标准多看格式。
///
/// 掌阅格式特点：`<aside>` 元素散落在正文中，紧跟 `<sup>` 标签，
/// `<li>` 内容无 `<p>` 包裹且无返回链接。
///
/// 转换后：移除散落的 `<aside>`，在 `</body>` 前集中生成标准多看
/// 脚注区域，每个脚注有 `<p>` 包裹和返回链接。
class ZhangyueOperation {
  ZhangyueOperation._();

  /// 执行掌阅转多看
  ///
  /// [epubPath] 输入 EPUB 文件路径
  /// [outputPath] 输出 EPUB 文件路径
  /// [notePngBytes] note.png 二进制数据（从 Flutter assets 加载）
  ///
  /// 返回处理结果日志字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    Uint8List? notePngBytes,
  }) async {
    final converter = _ZhangyueConverter(
      epubPath: epubPath,
      outputPath: outputPath,
      notePngBytes: notePngBytes,
    );
    return converter.process();
  }
}

/// 掌阅转多看转换器
class _ZhangyueConverter extends DuokanConverterBase {
  _ZhangyueConverter({
    required super.epubPath,
    required super.outputPath,
    super.notePngBytes,
  });

  @override
  String processHtml(String filename, String content) {
    try {
      var text = content;
      text = addEpubNamespace(text);

      // 转换掌阅散落的 aside 脚注
      final result = _convertZhangyueInlineAsides(text, imagesDir);
      text = result.$1;
      final footnotes = result.$2;

      if (footnotes.isNotEmpty) {
        injectNotePng();
        final section = buildFootnoteSection(footnotes);
        text = injectFootnotesBeforeBodyClose(text, section);
      }

      return text;
    } catch (e) {
      return content;
    }
  }
}

/// 提取正文中散落的掌阅 `<aside>` 脚注，移除原位置，收集脚注内容。
/// 同时将脚注 `<img>` 的 src 替换为 note.png 路径。
///
/// 返回 (修改后的内容, 脚注列表)
(String, List<FootnoteInfo>) _convertZhangyueInlineAsides(
  String text,
  String imagesDir,
) {
  final asidePattern = RegExp(
    r'<aside[^>]*epub:type="footnote"[^>]*id="([^"]+)"[^>]*>(.*?)</aside>',
    dotAll: true,
    caseSensitive: false,
  );

  final footnotes = <FootnoteInfo>[];
  final seenIds = <String>{};

  for (final match in asidePattern.allMatches(text)) {
    final noteId = match.group(1)!;
    final asideInner = match.group(2)!;

    if (seenIds.contains(noteId)) continue;
    seenIds.add(noteId);

    // 从 <li class="duokan-footnote-item"> 中提取脚注纯文本
    var noteContent = '';
    final liMatch = RegExp(
      r'<li[^>]*class="duokan-footnote-item"[^>]*>(.*?)</li>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(asideInner);

    if (liMatch != null) {
      final raw = liMatch.group(1)!.trim();
      // 剥离所有 HTML 标签
      noteContent = raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    }

    // 查找引用锚点的 id（两种属性顺序）
    final refPattern1 = RegExp(
      '<a[^>]*class="[^"]*duokan-footnote[^"]*"[^>]*href="#${RegExp.escape(noteId)}"[^>]*id="([^"]+)"',
      caseSensitive: false,
    );
    final refPattern2 = RegExp(
      '<a[^>]*id="([^"]+)"[^>]*class="[^"]*duokan-footnote[^"]*"[^>]*href="#${RegExp.escape(noteId)}"',
      caseSensitive: false,
    );

    final refMatch1 = refPattern1.firstMatch(text);
    final refMatch2 = refPattern2.firstMatch(text);
    final noteRefId =
        refMatch1?.group(1) ?? refMatch2?.group(1) ?? '${noteId}_ref';

    footnotes.add(
      FootnoteInfo(
        id: noteId,
        refId: noteRefId,
        content: escapeHtml(noteContent),
      ),
    );
  }

  // 移除正文中所有散落的 aside 脚注元素
  text = text.replaceAll(asidePattern, '');

  // 将掌阅脚注 img 的 src 统一替换为 note.png
  final imagesBasename = imagesDir.contains('/')
      ? imagesDir.split('/').last
      : imagesDir;
  final notePngSrc = '../$imagesBasename/note.png';

  final imgPattern = RegExp(
    r"""<img[^>]*class="[^"]*(?:zhangyue-footnote|epub-footnote)[^"]*"[^>]*/?>""",
    caseSensitive: false,
  );
  text = text.replaceAllMapped(imgPattern, (match) {
    final tag = match.group(0)!;
    return tag.replaceAll(RegExp(r'src="[^"]*"'), 'src="$notePngSrc"');
  });

  // 清理移除 aside 后可能留下的空白行
  text = text.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');

  return (text, footnotes);
}
