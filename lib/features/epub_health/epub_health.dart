import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_health_report.dart';

class EpubHealthInspector {
  EpubHealthInspector._();

  static Future<EpubHealthReport> scan(String epubPath) async {
    final source = File(epubPath);
    if (!await source.exists()) {
      return _ReportBuilder(
        epubPath,
      ).fatal('file-missing', '文件不存在', '找不到待检查的 EPUB 文件。', epubPath).build();
    }

    try {
      final bytes = await source.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      return scanArchive(archive, sourcePath: epubPath);
    } catch (error) {
      return _ReportBuilder(epubPath)
          .fatal('zip-invalid', 'ZIP 结构无效', '无法完整解压并校验 EPUB：$error', epubPath)
          .build();
    }
  }

  static EpubHealthReport scanArchive(
    Archive archive, {
    String sourcePath = '',
  }) {
    final builder = _ReportBuilder(sourcePath)
      ..fileCount = archive.files.length;
    final files = <String, ArchiveFile>{};
    final lowerNames = <String, String>{};

    for (final file in archive.files) {
      if (!file.isFile || file.name.isEmpty) continue;
      final name = _normalizeArchiveName(file.name);
      if (files.containsKey(name)) {
        builder.add(
          code: 'zip-duplicate-entry',
          severity: EpubHealthSeverity.error,
          title: 'ZIP 中存在重复文件名',
          message: '同一路径在压缩包中出现多次，阅读器可能读取到不同版本。',
          location: name,
        );
      }
      files[name] = file;

      final lower = name.toLowerCase();
      final existingCase = lowerNames[lower];
      if (existingCase != null && existingCase != name) {
        builder.add(
          code: 'zip-case-collision',
          severity: EpubHealthSeverity.warning,
          title: '文件路径仅大小写不同',
          message: '在不区分大小写的平台上可能发生资源覆盖。',
          location: '$existingCase ↔ $name',
        );
      } else {
        lowerNames[lower] = name;
      }

      if (file.name.startsWith('/') ||
          file.name.contains('\\') ||
          _containsParentTraversal(file.name)) {
        builder.add(
          code: 'zip-unsafe-path',
          severity: EpubHealthSeverity.error,
          title: 'ZIP 内部路径不规范',
          message: 'EPUB 资源路径不能使用绝对路径、反斜杠或越出包根目录。',
          location: file.name,
        );
      }
    }

    _checkMimetype(archive, files, builder);

    final opfCandidates = files.keys
        .where((name) => name.toLowerCase().endsWith('.opf'))
        .toList();
    final opfPath = _readContainer(files, opfCandidates, builder);
    if (opfPath == null) return builder.build();
    builder.opfPath = opfPath;

    final opfFile = files[opfPath];
    if (opfFile == null) {
      builder.add(
        code: 'opf-missing',
        severity: EpubHealthSeverity.error,
        title: '找不到 OPF 文件',
        message: 'container.xml 指向的 package document 不存在。',
        location: opfPath,
      );
      return builder.build();
    }

    XmlDocument opf;
    try {
      opf = XmlDocument.parse(_readText(opfFile));
    } catch (error) {
      builder.add(
        code: 'opf-invalid-xml',
        severity: EpubHealthSeverity.error,
        title: 'OPF XML 无法解析',
        message: 'package document 不是有效 XML：$error',
        location: opfPath,
      );
      return builder.build();
    }

    final package = opf.rootElement;
    builder.epubVersion = package.getAttribute('version')?.trim();
    _checkDuplicateIds(opf, opfPath, builder);

    final manifest = _readManifest(opf, opfPath, files, builder);
    builder.manifestItemCount = manifest.length;
    final spineIds = _checkSpine(opf, opfPath, manifest, builder);
    builder.spineItemCount = spineIds.length;
    _checkNavigation(opf, opfPath, manifest, files, builder);
    _checkCover(opf, opfPath, manifest, builder);
    _checkContentDocuments(files, manifest, builder);
    _checkUnmanifestedFiles(files, manifest, opfPath, builder);

    return builder.build();
  }

