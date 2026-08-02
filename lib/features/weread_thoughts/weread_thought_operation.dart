import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'chapter_mapper.dart';
import 'weread_api.dart';

/// 想法注入操作:把读书平台的热门划线想法注入到本地 EPUB。
///
/// 数据获取采用 pickthought.koplugin 的方案(/book/underlines + /book/readreviews)。
/// 注入和显示采用工具箱原有的弹窗注释方案(note.png 图标 + hover 弹窗):
/// 1. HTML 分词(tokenize):把 HTML 拆成 text token 和 tag token
/// 2. 构建文本索引(build_text_index):从可见文本中建立紧凑文本+位置映射
/// 3. 引文定位(locate_quote):用划线引文在文本索引中查找,找到最佳匹配位置
/// 4. 区间计算(intervals):排序、去重、合并重叠划线
/// 5. 渲染(render):在引文位置包裹 .reader 锚点 span,嵌入想法弹窗内容
/// 6. 注入内联样式(ensure_style):在 <head> 中注入 CSS(含 note.png data URI)
///
/// 产物是标准 EPUB,任何阅读器 hover 划线处即可查看想法弹窗。
class WereadThoughtOperation {
  WereadThoughtOperation._();

  /// 弹窗 CSS 样式标记(用于检测是否已注入)
  static const cssMarker = '/* ========== 读书想法样式 ========== */';

  /// EPUB 内 note.png 的路径(相对于 OPF 目录)
  static const _notePngPath = 'weread-note.png';

  /// EPUB 内 CSS 文件的路径(相对于 OPF 目录)
  static const _cssPath = 'weread-thoughts.css';

  /// 生成弹窗 CSS 样式(引用外部 note.png 文件,非 base64)
  ///
  /// CSS 文件和 note.png 都放在 OPF 目录下,两者同级,
  /// 因此 CSS 中引用 note.png 用相对路径 `url(weread-note.png)`。
  static String _generateCss() {
    return '''
$cssMarker
.reader {
    background-image: url($_notePngPath);
    background-repeat: no-repeat;
    background-position: right center;
    background-size: 1em 1em;
    padding-right: 1.2em;
    cursor: pointer;
}
.reader .reader-note-content {
    display: none;
}
.reader:hover .reader-note-content {
    display: block;
    position: fixed;
    left: 0;
    bottom: 0;
    margin: 1em;
    background: black;
    color: white;
    padding: 0.5em;
    font-size: 1em;
    font-family: "SourceHanSerifApp", sans-serif;
    z-index: 10;
    text-indent: 0em;
    max-width: 90vw;
}
''';
  }

  /// 计算从 HTML 文件到 CSS 文件的相对路径
  ///
  /// [htmlPath] HTML 文件在 EPUB 内的完整路径(如 OEBPS/Text/Section1.xhtml)
  /// [opfDir] OPF 所在目录(如 OEBPS/)
  /// 返回 HTML 中 <link> 标签的 href 属性值
  static String _relativeCssHref(String htmlPath, String opfDir) {
    // CSS 文件的完整路径 = opfDir + _cssPath
    // HTML 文件的目录 = htmlPath 的父目录
    final htmlDir = htmlPath.contains('/')
        ? htmlPath.substring(0, htmlPath.lastIndexOf('/') + 1)
        : '';

    // 如果 HTML 和 CSS 在同一目录,直接返回文件名
    if (htmlDir == opfDir) {
      return _cssPath;
    }

    // 否则计算相对路径:先回到公共父目录,再进入 CSS 所在目录
    final htmlParts = htmlDir.split('/').where((s) => s.isNotEmpty).toList();
    final opfParts = opfDir.split('/').where((s) => s.isNotEmpty).toList();

    // 找公共前缀
    var common = 0;
    while (common < htmlParts.length &&
        common < opfParts.length &&
        htmlParts[common] == opfParts[common]) {
      common++;
    }

    // 从 HTML 目录回到公共父目录:每个剩余层级一个 ../
    final ups = htmlParts.length - common;
    // 从公共父目录进入 CSS 所在目录
    final downs = opfParts.sublist(common);

    final parts = <String>[];
    for (var i = 0; i < ups; i++) {
      parts.add('..');
    }
    parts.addAll(downs);
    parts.add(_cssPath);

    return parts.join('/');
  }

  /// 在 OPF 的 <manifest> 中添加 note.png 和 CSS 文件的条目
  ///
  /// [opfContent] OPF XML 原文
  /// [notePngFullPath] note.png 相对于 OPF 的路径(如 weread-note.png)
  /// [cssFullPath] CSS 文件相对于 OPF 的路径(如 weread-thoughts.css)
  /// 返回修改后的 OPF XML
  static String _addManifestItems(
    String opfContent, {
    required String notePngFullPath,
    required String cssFullPath,
  }) {
    // 检查是否已存在(避免重复添加)
    final hasNotePng = opfContent.contains('weread-note.png');
    final hasCss = opfContent.contains('weread-thoughts.css');

    if (hasNotePng && hasCss) return opfContent;

    final items = <String>[];
    if (!hasNotePng) {
      items.add(
        '  <item id="weread-note-png" href="$notePngFullPath" '
        'media-type="image/png" />',
      );
    }
    if (!hasCss) {
      items.add(
        '  <item id="weread-thoughts-css" href="$cssFullPath" '
        'media-type="text/css" />',
      );
    }

    final insertStr = items.join('\n');

    // 插入到 </manifest> 前
    final manifestEnd = RegExp(r'</[Mm][Aa][Nn][Ii][Ff][Ee][Ss][Tt]\s*>')
        .firstMatch(opfContent);
    if (manifestEnd != null) {
      return opfContent.substring(0, manifestEnd.start) +
          insertStr +
          '\n' +
          opfContent.substring(manifestEnd.start);
    }

    // 兜底:无 </manifest> 标签,尝试 </package> 前
    final packageEnd =
        RegExp(r'</[Pp][Aa][Cc][Kk][Aa][Gg][Ee]\s*>').firstMatch(opfContent);
    if (packageEnd != null) {
      return opfContent.substring(0, packageEnd.start) +
          insertStr +
          '\n' +
          opfContent.substring(packageEnd.start);
    }

    return opfContent;
  }

