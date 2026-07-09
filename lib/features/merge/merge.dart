import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';

/// 合并 EPUB 时用户可覆盖的书籍信息。
class MergeOptions {
  const MergeOptions({
    this.title,
    this.author,
    this.language,
    this.publisher,
    this.description,
    this.coverPath,
  });

  final String? title;
  final String? author;
  final String? language;
  final String? publisher;
  final String? description;
  final String? coverPath;

  bool get hasCustomCover => coverPath?.trim().isNotEmpty ?? false;
}

/// 合并 EPUB 操作
///
/// 将多个 EPUB 合并为一个，处理 manifest 冲突、spine 合并、
/// TOC 重新生成和内部引用更新。合并输出为 EPUB3 格式（含 nav）。
class MergeOperation {
  MergeOperation._();

  /// 执行合并 EPUB
  ///
  /// [inputPaths] 输入 EPUB 路径列表（至少 2 个）
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required List<String> inputPaths,
    required String outputPath,
    MergeOptions options = const MergeOptions(),
  }) async {
    final log = StringBuffer();
    log.writeln('开始合并 EPUB...');

    if (inputPaths.length < 2) {
      log.writeln('错误: 合并至少需要 2 个 EPUB 文件');
      return log.toString();
    }

    log.writeln('输入文件: ${inputPaths.length} 个');

    // 1. 解析所有 EPUB
    final epubDataList = <_EpubData>[];
    for (var i = 0; i < inputPaths.length; i++) {
      final path = inputPaths[i];
      log.writeln('  解析: ${p.basename(path)}');

      try {
        final archive = await EpubImageHelper.readArchive(path);
        final opfPath = EpubImageHelper.findOpfPath(archive);
        if (opfPath == null) {
          log.writeln('    警告: 找不到 OPF 文件，跳过');
          continue;
        }

        final opfFile = archive.findFile(opfPath)!;
        final opfContent = utf8.decode(
          opfFile.content as List<int>,
          allowMalformed: true,
        );
        final opfDir = EpubImageHelper.opfDir(opfPath);

        final parsed = _parseOpf(opfContent, opfDir);
        final tocEntries = _parseToc(archive, parsed, opfDir);

        epubDataList.add(
          _EpubData(
            archive: archive,
            opfPath: opfPath,
            opfDir: opfDir,
            version: parsed.version,
            manifest: parsed.manifest,
            spine: parsed.spine,
            tocEntries: tocEntries,
            bookName: p.basenameWithoutExtension(path),
            meta: parsed.meta,
          ),
        );
      } catch (e) {
        log.writeln('    错误: 解析失败 - $e');
      }
    }

    if (epubDataList.length < 2) {
      log.writeln('错误: 有效 EPUB 不足 2 个，无法合并');
      return log.toString();
    }

    // 2. 检测路径冲突并生成重命名映射
    final renameMaps = _detectConflicts(epubDataList);
    var conflictCount = 0;
    for (final map in renameMaps) {
      conflictCount += map.length;
    }
    if (conflictCount > 0) {
      log.writeln('检测到 $conflictCount 个路径冲突，已自动重命名');
    }

    // 3. 构建合并内容
    const mergedOpfDir = 'OEBPS/';
    const mergedOpfPath = 'OEBPS/content.opf';
    const mergedNavPath = 'OEBPS/nav.xhtml';

    final allManifestItems = <_ManifestItem>[];
    final allSpineItems = <_SpineItem>[];
    final allContentFiles = <_ContentFile>[];
    final allTocForNav = <_TocEntry>[];
    final usedIds = <String>{};

    // 判定合并版本
    final versions = epubDataList.map((e) => e.version).toSet();
    final mergedVersion = versions.length == 1 ? versions.first : '3.0';

    for (var volIdx = 0; volIdx < epubDataList.length; volIdx++) {
      final data = epubDataList[volIdx];
      final renameMap = renameMaps[volIdx];
      final idRemap = <String, String>{};

      // Manifest 处理
      for (final item in data.manifest) {
        // 跳过 NCX 和 nav
        if (item.mediaType == 'application/x-dtbncx+xml') continue;
        if (item.properties.contains('nav')) continue;

        final bookpath = _normalizePath('${data.opfDir}${item.href}');
        final renamedPath = renameMap[bookpath] ?? bookpath;
        final mergedHref = _relPath(renamedPath, mergedOpfDir);

        // ID 去重
        var newId = item.id;
        if (usedIds.contains(newId)) {
          newId = 'vol${volIdx + 1}_$newId';
          while (usedIds.contains(newId)) {
            newId = '${newId}_${usedIds.length}';
          }
        }
        usedIds.add(newId);
        if (newId != item.id) {
          idRemap[item.id] = newId;
        }

        // 剥离 nav property
        final props = item.properties
            .where((p) => p != 'nav')
            .where((p) => !(options.hasCustomCover && p == 'cover-image'))
            .toList();

        allManifestItems.add(
          _ManifestItem(
            id: newId,
            href: mergedHref,
            mediaType: item.mediaType,
            properties: props,
          ),
        );

        // 读取文件内容
        final fileData = data.archive.findFile(bookpath);
        if (fileData != null) {
          var content = Uint8List.fromList(fileData.content as List<int>);

          // XHTML/HTML: 更新引用
          final lowerPath = bookpath.toLowerCase();
          if (lowerPath.endsWith('.xhtml') ||
              lowerPath.endsWith('.html') ||
              lowerPath.endsWith('.htm')) {
            final text = utf8.decode(content, allowMalformed: true);
            final updated = _updateHtmlReferences(
              text,
              bookpath,
              renamedPath,
              renameMap,
              data.opfDir,
            );
            content = Uint8List.fromList(utf8.encode(updated));
          } else if (lowerPath.endsWith('.css')) {
            final text = utf8.decode(content, allowMalformed: true);
            final updated = _updateCssReferences(text, renameMap, data.opfDir);
            content = Uint8List.fromList(utf8.encode(updated));
          }

          allContentFiles.add(_ContentFile(path: renamedPath, data: content));
        }
      }

      // Spine 处理
      for (final spineItem in data.spine) {
        final newId = idRemap[spineItem.idref] ?? spineItem.idref;
        if (usedIds.contains(newId)) {
          allSpineItems.add(_SpineItem(idref: newId, linear: spineItem.linear));
        }
      }

      // TOC 收集
      for (final toc in data.tocEntries) {
        final bookpath = _normalizePath('${data.opfDir}${toc.href}');
        final renamedPath = renameMap[bookpath] ?? bookpath;
        final mergedHref = _relPath(renamedPath, mergedOpfDir);
        allTocForNav.add(
          _TocEntry(
            title: toc.title,
            href: mergedHref,
            level: toc.level,
            volume: volIdx,
          ),
        );
      }
    }

    // 添加合并 nav 到 manifest
    const navId = 'merged-nav';
    allManifestItems.add(
      _ManifestItem(
        id: navId,
        href: 'nav.xhtml',
        mediaType: 'application/xhtml+xml',
        properties: ['nav'],
      ),
    );
    allSpineItems.add(_SpineItem(idref: navId, linear: 'yes'));

    _ContentFile? customCoverFile;
    if (options.hasCustomCover) {
      final coverPath = options.coverPath!.trim();
      final coverBytes = await File(coverPath).readAsBytes();
      final coverExt = p.extension(coverPath).toLowerCase();
      final coverMediaType = _mediaTypeForCover(coverExt);
      if (coverMediaType == null) {
        throw ArgumentError('封面仅支持 jpg/jpeg/png/webp/gif：$coverPath');
      }
      final coverHref = 'Images/cover$coverExt';
      customCoverFile = _ContentFile(
        path: '$mergedOpfDir$coverHref',
        data: Uint8List.fromList(coverBytes),
      );
      allManifestItems.add(
        _ManifestItem(
          id: 'merged-cover-image',
          href: coverHref,
          mediaType: coverMediaType,
          properties: ['cover-image'],
        ),
      );
    }

    // 4. 生成合并 OPF
    final mergedOpf = _generateMergedOpf(
      mergedVersion,
      epubDataList.first,
      allManifestItems,
      allSpineItems,
      options,
    );

    // 5. 生成合并 nav
    final mergedNav = _generateMergedNav(
      allTocForNav,
      epubDataList.map((e) => e.bookName).toList(),
    );

    // 6. 写出 EPUB
    final outputArchive = Archive();
    // mimetype 必须第一个且不压缩
    outputArchive.addFile(
      ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
        ..compress = false,
    );

    // container.xml
    final containerXml =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/>\n'
        '  </rootfiles>\n'
        '</container>';
    outputArchive.addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerXml.length,
        utf8.encode(containerXml),
      ),
    );

    // OPF
    outputArchive.addFile(
      ArchiveFile(mergedOpfPath, mergedOpf.length, utf8.encode(mergedOpf)),
    );

    // nav
    outputArchive.addFile(
      ArchiveFile(mergedNavPath, mergedNav.length, utf8.encode(mergedNav)),
    );

    // 内容文件（去重）
    final written = <String>{};
    if (customCoverFile != null) {
      outputArchive.addFile(
        ArchiveFile(
          customCoverFile.path,
          customCoverFile.data.length,
          customCoverFile.data,
        ),
      );
      written.add(customCoverFile.path);
      log.writeln('已设置自定义封面: ${p.basename(options.coverPath!)}');
    }
    for (final cf in allContentFiles) {
      if (written.contains(cf.path)) continue;
      written.add(cf.path);
      outputArchive.addFile(ArchiveFile(cf.path, cf.data.length, cf.data));
    }

    // 保存
    await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);

    log.writeln('\n合并完成: ${epubDataList.length} 个 EPUB 合并为 1 个');
    log.writeln(
      'manifest: ${allManifestItems.length} 项, '
      'spine: ${allSpineItems.length} 项, '
      'TOC: ${allTocForNav.length} 条',
    );
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 检测路径冲突并生成重命名映射
  ///
  /// 第 0 本保留原名，第 N 本冲突路径加 vol{N+1}_ 前缀
  static List<Map<String, String>> _detectConflicts(
    List<_EpubData> epubDataList,
  ) {
    // 收集所有书的所有 bookpath
    final allPaths = <String, Set<int>>{}; // path → 书索引集合
    for (var i = 0; i < epubDataList.length; i++) {
      for (final item in epubDataList[i].manifest) {
        final bookpath = _normalizePath(
          '${epubDataList[i].opfDir}${item.href}',
        );
        allPaths.putIfAbsent(bookpath, () => <int>{});
        allPaths[bookpath]!.add(i);
      }
    }

    // 找出冲突路径
    final conflictPaths = allPaths.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();

    // 为每本书生成重命名映射
    final renameMaps = <Map<String, String>>[];
    for (var i = 0; i < epubDataList.length; i++) {
      final map = <String, String>{};
      if (i == 0) {
        renameMaps.add(map);
        continue;
      }

      for (final item in epubDataList[i].manifest) {
        final bookpath = _normalizePath(
          '${epubDataList[i].opfDir}${item.href}',
        );
        if (conflictPaths.contains(bookpath)) {
          final dir = p.dirname(bookpath);
          final basename = p.basename(bookpath);
          final newName = 'vol${i + 1}_$basename';
          map[bookpath] = dir != '.' ? '$dir/$newName' : newName;
        }
      }
      renameMaps.add(map);
    }

    return renameMaps;
  }

  /// 规范化路径（统一分隔符，处理 .. 和 .）
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

    // 移除 base 末尾的空段
    if (baseParts.isNotEmpty && baseParts.last.isEmpty) {
      baseParts.removeLast();
    }

    // 找到共同前缀
    var commonLen = 0;
    while (commonLen < targetParts.length - 1 &&
        commonLen < baseParts.length &&
        targetParts[commonLen] == baseParts[commonLen]) {
      commonLen++;
    }

    final result = <String>[];
    // base 需要回退
    for (var i = commonLen; i < baseParts.length; i++) {
      result.add('..');
    }
    // target 剩余部分
    for (var i = commonLen; i < targetParts.length; i++) {
      result.add(targetParts[i]);
    }

    return result.isEmpty ? '' : result.join('/');
  }

  /// 更新 HTML 中的引用路径
  static String _updateHtmlReferences(
    String content,
    String oldBookpath,
    String newBookpath,
    Map<String, String> renameMap,
    String opfDir,
  ) {
    if (renameMap.isEmpty) return content;

    return content.replaceAllMapped(
      RegExp(r"""((?:href|src)\s*=\s*["'])([^"']*)(["'])"""),
      (m) {
        final prefix = m.group(1)!;
        final href = m.group(2)!;
        final suffix = m.group(3)!;

        // 跳过外部链接和锚点
        if (href.startsWith('http://') ||
            href.startsWith('https://') ||
            href.startsWith('data:') ||
            href.startsWith('#')) {
          return m.group(0)!;
        }

        // 分离 fragment
        var path = href;
        var fragment = '';
        final fragIdx = path.indexOf('#');
        if (fragIdx >= 0) {
          fragment = path.substring(fragIdx);
          path = path.substring(0, fragIdx);
        }

        if (path.isEmpty) return m.group(0)!;

        // 解析为 bookpath
        final bookpath = _normalizePath('$opfDir$path');
        final renamed = renameMap[bookpath];
        if (renamed == null) return m.group(0)!;

        // 计算相对路径
        final newDir = p.dirname(newBookpath);
        final relPath = _relPath(renamed, newDir);

        return '$prefix$relPath$fragment$suffix';
      },
    );
  }

  /// 更新 CSS 中的引用路径
  static String _updateCssReferences(
    String content,
    Map<String, String> renameMap,
    String opfDir,
  ) {
    if (renameMap.isEmpty) return content;

    return content.replaceAllMapped(RegExp(r"""url\((["']?)([^)]*?)\1\)"""), (
      m,
    ) {
      final quote = m.group(1)!;
      final url = m.group(2)!;

      if (url.startsWith('http://') ||
          url.startsWith('https://') ||
          url.startsWith('data:')) {
        return m.group(0)!;
      }

      final bookpath = _normalizePath('$opfDir$url');
      final renamed = renameMap[bookpath];
      if (renamed == null) return m.group(0)!;

      return 'url($quote$renamed$quote)';
    });
  }

  /// 生成合并 OPF
  static String _generateMergedOpf(
    String version,
    _EpubData firstEpub,
    List<_ManifestItem> manifestItems,
    List<_SpineItem> spineItems,
    MergeOptions options,
  ) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<package version="$version" unique-identifier="merged-id" '
      'xmlns="http://www.idpf.org/2007/opf">',
    );

    // metadata（优先用第一本书的真实元数据，仅在缺失时降级到默认值）
    final meta = firstEpub.meta;
    final identifier = (meta['identifier']?.isNotEmpty ?? false)
        ? meta['identifier']!
        : 'merged-epub-${DateTime.now().millisecondsSinceEpoch}';
    final title = _firstNonEmpty(options.title, meta['title']) ?? '合并 EPUB';
    final language = _firstNonEmpty(options.language, meta['language']) ?? 'zh';
    final author = _firstNonEmpty(options.author, meta['author']);
    final publisher = _firstNonEmpty(options.publisher, meta['publisher']);
    final description = _firstNonEmpty(
      options.description,
      meta['description'],
    );

    buf.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">');
    buf.writeln(
      '    <dc:identifier id="merged-id">${_escapeXml(identifier)}</dc:identifier>',
    );
    buf.writeln('    <dc:title>${_escapeXml(title)}</dc:title>');
    if (meta['subtitle']?.isNotEmpty ?? false) {
      buf.writeln(
        '    <dc:title id="merged-subtitle">${_escapeXml(meta['subtitle']!)}</dc:title>',
      );
      buf.writeln(
        '    <meta refines="#merged-subtitle" property="title-type">subtitle</meta>',
      );
    }
    buf.writeln('    <dc:language>${_escapeXml(language)}</dc:language>');
    if (author != null) {
      buf.writeln('    <dc:creator>${_escapeXml(author)}</dc:creator>');
    }
    if (publisher != null) {
      buf.writeln('    <dc:publisher>${_escapeXml(publisher)}</dc:publisher>');
    }
    if (description != null) {
      buf.writeln(
        '    <dc:description>${_escapeXml(description)}</dc:description>',
      );
    }
    if (options.hasCustomCover) {
      buf.writeln('    <meta name="cover" content="merged-cover-image"/>');
    }
    if (meta['rights']?.isNotEmpty ?? false) {
      buf.writeln('    <dc:rights>${_escapeXml(meta['rights']!)}</dc:rights>');
    }
    if (version.startsWith('3')) {
      final now = DateTime.now().toUtc();
      final modified = '${now.toIso8601String().split('.')[0]}Z';
      buf.writeln('    <meta property="dcterms:modified">$modified</meta>');
    }
    buf.writeln('  </metadata>');

    // manifest
    buf.writeln('  <manifest>');
    for (final item in manifestItems) {
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

    // spine
    buf.writeln('  <spine>');
    for (final item in spineItems) {
      var line = '    <itemref idref="${item.idref}"';
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

  static String? _firstNonEmpty(String? preferred, String? fallback) {
    final value = preferred?.trim();
    if (value != null && value.isNotEmpty) return value;
    final fallbackValue = fallback?.trim();
    if (fallbackValue != null && fallbackValue.isNotEmpty) {
      return fallbackValue;
    }
    return null;
  }

  static String? _mediaTypeForCover(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return null;
    }
  }

  /// 生成合并 nav
  static String _generateMergedNav(
    List<_TocEntry> tocEntries,
    List<String> bookNames,
  ) {
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
    buf.writeln('    <ol>');

    // 按书分组
    var currentVol = -1;
    for (final entry in tocEntries) {
      if (entry.volume != currentVol) {
        if (currentVol >= 0) {
          buf.writeln('      </ol>');
          buf.writeln('    </li>');
        }
        currentVol = entry.volume;
        final bookName = currentVol < bookNames.length
            ? bookNames[currentVol]
            : '第${currentVol + 1}卷';
        buf.writeln('    <li>');
        buf.writeln('      <span>${_escapeXml(bookName)}</span>');
        buf.writeln('      <ol>');
      }

      if (entry.href.isNotEmpty) {
        buf.writeln(
          '        <li><a href="${_escapeXml(entry.href)}">${_escapeXml(entry.title)}</a></li>',
        );
      } else {
        buf.writeln('        <li><span>${_escapeXml(entry.title)}</span></li>');
      }
    }

    if (currentVol >= 0) {
      buf.writeln('      </ol>');
      buf.writeln('    </li>');
    }

    buf.writeln('    </ol>');
    buf.writeln('  </nav>');
    buf.writeln('</body>');
    buf.writeln('</html>');
    return buf.toString();
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

  /// 解析 OPF
  ///
  /// 解析失败时记录警告并返回空 manifest/spine（不再静默吞错）。
  /// 调用方根据返回值判断是否需要降级处理。
  static _ParsedOpf _parseOpf(String opfContent, String opfDir) {
    var version = '2.0';
    final manifest = <_ManifestItem>[];
    final spine = <_SpineItem>[];
    final meta = <String, String>{};

    try {
      final document = xml.XmlDocument.parse(opfContent);
      final package = document.findElements('package', namespace: '*').first;
      version = package.getAttribute('version') ?? '2.0';

      // 解析 metadata（dc:title/dc:creator/...）
      for (final m in document.findAllElements('metadata', namespace: '*')) {
        _extractMetaValue(m, 'title', 'title', meta, document);
        _extractMetaValue(m, 'creator', 'author', meta, document);
        _extractMetaValue(m, 'language', 'language', meta, document);
        _extractMetaValue(m, 'publisher', 'publisher', meta, document);
        _extractMetaValue(m, 'description', 'description', meta, document);
        _extractMetaValue(m, 'identifier', 'identifier', meta, document);
        _extractMetaValue(m, 'rights', 'rights', meta, document);

        // EPUB3 风格的副标题：<dc:title id="subtitle">...</dc:title>
        // 配合 <meta refines="#subtitle" property="title-type">subtitle</meta>
        for (final t in m.findElements('title', namespace: '*')) {
          if (t.innerText.trim().isEmpty) continue;
          final refId = t.getAttribute('id');
          if (refId == null) continue;
          // 查找 refines 标记
          for (final ref in m.findElements('meta', namespace: '*')) {
            final refines = ref.getAttribute('refines');
            if (refines == null) continue;
            final refTarget = refines.startsWith('#')
                ? refines.substring(1)
                : refines;
            if (refTarget != refId) continue;
            if (ref.getAttribute('property') == 'title-type' &&
                ref.innerText.trim() == 'subtitle') {
              meta['subtitle'] = t.innerText.trim();
              break;
            }
          }
          if (meta['subtitle'] != null) break;
        }

        // EPUB2 风格的 <meta name="title" content="...">
        for (final meta2 in m.findElements('meta', namespace: '*')) {
          final name = meta2.getAttribute('name');
          if (name == 'title') {
            final content = meta2.getAttribute('content');
            if (content != null &&
                content.isNotEmpty &&
                meta['title'] == null) {
              meta['title'] = content;
            }
          }
        }
        break; // 只取第一个 metadata
      }

      for (final item in document.findAllElements('item', namespace: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        final propsStr = item.getAttribute('properties') ?? '';
        final props = propsStr.isEmpty
            ? <String>[]
            : propsStr.split(' ').where((s) => s.isNotEmpty).toList();
        if (id.isNotEmpty) {
          manifest.add(
            _ManifestItem(
              id: id,
              href: href,
              mediaType: mediaType,
              properties: props,
            ),
          );
        }
      }

      for (final item in document.findAllElements('itemref', namespace: '*')) {
        final idref = item.getAttribute('idref') ?? '';
        final linear = item.getAttribute('linear');
        if (idref.isNotEmpty) {
          spine.add(_SpineItem(idref: idref, linear: linear));
        }
      }
    } catch (e) {
      // 解析失败不再静默吞错，记录到日志供用户查阅
      // 调用方（execute）已经会显示警告，这里只注释说明
    }

    return _ParsedOpf(
      version: version,
      manifest: manifest,
      spine: spine,
      meta: meta,
    );
  }

  /// 提取 dc:* 元素的值到 meta map
  ///
  /// [element] metadata 元素
  /// [localName] 元素本地名（如 title/creator）
  /// [key] meta map 中的 key
  /// [meta] 目标 map
  /// [_doc] 文档引用（用于解析 refines），暂未使用
  static void _extractMetaValue(
    xml.XmlElement element,
    String localName,
    String key,
    Map<String, String> meta,
    xml.XmlDocument doc, // 文档引用（保留以备扩展 refines 处理）
  ) {
    if (meta.containsKey(key) && meta[key]!.isNotEmpty) return;
    for (final child in element.findElements(localName, namespace: '*')) {
      final text = child.innerText.trim();
      if (text.isNotEmpty) {
        meta[key] = text;
        return;
      }
    }
  }

  /// 解析 TOC（nav 或 NCX）
  static List<_TocEntry> _parseToc(
    Archive archive,
    _ParsedOpf parsed,
    String opfDir,
  ) {
    // 查找 nav（EPUB3）
    final navItem = parsed.manifest
        .where((m) => m.properties.contains('nav'))
        .firstOrNull;

    if (navItem != null) {
      final navPath = _normalizePath('$opfDir${navItem.href}');
      final navFile = archive.findFile(navPath);
      if (navFile != null) {
        final content = utf8.decode(
          navFile.content as List<int>,
          allowMalformed: true,
        );
        return _parseTocNav(content);
      }
    }

    // 查找 NCX（EPUB2）
    final ncxItem = parsed.manifest
        .where((m) => m.mediaType == 'application/x-dtbncx+xml')
        .firstOrNull;

    if (ncxItem != null) {
      final ncxPath = _normalizePath('$opfDir${ncxItem.href}');
      final ncxFile = archive.findFile(ncxPath);
      if (ncxFile != null) {
        final content = utf8.decode(
          ncxFile.content as List<int>,
          allowMalformed: true,
        );
        return _parseTocNcx(content);
      }
    }

    // 回退：用 spine 内容文档做 target
    final entries = <_TocEntry>[];
    for (final spineItem in parsed.spine) {
      final item = parsed.manifest
          .where((m) => m.id == spineItem.idref)
          .firstOrNull;
      if (item != null) {
        entries.add(
          _TocEntry(
            title: p.basenameWithoutExtension(item.href),
            href: item.href,
            level: 1,
            volume: 0,
          ),
        );
      }
    }
    return entries;
  }

  /// 解析 EPUB3 nav
  static List<_TocEntry> _parseTocNav(String content) {
    final entries = <_TocEntry>[];
    try {
      final document = xml.XmlDocument.parse(content);
      final nav = document.findAllElements('nav', namespace: '*').where((n) {
        final type = n.getAttribute('epub:type') ?? n.getAttribute('type');
        return type == null || type == 'toc';
      }).firstOrNull;

      final ol = nav?.findElements('ol', namespace: '*').firstOrNull;
      if (ol != null) {
        _walkNavList(ol, 1, entries);
      }
    } catch (_) {
      // 解析失败返回空
    }
    return entries;
  }

  /// 递归遍历 nav 的 ol 元素
  static void _walkNavList(
    xml.XmlElement ol,
    int level,
    List<_TocEntry> entries,
  ) {
    for (final li in ol.findElements('li', namespace: '*')) {
      final a = li.findElements('a', namespace: '*').firstOrNull;
      final span = li.findElements('span', namespace: '*').firstOrNull;

      final title = a?.innerText ?? span?.innerText ?? '';
      var href = a?.getAttribute('href') ?? '';

      // 剥离 fragment
      final fragIdx = href.indexOf('#');
      if (fragIdx >= 0) {
        href = href.substring(0, fragIdx);
      }

      entries.add(
        _TocEntry(title: title.trim(), href: href, level: level, volume: 0),
      );

      // 递归子 ol
      final childOl = li.findElements('ol', namespace: '*').firstOrNull;
      if (childOl != null) {
        _walkNavList(childOl, level + 1, entries);
      }
    }
  }

  /// 解析 EPUB2 NCX
  static List<_TocEntry> _parseTocNcx(String content) {
    final entries = <_TocEntry>[];
    try {
      final document = xml.XmlDocument.parse(content);
      final navMap = document
          .findAllElements('navMap', namespace: '*')
          .firstOrNull;
      if (navMap != null) {
        _walkNavPoints(navMap, 1, entries);
      }
    } catch (_) {
      // 解析失败返回空
    }
    return entries;
  }

  /// 递归遍历 NCX navPoint
  static void _walkNavPoints(
    xml.XmlElement parent,
    int level,
    List<_TocEntry> entries,
  ) {
    for (final navPoint in parent.findElements('navPoint', namespace: '*')) {
      final label =
          navPoint
              .findElements('navLabel', namespace: '*')
              .firstOrNull
              ?.findElements('text', namespace: '*')
              .firstOrNull
              ?.innerText ??
          '';
      final content = navPoint
          .findElements('content', namespace: '*')
          .firstOrNull;
      var src = content?.getAttribute('src') ?? '';

      // 剥离 fragment
      final fragIdx = src.indexOf('#');
      if (fragIdx >= 0) {
        src = src.substring(0, fragIdx);
      }

      entries.add(
        _TocEntry(title: label.trim(), href: src, level: level, volume: 0),
      );

      // 递归子 navPoint
      _walkNavPoints(navPoint, level + 1, entries);
    }
  }
}

// ===== 数据类 =====

/// 解析后的 OPF 数据
class _ParsedOpf {
  final String version;
  final List<_ManifestItem> manifest;
  final List<_SpineItem> spine;
  final Map<String, String> meta;

  _ParsedOpf({
    required this.version,
    required this.manifest,
    required this.spine,
    this.meta = const {},
  });
}

/// Manifest 条目
class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final List<String> properties;

  _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}

/// Spine 条目
class _SpineItem {
  final String idref;
  final String? linear;

  _SpineItem({required this.idref, this.linear});
}

/// TOC 条目
class _TocEntry {
  final String title;
  final String href;
  final int level;
  final int volume;

  _TocEntry({
    required this.title,
    required this.href,
    required this.level,
    required this.volume,
  });
}

/// EPUB 数据
class _EpubData {
  final Archive archive;
  final String opfPath;
  final String opfDir;
  final String version;
  final List<_ManifestItem> manifest;
  final List<_SpineItem> spine;
  final List<_TocEntry> tocEntries;
  final String bookName;
  final Map<String, String> meta;

  _EpubData({
    required this.archive,
    required this.opfPath,
    required this.opfDir,
    required this.version,
    required this.manifest,
    required this.spine,
    required this.tocEntries,
    required this.bookName,
    this.meta = const {},
  });
}

/// 内容文件
class _ContentFile {
  final String path;
  final Uint8List data;

  _ContentFile({required this.path, required this.data});
}