  static void _checkMimetype(
    Archive archive,
    Map<String, ArchiveFile> files,
    _ReportBuilder builder,
  ) {
    final mimetype = files['mimetype'];
    if (mimetype == null) {
      builder.add(
        code: 'mimetype-missing',
        severity: EpubHealthSeverity.error,
        title: '缺少 mimetype',
        message: 'EPUB 根目录必须包含内容为 application/epub+zip 的 mimetype 文件。',
        location: 'mimetype',
        fix: builder.fix(
          kind: 'canonicalMimetype',
          label: '创建标准 mimetype',
          description: '在 ZIP 首项创建未压缩的标准 mimetype 文件。',
        ),
      );
      return;
    }

    String content;
    try {
      content = utf8.decode(mimetype.content as List<int>);
    } catch (_) {
      content = '';
    }
    if (content != 'application/epub+zip') {
      builder.add(
        code: 'mimetype-content',
        severity: EpubHealthSeverity.error,
        title: 'mimetype 内容错误',
        message: '内容必须精确等于 application/epub+zip，不能包含 BOM、空格或换行。',
        location: 'mimetype',
        fix: builder.fix(
          kind: 'canonicalMimetype',
          label: '重写标准 mimetype',
          description: '用规范要求的固定内容替换当前文件。',
        ),
      );
    }
    if (archive.files.isEmpty ||
        _normalizeArchiveName(archive.files.first.name) != 'mimetype') {
      builder.add(
        code: 'mimetype-order',
        severity: EpubHealthSeverity.error,
        title: 'mimetype 不是 ZIP 首项',
        message: '严格阅读器要求 mimetype 是第一个 local file header。',
        location: 'mimetype',
        fix: builder.fix(
          kind: 'canonicalMimetype',
          label: '将 mimetype 移到首项',
          description: '重新打包并把 mimetype 固定为第一个文件。',
        ),
      );
    }
    if (mimetype.compressionType != ArchiveFile.STORE) {
      builder.add(
        code: 'mimetype-compressed',
        severity: EpubHealthSeverity.error,
        title: 'mimetype 被压缩',
        message: 'mimetype 必须使用 STORE 方式保存。',
        location: 'mimetype',
        fix: builder.fix(
          kind: 'canonicalMimetype',
          label: '取消 mimetype 压缩',
          description: '重新打包并以 STORE 方式写入 mimetype。',
        ),
      );
    }
  }

