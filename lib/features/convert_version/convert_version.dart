import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'epub_image_helper.dart';
import 'epub_packer.dart';

/// EPUB 版本转换操作
///
/// 实现 EPUB 2.0 与 3.0 之间的相互转换：
/// - 升级到 3.0：修改 package version 为 3.0，添加 dcterms:modified 元数据，
///   若存在 NCX 则自动生成 nav.xhtml 导航文件。
/// - 降级到 2.0：修改 package version 为 2.0，移除 dcterms:modified 元数据和
///   nav.xhtml 导航文件。
class ConvertVersionOperation {
  ConvertVersionOperation._();

  /// EPUB 2.0 与 3.0 互转
  ///
  /// 参数 [epubPath] 输入 EPUB 文件路径
  /// 参数 [outputPath] 输出 EPUB 文件路径
  /// 参数 [targetVersion] 目标版本：'2.0' 或 '3.0'
  static Future<void> execute({
    required String epubPath,
    required String outputPath,
    required String targetVersion,
  }) async {
    // 校验目标版本参数
    if (targetVersion != '2.0' && targetVersion != '3.0') {
      throw ArgumentError('targetVersion 仅支持 "2.0" 或 "3.0"，当前值：$targetVersion');
    }

    // 读取并解压 EPUB
    final bytes = await File(epubPath).readAsBytes();
    var archive = ZipDecoder().decodeBytes(bytes);

    // 定位 OPF 文件路径及其所在目录
    final opfPath = _locateOpfPath(archive);
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // 读取 OPF 原始内容
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件 $opfPath');
    }
    var opfContent = utf8.decode(opfFile.content as List<int>);

    // 根据目标版本执行转换
    if (targetVersion == '3.0') {
      opfContent = _upgradeTo3(archive, opfDir, opfContent);
    } else {
      opfContent = _downgradeTo2(archive, opfDir, opfContent);
      // _downgradeTo2 内部调用了 removeFile 删除 nav.xhtml，
      // archive 包的 removeFile 会损坏 _fileMap 索引，需重建修复
      archive = EpubImageHelper.rebuildArchive(archive);
    }

    // 将修改后的 OPF 写回（addFile 会自动替换同名文件）
    EpubImageHelper.addOrReplaceFile(
      archive,
      ArchiveFile(opfPath, opfContent.length, utf8.encode(opfContent)),
    );