  // === HTML 实体映射(移植自 annotations.lua NAMED_ENTITIES) ===

  static const _namedEntities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ensp': ' ',
    'emsp': ' ',
    'thinsp': ' ',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'lsquo': '\u2018',
    'rsquo': '\u2019',
    'ldquo': '\u201C',
    'rdquo': '\u201D',
    'zwnj': '',
    'zwj': '',
  };

  /// 需要跳过内容的标签(移植自 annotations.lua SKIP_TEXT_TAGS)
  static const _skipTextTags = {
    'script',
    'style',
    'noscript',
    'template',
    'svg',
  };

  /// 执行想法注入
  ///
  /// [epubPath] 本地 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// [chapters] 从读书平台拉取的章节数据(含划线和想法)
  /// [notePngBytes] note.png 图标字节(用于弹窗标记背景)
  /// [onProgress] 进度回调 (phase, current, total, text)
  /// 返回处理结果日志
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required List<ChapterData> chapters,
    required Uint8List notePngBytes,
    void Function(String phase, int current, int total, String text)?
        onProgress,
  }) async {
    onProgress ??= (_, _, _, _) {};
    final log = StringBuffer('开始注入读书想法...\n');

    // 1. 读取 EPUB
    onProgress('read', 0, 1, '读取 EPUB');
    final inputBytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(inputBytes);

    // 2. 解析 OPF 获取 spine 顺序和文件路径
    onProgress('parse', 0, 1, '解析 EPUB 结构');
    final epubInfo = _parseEpubStructure(archive);
    if (epubInfo.spine.isEmpty) {
      log.writeln('错误: EPUB 中没有找到 HTML 文件');
      return log.toString();
    }
    onProgress('parse', 1, 1, '共 ${epubInfo.spine.length} 个文件');

    // 3. 读取所有 spine HTML 内容
    final htmlMap = <String, String>{};
    for (final href in epubInfo.spine) {
      final file = archive.findFile(href);
      if (file != null) {
        htmlMap[href] =
            utf8.decode(file.content as List<int>, allowMalformed: true);
      }
    }

    // 4. 转换 API 数据为映射器输入
    final chapterInputs = <ChapterInput>[];
    for (final ch in chapters) {
      if (!ch.hasData) continue;
      chapterInputs.add(ChapterInput(
        uid: ch.chapterUid,
        title: ch.title,
        underlines: ch.underlines
            .map((u) => UnderlineInput(range: u.range, markText: u.markText))
            .toList(),
        reviewMap: ch.reviewMap.map((range, reviews) => MapEntry(
              range,
              reviews
                  .map((r) => ReviewInput(
                        content: r.content,
                        abstract: r.abstract,
                        author: r.author,
                        likes: r.likes,
                      ))
                  .toList(),
            )),
      ));
    }

    if (chapterInputs.isEmpty) {
      log.writeln('错误: 没有可用的章节数据');
      return log.toString();
    }

    // 5. 章节映射
    onProgress('map', 0, chapterInputs.length, '匹配章节');
    final (mapped, unmatched) = ChapterMapper.build(
      epubInfo.spine,
      (href) => htmlMap[href] ?? '',
      chapterInputs,
    );

    log.writeln('章节映射: ${mapped.length} 个映射, ${unmatched.length} 个未匹配');
    if (unmatched.isNotEmpty) {
      final noHit = unmatched.where((u) => u.reason == 'no_hit').length;
      final noData = unmatched.where((u) => u.reason == 'no_data').length;
      log.writeln('  未匹配: $noHit 章引文不中, $noData 章无数据');
      if (noHit > 0) {
        // 列出未匹配章节标题,帮助用户判断
        final noHitTitles = unmatched
            .where((u) => u.reason == 'no_hit')
            .map((u) => u.title)
            .join('、');
        log.writeln('  引文不中的章节: $noHitTitles');
      }
      log.writeln('  说明: 封面/版权页/附录等无正文的章节无法匹配,属正常现象');
    }

    if (mapped.isEmpty) {
      log.writeln('错误: 没有任何章节能匹配到本地书,请确认绑定的和本地打开的是同一本书');
      return log.toString();
    }

    // 6. 按文件分组注入目标
    final groupsByHref = <String, List<MappedChapter>>{};
    for (final m in mapped) {
      groupsByHref.putIfAbsent(m.href, () => []).add(m);
    }

    // 7. 逐文件注入想法
    onProgress('inject', 0, groupsByHref.length, '注入想法');
    var totalInjected = 0;
    var fileIndex = 0;

    for (final entry in groupsByHref.entries) {
      fileIndex++;
      final href = entry.key;
      final chaptersForFile = entry.value;
      onProgress('inject', fileIndex, groupsByHref.length, href);

      final originalHtml = htmlMap[href];
      if (originalHtml == null) continue;

      // 合并同文件多章数据,单次分词+注入
      final (injectedHtml, count) = _injectFile(
        originalHtml,
        chaptersForFile,
        htmlPath: href,
        opfDir: epubInfo.opfDir,
      );
      if (count > 0) {
        htmlMap[href] = injectedHtml;
        totalInjected += count;
        log.writeln('  $href: 注入 $count 个想法锚点');
      }
    }

    onProgress('inject', groupsByHref.length, groupsByHref.length, '完成');
    log.writeln('共注入 $totalInjected 个想法锚点');

    if (totalInjected == 0) {
      log.writeln('警告: 没有成功注入任何想法(引文可能在本地书中被精校修改)');
    }

    // 8. 构建输出 EPUB(外部 CSS 文件 + note.png 图片)
    onProgress('pack', 0, 1, '打包 EPUB');
    final outputArchive = Archive();
    final writtenFiles = <String>{};

    // note.png 和 CSS 在 EPUB 内的完整路径(放在 OPF 目录下)
    final notePngFullPath = '${epubInfo.opfDir}$_notePngPath';
    final cssFullPath = '${epubInfo.opfDir}$_cssPath';

    for (final file in archive.files) {
      if (file.name.isEmpty || writtenFiles.contains(file.name)) continue;
      final rawBytes = Uint8List.fromList(file.content as List<int>);

      if (file.name == 'mimetype') {
        final mf = ArchiveFile('mimetype', rawBytes.length, rawBytes)
          ..compress = false;
        outputArchive.addFile(mf);
      } else if (file.name == epubInfo.opfPath) {
        // 修改 OPF:添加 manifest 条目
        final opfContent =
            utf8.decode(rawBytes, allowMalformed: true);
        final modifiedOpf = _addManifestItems(
          opfContent,
          notePngFullPath: _notePngPath,
          cssFullPath: _cssPath,
        );
        final newBytes = Uint8List.fromList(utf8.encode(modifiedOpf));
        outputArchive.addFile(
          ArchiveFile(file.name, newBytes.length, newBytes),
        );
      } else if (htmlMap.containsKey(file.name)) {
        // 注入后的 HTML 文件
        final newBytes = Uint8List.fromList(utf8.encode(htmlMap[file.name]!));
        outputArchive.addFile(
          ArchiveFile(file.name, newBytes.length, newBytes),
        );
      } else {
        outputArchive.addFile(
          ArchiveFile(file.name, rawBytes.length, rawBytes),
        );
      }
      writtenFiles.add(file.name);
    }

    // 添加 note.png 图片文件(如果尚未存在)
    if (!writtenFiles.contains(notePngFullPath)) {
      outputArchive.addFile(
        ArchiveFile(notePngFullPath, notePngBytes.length, notePngBytes),
      );
      writtenFiles.add(notePngFullPath);
    }

    // 添加 CSS 文件
    if (!writtenFiles.contains(cssFullPath)) {
      final cssContent = _generateCss();
      final cssBytes = Uint8List.fromList(utf8.encode(cssContent));
      outputArchive.addFile(
        ArchiveFile(cssFullPath, cssBytes.length, cssBytes),
      );
      writtenFiles.add(cssFullPath);
    }

    await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);
    onProgress('pack', 1, 1, '完成');

    log.writeln('想法注入完成');
    log.writeln('输出: $outputPath');
    return log.toString();
  }

  // === 文件级注入(合并多章,单次分词) ===

  /// 在单个 HTML 文件中注入想法
  ///
  /// 合并同一文件的多个微信章节数据,进行单次分词和注入。
  /// 多章合并时禁用数字 range 兜底(range 是章内偏移,跨章无意义)。
  /// [htmlPath] HTML 文件在 EPUB 内的路径(用于计算 CSS 相对路径)
  /// [opfDir] OPF 所在目录(用于计算 CSS 相对路径)
  static (String, int) _injectFile(
    String html,
    List<MappedChapter> chaptersForFile, {
    String htmlPath = '',
    String opfDir = '',
  }) {
    // 合并所有章节的划线和想法
    final allUnderlines = <UnderlineInput>[];
    final allReviews = <String, List<ReviewInput>>{};
    final seenRanges = <String>{};

    for (final ch in chaptersForFile) {
      for (final u in ch.underlines) {
        if (!seenRanges.contains(u.range)) {
          seenRanges.add(u.range);
          allUnderlines.add(u);
        }
      }
      for (final entry in ch.reviewMap.entries) {
        if (!allReviews.containsKey(entry.key)) {
          allReviews[entry.key] = [];
        }
        allReviews[entry.key]!.addAll(entry.value);
      }
    }

    // 多章合并时禁用数字兜底
    final noNumericFallback = chaptersForFile.length > 1 ||
        chaptersForFile.any((ch) => ch.quoteOnly);

    final data = _InjectionData(
      underlines: allUnderlines,
      reviewMap: allReviews,
      noNumericFallback: noNumericFallback,
    );

    final (rendered, stats) = _inject(html, data);
    final count = stats.quoteAligned + stats.numeric;

    if (count == 0) return (html, 0);

    // 注入外部 CSS 引用(通过 <link> 标签)
    final cssHref = _relativeCssHref(htmlPath, opfDir);
    final withStyle = _ensureStyle(rendered, cssHref);
    return (withStyle, count);
  }

  // === HTML 分词器(移植自 annotations.lua tokenize) ===

  /// 把 HTML 拆分为 token 序列
  ///
  /// text token 包含原始文本、分词后的 units、可见起始位置。
  /// tag token 只包含原始标签文本。
  /// 跳过 script/style 等标签内的内容,也跳过 reader-note-content 内的内容。
  static List<_Token> _tokenize(String html) {
    final tokens = <_Token>[];
    var visible = 0;
    var skipDepth = 0;
    var noteSkipDepth = 0; // 跳过 reader-note-content 内的文本
    var i = 0;

    while (i < html.length) {
      if (html[i] == '<') {
        // 查找标签结束位置
        final j = html.indexOf('>', i + 1);
        if (j < 0) {
          // 没有匹配的 >,剩余部分作为 text token
          final raw = html.substring(i);
          final units = _splitUnits(raw);
          final skipped = skipDepth > 0 || noteSkipDepth > 0;
          tokens.add(_Token.text(
            raw: raw,
            units: units,
            start: visible,
            skip: skipped,
          ));
          if (!skipped) visible += units.length;
          break;
        }

        final raw = html.substring(i, j + 1);
        final (closing, name, selfClosing) = _tagInfo(raw);

        // 处理 reader-note-content 跳过
        if (noteSkipDepth > 0) {
          if (closing && name == 'span') {
            noteSkipDepth = 0;
          }
          tokens.add(_Token.tag(raw));
          i = j + 1;
          continue;
        }

        if (!closing &&
            name == 'span' &&
            RegExp("class\\s*=\\s*[\"'][^\"']*reader-note-content")
                .hasMatch(raw)) {
          noteSkipDepth = 1;
          tokens.add(_Token.tag(raw));
          i = j + 1;
          continue;
        }

        // 处理 skip 标签(script/style 等)
        if (closing && _skipTextTags.contains(name)) {
          skipDepth = skipDepth > 0 ? skipDepth - 1 : 0;
        } else if (!closing && !selfClosing && _skipTextTags.contains(name)) {
          skipDepth++;
        }

        tokens.add(_Token.tag(raw));
        i = j + 1;
      } else {
        // 文本内容:查找到下一个 < 或字符串末尾
        final j = html.indexOf('<', i);
        final end = j < 0 ? html.length : j;
        final raw = html.substring(i, end);
        final units = _splitUnits(raw);
        final skipped = skipDepth > 0 || noteSkipDepth > 0;
        tokens.add(_Token.text(
          raw: raw,
          units: units,
          start: visible,
          skip: skipped,
        ));
        if (!skipped) visible += units.length;
        i = end;
      }
    }

    return tokens;
  }

  /// 把文本拆分为 HTML 单元(实体 + 字符)
  ///
  /// 移植自 annotations.lua split_units。
  /// 每个单元要么是 HTML 实体(&...;),要么是一个字符(处理代理对)。
  static List<String> _splitUnits(String raw) {
    final units = <String>[];
    var i = 0;

    while (i < raw.length) {
      // 检查 HTML 实体 &...;
      if (raw[i] == '&') {
        final entityEnd = raw.indexOf(';', i);
        if (entityEnd > 0 && entityEnd - i < 20) {
          final entity = raw.substring(i, entityEnd + 1);
          if (RegExp(r'^&[#\w]+;$').hasMatch(entity)) {
            units.add(entity);
            i = entityEnd + 1;
            continue;
          }
        }
      }

      // 普通字符:处理代理对(4 字节 UTF-8 字符)
      final codeUnit = raw.codeUnitAt(i);
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < raw.length) {
        units.add(raw.substring(i, i + 2));
        i += 2;
      } else {
        units.add(raw.substring(i, i + 1));
        i++;
      }
    }

    return units;
  }

  /// 解码 HTML 实体单元
  ///
  /// 移植自 annotations.lua decode_html_unit。
  static String _decodeHtmlUnit(String unit) {
    // 数值实体 &#123;
    final decimal = RegExp(r'^&#(\d+);$').firstMatch(unit);
    if (decimal != null) {
      final code = int.parse(decimal.group(1)!);
      if (_isValidCodepoint(code)) return String.fromCharCode(code);
      return unit;
    }

    // 十六进制实体 &#x1F600;
    final hex = RegExp(r'^&#[xX]([0-9a-fA-F]+);$').firstMatch(unit);
    if (hex != null) {
      final code = int.parse(hex.group(1)!, radix: 16);
      if (_isValidCodepoint(code)) return String.fromCharCode(code);
      return unit;
    }

    // 命名实体 &amp;
    final named = RegExp(r'^&(\w+);$').firstMatch(unit);
    if (named != null) {
      return _namedEntities[named.group(1)] ?? unit;
    }

    return unit;
  }

  /// 检查码点是否有效(非代理区、非超出范围)
  static bool _isValidCodepoint(int code) {
    return code >= 0 &&
        code <= 0x10FFFF &&
        (code < 0xD800 || code > 0xDFFF);
  }

  /// 判断文本是否可忽略(空白、零宽字符等)
  ///
  /// 移植自 annotations.lua is_ignorable_text。
  static bool _isIgnorableText(String value) {
    if (value.isEmpty) return true;
    if (RegExp(r'^\s+$').hasMatch(value)) return true;
    return value == '\u00A0' // nbsp
        || value == '\u3000' // 全角空格
        || value == '\u200B' // 零宽空格
        || value == '\u200C' // 零宽非连接符
        || value == '\u200D' // 零宽连接符
        || value == '\uFEFF'; // BOM
  }

  /// 从标签文本中提取信息
  ///
  /// 返回 (是否闭合, 标签名, 是否自闭合)
  /// 移植自 annotations.lua tag_info。
  static (bool, String, bool) _tagInfo(String raw) {
    final match = RegExp(r'^<\s*(/?)\s*([\w:%_-]+)').firstMatch(raw);
    if (match == null) return (false, '', false);
    final closing = match.group(1) == '/';
    final name = match.group(2)!.toLowerCase();
    final selfClosing = RegExp(r'/\s*>$').hasMatch(raw);
    return (closing, name, selfClosing);
  }

  // === 文本索引(移植自 annotations.lua build_text_index) ===

  /// 构建文本索引
  ///
  /// 从可见 text token 中建立紧凑文本(解码后去空白)和位置映射。
  /// - starts/ends: 紧凑文本字节位置 → 原始可见位置
  /// - ordinals: 紧凑文本字节位置 → 紧凑序号
  /// - utf16Bounds: UTF-16 位置 → 原始可见位置(用于数字 range 兜底)
  static _TextIndex _buildTextIndex(List<_Token> tokens) {
    final pieces = <String>[];
    final starts = <int, int>{};
    final ends = <int, int>{};
    final ordinals = <int, int>{};
    final compactBounds = <int, int>{};
    final utf16Bounds = <int, int>{};
    var bytePos = 0;
    var compactCount = 0;
    var utf16Count = 0;

    for (final token in tokens) {
      if (token.isTag || token.skip) continue;
      final units = token.units;
      if (units == null) continue;

      for (var index = 0; index < units.length; index++) {
        final unit = units[index];
        final rawPos = token.start + index;
        final decoded = _decodeHtmlUnit(unit);

        // UTF-16 边界映射
        utf16Bounds.putIfAbsent(utf16Count, () => rawPos);
        final width = _utf16Width(decoded);
        for (var extra = 1; extra < width; extra++) {
          utf16Bounds[utf16Count + extra] = rawPos;
        }
        utf16Count += width;
        utf16Bounds[utf16Count] = rawPos + 1;

        if (!_isIgnorableText(decoded)) {
          compactBounds.putIfAbsent(compactCount, () => rawPos);
          pieces.add(decoded);
          starts[bytePos] = rawPos;
          ordinals[bytePos] = compactCount;
          final endByte = bytePos + decoded.length - 1;
          ends[endByte] = rawPos + 1;
          bytePos = endByte + 1;
          compactCount++;
          compactBounds[compactCount] = rawPos + 1;
        }
      }
    }

    return _TextIndex(
      text: pieces.join(),
      starts: starts,
      ends: ends,
      ordinals: ordinals,
      compactBounds: compactBounds,
      compactCount: compactCount,
      utf16Bounds: utf16Bounds,
      utf16Count: utf16Count,
    );
  }

  /// UTF-16 字符宽度(用于数字 range 兜底)
  ///
  /// 码点 >= U+10000 的字符在 UTF-16 中占 2 个码元(代理对)。
  static int _utf16Width(String value) {
    if (value.isEmpty) return 1;
    final rune = value.runes.first;
    return rune >= 0x10000 ? 2 : 1;
  }

  // === 引文匹配(移植自 annotations.lua normalize_text / quote_candidates / locate_quote) ===

  /// 归一化文本:剥标签、解码实体、去可忽略字符
  ///
  /// 移植自 annotations.lua normalize_text。
  /// 与 chapter_mapper.dart 的 normalize 不同(后者还做全角转半角、去所有空白),
  /// 这里只解码实体和去可忽略字符,保留内容标点。
  static String _normalizeText(String value) {
    // 剥标签
    final raw = value.replaceAll(RegExp(r'<[^>]+>'), '');
    final out = <String>[];

    for (final unit in _splitUnits(raw)) {
      final decoded = _decodeHtmlUnit(unit);
      if (!_isIgnorableText(decoded)) {
        out.add(decoded);
      }
    }

    return out.join();
  }

  /// 清理引文中的排版占位符
  ///
  /// 移植自 web_fetch.lua clean_quote。
  /// [插图] 等占位符不在正文中,留着会毁掉引文对齐。
  static String _cleanQuote(String text) {
    return text.replaceAll('[插图]', '');
  }

  /// 生成引文候选列表
  ///
  /// 移植自 annotations.lua quote_candidates。
  /// 尝试多个字段:markText → abstract → review.abstract。
  /// 每个候选归一化后去重,长度 2~800 字符。
  static List<String> _quoteCandidates(
    UnderlineInput underline,
    Map<String, List<ReviewInput>> reviewMap,
  ) {
    final values = <String>[];
    final seen = <String>{};

    void add(String? value) {
      if (value == null) return;
      final cleaned = _cleanQuote(value);
      final normalized = _normalizeText(cleaned);
      if (normalized.length >= 2 &&
          normalized.length <= 800 &&
          normalized.isNotEmpty &&
          !seen.contains(normalized)) {
        seen.add(normalized);
        values.add(normalized);
      }
    }

    // 尝试划线的 markText
    add(underline.markText);

    // 尝试同 range 想法的 abstract
    final reviews = reviewMap[underline.range];
    if (reviews != null) {
      for (final review in reviews) {
        add(review.abstract);
      }
    }

    return values;
  }

  /// 在文本索引中查找引文,返回最佳匹配的原始位置
  ///
  /// 移植自 annotations.lua locate_quote。
  /// 在紧凑文本中查找所有出现位置,选择与预期位置(expected)最接近的。
  /// 返回 (起始原始位置, 结束原始位置) 或 null。
  static ({int a, int b})? _locateQuote(
    _TextIndex index,
    String needle,
    int expected,
  ) {
    if (index.text.isEmpty || needle.isEmpty) return null;

    int? bestA, bestB, bestScore;
    var from = 0;

    while (true) {
      final first = index.text.indexOf(needle, from);
      if (first < 0) break;

      final last = first + needle.length - 1;
      final a = index.starts[first];
      final b = index.ends[last];

      if (a != null && b != null && b > a) {
        final compactA = index.ordinals[first] ?? a;
        final score =
            (a - expected).abs() < (compactA - expected).abs()
                ? (a - expected).abs()
                : (compactA - expected).abs();
        if (bestScore == null || score < bestScore) {
          bestA = a;
          bestB = b;
          bestScore = score;
        }
      }

      from = first + 1;
    }

    if (bestA != null && bestB != null) {
      return (a: bestA, b: bestB);
    }
    return null;
  }

  /// 解析 range 字符串 "a-b" 为数字
  ///
  /// 移植自 annotations.lua parse_range。
  static ({int a, int b})? _parseRange(String value) {
    final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(value);
    if (match == null) return null;
    final a = int.tryParse(match.group(1)!);
    final b = int.tryParse(match.group(2)!);
    if (a == null || b == null || b <= a) return null;
    return (a: a, b: b);
  }

  // === 区间计算(移植自 annotations.lua intervals) ===

  /// 计算注入区间(marks),含引文定位、数字兜底、重叠合并
  ///
  /// 移植自 annotations.lua intervals。
  /// 返回 (排序去重后的 marks, 统计信息)。
  static ({List<_Mark> marks, _AlignmentStats stats}) _computeMarks(
    List<UnderlineInput> underlines,
    Map<String, List<ReviewInput>> reviewMap,
    _TextIndex index,
    bool noNumericFallback,
  ) {
    final out = <_Mark>[];
    final stats = _AlignmentStats();

    for (final row in underlines) {
      final rangeStr = row.range;
      final parsed = _parseRange(rangeStr);

      if (parsed == null) {
        stats.dropped++;
        stats.unlocated++;
        continue;
      }

      int? a, b;

      // 尝试引文候选
      for (final quote in _quoteCandidates(row, reviewMap)) {
        final result = _locateQuote(index, quote, parsed.a);
        if (result != null) {
          a = result.a;
          b = result.b;
          break;
        }
      }

      if (a != null) {
        stats.quoteAligned++;
      } else if (!noNumericFallback) {
        // 数字 range 兜底:通过 UTF-16 边界映射
        final mappedA = index.utf16Bounds[parsed.a];
        final mappedB = index.utf16Bounds[parsed.b];
        if (mappedA != null && mappedB != null && mappedB > mappedA) {
          a = mappedA;
          b = mappedB;
          stats.numeric++;
        }
      }

      if (a != null && b != null && b > a) {
        final hasThought =
            (reviewMap[rangeStr] ?? []).isNotEmpty;
        out.add(_Mark(a: a, b: b, key: rangeStr, thought: hasThought));
      } else {
        stats.dropped++;
        stats.unlocated++;
      }
    }

    // 按位置排序(a 相同则 b 小的在前)
    out.sort((x, y) {
      if (x.a == y.a) return x.b.compareTo(y.b);
      return x.a.compareTo(y.a);
    });

    // 重叠合并:与前一条交叠的划线被合并到存活锚点
    final clean = <_Mark>[];
    var cursor = -1;

    for (final it in out) {
      if (it.a >= cursor) {
        clean.add(it);
        cursor = it.b;
      } else {
        // 与前一条交叠:合并
        stats.dropped++;
        stats.overlapped++;
        stats.overlappedKeys.add(it.key);

        final survivor = clean.isNotEmpty ? clean.last : null;
        if (it.thought && survivor != null) {
          survivor.thought = true;
          survivor.mergedFromKeys.add(it.key);
          stats.merged.add((from: it.key, into: survivor.key));
        }
      }
    }

    return (marks: clean, stats: stats);
  }

  // === 渲染(移植自 annotations.lua render_text_token + inject) ===

  /// 在 HTML 中注入想法锚点
  ///
  /// 移植自 annotations.lua inject。
  /// 1. 分词 HTML
  /// 2. 构建文本索引
  /// 3. 计算注入区间
  /// 4. 渲染:在引文位置包裹 span
  static (String, _AlignmentStats) _inject(
    String html,
    _InjectionData data,
  ) {
    final tokens = _tokenize(html);
    final index = _buildTextIndex(tokens);
    final (:marks, :stats) = _computeMarks(
      data.underlines,
      data.reviewMap,
      index,
      data.noNumericFallback,
    );

    if (marks.isEmpty) return (html, stats);

    // 预计算每个 mark 的想法弹窗文本
    final thoughtTexts = <String, String>{};
    for (final mark in marks) {
      if (!mark.thought) continue;

      // 收集自身 + 合并的 reviews
      final allReviews = <ReviewInput>[
        ...?data.reviewMap[mark.key],
        ...mark.mergedFromKeys.expand((k) => data.reviewMap[k] ?? []),
      ];

      final text = _formatThoughts(allReviews);
      if (text.isNotEmpty) {
        thoughtTexts[mark.key] = text;
      } else {
        // 想法内容全空,降级为普通划线
        mark.thought = false;
      }
    }

    // 过滤:只保留有想法的 mark,无想法的划线不标记
    final thoughtMarks = marks
        .where((m) => m.thought && thoughtTexts.containsKey(m.key))
        .toList();
    if (thoughtMarks.isEmpty) return (html, stats);

    // 渲染
    final out = <String>[];
    for (final token in tokens) {
      if (token.isTag) {
        out.add(token.raw);
      } else {
        out.add(_renderTextToken(token, thoughtMarks, thoughtTexts));
      }
    }

    return (out.join(), stats);
  }

  /// 渲染文本 token:在 mark 位置包裹 span
  ///
  /// 移植自 annotations.lua render_text_token。
  /// 只有有想法的 mark 才会包裹 <span class="reader"> + 弹窗内容 + </span>。
  /// 无想法的划线不标记,输出纯文本。
  static String _renderTextToken(
    _Token token,
    List<_Mark> marks,
    Map<String, String> thoughtTexts,
  ) {
    if (token.skip || token.units == null || token.units!.isEmpty) {
      return token.raw;
    }

    final out = <String>[];
    var pos = token.start;
    _Mark? active;

    void closeActive() {
      if (active == null) return;
      out.add('</span>');
      active = null;
    }

    for (final unit in token.units!) {
      // 查找当前位置是否在某个 mark 内
      _Mark? mark;
      for (final it in marks) {
        if (pos >= it.a && pos < it.b) {
          mark = it;
          break;
        }
      }

      if (mark != active) {
        closeActive();
        active = mark;

        if (active != null) {
          final a = active!;
          // 有想法:note.png 图标 + 弹窗内容
          final thoughtText = thoughtTexts[a.key]!;
          // data-wr-footernote 属性:用 &#10; 换行(兼容阅微转多看工具)
          final attrText = thoughtText
              .replaceAll('<br/><br/>', '&#10;&#10;')
              .replaceAll('<br/>', '&#10;');

          out.add(
            '<span class="reader" '
            'data-wr-range="${a.key}" '
            'data-wr-footernote="$attrText">'
            '<span class="reader-note-content">$thoughtText</span>',
          );
        }
      }

      out.add(unit);
      pos++;

      if (active != null && pos >= active!.b) {
        closeActive();
      }
    }

    closeActive();
    return out.join();
  }

  // === 想法格式化(移植自 thoughts.lua popup_text) ===

  /// 格式化想法列表为弹窗 HTML 文本
  ///
  /// 移植自 thoughts.lua popup_text。
  /// 每条想法格式: ▸ 作者 · 赞 N<br/>　　内容(内容前缩进 2em)
  /// 条目间用 <br/><br/> 分隔。
  /// 内容中的 HTML 特殊字符会先转义。
  static String _formatThoughts(List<ReviewInput> reviews) {
    final parts = <String>[];
    final seen = <String>{};

    for (final r in reviews) {
      final content = _cleanThoughtText(r.content);
      if (content.isEmpty) continue;

      final author = _cleanThoughtText(r.author);
      final authorDisplay = author.isEmpty ? '微信读书用户' : author;

      // 去重(按作者+内容)
      final key = '$authorDisplay\0$content';
      if (seen.contains(key)) continue;
      seen.add(key);

      // 格式化元信息: ▸ 作者
      final meta = '▸ $authorDisplay';

      // HTML 转义
      final escapedMeta = _escapeHtml(meta);
      final escapedContent = _escapeHtml(content);

      // 评论内容前缩进 2em:用两个全角空格(U+3000)实现,
      // 每个 U+3000 在 CJK 字体中宽度为 1em,兼容所有阅读器(无需 CSS)
      parts.add('$escapedMeta<br/>\u3000\u3000$escapedContent');
    }

    return parts.join('<br/><br/>');
  }

  /// 清理想法文本:替换控制字符、折叠空白、trim
  ///
  /// 移植自 thoughts.lua clean。
  static String _cleanThoughtText(String value) {
    var text = value.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  /// HTML 特殊字符转义
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // === 样式注入(外部 CSS 文件引用) ===

  /// 在 HTML 的 <head> 中注入 <link> 标签引用外部 CSS 文件
  ///
  /// [cssHref] CSS 文件相对于 HTML 文件的路径(如 ../weread-thoughts.css)
  /// 如果已有样式标记则跳过,否则插入到 </head> 前。
  static String _ensureStyle(String html, String cssHref) {
    if (html.contains(cssMarker)) return html;

    final linkTag =
        '<link rel="stylesheet" type="text/css" href="$cssHref" />';

    // 尝试插入到 </head> 前
    final headEnd = RegExp(r'</[Hh][Ee][Aa][Dd]\s*>').firstMatch(html);
    if (headEnd != null) {
      return html.substring(0, headEnd.start) +
          linkTag +
          html.substring(headEnd.start);
    }

    // 尝试插入到 <body> 后
    final bodyStart = RegExp(r'<[Bb][Oo][Dd][Yy][^>]*>').firstMatch(html);
    if (bodyStart != null) {
      return html.substring(0, bodyStart.end) +
          linkTag +
          html.substring(bodyStart.end);
    }

    // 尝试插入到 <html> 后
    final htmlStart = RegExp(r'<[Hh][Tt][Mm][Ll][^>]*>').firstMatch(html);
    if (htmlStart != null) {
      return html.substring(0, htmlStart.end) +
          linkTag +
          html.substring(htmlStart.end);
    }

    // 尝试插入到 XML 声明后
    final declEnd = RegExp(r'^\s*<\?[^>]*\?>').firstMatch(html);
    if (declEnd != null) {
      return html.substring(0, declEnd.end) +
          linkTag +
          html.substring(declEnd.end);
    }

    // 兜底:插在最前面
    return linkTag + html;
  }

  // === EPUB 结构解析 ===

  /// 解析 EPUB 结构,获取 spine 文件路径列表
  static _EpubInfo _parseEpubStructure(Archive archive) {
    // 找到 container.xml 获取 OPF 路径
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      return _EpubInfo(spine: []);
    }
    final containerXml =
        utf8.decode(containerFile.content as List<int>, allowMalformed: true);
    final opfPathMatch = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (opfPathMatch == null) {
      return _EpubInfo(spine: []);
    }
    final opfPath = opfPathMatch.group(1)!;
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // 读取 OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      return _EpubInfo(spine: []);
    }
    final opfContent =
        utf8.decode(opfFile.content as List<int>, allowMalformed: true);

    // 解析 manifest:收集 HTML 文件的 id → href
    final manifestItems = <String, String>{};
    final itemPattern = RegExp(
      r'<item\s[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*/?>',
      caseSensitive: false,
    );
    for (final match in itemPattern.allMatches(opfContent)) {
      final id = match.group(1)!;
      final href = match.group(2)!;
      final lower = href.toLowerCase();
      if (lower.endsWith('.html') ||
          lower.endsWith('.xhtml') ||
          lower.endsWith('.htm')) {
        manifestItems[id] = href;
      }
    }

    // 解析 spine 顺序
    final spineOrder = <String>[];
    final itemrefPattern = RegExp(
      r'<itemref\s[^>]*idref="([^"]+)"',
      caseSensitive: false,
    );
    for (final match in itemrefPattern.allMatches(opfContent)) {
      spineOrder.add(match.group(1)!);
    }

    // 按 spine 顺序构建文件路径列表
    final spine = <String>[];
    for (final id in spineOrder) {
      final href = manifestItems[id];
      if (href == null) continue;
      final fullPath = opfDir + href;
      if (archive.findFile(fullPath) != null) {
        spine.add(fullPath);
      }
    }

    // 若 spine 为空,降级为所有 HTML 文件
    if (spine.isEmpty) {
      for (final f in archive.files) {
        if (f.name.isEmpty) continue;
        final lower = f.name.toLowerCase();
        if (lower.endsWith('.html') ||
            lower.endsWith('.xhtml') ||
            lower.endsWith('.htm')) {
          spine.add(f.name);
        }
      }
    }

    return _EpubInfo(spine: spine, opfPath: opfPath, opfDir: opfDir);
  }
}