  static String? _readContainer(
    Map<String, ArchiveFile> files,
    List<String> opfCandidates,
    _ReportBuilder builder,
  ) {
    final container = files['META-INF/container.xml'];
    if (container == null) {
      final repairPath = opfCandidates.length == 1
          ? opfCandidates.single
          : null;
      builder.add(
        code: 'container-missing',
        severity: EpubHealthSeverity.error,
        title: '缺少 container.xml',
        message: repairPath == null
            ? '无法定位唯一的 OPF，不能自动重建容器声明。'
            : '已找到唯一 OPF，可以安全重建容器声明。',
        location: 'META-INF/container.xml',
        fix: repairPath == null
            ? null
            : builder.fix(
                kind: 'repairContainer',
                label: '重建 container.xml',
                description: '将唯一 OPF 写入标准 rootfile 声明。',
                data: {'opfPath': repairPath},
              ),
      );
      return repairPath;
    }

    try {
      final document = XmlDocument.parse(_readText(container));
      final rootfiles = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'rootfile')
          .toList();
      if (rootfiles.isEmpty) {
        throw const FormatException('缺少 rootfile');
      }
      final fullPath = rootfiles.first.getAttribute('full-path')?.trim() ?? '';
      if (fullPath.isEmpty) throw const FormatException('full-path 为空');
      final normalized = _normalizeReferencePath('', fullPath);
      if (files.containsKey(normalized)) return normalized;

      final repairPath = opfCandidates.length == 1
          ? opfCandidates.single
          : null;
      builder.add(
        code: 'container-opf-missing',
        severity: EpubHealthSeverity.error,
        title: 'container.xml 指向不存在的 OPF',
        message: 'rootfile 的 full-path 无法在 EPUB 中找到。',
        location: fullPath,
        fix: repairPath == null
            ? null
            : builder.fix(
                kind: 'repairContainer',
                label: '改为唯一可用 OPF',
                description: '重建 container.xml 并指向 $repairPath。',
                data: {'opfPath': repairPath},
              ),
      );
      return repairPath;
    } catch (error) {
      final repairPath = opfCandidates.length == 1
          ? opfCandidates.single
          : null;
      builder.add(
        code: 'container-invalid',
        severity: EpubHealthSeverity.error,
        title: 'container.xml 无法解析',
        message: '$error',
        location: 'META-INF/container.xml',
        fix: repairPath == null
            ? null
            : builder.fix(
                kind: 'repairContainer',
                label: '重建 container.xml',
                description: '使用唯一 OPF 生成标准容器声明。',
                data: {'opfPath': repairPath},
              ),
      );
      return repairPath;
    }
  }

  static Map<String, _ManifestItem> _readManifest(
    XmlDocument opf,
    String opfPath,
    Map<String, ArchiveFile> files,
    _ReportBuilder builder,
  ) {
    final result = <String, _ManifestItem>{};
    final manifestElements = opf.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'manifest')
        .toList();
    if (manifestElements.isEmpty) {
      builder.add(
        code: 'manifest-missing',
        severity: EpubHealthSeverity.error,
        title: 'OPF 缺少 manifest',
        message: '无法确定 EPUB 包含的阅读资源。',
        location: opfPath,
      );
      return result;
    }

    final seenPaths = <String, String>{};
    for (final element in manifestElements.first.childElements.where(
      (child) => child.name.local == 'item',
    )) {
      final id = element.getAttribute('id')?.trim() ?? '';
      final href = element.getAttribute('href')?.trim() ?? '';
      final mediaType = element.getAttribute('media-type')?.trim() ?? '';
      final properties = element.getAttribute('properties')?.trim() ?? '';
      if (id.isEmpty || href.isEmpty) {
        builder.add(
          code: 'manifest-item-incomplete',
          severity: EpubHealthSeverity.error,
          title: 'manifest 项缺少 id 或 href',
          message: '每个 manifest item 都必须声明唯一 id 和资源路径。',
          location: opfPath,
        );
        continue;
      }
      if (result.containsKey(id)) {
        builder.add(
          code: 'manifest-duplicate-id',
          severity: EpubHealthSeverity.error,
          title: 'manifest 存在重复 ID',
          message: 'spine 无法可靠区分同名资源。',
          location: '$opfPath#$id',
        );
        continue;
      }

      final remote = _isRemoteReference(href);
      final resolvedPath = remote
          ? href
          : _normalizeReferencePath(opfPath, href);
      final item = _ManifestItem(
        id: id,
        href: href,
        mediaType: mediaType,
        properties: properties,
        path: resolvedPath,
      );
      result[id] = item;

      if (!remote && !files.containsKey(resolvedPath)) {
        builder.add(
          code: 'manifest-resource-missing',
          severity: EpubHealthSeverity.error,
          title: 'manifest 资源不存在',
          message: 'OPF 声明了资源，但 ZIP 中找不到对应文件。',
          location: '$opfPath → $href',
        );
      }
      final existingId = seenPaths[resolvedPath];
      if (existingId != null) {
        builder.add(
          code: 'manifest-duplicate-href',
          severity: EpubHealthSeverity.warning,
          title: '多个 manifest 项指向同一资源',
          message: '重复声明会增加 spine、导航和属性解析的歧义。',
          location: '$existingId / $id → $href',
        );
      } else {
        seenPaths[resolvedPath] = id;
      }

      final accepted = _acceptedMediaTypes(resolvedPath);
      if (!remote && accepted.isNotEmpty && !accepted.contains(mediaType)) {
        final canonical = accepted.first;
        builder.add(
          code: 'manifest-media-type',
          severity: EpubHealthSeverity.warning,
          title: '资源媒体类型不匹配',
          message: mediaType.isEmpty
              ? 'manifest 未声明 media-type，按扩展名应为 $canonical。'
              : '当前为 $mediaType，按扩展名应为 ${accepted.join(' 或 ')}。',
          location: '$opfPath#$id → $href',
          fix: builder.fix(
            kind: 'correctMediaType',
            label: '改为 $canonical',
            description: '仅修正 OPF 中该资源的 media-type。',
            data: {'opfPath': opfPath, 'itemId': id, 'mediaType': canonical},
          ),
        );
      }
    }
    return result;
  }

  static List<String> _checkSpine(
    XmlDocument opf,
    String opfPath,
    Map<String, _ManifestItem> manifest,
    _ReportBuilder builder,
  ) {
    final spineElements = opf.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'spine')
        .toList();
    if (spineElements.isEmpty) {
      builder.add(
        code: 'spine-missing',
        severity: EpubHealthSeverity.error,
        title: 'OPF 缺少 spine',
        message: 'EPUB 没有可确定的默认阅读顺序。',
        location: opfPath,
      );
      return const [];
    }

    final ids = <String>[];
    for (final itemref in spineElements.first.childElements.where(
      (child) => child.name.local == 'itemref',
    )) {
      final idref = itemref.getAttribute('idref')?.trim() ?? '';
      if (idref.isEmpty) {
        builder.add(
          code: 'spine-empty-idref',
          severity: EpubHealthSeverity.error,
          title: 'spine 项缺少 idref',
          message: '阅读顺序中存在无法定位的空项。',
          location: opfPath,
        );
        continue;
      }
      ids.add(idref);
      final target = manifest[idref];
      if (target == null) {
        builder.add(
          code: 'spine-target-missing',
          severity: EpubHealthSeverity.error,
          title: 'spine 引用了不存在的 manifest ID',
          message: '阅读顺序中的章节无法解析。',
          location: '$opfPath#$idref',
        );
      } else if (target.mediaType != 'application/xhtml+xml' &&
          target.mediaType != 'image/svg+xml') {
        builder.add(
          code: 'spine-non-content',
          severity: EpubHealthSeverity.warning,
          title: 'spine 项不是 XHTML/SVG 文档',
          message: '部分阅读器可能无法把该资源作为章节显示。',
          location: target.path,
        );
      }
    }
    if (ids.isEmpty) {
      builder.add(
        code: 'spine-empty',
        severity: EpubHealthSeverity.error,
        title: 'spine 为空',
        message: 'EPUB 没有任何默认阅读内容。',
        location: opfPath,
      );
    }
    return ids;
  }

  static void _checkNavigation(
    XmlDocument opf,
    String opfPath,
    Map<String, _ManifestItem> manifest,
    Map<String, ArchiveFile> files,
    _ReportBuilder builder,
  ) {
    final version = builder.epubVersion ?? '';
    final isEpub3 = version.startsWith('3');
    final navItems = manifest.values
        .where((item) => item.propertyTokens.contains('nav'))
        .toList();
    final navCandidates = manifest.values.where((item) {
      if (item.mediaType != 'application/xhtml+xml') return false;
      final file = files[item.path];
      if (file == null) return false;
      try {
        final doc = XmlDocument.parse(_readText(file));
        return doc.descendants.whereType<XmlElement>().any((element) {
          if (element.name.local != 'nav') return false;
          return element.attributes.any(
            (attribute) =>
                attribute.name.local == 'type' &&
                attribute.value.split(RegExp(r'\s+')).contains('toc'),
          );
        });
      } catch (_) {
        return false;
      }
    }).toList();

    if (navItems.length > 1) {
      builder.add(
        code: 'nav-multiple',
        severity: EpubHealthSeverity.error,
        title: '声明了多个 EPUB 3 NAV 文档',
        message: 'properties="nav" 应只出现在一个 manifest item 上。',
        location: opfPath,
      );
    } else if (navItems.isEmpty && isEpub3) {
      final candidate = navCandidates.length == 1 ? navCandidates.single : null;
      builder.add(
        code: 'nav-missing',
        severity: EpubHealthSeverity.error,
        title: 'EPUB 3 缺少 NAV 声明',
        message: candidate == null
            ? '没有找到唯一、可确认的目录文档。'
            : '已识别目录文档，但 manifest item 缺少 properties="nav"。',
        location: opfPath,
        fix: candidate == null
            ? null
            : builder.fix(
                kind: 'addNavProperty',
                label: '补充 NAV 属性',
                description: '在 ${candidate.id} 上添加 properties="nav"。',
                data: {'opfPath': opfPath, 'itemId': candidate.id},
              ),
      );
    }

    final ncxItems = manifest.values
        .where(
          (item) =>
              item.mediaType == 'application/x-dtbncx+xml' ||
              item.path.toLowerCase().endsWith('.ncx'),
        )
        .toList();
    final spine = opf.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'spine')
        .firstOrNull;
    final tocId = spine?.getAttribute('toc')?.trim();
    if (!isEpub3) {
      if (ncxItems.isEmpty) {
        builder.add(
          code: 'ncx-missing',
          severity: EpubHealthSeverity.error,
          title: 'EPUB 2 缺少 NCX',
          message: 'EPUB 2 阅读器通常依赖 NCX 提供目录导航。',
          location: opfPath,
        );
      } else if (tocId == null || tocId.isEmpty) {
        builder.add(
          code: 'ncx-spine-toc-missing',
          severity: EpubHealthSeverity.warning,
          title: 'spine 未关联 NCX',
          message: 'OPF spine 缺少 toc 属性。',
          location: opfPath,
        );
      } else if (!manifest.containsKey(tocId)) {
        builder.add(
          code: 'ncx-spine-toc-invalid',
          severity: EpubHealthSeverity.error,
          title: 'spine 的 toc 指向不存在的 ID',
          message: '无法定位 NCX manifest item。',
          location: '$opfPath#$tocId',
        );
      }
    } else if (ncxItems.isEmpty) {
      builder.add(
        code: 'ncx-compatibility',
        severity: EpubHealthSeverity.suggestion,
        title: '未提供兼容性 NCX',
        message: 'EPUB 3 不强制要求 NCX，但添加后可改善部分旧阅读器兼容性。',
        location: opfPath,
      );
    }
  }

  static void _checkCover(
    XmlDocument opf,
    String opfPath,
    Map<String, _ManifestItem> manifest,
    _ReportBuilder builder,
  ) {
    final isEpub3 = (builder.epubVersion ?? '').startsWith('3');
    final declaredIds = <String>{};
    declaredIds.addAll(
      manifest.values
          .where((item) => item.propertyTokens.contains('cover-image'))
          .map((item) => item.id),
    );
    for (final meta in opf.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'meta',
    )) {
      if (meta.getAttribute('name') == 'cover') {
        final content = meta.getAttribute('content')?.trim();
        if (content != null && content.isNotEmpty) declaredIds.add(content);
      }
    }

    if (declaredIds.length > 1) {
      builder.add(
        code: 'cover-multiple',
        severity: EpubHealthSeverity.warning,
        title: '封面声明不唯一',
        message: '多个资源被声明为封面，阅读器选择可能不一致。',
        location: '$opfPath → ${declaredIds.join(', ')}',
      );
    }
    for (final id in declaredIds) {
      final item = manifest[id];
      if (item == null) {
        builder.add(
          code: 'cover-target-missing',
          severity: EpubHealthSeverity.error,
          title: '封面声明指向不存在的 manifest ID',
          message: '无法定位封面图片资源。',
          location: '$opfPath#$id',
        );
      } else if (!item.mediaType.startsWith('image/')) {
        builder.add(
          code: 'cover-not-image',
          severity: EpubHealthSeverity.error,
          title: '封面声明不是图片',
          message: '封面资源的 media-type 不是 image/*。',
          location: item.path,
        );
      }
    }

    if (declaredIds.isNotEmpty) return;
    final candidates = manifest.values.where((item) {
      if (!item.mediaType.startsWith('image/')) return false;
      final text = '${item.id}/${item.href}'.toLowerCase();
      return text.contains('cover') || text.contains('fengmian');
    }).toList();
    final candidate = candidates.length == 1 ? candidates.single : null;
    builder.add(
      code: 'cover-missing',
      severity: EpubHealthSeverity.warning,
      title: '缺少封面声明',
      message: candidate == null
          ? '未找到唯一且名称明确的封面图片，需人工指定。'
          : '已找到唯一封面候选 ${candidate.href}。',
      location: opfPath,
      fix: candidate == null
          ? null
          : builder.fix(
              kind: 'declareCover',
              label: '声明 ${candidate.href} 为封面',
              description: isEpub3
                  ? '添加 EPUB 3 cover-image 属性。'
                  : '添加 EPUB 2 meta cover 声明。',
              data: {
                'opfPath': opfPath,
                'itemId': candidate.id,
                'epub3': isEpub3,
              },
            ),
    );
  }

  static void _checkContentDocuments(
    Map<String, ArchiveFile> files,
    Map<String, _ManifestItem> manifest,
    _ReportBuilder builder,
  ) {
    final manifestPaths = manifest.values.map((item) => item.path).toSet();
    final idCache = <String, Set<String>?>{};
    for (final entry in files.entries) {
      final path = entry.key;
      final lower = path.toLowerCase();
      if (_isXmlContent(lower)) {
        XmlDocument document;
        try {
          document = XmlDocument.parse(_readText(entry.value));
        } catch (error) {
          builder.add(
            code: 'content-invalid-xml',
            severity: EpubHealthSeverity.error,
            title: '内容文档不是有效 XML',
            message: '$error',
            location: path,
          );
          idCache[path] = null;
          continue;
        }
        final ids = _checkDuplicateIds(document, path, builder);
        idCache[path] = ids;
        for (final element in document.descendants.whereType<XmlElement>()) {
          for (final attribute in element.attributes) {
            if (!_referenceAttributes.contains(attribute.name.local)) continue;
            _checkReference(
              sourcePath: path,
              rawReference: attribute.value,
              files: files,
              manifestPaths: manifestPaths,
              idCache: idCache,
              builder: builder,
              isFontReference: false,
            );
          }
        }
      } else if (lower.endsWith('.css')) {
        final css = _readText(entry.value);
        for (final match in RegExp(
          r'''url\(\s*(["']?)(.*?)\1\s*\)''',
          caseSensitive: false,
        ).allMatches(css)) {
          final reference = match.group(2)?.trim() ?? '';
          final prefixStart = match.start > 240 ? match.start - 240 : 0;
          final context = css.substring(prefixStart, match.start).toLowerCase();
          final fontFaceStart = context.lastIndexOf('@font-face');
          final closingBrace = context.lastIndexOf('}');
          _checkReference(
            sourcePath: path,
            rawReference: reference,
            files: files,
            manifestPaths: manifestPaths,
            idCache: idCache,
            builder: builder,
            isFontReference: fontFaceStart > closingBrace,
          );
        }
        for (final match in RegExp(
          r'''@import\s+(?:url\()?\s*["']([^"']+)["']''',
          caseSensitive: false,
        ).allMatches(css)) {
          _checkReference(
            sourcePath: path,
            rawReference: match.group(1) ?? '',
            files: files,
            manifestPaths: manifestPaths,
            idCache: idCache,
            builder: builder,
            isFontReference: false,
          );
        }
      }
    }
  }

  static Set<String> _checkDuplicateIds(
    XmlDocument document,
    String path,
    _ReportBuilder builder,
  ) {
    final ids = <String>{};
    final duplicateIds = <String>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      final id = element.getAttribute('id')?.trim();
      if (id != null && id.isNotEmpty && !ids.add(id)) {
        duplicateIds.add(id);
      }
      final xmlId = element.attributes
          .where(
            (attribute) =>
                attribute.name.local == 'id' && attribute.name.prefix == 'xml',
          )
          .firstOrNull
          ?.value
          .trim();
      if (xmlId != null && xmlId.isNotEmpty && !ids.add(xmlId)) {
        duplicateIds.add(xmlId);
      }
    }
    for (final id in duplicateIds) {
      builder.add(
        code: 'duplicate-id',
        severity: EpubHealthSeverity.error,
        title: '文档中存在重复 ID',
        message: '同一文档内的锚点 ID 必须唯一。',
        location: '$path#$id',
      );
    }
    return ids;
  }

  static void _checkReference({
    required String sourcePath,
    required String rawReference,
    required Map<String, ArchiveFile> files,
    required Set<String> manifestPaths,
    required Map<String, Set<String>?> idCache,
    required _ReportBuilder builder,
    required bool isFontReference,
  }) {
    final reference = rawReference.trim();
    if (reference.isEmpty ||
        reference == '#' ||
        _isRemoteReference(reference) ||
        reference.startsWith('data:') ||
        reference.startsWith('mailto:') ||
        reference.startsWith('tel:') ||
        reference.startsWith('javascript:')) {
      return;
    }

    final hash = reference.indexOf('#');
    final fragment = hash >= 0 ? _decode(reference.substring(hash + 1)) : '';
    final pathPart = hash >= 0 ? reference.substring(0, hash) : reference;
    final targetPath = pathPart.isEmpty
        ? sourcePath
        : _normalizeReferencePath(sourcePath, pathPart);
    final target = files[targetPath];
    if (target == null) {
      builder.add(
        code: isFontReference
            ? 'font-reference-missing'
            : 'resource-link-broken',
        severity: EpubHealthSeverity.error,
        title: isFontReference ? '字体引用断链' : '资源引用断链',
        message: '文档引用的本地资源在 EPUB 中不存在。',
        location: '$sourcePath → $reference',
      );
      return;
    }

    if (!manifestPaths.contains(targetPath) &&
        !targetPath.startsWith('META-INF/')) {
      builder.add(
        code: isFontReference
            ? 'font-reference-unmanifested'
            : 'resource-link-unmanifested',
        severity: EpubHealthSeverity.warning,
        title: isFontReference ? '字体未在 manifest 声明' : '引用资源未在 manifest 声明',
        message: '文件存在，但没有进入 OPF manifest，严格阅读器可能忽略它。',
        location: '$sourcePath → $reference',
      );
    }

    if (fragment.isEmpty || !_isXmlContent(targetPath.toLowerCase())) return;
    var ids = idCache[targetPath];
    if (!idCache.containsKey(targetPath)) {
      try {
        final document = XmlDocument.parse(_readText(target));
        ids = document.descendants
            .whereType<XmlElement>()
            .expand(
              (element) => element.attributes
                  .where((attribute) => attribute.name.local == 'id')
                  .map((attribute) => attribute.value),
            )
            .toSet();
      } catch (_) {
        ids = null;
      }
      idCache[targetPath] = ids;
    }
    if (ids != null && !ids.contains(fragment)) {
      builder.add(
        code: 'anchor-invalid',
        severity: EpubHealthSeverity.error,
        title: '锚点不存在',
        message: '目标文档中找不到引用的 ID。',
        location: '$sourcePath → $reference',
      );
    }
  }

  static void _checkUnmanifestedFiles(
    Map<String, ArchiveFile> files,
    Map<String, _ManifestItem> manifest,
    String opfPath,
    _ReportBuilder builder,
  ) {
    final manifestPaths = manifest.values.map((item) => item.path).toSet();
    for (final path in files.keys) {
      if (path == 'mimetype' ||
          path == opfPath ||
          path.startsWith('META-INF/') ||
          manifestPaths.contains(path)) {
        continue;
      }
      builder.add(
        code: 'resource-unmanifested',
        severity: EpubHealthSeverity.suggestion,
        title: 'ZIP 中存在未声明资源',
        message: '该文件不在当前 OPF manifest 中，可能是遗留或未纳入包清单的资源。',
        location: path,
      );
    }
  }

  static bool _isXmlContent(String lowerPath) {
    return lowerPath.endsWith('.xhtml') ||
        lowerPath.endsWith('.html') ||
        lowerPath.endsWith('.htm') ||
        lowerPath.endsWith('.svg') ||
        lowerPath.endsWith('.ncx');
  }

  static bool _isRemoteReference(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('//')) return true;
    try {
      final uri = Uri.parse(trimmed);
      return uri.hasScheme;
    } catch (_) {
      return false;
    }
  }

  static bool _containsParentTraversal(String value) {
    var depth = 0;
    for (final segment in value.replaceAll('\\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        depth--;
        if (depth < 0) return true;
      } else {
        depth++;
      }
    }
    return false;
  }

  static String _normalizeArchiveName(String value) {
    return value.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  static String _normalizeReferencePath(String basePath, String reference) {
    var raw = reference;
    final hash = raw.indexOf('#');
    if (hash >= 0) raw = raw.substring(0, hash);
    final query = raw.indexOf('?');
    if (query >= 0) raw = raw.substring(0, query);
    raw = _decode(raw).replaceAll('\\', '/');
    final combined = raw.startsWith('/')
        ? raw.substring(1)
        : p.posix.join(p.posix.dirname(basePath), raw);
    return p.posix.normalize(combined).replaceFirst(RegExp(r'^\./'), '');
  }

  static String _decode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  static String _readText(ArchiveFile file) {
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  static List<String> _acceptedMediaTypes(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm')) {
      return const ['application/xhtml+xml'];
    }
    if (lower.endsWith('.css')) return const ['text/css'];
    if (lower.endsWith('.ncx')) return const ['application/x-dtbncx+xml'];
    if (lower.endsWith('.svg')) return const ['image/svg+xml'];
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return const ['image/jpeg'];
    }
    if (lower.endsWith('.png')) return const ['image/png'];
    if (lower.endsWith('.gif')) return const ['image/gif'];
    if (lower.endsWith('.webp')) return const ['image/webp'];
    if (lower.endsWith('.avif')) return const ['image/avif'];
    if (lower.endsWith('.ttf')) {
      return const [
        'font/ttf',
        'application/x-font-ttf',
        'application/vnd.ms-opentype',
      ];
    }
    if (lower.endsWith('.otf')) {
      return const ['font/otf', 'application/vnd.ms-opentype'];
    }
    if (lower.endsWith('.woff')) {
      return const ['font/woff', 'application/font-woff'];
    }
    if (lower.endsWith('.woff2')) return const ['font/woff2'];
    if (lower.endsWith('.js')) {
      return const ['text/javascript', 'application/javascript'];
    }
    if (lower.endsWith('.smil')) return const ['application/smil+xml'];
    if (lower.endsWith('.mp3')) return const ['audio/mpeg'];
    if (lower.endsWith('.mp4')) return const ['video/mp4', 'audio/mp4'];
    return const [];
  }

  static const _referenceAttributes = {'href', 'src', 'poster', 'data'};
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String properties;
  final String path;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
    required this.path,
  });

  Set<String> get propertyTokens => properties
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();
}

