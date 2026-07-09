import 'dart:typed_data';

import 'duokan_base.dart';

/// 阅微转多看操作（B13）
///
/// 将阅微（微信读书/阅微书城）格式的脚注 span 转换为标准多看格式。
///
/// 阅微格式：正文中散落 `<span class="reader js_readerFooterNote"
/// data-wr-footernote="脚注内容"></span>` 弹窗注释。
///
/// 转换后：正文中变为带 `duokan-footnote` 类的上标锚点（含 note.png 图标），
/// `</body>` 前集中生成 `aside` 脚注区域。
class YueweiOperation {
  YueweiOperation._();

  /// 执行阅微转多看
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
    final converter = _YueweiConverter(
      epubPath: epubPath,
      outputPath: outputPath,
      notePngBytes: notePngBytes,
    );
    return converter.process();
  }
}

/// 阅微转多看转换器
class _YueweiConverter extends DuokanConverterBase {
  _YueweiConverter({
    required super.epubPath,
    required super.outputPath,
    super.notePngBytes,
  });

  @override
  String processHtml(String filename, String content) {
    try {
      var text = content;
      text = addEpubNamespace(text);

      // 转换阅微 span 脚注
      final result = _convertYueweiSpans(text);
      text = result.$1;
      var footnotes = result.$2;

      // 收集已存在的多看锚点脚注（缺少 aside 的）
      footnotes = [...footnotes, ..._collectExistingDuokanFootnotes(text)];

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

/// 转换阅微 reader span 脚注为多看格式
///
/// 返回 (修改后的内容, 脚注列表)
(String, List<FootnoteInfo>) _convertYueweiSpans(String text) {
  // 匹配两种 class 顺序的阅微脚注 span
  final spanPattern1 = RegExp(
    r"""<span[^>]*class="[^"]*reader[^"]*js_readerFooterNote[^"]*"[^>]*data-wr-footernote="([^"]*)"[^>]*>\s*</span>""",
    dotAll: true,
  );
  final spanPattern2 = RegExp(
    r"""<span[^>]*class="[^"]*js_readerFooterNote[^"]*reader[^"]*"[^>]*data-wr-footernote="([^"]*)"[^>]*>\s*</span>""",
    dotAll: true,
  );

  final matches1 = spanPattern1.allMatches(text).toList();
  final seenSpans = matches1.map((m) => m.group(0)!).toSet();
  final matches2 = spanPattern2.allMatches(text).where((m) {
    return !seenSpans.contains(m.group(0)!);
  }).toList();

  final allMatches = [...matches1, ...matches2]
    ..sort((a, b) => a.start.compareTo(b.start));

  if (allMatches.isEmpty) return (text, []);

  final footnotes = <FootnoteInfo>[];

  // 倒序替换以避免索引偏移
  for (var i = allMatches.length - 1; i >= 0; i--) {
    final match = allMatches[i];
    final noteNumber = i + 1;
    final noteId = 'note$noteNumber';
    final noteRefId = 'note_ref$noteNumber';
    final noteContent = escapeHtml(match.group(1)!);

    final replacement =
        '      <sup>\n'
        '         <a class="duokan-footnote" epub:type="noteref" href="#$noteId" id="$noteRefId">\n'
        '           <img alt="note" class="zhangyue-footnote" src="../Images/note.png" zy-footnote="$noteContent"/>\n'
        '         </a>\n'
        '       </sup>';

    text =
        text.substring(0, match.start) +
        replacement +
        text.substring(match.end);

    footnotes.add(
      FootnoteInfo(id: noteId, refId: noteRefId, content: noteContent),
    );
  }

  // 反转脚注列表（因为是倒序替换的）
  return (text, footnotes.reversed.toList());
}

/// 提取 zy-footnote 或 alt 属性内容
String _extractZyFootnoteContent(String text, int matchStart) {
  final searchEnd = matchStart + 800 < text.length
      ? matchStart + 800
      : text.length;
  final window = text.substring(matchStart, searchEnd);

  var m = RegExp(r'zy-footnote="([^"]*)"').firstMatch(window);
  m ??= RegExp(r'alt="([^"]*)"').firstMatch(window);
  return m?.group(1) ?? '';
}

/// 收集已存在的多看锚点脚注（缺少 aside 元素的）
List<FootnoteInfo> _collectExistingDuokanFootnotes(String text) {
  final footnotes = <FootnoteInfo>[];

  // 三种属性顺序的匹配模式
  final patterns = <(RegExp, int, int)>[
    // href 在前，id 在后
    (
      RegExp(
        r"""<a[^>]*class="[^"]*duokan-footnote[^"]*"[^>]*href="#([^"]+)"[^>]*id="([^"]+)"[^>]*>""",
      ),
      1,
      2,
    ),
    // id 在前，href 在后
    (
      RegExp(
        r"""<a[^>]*id="([^"]+)"[^>]*class="[^"]*duokan-footnote[^"]*"[^>]*href="#([^"]+)"[^>]*>""",
      ),
      2,
      1,
    ),
    // 只有 href，无 id
    (
      RegExp(
        r"""<a(?![^>]*\bid\s*=)[^>]*class="[^"]*duokan-footnote[^"]*"[^>]*href="#([^"]+)"[^>]*>""",
      ),
      1,
      -1, // ref_id = note_id + "_ref"
    ),
  ];

  final seenIds = <String>{};

  for (final (pattern, noteIdGroup, refIdGroup) in patterns) {
    for (final match in pattern.allMatches(text)) {
      final noteId = match.group(noteIdGroup)!;
      final noteRefId = refIdGroup == -1
          ? '${noteId}_ref'
          : match.group(refIdGroup)!;

      if (seenIds.contains(noteId)) continue;

      // 跳过已有 aside 的
      final asidePattern = RegExp(
        '<aside[^>]*id="${RegExp.escape(noteId)}"[^>]*>',
      );
      if (asidePattern.hasMatch(text)) continue;

      final noteContent = escapeHtml(
        _extractZyFootnoteContent(text, match.start),
      );
      seenIds.add(noteId);
      footnotes.add(
        FootnoteInfo(id: noteId, refId: noteRefId, content: noteContent),
      );
    }
  }

  return footnotes;
}
