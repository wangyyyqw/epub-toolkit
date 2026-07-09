import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';
import 'list_split_targets.dart';

/// 拆分 EPUB 操作
///
/// 按 TOC 章节拆分点将一个 EPUB 拆分为多个 EPUB。
/// 保留原 EPUB 版本（EPUB2 输出带 NCX，EPUB3 输出带 nav）。
/// 每段仅包含其引用的内容文档和资源文件。
class SplitOperation {
  SplitOperation._();

  /// 执行拆分 EPUB
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputDir] 输出目录
  /// [splitPoints] 拆分点索引列表（指向 list_split_targets 返回的列表）
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputDir,
    required List<int> splitPoints,
  }) async {
    final log = StringBuffer();
    log.writeln('开始拆分 EPUB...');

    final archive = await EpubImageHelper.readArchive(epubPath);
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) {
      log.writeln('错误: 找不到 OPF 文件');
      return log.toString();
    }

    final opfFile = archive.findFile(opfPath)!;
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDir = EpubImageHelper.opfDir(opfPath);

    // 1. 解析 OPF
    final (version, manifest, spine) = _parseOpf(opfContent);
    final isEpub3 = version.startsWith('3');
    log.writeln('EPUB 版本: $version');

    // 2. 获取 TOC 目标
    final targets = await ListSplitTargetsOperation.execute(epubPath: epubPath);
    if (targets.isEmpty) {
      log.writeln('错误: 无法解析 TOC，无拆分目标');
      return log.toString();
    }
    log.writeln('TOC 目标: ${targets.length} 个');

    // 3. 校验拆分点
    final sortedPoints = (Set<int>.from(
      splitPoints,
    ).toList()..sort()).where((pt) => pt >= 0 && pt < targets.length).toList();

    if (sortedPoints.isEmpty) {
      log.writeln('错误: 无有效拆分点');
      return log.toString();
    }
    log.writeln('拆分点: $sortedPoints');

    // 4. 构建 spine bookpath 列表
    final spineBookpaths = <String>[];
    final spineIdMap = <String, _SpineEntry>{};

    for (final spineItem in spine) {
      final item = manifest[spineItem.id];
      if (item == null) continue;
      final lowerHref = item.href.toLowerCase();
      if (!lowerHref.endsWith('.xhtml') &&
          !lowerHref.endsWith('.html') &&
          !lowerHref.endsWith('.htm')) {
        continue;
      }
      final bookpath = _normalizePath('$opfDir${item.href}');
      spineBookpaths.add(bookpath);
      spineIdMap[bookpath] = _SpineEntry(
        id: spineItem.id,
        href: item.href,
        mediaType: item.mediaType,
        properties: item.properties,
        linear: spineItem.linear,
      );
    }

    // 5. TOC target → spine 索引
    final targetSpineIndices = <int>[];
    for (final target in targets) {
      final bookpath = _normalizePath('$opfDir${target.href}');
      final idx = spineBookpaths.indexOf(bookpath);
      targetSpineIndices.add(idx);
    }

    // 6. 根据 spine 索引构建拆分范围
    final segmentRanges = <(int, int)>[]; // (start_spine, end_spine)
    var startSpine = 0;

    for (final pt in sortedPoints) {
      final spineIdx = targetSpineIndices[pt];
      if (spineIdx < 0) {
        log.writeln('  警告: 拆分点 $pt 对应的 href 不在 spine 中，跳过');
        continue;
      }
      if (spineIdx > startSpine) {
        segmentRanges.add((startSpine, spineIdx));
      }
      startSpine = spineIdx;
    }

    // 最后一段
    if (startSpine < spineBookpaths.length) {
      segmentRanges.add((startSpine, spineBookpaths.length));
    }

    if (segmentRanges.isEmpty) {
      log.writeln('错误: 无有效拆分段');
      return log.toString();
    }

    log.writeln('拆分段数: ${segmentRanges.length}');

    // 7. 逐段生成 EPUB
    final assignedDocs = <String>{};
    final baseName = p.basenameWithoutExtension(epubPath);
    final now = DateTime.now().toUtc();
    final modified = '${now.toIso8601String().split('.')[0]}Z';

    // 确保输出目录存在
    Directory(outputDir).createSync(recursive: true);

    for (var segIdx = 0; segIdx < segmentRanges.length; segIdx++) {
      final (startSp, endSp) = segmentRanges[segIdx];
      final segFiles = <String>[];
      final segManifest = <_ManifestEntry>[];
      final segSpine = <_SpineEntry>[];
      final usedIds = <String>{};

      // 收集本段内容文档
      for (var i = startSp; i < endSp; i++) {
        final bookpath = spineBookpaths[i];
        if (assignedDocs.contains(bookpath)) continue;
        assignedDocs.add(bookpath);
        segFiles.add(bookpath);

        final entry = spineIdMap[bookpath]!;
        final relHref = _relPath(bookpath, opfDir);

        var id = entry.id;
        if (usedIds.contains(id)) {
          id = '${id}_$i';
        }
        usedIds.add(id);

        segManifest.add(
          _ManifestEntry(
            id: id,
            href: relHref,
            mediaType: entry.mediaType,
            properties: entry.properties.where((p) => p != 'nav').toList(),
          ),
        );
        segSpine.add(
          _SpineEntry(
            id: id,
            href: entry.href,
            mediaType: entry.mediaType,
            properties: entry.properties,
            linear: entry.linear,
          ),
        );
      }

      if (segFiles.isEmpty) continue;

      // 收集引用资源
      final referencedResources = _collectReferencedResources(
        archive,
        segFiles,
        manifest,
        opfDir,
      );

      for (final resPath in referencedResources) {
        if (segFiles.contains(resPath)) continue;

        // 查找 manifest 中对应的条目
        String? resId;
        String resMediaType = 'application/octet-stream';
        List<String> resProps = [];
        for (final entry in manifest.entries) {
          final bp = _normalizePath('$opfDir${entry.value.href}');
          if (bp == resPath) {
            resId = entry.key;
            resMediaType = entry.value.mediaType;
            resProps = entry.value.properties;
            break;
          }
        }

        var id = resId ?? p.basenameWithoutExtension(resPath);
        if (usedIds.contains(id)) {
          id = '${id}_${resPath.hashCode.toRadixString(16).substring(0, 4)}';
        }
        usedIds.add(id);

        segManifest.add(
          _ManifestEntry(
            id: id,
            href: _relPath(resPath, opfDir),
            mediaType: resMediaType,
            properties: resProps.where((p) => p != 'nav').toList(),
          ),
        );
        segFiles.add(resPath);
      }

      // 生成本段 TOC
      final segTocTargets = <SplitTarget>[];
      final segFileSet = Set<String>.from(segFiles);
      for (var i = 0; i < targets.length; i++) {
        final target = targets[i];
        final bookpath = _normalizePath('$opfDir${target.href}');
        if (segFileSet.contains(bookpath)) {
          segTocTargets.add(target);
        }
      }

      // 生成 TOC 文件
      String tocContent;
      String tocHref;
      String tocMediaType;
      String tocId;
      List<String> tocProps;

      if (isEpub3) {
        tocId = 'split-nav';
        tocHref = 'nav_split.xhtml';
        tocMediaType = 'application/xhtml+xml';
        tocProps = ['nav'];
        tocContent = _generateSplitNav(segTocTargets, opfDir);
      } else {
        tocId = 'split-ncx';
        tocHref = 'toc_split.ncx';
        tocMediaType = 'application/x-dtbncx+xml';
        tocProps = [];
        tocContent = _generateSplitNcx(segTocTargets, opfDir);
      }

      segManifest.add(
        _ManifestEntry(
          id: tocId,
          href: tocHref,
          mediaType: tocMediaType,
          properties: tocProps,
        ),
      );

      // 生成 OPF
      final segOpfContent = _generateSplitOpf(
        version,
        manifest,
        segManifest,
        segSpine,
        tocId,
        modified,
        isEpub3,
        segmentIndex: segIdx,
        segmentCount: segmentRanges.length,
        originalTitle: _extractTitle(opfContent),
      );

      // 写出 EPUB
      final segArchive = Archive();
      segArchive.addFile(
        ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
          ..compress = false,
      );

      final containerXml =
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
          '  <rootfiles>\n'
          '    <rootfile full-path="$opfPath" '
          'media-type="application/oebps-package+xml"/>\n'
          '  </rootfiles>\n'
          '</container>';
      segArchive.addFile(
        ArchiveFile(
          'META-INF/container.xml',
          containerXml.length,
          utf8.encode(containerXml),
        ),
      );

      segArchive.addFile(
        ArchiveFile(opfPath, segOpfContent.length, utf8.encode(segOpfContent)),
      );

      // TOC 文件
      final tocPath = _normalizePath('$opfDir$tocHref');
      segArchive.addFile(
        ArchiveFile(tocPath, tocContent.length, utf8.encode(tocContent)),
      );

      // 内容文件
      for (final fp in segFiles) {
        final f = archive.findFile(fp);
        if (f != null) {
          final data = Uint8List.fromList(f.content as List<int>);
          segArchive.addFile(ArchiveFile(fp, data.length, data));
        }
      }

      // 保存
      final segFileName =
          '${baseName}_${(segIdx + 1).toString().padLeft(2, '0')}.epub';
      final segOutputPath = p.join(outputDir, segFileName);
      await EpubPacker.pack(archive: segArchive, outputPath: segOutputPath);

      log.writeln('  段 ${segIdx + 1}: ${segFiles.length} 文件 → $segFileName');
    }

    log.writeln('\n拆分完成: ${segmentRanges.length} 个 EPUB');
    log.writeln('输出目录: $outputDir');

    return log.toString();
  }

  /// 收集引用的资源文件
  static Set<String> _collectReferencedResources(
    Archive archive,
    List<String> contentFiles,
    Map<String, _ManifestEntry> manifest,
    String opfDir,
  ) {
    final referenced = <String>{};
    final allBookpaths = <String>{};
    for (final item in manifest.values) {
      allBookpaths.add(_normalizePath('$opfDir${item.href}'));
    }

    // 扫描内容文档
    for (final bookpath in contentFiles) {
      final file = archive.findFile(bookpath);
      if (file == null) continue;

      final content = utf8.decode(file.content as List<int>);
      final refs = _extractReferences(content, opfDir, bookpath, allBookpaths);
      referenced.addAll(refs);
    }

    // 扫描引用的 CSS
    final cssToScan = referenced
        .where((p) => p.toLowerCase().endsWith('.css'))
        .toList();
    for (final cssPath in cssToScan) {
      final file = archive.findFile(cssPath);
      if (file == null) continue;

      final content = utf8.decode(file.content as List<int>);
      final cssDir = _getDir(cssPath);
      final refs = _extractCssReferences(content, cssDir, allBookpaths);
      referenced.addAll(refs);
    }

    // 排除内容文档本身
    referenced.removeAll(contentFiles);

    return referenced;
  }

  /// 从 HTML 内容提取引用
  static Set<String> _extractReferences(
    String content,
    String opfDir,
    String currentPath,
    Set<String> allBookpaths,
  ) {
    final refs = <String>{};
    final currentDir = _getDir(currentPath);

    for (final match in RegExp(
      r"""(?:href|src)\s*=\s*["']([^"']*)["']""",
    ).allMatches(content)) {
      var href = match.group(1)!;

      if (href.startsWith('http://') ||
          href.startsWith('https://') ||
          href.startsWith('data:') ||
          href.startsWith('#')) {
        continue;
      }

      final fragIdx = href.indexOf('#');
      if (fragIdx >= 0) {
        href = href.substring(0, fragIdx);
      }

      if (href.isEmpty) continue;

      final bookpath = _normalizePath('$currentDir$href');
      if (allBookpaths.contains(bookpath)) {
        refs.add(bookpath);
      }
    }

    return refs;
  }

  /// 从 CSS 内容提取引用
  static Set<String> _extractCssReferences(
    String content,
    String cssDir,
    Set<String> allBookpaths,
  ) {
    final refs = <String>{};

    for (final match in RegExp(
      r"""url\(["']?([^)]*?)["']?\)""",
    ).allMatches(content)) {
      var url = match.group(1)!;

      if (url.startsWith('http://') ||
          url.startsWith('https://') ||
          url.startsWith('data:')) {
        continue;
      }

      final bookpath = _normalizePath('$cssDir$url');
      if (allBookpaths.contains(bookpath)) {
        refs.add(bookpath);
      }
    }

    return refs;
  }

  /// 生成拆分 nav（EPUB3）
  static String _generateSplitNav(List<SplitTarget> targets, String opfDir) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops">',
    );
    buf.writeln('<head>');
    buf.writeln('  <meta charset="utf-8"/>');
    buf.writeln('  <title>目录</title>');
    buf.writeln('</head>');
    buf.writeln('<body>');
    buf.writeln('  <nav epub:type="toc" id="toc">');
    buf.writeln('    <h1>目录</h1>');

    if (targets.isNotEmpty) {
      buf.writeln('    <ol>');
      _writeNavItems(buf, targets, 1);
      buf.writeln('    </ol>');
    }

    buf.writeln('  </nav>');
    buf.writeln('</body>');
    buf.writeln('</html>');
    return buf.toString();
  }

  /// 递归写入 nav 列表项
  static void _writeNavItems(
    StringBuffer buf,
    List<SplitTarget> targets,
    int level,
  ) {
    var i = 0;
    while (i < targets.length) {
      final t = targets[i];
      if (t.level != level) {
        if (t.level > level) {
          buf.writeln('      <ol>');
          _writeNavItems(buf, targets.sublist(i), level + 1);
          buf.writeln('      </ol>');
        }
        break;
      }

      final indent = '      ' * level;
      if (t.href.isNotEmpty) {
        buf.writeln(
          '$indent<li><a href="${_escapeXml(t.href)}">${_escapeXml(t.title)}</a></li>',
        );
      } else {
        buf.writeln('$indent<li><span>${_escapeXml(t.title)}</span></li>');
      }
      i++;
    }
  }

  /// 生成拆分 NCX（EPUB2）
  static String _generateSplitNcx(List<SplitTarget> targets, String opfDir) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
    );
    buf.writeln('  <head>');
    buf.writeln('    <meta name="dtb:uid" content="split-epub"/>');
    buf.writeln('    <meta name="dtb:depth" content="1"/>');
    buf.writeln('  </head>');
    buf.writeln('  <docTitle><text>目录</text></docTitle>');
    buf.writeln('  <navMap>');

    var playOrder = 1;
    for (final t in targets) {
      buf.writeln('    <navPoint id="np$playOrder" playOrder="$playOrder">');
      buf.writeln(
        '      <navLabel><text>${_escapeXml(t.title)}</text></navLabel>',
      );
      buf.writeln('      <content src="${_escapeXml(t.href)}"/>');
      buf.writeln('    </navPoint>');
      playOrder++;
    }

    buf.writeln('  </navMap>');
    buf.writeln('</ncx>');
    return buf.toString();
  }

  /// 生成拆分 OPF
  static String _generateSplitOpf(
    String version,
    Map<String, _ManifestEntry> originalManifest,
    List<_ManifestEntry> segManifest,
    List<_SpineEntry> segSpine,
    String tocId,
    String modified,
    bool isEpub3, {
    int segmentIndex = 0,
    int segmentCount = 1,
    String originalTitle = '',
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    // 给每个分卷生成唯一的 unique-identifier id（避免 Kindle 等阅读器
    // 把所有分卷当作同一本书处理：相同的 unique-identifier + 相同的 dc:identifier
    // 会让阅读器自动合并目录或拒绝重复推送）
    final uniqueId = segmentCount > 1
        ? 'split-id-${segmentIndex + 1}'
        : 'split-id';
    final uniqueIdentifierValue = segmentCount > 1
        ? 'split-epub-${segmentIndex + 1}-of-$segmentCount-${DateTime.now().millisecondsSinceEpoch}'
        : 'split-epub-${DateTime.now().millisecondsSinceEpoch}';
    final titleValue = originalTitle.isNotEmpty
        ? '$originalTitle (${segmentIndex + 1}/$segmentCount)'
        : '拆分 EPUB ${segmentIndex + 1}/$segmentCount';
    buf.writeln(
      '<package version="$version" unique-identifier="$uniqueId" '
      'xmlns="http://www.idpf.org/2007/opf">',
    );

    buf.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">');
    buf.writeln(
      '    <dc:identifier id="$uniqueId">$uniqueIdentifierValue</dc:identifier>',
    );
    buf.writeln('    <dc:title>${_escapeXml(titleValue)}</dc:title>');
    buf.writeln('    <dc:language>zh</dc:language>');
    if (isEpub3) {
      buf.writeln('    <meta property="dcterms:modified">$modified</meta>');
    }
    buf.writeln('  </metadata>');

    buf.writeln('  <manifest>');
    for (final item in segManifest) {
      final escapedHref = item.href.replaceAll('&', '&amp;');
      var line =
          '    <item id="${item.id}" href="$escapedHref" '
          'media-type="${item.mediaType}"';
      if (item.properties.isNotEmpty) {
        line += ' properties="${item.properties.join(' ')}"';
      }
      line += '/>';
      buf.writeln(line);
    }
    buf.writeln('  </manifest>');

    final tocAttr = isEpub3 ? '' : ' toc="$tocId"';
    buf.writeln('  <spine$tocAttr>');
    for (final item in segSpine) {
      var line = '    <itemref idref="${item.id}"';
      if (item.linear != null) {
        line += ' linear="${item.linear}"';
      }
      line += '/>';
      buf.writeln(line);
    }
    buf.writeln('  </spine>');

    buf.writeln('</package>');
    return buf.toString();
  }

  /// 解析 OPF
  static (String, Map<String, _ManifestEntry>, List<_SpineEntry>) _parseOpf(
    String opfContent,
  ) {
    var version = '2.0';
    final manifest = <String, _ManifestEntry>{};
    final spine = <_SpineEntry>[];

    try {
      final document = xml.XmlDocument.parse(opfContent);
      final package = document.findElements('package', namespace: '*').first;
      version = package.getAttribute('version') ?? '2.0';

      for (final item in document.findAllElements('item', namespace: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        final propsStr = item.getAttribute('properties') ?? '';
        final props = propsStr.isEmpty
            ? <String>[]
            : propsStr.split(' ').where((s) => s.isNotEmpty).toList();
        if (id.isNotEmpty) {
          manifest[id] = _ManifestEntry(
            id: id,
            href: href,
            mediaType: mediaType,
            properties: props,
          );
        }
      }

      for (final item in document.findAllElements('itemref', namespace: '*')) {
        final idref = item.getAttribute('idref') ?? '';
        final linear = item.getAttribute('linear');
        if (idref.isNotEmpty) {
          spine.add(
            _SpineEntry(
              id: idref,
              href: '',
              mediaType: '',
              properties: [],
              linear: linear,
            ),
          );
        }
      }
    } catch (_) {}

    return (version, manifest, spine);
  }

  /// 提取原书标题（dc:title 或 EPUB2 风格的 <meta name="title">）
  ///
  /// 用于在拆分时给每个分卷生成带原书名 + 分卷序号的标题，
  /// 避免所有分卷都用「拆分 EPUB」这种无意义标题。
  static String _extractTitle(String opfContent) {
    try {
      final document = xml.XmlDocument.parse(opfContent);
      // 优先 dc:title
      for (final m in document.findAllElements('metadata', namespace: '*')) {
        for (final t in m.findElements('title', namespace: '*')) {
          final text = t.innerText.trim();
          if (text.isNotEmpty) return text;
        }
        // 降级：EPUB2 风格的 <meta name="title" content="...">
        for (final meta in m.findElements('meta', namespace: '*')) {
          if (meta.getAttribute('name') == 'title') {
            final content = meta.getAttribute('content');
            if (content != null && content.isNotEmpty) return content;
          }
        }
        break;
      }
    } catch (_) {
      // 解析失败返回空字符串，让 _generateSplitOpf 走默认值
    }
    return '';
  }

  /// 规范化路径
  static String _normalizePath(String path) {
    path = path.replaceAll('\\', '/');
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  /// 计算相对路径
  static String _relPath(String target, String base) {
    final targetParts = _normalizePath(target).split('/');
    final baseParts = _normalizePath(base).split('/').toList();
    if (baseParts.isNotEmpty && baseParts.last.isEmpty) {
      baseParts.removeLast();
    }

    var commonLen = 0;
    while (commonLen < targetParts.length - 1 &&
        commonLen < baseParts.length &&
        targetParts[commonLen] == baseParts[commonLen]) {
      commonLen++;
    }

    final result = <String>[];
    for (var i = commonLen; i < baseParts.length; i++) {
      result.add('..');
    }
    for (var i = commonLen; i < targetParts.length; i++) {
      result.add(targetParts[i]);
    }

    return result.isEmpty ? '' : result.join('/');
  }

  /// 获取文件所在目录
  static String _getDir(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx + 1) : '';
  }

  /// XML 转义
  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// Manifest 条目
class _ManifestEntry {
  final String id;
  final String href;
  final String mediaType;
  final List<String> properties;

  _ManifestEntry({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}

/// Spine 条目
class _SpineEntry {
  final String id;
  final String href;
  final String mediaType;
  final List<String> properties;
  final String? linear;

  _SpineEntry({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
    this.linear,
  });
}