// === 数据类 ===

/// HTML token(文本或标签)
class _Token {
  final bool isTag;
  final String raw;

  /// text token 的分词单元
  final List<String>? units;

  /// text token 的可见起始位置
  final int start;

  /// 是否跳过(script/style/reader-note-content 内)
  final bool skip;

  _Token.tag(this.raw)
      : isTag = true,
        units = null,
        start = 0,
        skip = false;

  _Token.text({
    required String raw,
    required List<String> units,
    required int start,
    required bool skip,
  })  : isTag = false,
        raw = raw,
        units = units,
        start = start,
        skip = skip;
}

/// 文本索引
class _TextIndex {
  /// 紧凑文本(解码后去可忽略字符)
  final String text;

  /// 紧凑文本字节位置 → 原始可见位置
  final Map<int, int> starts;

  /// 紧凑文本字节位置 → 原始可见位置 + 1
  final Map<int, int> ends;

  /// 紧凑文本字节位置 → 紧凑序号
  final Map<int, int> ordinals;

  /// 紧凑序号 → 原始可见位置
  final Map<int, int> compactBounds;

  /// 紧凑文本单元数
  final int compactCount;

  /// UTF-16 位置 → 原始可见位置(用于数字 range 兜底)
  final Map<int, int> utf16Bounds;