class _ReportBuilder {
  final String sourcePath;
  final List<EpubHealthIssue> issues = [];
  int fileCount = 0;
  int manifestItemCount = 0;
  int spineItemCount = 0;
  String? epubVersion;
  String? opfPath;
  int _issueCounter = 0;

  _ReportBuilder(this.sourcePath);

  void add({
    required String code,
    required EpubHealthSeverity severity,
    required String title,
    required String message,
    String? location,
    EpubHealthFix? fix,
  }) {
    issues.add(
      EpubHealthIssue(
        id: '$code-${_issueCounter++}',
        code: code,
        severity: severity,
        title: title,
        message: message,
        location: location,
        fix: fix,
      ),
    );
  }

  _ReportBuilder fatal(
    String code,
    String title,
    String message,
    String location,
  ) {
    add(
      code: code,
      severity: EpubHealthSeverity.error,
      title: title,
      message: message,
      location: location,
    );
    return this;
  }

  EpubHealthFix fix({
    required String kind,
    required String label,
    required String description,
    Map<String, Object?> data = const {},
  }) {
    final keys = data.keys.toList()..sort();
    final identity = keys
        .map((key) => '$key=${Uri.encodeComponent('${data[key]}')}')
        .join('&');
    return EpubHealthFix(
      id: identity.isEmpty ? kind : '$kind?$identity',
      kind: kind,
      label: label,
      description: description,
      data: data,
    );
  }

  EpubHealthReport build() => EpubHealthReport(
    sourcePath: sourcePath,
    scannedAt: DateTime.now().toIso8601String(),
    epubVersion: epubVersion,
    opfPath: opfPath,
    fileCount: fileCount,
    manifestItemCount: manifestItemCount,
    spineItemCount: spineItemCount,
    issues: List.unmodifiable(issues),
  );
}