    // 重新打包并保存
    // 用 EpubPacker 而非 ZipEncoder：强制 mimetype 第一个 + STORED，
    // 符合 EPUB 规范，否则 Kindle/多看/Sigil 严格模式会拒绝导入。
    EpubPacker.ensureMimetype(archive);
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }

  // ==================== EPUB 3.0 升级 ====================

  /// 将 OPF 内容升级到 EPUB 3.0
  ///
  /// 参数 [archive] 已解压的 EPUB 归档
  /// 参数 [opfDir] OPF 所在目录
  /// 参数 [opfContent] OPF 原始 XML 字符串
  /// 返回修改后的 OPF XML 字符串
  static String _upgradeTo3(Archive archive, String opfDir, String opfContent) {
    // 修改 package 版本号为 3.0
    var content = _replaceVersion(opfContent, '3.0');

    // 添加或更新 dcterms:modified 元数据（EPUB 3.0 必需）
    content = _ensureModifiedMeta(content);

    // 若存在 NCX 且尚无 nav.xhtml，则根据 NCX 生成导航文件
    final ncxHref = _findNcxHref(content);
    if (ncxHref != null && !content.contains('href="nav.xhtml"')) {
      final ncxPath = _resolvePath(opfDir, ncxHref);
      final ncxFile = archive.findFile(ncxPath);
      if (ncxFile != null) {
        final ncxContent = utf8.decode(ncxFile.content as List<int>);
        final navHtml = _generateNavFromNcx(ncxContent);
        // 将 nav.xhtml 添加到 ZIP
        final navPath = '${opfDir}nav.xhtml';
        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile(navPath, navHtml.length, utf8.encode(navHtml)),
        );
        // 在 manifest 中添加 nav item
        content = content.replaceFirst(
          '</manifest>',
          '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n    </manifest>',
        );
      }
    }

    return content;
  }

  // ==================== EPUB 2.0 降级 ====================

  /// 将 OPF 内容降级到 EPUB 2.0
  ///
  /// 参数 [archive] 已解压的 EPUB 归档
  /// 参数 [opfDir] OPF 所在目录
  /// 参数 [opfContent] OPF 原始 XML 字符串
  /// 返回修改后的 OPF XML 字符串
  static String _downgradeTo2(
    Archive archive,
    String opfDir,
    String opfContent,
  ) {
    final navItems = _findNavItems(opfContent);

    // 修改 package 版本号为 2.0
    var content = _replaceVersion(opfContent, '2.0');

    // 移除 dcterms:modified 元数据（EPUB 2.0 不支持）
    content = _removeModifiedMeta(content);

    // EPUB2 需要 NCX。纯 EPUB3 书籍通常只有 nav.xhtml，没有 toc.ncx；
    // 降级时要先用 nav 生成 NCX，再移除 nav。
    content = _ensureNcxForEpub2(archive, opfDir, content, navItems);

    // 移除 nav.xhtml 的 manifest/spine 引用和实际文件。
    // 一些 EPUB3 会把 nav 放在 Text/nav.xhtml 等子目录中，不能只删除
    // OPF 同级的 nav.xhtml。
    content = _removeNavItem(content);
    for (final navItem in navItems) {
      if (navItem.id != null && navItem.id!.isNotEmpty) {
        content = _removeSpineItemref(content, navItem.id!);
      }
      final navPath = _resolvePath(opfDir, navItem.href);
      final navFile = archive.findFile(navPath);
      if (navFile != null) {
        archive.removeFile(navFile);
      }
    }
    final fallbackNavFile = archive.findFile('${opfDir}nav.xhtml');
    if (fallbackNavFile != null) archive.removeFile(fallbackNavFile);

    return content;
  }

  // ==================== OPF 字符串操作工具 ====================

  /// 替换 package 元素的 version 属性值
  ///
  /// 参数 [opfContent] OPF XML 字符串
  /// 参数 [version] 目标版本号
  /// 返回修改后的 OPF XML 字符串
  static String _replaceVersion(String opfContent, String version) {
    return opfContent.replaceFirstMapped(
      RegExp(r'(<package[^>]*?\sversion=")[^"]*"'),
      (match) => '${match.group(1)}$version"',
    );
  }

  /// 确保 OPF 中存在 dcterms:modified 元数据（EPUB 3.0 必需）
  ///
  /// 若已存在则先移除再重新添加，确保时间戳为当前时间。
  ///
  /// 参数 [opfContent] OPF XML 字符串
  /// 返回修改后的 OPF XML 字符串
  static String _ensureModifiedMeta(String opfContent) {
    // 先移除已有的 dcterms:modified，避免重复
    var content = _removeModifiedMeta(opfContent);
    // 生成当前 UTC 时间戳，格式：YYYY-MM-DDThh:mm:ssZ
    final now = DateTime.now().toUtc();
    final modified =
        '${now.year.toString().padLeft(4, '0')}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}'
        'T${now.hour.toString().padLeft(2, '0')}'
        ':${now.minute.toString().padLeft(2, '0')}'
        ':${now.second.toString().padLeft(2, '0')}Z';
    // 在 </metadata> 闭合标签前插入
    content = content.replaceFirst(
      '</metadata>',
      '<meta property="dcterms:modified">$modified</meta>\n  </metadata>',
    );
    return content;
  }

  /// 移除 OPF 中的 dcterms:modified 元数据
  ///
  /// 同时处理成对标签和自闭合两种形式。
  ///
  /// 参数 [opfContent] OPF XML 字符串
  /// 返回修改后的 OPF XML 字符串
  static String _removeModifiedMeta(String opfContent) {
    // 移除成对标签形式：<meta property="dcterms:modified">...</meta>
    var content = opfContent.replaceAll(
      RegExp(r'<meta\s+property="dcterms:modified"[^>]*>[\s\S]*?</meta>'),
      '',
    );
    // 移除自闭合形式：<meta property="dcterms:modified" .../>
    content = content.replaceAll(
      RegExp(r'<meta\s+property="dcterms:modified"[^>]*/>'),
      '',
    );
    return content;
  }

  /// 在 OPF manifest 中查找 NCX 文件的 href
  ///
  /// 通过匹配 media-type="application/x-dtbncx+xml" 的 item 元素来定位 NCX。
  ///
  /// 参数 [opfContent] OPF XML 字符串
  /// 返回 NCX 文件的 href；若不存在则返回 null
  static String? _findNcxHref(String opfContent) {
    // 逐个检查 <item> 元素，查找 NCX 类型的项
    final itemRegex = RegExp(r'<item\s+[^>]*/?>');
    for (final match in itemRegex.allMatches(opfContent)) {
      final itemStr = match.group(0)!;
      if (itemStr.contains('application/x-dtbncx+xml')) {
        final hrefMatch = RegExp(r'href="([^"]+)"').firstMatch(itemStr);
        return hrefMatch?.group(1);
      }
    }
    return null;
  }

  /// 从 OPF manifest 中移除 nav 相关 item
  ///
  /// 参数 [opfContent] OPF XML 字符串
  /// 返回修改后的 OPF XML 字符串
  static String _removeNavItem(String opfContent) {
    var content = opfContent;
    final itemRegex = RegExp(r'\s*<item\s+[^>]*?/?>');
    content = content.replaceAllMapped(itemRegex, (match) {
      final item = match.group(0)!;
      final properties = _attrValue(item, 'properties') ?? '';
      final href = _attrValue(item, 'href') ?? '';
      if (_hasToken(properties, 'nav') || _isNavHref(href)) return '';
      return item;
    });
    return content;
  }

  static String _ensureNcxForEpub2(
    Archive archive,
    String opfDir,
    String opfContent,
    List<_NavItem> navItems,
  ) {
    final existingNcxHref = _findNcxHref(opfContent);
    final ncxHref = existingNcxHref ?? 'toc.ncx';
    final ncxPath = _resolvePath(opfDir, ncxHref);
    final ncxExists = archive.findFile(ncxPath) != null;

    var content = opfContent;
    final ncxId = existingNcxHref == null
        ? _uniqueManifestId(content, 'ncx')
        : (_findManifestIdByHref(content, existingNcxHref) ?? 'ncx');

    if (!ncxExists) {
      final entries = _tocEntriesFromNavItems(archive, opfDir, navItems);
      final fallbackEntries = entries.isNotEmpty
          ? entries
          : _tocEntriesFromSpine(content);
      final ncxContent = _generateNcx(
        opfContent: content,
        entries: fallbackEntries,
      );
      final ncxBytes = utf8.encode(ncxContent);
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile(ncxPath, ncxBytes.length, ncxBytes),
      );
    }

    if (existingNcxHref == null) {
      content = content.replaceFirst(
        '</manifest>',
        '<item id="$ncxId" href="${_escapeXmlAttr(ncxHref)}" media-type="application/x-dtbncx+xml"/>\n    </manifest>',
      );
    }

    content = _ensureSpineToc(content, ncxId);
    return content;
  }

  static List<_TocEntry> _tocEntriesFromNavItems(
    Archive archive,
    String opfDir,
    List<_NavItem> navItems,
  ) {
    for (final navItem in navItems) {
      final navPath = _resolvePath(opfDir, navItem.href);
      final navFile = archive.findFile(navPath);
      if (navFile == null) continue;

      final navContent = utf8.decode(navFile.content as List<int>);
      final entries = _tocEntriesFromNav(navContent, opfDir, navPath);
      if (entries.isNotEmpty) return entries;
    }
    return const [];
  }

  static List<_TocEntry> _tocEntriesFromNav(
    String navContent,
    String opfDir,
    String navPath,
  ) {
    try {
      final document = XmlDocument.parse(navContent);
      Iterable<XmlElement> anchors = const [];
      final tocNavs = document.findAllElements('nav', namespace: '*').where((
        nav,
      ) {
        var type =
            nav.getAttribute('type', namespace: '*') ??
            nav.getAttribute('epub:type');
        if (type == null) {
          for (final attr in nav.attributes) {
            if (attr.name.local == 'type') {
              type = attr.value;
              break;
            }
          }
        }
        type ??= '';
        return _hasToken(type, 'toc');
      });
      if (tocNavs.isNotEmpty) {
        anchors = tocNavs.first.findAllElements('a', namespace: '*');
      } else {
        anchors = document.findAllElements('a', namespace: '*');
      }

      final entries = <_TocEntry>[];
      for (final anchor in anchors) {
        final href = anchor.getAttribute('href');
        if (href == null || href.isEmpty) continue;
        final label = anchor.innerText.trim();
        entries.add(
          _TocEntry(
            label: label.isEmpty ? '目录 ${entries.length + 1}' : label,
            src: _navHrefToOpfRelative(opfDir, navPath, href),
          ),
        );
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  static List<_TocEntry> _tocEntriesFromSpine(String opfContent) {
    final manifest = <String, String>{};
    for (final match in RegExp(r'<item\s+[^>]*?/?>').allMatches(opfContent)) {
      final item = match.group(0)!;
      final id = _attrValue(item, 'id');
      final href = _attrValue(item, 'href');
      final mediaType = _attrValue(item, 'media-type') ?? '';
      if (id == null || href == null) continue;
      if (mediaType == 'application/xhtml+xml' || mediaType == 'text/html') {
        manifest[id] = href;
      }
    }

    final entries = <_TocEntry>[];
    for (final match in RegExp(
      r'<itemref\s+[^>]*?/?>',
    ).allMatches(opfContent)) {
      final itemref = match.group(0)!;
      final idref = _attrValue(itemref, 'idref');
      final href = idref == null ? null : manifest[idref];
      if (href == null || _isNavHref(href)) continue;
      entries.add(_TocEntry(label: '章节 ${entries.length + 1}', src: href));
    }
    return entries;
  }

  static String _generateNcx({
    required String opfContent,
    required List<_TocEntry> entries,
  }) {
    final title =
        _firstElementText(opfContent, 'dc:title') ??
        _firstElementText(opfContent, 'title') ??
        'Untitled';
    final uid =
        _firstElementText(opfContent, 'dc:identifier') ??
        _firstElementText(opfContent, 'identifier') ??
        'bookid';
    final tocEntries = entries.isNotEmpty
        ? entries
        : const [_TocEntry(label: '目录', src: '')];

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
    );
    buffer.writeln('  <head>');
    buffer.writeln(
      '    <meta name="dtb:uid" content="${_escapeXmlAttr(uid)}"/>',
    );
    buffer.writeln('    <meta name="dtb:depth" content="1"/>');
    buffer.writeln('    <meta name="dtb:totalPageCount" content="0"/>');
    buffer.writeln('    <meta name="dtb:maxPageNumber" content="0"/>');
    buffer.writeln('  </head>');
    buffer.writeln(
      '  <docTitle><text>${_escapeXmlText(title)}</text></docTitle>',
    );
    buffer.writeln('  <navMap>');
    for (var i = 0; i < tocEntries.length; i++) {
      final entry = tocEntries[i];
      buffer.writeln(
        '    <navPoint id="navPoint-${i + 1}" playOrder="${i + 1}">',
      );
      buffer.writeln(
        '      <navLabel><text>${_escapeXmlText(entry.label)}</text></navLabel>',
      );
      buffer.writeln('      <content src="${_escapeXmlAttr(entry.src)}"/>');
      buffer.writeln('    </navPoint>');
    }
    buffer.writeln('  </navMap>');
    buffer.writeln('</ncx>');
    return buffer.toString();
  }

  static String _ensureSpineToc(String opfContent, String ncxId) {
    return opfContent.replaceFirstMapped(RegExp(r'<spine\b([^>]*)>'), (match) {
      final attrs = match.group(1) ?? '';
      if (RegExp(r'\btoc\s*=').hasMatch(attrs)) return match.group(0)!;
      return '<spine toc="${_escapeXmlAttr(ncxId)}"$attrs>';
    });
  }

  static String _uniqueManifestId(String opfContent, String preferred) {
    if (!_manifestHasId(opfContent, preferred)) return preferred;
    var index = 1;
    while (_manifestHasId(opfContent, '$preferred$index')) {
      index++;
    }
    return '$preferred$index';
  }

  static bool _manifestHasId(String opfContent, String id) {
    for (final match in RegExp(r'<item\s+[^>]*?/?>').allMatches(opfContent)) {
      if (_attrValue(match.group(0)!, 'id') == id) return true;
    }
    return false;
  }

  static String? _findManifestIdByHref(String opfContent, String href) {
    for (final match in RegExp(r'<item\s+[^>]*?/?>').allMatches(opfContent)) {
      final item = match.group(0)!;
      if (_attrValue(item, 'href') == href) return _attrValue(item, 'id');
    }
    return null;
  }

  static String _navHrefToOpfRelative(
    String opfDir,
    String navPath,
    String href,
  ) {
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(href) ||
        href.startsWith('#')) {
      return href;
    }

    final navDir = navPath.contains('/')
        ? navPath.substring(0, navPath.lastIndexOf('/') + 1)
        : '';
    final resolved = _resolvePath(navDir, href);
    if (opfDir.isNotEmpty && resolved.startsWith(opfDir)) {
      return resolved.substring(opfDir.length);
    }
    return resolved;
  }

  static String? _firstElementText(String xml, String elementName) {
    final escaped = RegExp.escape(elementName);
    final match = RegExp(
      '<$escaped\\b[^>]*>([\\s\\S]*?)</$escaped>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (match == null) return null;
    return match.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  static String _escapeXmlText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _escapeXmlAttr(String value) {
    return _escapeXmlText(value).replaceAll('"', '&quot;');
  }

  static String _removeSpineItemref(String opfContent, String idref) {
    final itemrefRegex = RegExp(r'\s*<itemref\s+[^>]*?/?>');
    return opfContent.replaceAllMapped(itemrefRegex, (match) {
      final itemref = match.group(0)!;
      return _attrValue(itemref, 'idref') == idref ? '' : itemref;
    });
  }

  static List<_NavItem> _findNavItems(String opfContent) {
    final items = <_NavItem>[];
    final itemRegex = RegExp(r'<item\s+[^>]*?/?>');
    for (final match in itemRegex.allMatches(opfContent)) {
      final item = match.group(0)!;
      final href = _attrValue(item, 'href');
      if (href == null || href.isEmpty) continue;
      final properties = _attrValue(item, 'properties') ?? '';
      if (_hasToken(properties, 'nav') || _isNavHref(href)) {
        items.add(_NavItem(id: _attrValue(item, 'id'), href: href));
      }
    }
    return items;
  }

  static bool _hasToken(String value, String token) {
    return value.split(RegExp(r'\s+')).contains(token);
  }

  static bool _isNavHref(String href) {
    final path = href.split(RegExp(r'[?#]')).first;
    return path.split('/').last.toLowerCase() == 'nav.xhtml';
  }

  static String? _attrValue(String xmlElement, String name) {
    final match =
        RegExp('$name="([^"]*)"').firstMatch(xmlElement) ??
        RegExp("$name='([^']*)'").firstMatch(xmlElement);
    return match?.group(1);
  }

  // ==================== nav.xhtml 生成 ====================

  /// 根据 NCX 内容生成 EPUB 3.0 的 nav.xhtml 导航文件
  ///
  /// 解析 NCX 的 navMap 结构，递归生成对应的 nav 导航 HTML。
  ///
  /// 参数 [ncxContent] NCX 文件的 XML 字符串
  /// 返回 nav.xhtml 的 HTML 字符串
  static String _generateNavFromNcx(String ncxContent) {
    final document = XmlDocument.parse(ncxContent);
    final navMaps = document.findAllElements('navMap', namespace: '*');

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops">',
    );
    buffer.writeln('<head><meta charset="utf-8"/><title>导航</title></head>');
    buffer.writeln('<body>');
    buffer.writeln('<nav epub:type="toc" id="toc">');
    buffer.writeln('<h1>目录</h1>');
    buffer.writeln('<ol>');

    // 遍历 navMap 下的顶层 navPoint，递归生成列表项
    if (navMaps.isNotEmpty) {
      for (final navPoint in navMaps.first.findElements(
        'navPoint',
        namespace: '*',
      )) {
        _writeNavPoint(buffer, navPoint, 1);
      }
    }

    buffer.writeln('</ol>');
    buffer.writeln('</nav>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    return buffer.toString();
  }

  /// 递归将 NCX navPoint 写入 nav 列表项
  ///
  /// 参数 [buffer] 字符串缓冲区
  /// 参数 [navPoint] NCX 中的 navPoint 元素
  /// 参数 [depth] 当前嵌套深度（用于控制缩进）
  static void _writeNavPoint(
    StringBuffer buffer,
    XmlElement navPoint,
    int depth,
  ) {
    final indent = '  ' * (depth + 2);

    // 获取章节标题文本
    final navLabels = navPoint.findElements('navLabel', namespace: '*');
    String label = '';
    if (navLabels.isNotEmpty) {
      final texts = navLabels.first.findElements('text', namespace: '*');
      if (texts.isNotEmpty) {
        label = texts.first.innerText;
      }
    }

    // 获取章节链接地址
    final contents = navPoint.findElements('content', namespace: '*');
    final src = contents.isNotEmpty
        ? (contents.first.getAttribute('src') ?? '')
        : '';

    buffer.writeln('$indent<li><a href="$src">$label</a>');

    // 递归处理嵌套子章节
    final subPoints = navPoint.findElements('navPoint', namespace: '*');
    if (subPoints.isNotEmpty) {
      buffer.writeln('$indent  <ol>');
      for (final sub in subPoints) {
        _writeNavPoint(buffer, sub, depth + 1);
      }
      buffer.writeln('$indent  </ol>');
    }
    buffer.writeln('$indent</li>');
  }

  // ==================== 路径工具 ====================

  /// 从 container.xml 中定位 OPF 文件路径
  ///
  /// 参数 [archive] 已解压的 EPUB 归档
  /// 返回 OPF 文件在 ZIP 中的完整路径
  static String _locateOpfPath(Archive archive) {
    const containerPath = 'META-INF/container.xml';
    final containerFile = archive.findFile(containerPath);
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 META-INF/container.xml');
    }
    final containerXml = utf8.decode(containerFile.content as List<int>);
    final match = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (match == null) {
      throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
    }
    return match.group(1)!;
  }

  /// 将相对于 OPF 目录的 href 解析为 ZIP 内完整路径
  ///
  /// 处理 URL 片段、查询参数和相对路径片段（./ 和 ../）。
  ///
  /// 参数 [opfDir] OPF 所在目录（以 / 结尾）
  /// 参数 [href] 相对路径
  /// 返回 ZIP 内的完整文件路径
  static String _resolvePath(String opfDir, String href) {
    // 去除 URL 片段和查询参数
    final pathPart = href.split(RegExp(r'[?#]')).first;
    final combined = opfDir + Uri.decodeFull(pathPart);
    // 逐段处理，解析 ./ 和 ../
    final segments = <String>[];
    for (final part in combined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments.join('/');
  }
}

class _NavItem {
  const _NavItem({required this.id, required this.href});

  final String? id;
  final String href;
}

class _TocEntry {
  const _TocEntry({required this.label, required this.src});

  final String label;
  final String src;
}