  /// UTF-16 字符总数
  final int utf16Count;

  _TextIndex({
    required this.text,
    required this.starts,
    required this.ends,
    required this.ordinals,
    required this.compactBounds,
    required this.compactCount,
    required this.utf16Bounds,
    required this.utf16Count,
  });
}

/// 注入区间(mark)
class _Mark {
  /// 起始可见位置
  int a;

  /// 结束可见位置(不含)
  int b;

  /// range 键
  final String key;

  /// 是否有想法
  bool thought;

  /// 被重叠合并进此 mark 的 range 键列表
  final List<String> mergedFromKeys;

  _Mark({
    required this.a,
    required this.b,
    required this.key,
    required this.thought,
  }) : mergedFromKeys = [];
}

/// 对齐统计信息
class _AlignmentStats {
  int quoteAligned = 0;
  int numeric = 0;
  int dropped = 0;
  int overlapped = 0;
  int unlocated = 0;
  final List<({String from, String into})> merged = [];
  final List<String> overlappedKeys = [];
}

/// 注入数据(合并后的章节数据)
class _InjectionData {
  final List<UnderlineInput> underlines;
  final Map<String, List<ReviewInput>> reviewMap;
  final bool noNumericFallback;

  _InjectionData({
    required this.underlines,
    required this.reviewMap,
    required this.noNumericFallback,
  });
}

/// EPUB 结构信息
class _EpubInfo {
  final List<String> spine;

  /// OPF 文件在 EPUB 内的完整路径(如 OEBPS/content.opf)
  final String opfPath;

  /// OPF 所在目录(如 OEBPS/,根目录则为空字符串)
  final String opfDir;

  _EpubInfo({
    required this.spine,
    this.opfPath = '',
    this.opfDir = '',
  });
}