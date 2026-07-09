import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/epub_image_helper.dart';

/// EPUB 元数据数据模型
///
/// 包含 EPUB 的核心元数据字段以及封面图片信息。
/// 用于 [MetadataService.read] 的返回值和 [MetadataService.write] 的入参。
class MetadataData {
  /// 书名（dc:title，主标题）
  final String title;

  /// 副标题（EPUB3 通过 refines meta 标记 title-type 为 subtitle）
  final String subtitle;

  /// 作者（dc:creator）
  final String author;

  /// 语言（dc:language），默认 'zh-CN'
  final String language;

  /// 出版者（dc:publisher）
  final String publisher;

  /// 描述（dc:description）
  final String description;

  /// 唯一标识符（dc:identifier）
  final String identifier;

  /// 版权信息（dc:rights）
  final String rights;

  /// 封面图片字节，无封面时为 null
  final Uint8List? coverBytes;

  /// 封面图片扩展名（如 'jpg'、'png'），无封面时为 null
  final String? coverExt;

  const MetadataData({
    required this.title,
    this.subtitle = '',
    required this.author,
    this.language = 'zh-CN',
    this.publisher = '',
    this.description = '',
    this.identifier = '',
    this.rights = '',
    this.coverBytes,
    this.coverExt,
  });

  /// 创建副本并替换部分字段
  MetadataData copyWith({
    String? title,
    String? subtitle,
    String? author,
    String? language,
    String? publisher,
    String? description,
    String? identifier,
    String? rights,
    Uint8List? coverBytes,
    String? coverExt,
  }) {
    return MetadataData(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      author: author ?? this.author,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      description: description ?? this.description,
      identifier: identifier ?? this.identifier,
      rights: rights ?? this.rights,
      coverBytes: coverBytes ?? this.coverBytes,
      coverExt: coverExt ?? this.coverExt,
    );
  }
}

/// EPUB 元数据读写服务
///
/// 提供从 EPUB 文件中读取元数据（含封面）以及将修改后的元数据写回 EPUB 的能力。
/// 内部使用 archive 库解压/打包 ZIP，使用 xml 库解析和修改 OPF 文件。
class MetadataService {
  MetadataService._();

  /// 读取 EPUB 元数据
  ///
  /// 解压 EPUB，解析 container.xml 定位 OPF 文件，从 OPF 中提取
  /// dc:title、dc:creator、dc:language 等元数据字段，并读取封面图片字节。
  ///
  /// 参数 [epubPath] EPUB 文件路径
  /// 返回包含元数据和封面信息的 [MetadataData]
  static Future<MetadataData> read(String epubPath) async {
    // 读取 EPUB 文件字节并解压为 Archive 对象
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 解析 container.xml 定位 OPF 文件路径
    final opfPath = _findOpfPath(archive);
    final dir = _opfDir(opfPath);

    // 读取 OPF 文件内容（使用 UTF-8 解码，兼容中文等多字节字符）
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件 $opfPath');
    }
    final opfContent = _decodeFileContent(opfFile);
    final document = XmlDocument.parse(opfContent);

    // 定位 metadata 和 manifest 元素
    final metadata = _findFirstElement(document, 'metadata');
    final manifest = _findFirstElement(document, 'manifest');
    if (metadata == null) {
      throw Exception('OPF 结构异常：找不到 metadata 元素');
    }

    // 提取主标题和副标题（处理 EPUB3 refines 机制）
    final titles = _extractTitles(metadata);
    final title = titles.$1;
    final subtitle = titles.$2;

    // 提取其他 dc 元素文本
    final author = _getDcText(metadata, 'creator');
    final language = _getDcText(metadata, 'language');
    final publisher = _getDcText(metadata, 'publisher');
    final description = _getDcText(metadata, 'description');
    final identifier = _getDcText(metadata, 'identifier');
    final rights = _getDcText(metadata, 'rights');

    // 读取封面图片
    Uint8List? coverBytes;
    String? coverExt;
    if (manifest != null) {
      final cover = _readCover(archive, metadata, manifest, dir);
      coverBytes = cover.$1;
      coverExt = cover.$2;
    }

    return MetadataData(
      title: title,
      subtitle: subtitle,
      author: author,
      language: language.isEmpty ? 'zh-CN' : language,
      publisher: publisher,
      description: description,
      identifier: identifier,
      rights: rights,
      coverBytes: coverBytes,
      coverExt: coverExt,
    );
  }

  /// 将修改后的元数据写回 EPUB
  ///
  /// 解压原始 EPUB，修改 OPF 中的 dc 元素（找到则更新，找不到则新建），
  /// 处理标题/副标题的 EPUB3 refines meta，可选替换或移除封面图片，
  /// 最后重新打包保存。mimetype 文件不会被压缩（符合 EPUB 规范）。
  ///
  /// 参数 [epubPath] 原始 EPUB 文件路径
  /// 参数 [outputPath] 输出 EPUB 文件路径
  /// 参数 [metadata] 要写入的元数据
  /// 参数 [coverPath] 新封面图片路径，为 null 时不替换封面
  /// 参数 [removeCover] 是否移除封面，为 true 时忽略 [coverPath]
  static Future<void> write({
    required String epubPath,
    required String outputPath,
    required MetadataData metadata,
    String? coverPath,
    bool removeCover = false,
  }) async {
    // 读取并解压原始 EPUB
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 定位 OPF 文件路径和所在目录
    final opfPath = _findOpfPath(archive);
    final dir = _opfDir(opfPath);

    // 读取并解析 OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件 $opfPath');
    }
    final opfContent = _decodeFileContent(opfFile);
    final document = XmlDocument.parse(opfContent);

    final metaElement = _findFirstElement(document, 'metadata');
    final manifestElement = _findFirstElement(document, 'manifest');
    if (metaElement == null) {
      throw Exception('OPF 结构异常：找不到 metadata 元素');
    }

    // 推断 dc 前缀
    final dcPrefix = _detectDcPrefix(metaElement);

    // 更新主标题和副标题（处理 EPUB3 refines）
    _updateTitles(metaElement, metadata.title, metadata.subtitle, dcPrefix);

    // 更新其他 dc 元素
    _updateDcElement(metaElement, 'creator', metadata.author, dcPrefix);
    _updateDcElement(metaElement, 'language', metadata.language, dcPrefix);
    _updateDcElement(metaElement, 'publisher', metadata.publisher, dcPrefix);
    _updateDcElement(
      metaElement,
      'description',
      metadata.description,
      dcPrefix,
    );
    _updateDcElement(metaElement, 'identifier', metadata.identifier, dcPrefix);
    _updateDcElement(metaElement, 'rights', metadata.rights, dcPrefix);

    // 处理封面（替换或移除）
    // 返回值：若 removeCover 删除文件后返回新 archive（用于避免原地修改导致
    // archive 包 _fileMap 索引漂移），否则返回 null 表示 archive 保持原状。
    Archive? newArchive;
    if (manifestElement != null) {
      newArchive = _processCover(
        archive: archive,
        metadata: metaElement,
        manifest: manifestElement,
        opfDir: dir,
        coverPath: coverPath,
        removeCover: removeCover,
      );
    }
    // 若封面删除触发了 archive 重建，使用新 archive；否则沿用原 archive
    final finalArchive = newArchive ?? archive;

    // 将修改后的 OPF 写回 archive（使用 UTF-8 编码）
    final newOpfContent = document.toXmlString(pretty: true, indent: '  ');
    final opfBytes = utf8.encode(newOpfContent);
    finalArchive.addFile(ArchiveFile(opfPath, opfBytes.length, opfBytes));

    // 确保 mimetype 文件不压缩（EPUB 规范要求）
    _ensureMimetypeUncompressed(finalArchive);

    // 重新打包并保存
    await EpubPacker.pack(archive: finalArchive, outputPath: outputPath);
  }

  // ============ 私有辅助方法 ============

  /// 从 Archive 中解析 container.xml 定位 OPF 文件路径
  ///
  /// 参数 [archive] 已解压的 EPUB Archive 对象
  /// 返回 OPF 文件在 ZIP 中的完整路径
  static String _findOpfPath(Archive archive) {
    const containerPath = 'META-INF/container.xml';
    final containerFile = archive.findFile(containerPath);
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 META-INF/container.xml');
    }

    final containerXml = _decodeFileContent(containerFile);
    final document = XmlDocument.parse(containerXml);

    // container.xml 中 rootfile 元素的 full-path 属性指向 OPF
    final rootfiles = document.findAllElements('rootfile', namespace: '*');
    for (final rootfile in rootfiles) {
      final fullPath = rootfile.getAttribute('full-path');
      if (fullPath != null && fullPath.isNotEmpty) {
        return fullPath;
      }
    }
    throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
  }

  /// 获取 OPF 文件所在目录（含末尾斜杠）
  ///
  /// 例如 'OEBPS/content.opf' → 'OEBPS/'，'content.opf' → ''
  static String _opfDir(String opfPath) {
    final idx = opfPath.lastIndexOf('/');
    return idx >= 0 ? opfPath.substring(0, idx + 1) : '';
  }

  /// 安全解码 Archive 文件内容为字符串（UTF-8）
  ///
  /// 使用 allowMalformed 避免个别异常字节导致解码失败
  static String _decodeFileContent(ArchiveFile file) {
    final raw = file.content as List<int>;
    return utf8.decode(raw, allowMalformed: true);
  }

  /// 在 XML 文档中查找第一个指定本地名的元素
  ///
  /// 使用 namespace: '*' 匹配任意命名空间前缀
  static XmlElement? _findFirstElement(XmlNode node, String localName) {
    final elements = node.findAllElements(localName, namespace: '*');
    return elements.isEmpty ? null : elements.first;
  }

  /// 从现有 dc 元素推断命名空间前缀
  ///
  /// 检查 metadata 下已有的 dc 元素（如 title），获取其前缀。
  /// 如果没有 dc 元素则默认返回 'dc'。
  static String _detectDcPrefix(XmlElement metadata) {
    final titles = metadata.findElements('title', namespace: '*');
    if (titles.isNotEmpty) {
      final prefix = titles.first.name.prefix;
      if (prefix != null && prefix.isNotEmpty) {
        return prefix;
      }
    }
    // 检查其他常见 dc 元素
    for (final localName in ['creator', 'language', 'identifier']) {
      final elements = metadata.findElements(localName, namespace: '*');
      if (elements.isNotEmpty) {
        final prefix = elements.first.name.prefix;
        if (prefix != null && prefix.isNotEmpty) {
          return prefix;
        }
      }
    }
    return 'dc';
  }

  /// 获取 metadata 中指定本地名的第一个 dc 元素文本
  ///
  /// 参数 [metadata] OPF metadata 元素
  /// 参数 [localName] dc 元素本地名（如 'title'、'creator'）
  /// 返回元素文本内容，找不到则返回空字符串
  static String _getDcText(XmlElement metadata, String localName) {
    final elements = metadata.findElements(localName, namespace: '*');
    if (elements.isEmpty) return '';
    return elements.first.innerText.trim();
  }

  /// 从 metadata 中提取主标题和副标题
  ///
  /// EPUB3 通过 refines 机制区分主标题和副标题：
  /// `<dc:title id="t1">主标题</dc:title>`
  /// `<meta refines="#t1" property="title-type">main</meta>`
  /// `<dc:title id="t2">副标题</dc:title>`
  /// `<meta refines="#t2" property="title-type">subtitle</meta>`
  ///
  /// 对于 EPUB2（无 refines），第一个 dc:title 视为主标题。
  /// 若没有任何 dc:title，则降级查找 EPUB2 风格的 `<meta name="title" content="...">`。
  ///
  /// 返回 (主标题, 副标题)
  static (String, String) _extractTitles(XmlElement metadata) {
    final titles = metadata.findElements('title', namespace: '*').toList();

    var mainTitle = '';
    var subtitle = '';

    for (final titleElement in titles) {
      final id = titleElement.getAttribute('id');
      // 查找该 title 的 title-type refines meta
      final titleType = id != null ? _getRefinesTitleType(metadata, id) : null;

      if (titleType == 'subtitle') {
        // 明确标记为副标题
        subtitle = titleElement.innerText.trim();
      } else if (titleType == 'main') {
        // 明确标记为主标题
        mainTitle = titleElement.innerText.trim();
      } else if (mainTitle.isEmpty) {
        // 无 title-type 标记的第一个 title 视为主标题
        mainTitle = titleElement.innerText.trim();
      }
    }

    // 降级：EPUB2 风格的 <meta name="title" content="...">
    if (mainTitle.isEmpty) {
      mainTitle = _extractEpub2Title(metadata);
    }

    return (mainTitle, subtitle);
  }

  /// 从 EPUB2 风格的 <meta name="title" content="..."> 提取标题
  ///
  /// EPUB2 OPF 中主标题可能以 `<meta name="title" content="主标题"/>` 形式存储，
  /// 而非 dc:title 元素。这种格式在 sigil 生成的 EPUB 中很常见。
  ///
  /// 参数 [metadata] OPF 的 metadata 元素
  /// 返回 title 文本，找不到返回空字符串
  static String _extractEpub2Title(XmlElement metadata) {
    final metas = metadata.findElements('meta', namespace: '*');
    for (final meta in metas) {
      final name = meta.getAttribute('name');
      if (name == 'title') {
        final content = meta.getAttribute('content');
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
    }
    return '';
  }

  /// 获取指定 id 的 refines title-type 值
  ///
  /// 在 metadata 中查找 `<meta refines="#id" property="title-type">` 元素，
  /// 返回其文本内容（如 'main'、'subtitle'），找不到则返回 null
  static String? _getRefinesTitleType(XmlElement metadata, String id) {
    final metas = metadata.findElements('meta', namespace: '*');
    for (final meta in metas) {
      final refines = meta.getAttribute('refines');
      final property = meta.getAttribute('property');
      if (refines == '#$id' && property == 'title-type') {
        return meta.innerText.trim();
      }
    }
    return null;
  }

  /// 读取封面图片字节
  ///
  /// 优先通过 meta name="cover" → manifest item 定位封面，
  /// 找不到时兜底搜索 manifest 中 href 含 "cover" 的图片项。
  ///
  /// 返回 (封面字节, 扩展名)，无封面时返回 (null, null)
  static (Uint8List?, String?) _readCover(
    Archive archive,
    XmlElement metadata,
    XmlElement manifest,
    String opfDir,
  ) {
    // 1. 查找 meta name="cover" 获取封面 item id
    String? coverItemId;
    final metas = metadata.findElements('meta', namespace: '*');
    for (final meta in metas) {
      if (meta.getAttribute('name') == 'cover') {
        coverItemId = meta.getAttribute('content');
        break;
      }
    }

    // 2. 在 manifest 中查找封面 item 的 href
    String? coverHref;
    final items = manifest.findElements('item', namespace: '*');

    if (coverItemId != null) {
      for (final item in items) {
        if (item.getAttribute('id') == coverItemId) {
          coverHref = item.getAttribute('href');
          break;
        }
      }
    }

    // 3. 兜底：搜索 manifest 中 href 含 cover 的图片项
    if (coverHref == null) {
      for (final item in items) {
        final href = (item.getAttribute('href') ?? '').toLowerCase();
        final mediaType = item.getAttribute('media-type') ?? '';
        if (href.contains('cover') &&
            (mediaType == 'image/jpeg' || mediaType == 'image/png')) {
          coverHref = item.getAttribute('href');
          break;
        }
      }
    }

    if (coverHref == null) return (null, null);

    // 4. 读取封面图片字节
    final coverArchivePath = opfDir + coverHref;
    final coverFile = archive.findFile(coverArchivePath);
    if (coverFile == null) return (null, null);

    final coverBytes = Uint8List.fromList(coverFile.content as List<int>);
    // 根据扩展名确定封面格式
    final ext = _getImageExt(coverHref);
    return (coverBytes, ext);
  }

  /// 从文件路径或 href 中提取图片扩展名
  ///
  /// 返回 'png' 或 'jpg'（jpeg 统一为 jpg）
  static String _getImageExt(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'png';
    return 'jpg';
  }

  /// 设置 XML 元素的文本内容
  ///
  /// 清除原有子节点，添加单个文本节点
  static void _setElementText(XmlElement element, String text) {
    element.children
      ..clear()
      ..add(XmlText(text));
  }

  /// 更新或创建 metadata 中的 dc 元素
  ///
  /// 如果元素已存在则更新第一个的文本并删除多余的同类元素；
  /// 如果元素不存在且值非空则创建新元素；
  /// 如果值为空则删除所有同类元素。
  ///
  /// 参数 [metadata] OPF metadata 元素
  /// 参数 [localName] dc 元素本地名
  /// 参数 [value] 要写入的值
  /// 参数 [dcPrefix] dc 命名空间前缀
  static void _updateDcElement(
    XmlElement metadata,
    String localName,
    String value,
    String dcPrefix,
  ) {
    final elements = metadata.findElements(localName, namespace: '*').toList();

    if (elements.isNotEmpty) {
      if (value.isEmpty) {
        // 值为空，删除所有同类元素
        for (final e in elements) {
          e.remove();
        }
      } else {
        // 更新第一个元素的文本，删除多余的
        _setElementText(elements.first, value);
        for (var i = 1; i < elements.length; i++) {
          elements[i].remove();
        }
      }
    } else if (value.isNotEmpty) {
      // 元素不存在但有值，创建新元素并添加到 metadata 末尾
      final newElement = XmlElement.tag(
        '$dcPrefix:$localName',
        children: [XmlText(value)],
      );
      metadata.children.add(newElement);
    }
  }

  /// 更新主标题和副标题（处理 EPUB3 refines 机制）
  ///
  /// 找到带有 title-type=main 的 dc:title 更新主标题，
  /// 找到带有 title-type=subtitle 的 dc:title 更新副标题。
  /// 找不到时创建新的 dc:title 并附带 refines meta。
  /// 值为空时删除对应的元素和 refines meta。
  static void _updateTitles(
    XmlElement metadata,
    String title,
    String subtitle,
    String dcPrefix,
  ) {
    final titles = metadata.findElements('title', namespace: '*').toList();

    // 分类现有 title 元素
    XmlElement? mainTitleElement;
    XmlElement? subtitleElement;
    final extraTitles = <XmlElement>[];

    for (final t in titles) {
      final id = t.getAttribute('id');
      final titleType = id != null ? _getRefinesTitleType(metadata, id) : null;
      if (titleType == 'subtitle') {
        subtitleElement ??= t;
      } else if (titleType == 'main') {
        mainTitleElement ??= t;
      } else {
        // 无 title-type 标记的元素
        if (mainTitleElement == null) {
          mainTitleElement = t;
        } else {
          extraTitles.add(t);
        }
      }
    }

    // 更新主标题
    if (title.isNotEmpty) {
      if (mainTitleElement != null) {
        _setElementText(mainTitleElement, title);
      } else {
        // 创建新的主标题元素及 refines meta
        final titleId = _generateTitleId(metadata, 'title');
        final newTitle = XmlElement.tag(
          '$dcPrefix:title',
          attributes: [XmlAttribute(XmlName.fromString('id'), titleId)],
          children: [XmlText(title)],
        );
        metadata.children.add(newTitle);
        metadata.children.add(_createTitleTypeMeta(titleId, 'main'));
      }
    } else if (mainTitleElement != null) {
      // 主标题为空，删除元素及关联的 refines meta
      final id = mainTitleElement.getAttribute('id');
      if (id != null) _removeRefinesMetas(metadata, id);
      mainTitleElement.remove();
    }

    // 更新副标题
    if (subtitle.isNotEmpty) {
      if (subtitleElement != null) {
        _setElementText(subtitleElement, subtitle);
      } else {
        // 创建新的副标题元素及 refines meta
        final subtitleId = _generateTitleId(metadata, 'subtitle');
        final newSubtitle = XmlElement.tag(
          '$dcPrefix:title',
          attributes: [XmlAttribute(XmlName.fromString('id'), subtitleId)],
          children: [XmlText(subtitle)],
        );
        metadata.children.add(newSubtitle);
        metadata.children.add(_createTitleTypeMeta(subtitleId, 'subtitle'));
      }
    } else if (subtitleElement != null) {
      // 副标题为空，删除元素及关联的 refines meta
      final id = subtitleElement.getAttribute('id');
      if (id != null) _removeRefinesMetas(metadata, id);
      subtitleElement.remove();
    }

    // 删除多余的 title 元素及其 refines meta
    for (final t in extraTitles) {
      final id = t.getAttribute('id');
      if (id != null) _removeRefinesMetas(metadata, id);
      t.remove();
    }
  }

  /// 生成不重复的 title 元素 id
  ///
  /// 参数 [metadata] OPF metadata 元素
  /// 参数 [base] id 基础名称（如 'title'、'subtitle'）
  static String _generateTitleId(XmlElement metadata, String base) {
    final titles = metadata.findElements('title', namespace: '*');
    final existingIds = titles
        .map((e) => e.getAttribute('id'))
        .whereType<String>()
        .toSet();

    final baseId = '$base-id';
    if (!existingIds.contains(baseId)) return baseId;

    var counter = 1;
    while (existingIds.contains('$baseId-$counter')) {
      counter++;
    }
    return '$baseId-$counter';
  }

  /// 创建 title-type refines meta 元素
  ///
  /// 生成 `<meta refines="#id" property="title-type">type</meta>`
  static XmlElement _createTitleTypeMeta(String titleId, String titleType) {
    return XmlElement.tag(
      'meta',
      attributes: [
        XmlAttribute(XmlName.fromString('refines'), '#$titleId'),
        XmlAttribute(XmlName.fromString('property'), 'title-type'),
      ],
      children: [XmlText(titleType)],
    );
  }

  /// 删除指定 id 关联的所有 refines meta 元素
  static void _removeRefinesMetas(XmlElement metadata, String id) {
    final metas = metadata.findElements('meta', namespace: '*').toList();
    for (final meta in metas) {
      if (meta.getAttribute('refines') == '#$id') {
        meta.remove();
      }
    }
  }

  /// 处理封面图片的替换或移除
  ///
  /// 当 [coverPath] 不为空时，将新封面复制到 Images/cover.{ext}，
  /// 更新 manifest item 和 meta name="cover"。
  /// 当 [removeCover] 为 true 时，删除封面图片文件、manifest item 和 meta。
  /// 返回值：若 archive 被重建（删除封面文件）则返回新 archive，否则返回 null。
  static Archive? _processCover({
    required Archive archive,
    required XmlElement metadata,
    required XmlElement manifest,
    required String opfDir,
    String? coverPath,
    bool removeCover = false,
  }) {
    // 查找现有的封面 meta 和 manifest item
    final coverMetas = metadata
        .findElements('meta', namespace: '*')
        .where((m) => m.getAttribute('name') == 'cover')
        .toList();

    String? coverItemId;
    if (coverMetas.isNotEmpty) {
      coverItemId = coverMetas.first.getAttribute('content');
    }

    // 在 manifest 中查找封面 item
    XmlElement? coverItem;
    String? coverHref;
    final items = manifest.findElements('item', namespace: '*').toList();
    if (coverItemId != null) {
      for (final item in items) {
        if (item.getAttribute('id') == coverItemId) {
          coverItem = item;
          coverHref = item.getAttribute('href');
          break;
        }
      }
    }
    // 兜底搜索 href 含 cover 的图片项
    if (coverItem == null) {
      for (final item in items) {
        final href = (item.getAttribute('href') ?? '').toLowerCase();
        final mediaType = item.getAttribute('media-type') ?? '';
        if (href.contains('cover') &&
            (mediaType == 'image/jpeg' || mediaType == 'image/png')) {
          coverItem = item;
          coverHref = item.getAttribute('href');
          coverItemId = item.getAttribute('id');
          break;
        }
      }
    }

    // 移除封面
    if (removeCover) {
      // 删除 manifest 中的 cover item
      coverItem?.remove();
      // 删除 meta name="cover"
      for (final m in coverMetas) {
        m.remove();
      }
      // 同时从 archive 中安全删除封面文件本身（用 removeFiles 重建 archive
      // 避免 archive 包 removeFile 的索引损坏 bug）。仅删除明确属于封面的文件，
      // 防止误删其他被引用的图片。
      if (coverHref != null) {
        final coverArchivePath = opfDir + coverHref;
        final cleanedArchive = EpubImageHelper.removeFiles(archive, {
          coverArchivePath,
        });
        return cleanedArchive;
      }
      return null;
    }

    // 替换封面
    Archive? resultArchive;
    if (coverPath != null) {
      final newCoverBytes = File(coverPath).readAsBytesSync();
      final ext = _getImageExt(coverPath);
      final mediaType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final newCoverHref = 'Images/cover.$ext';
      final newCoverArchivePath = opfDir + newCoverHref;

      // 替换封面文件（使用 addOrReplaceFileSafe 避免 archive 包 _fileMap
      // 索引损坏 bug：removeFile 之后 addFile 在某些路径下会触发 RangeError，
      // 重建 archive 才是安全的做法）
      if (coverHref != null && coverHref != newCoverHref) {
        // 旧封面路径与新封面不同：先安全删除旧文件，再添加新文件
        final oldCoverArchivePath = opfDir + coverHref;
        final cleaned = EpubImageHelper.removeFiles(archive, {
          oldCoverArchivePath,
        });
        resultArchive = EpubImageHelper.addOrReplaceFileSafe(
          cleaned,
          ArchiveFile(newCoverArchivePath, newCoverBytes.length, newCoverBytes),
        );
      } else {
        // 同名或无旧封面：通过 addOrReplaceFileSafe 自动处理重复
        resultArchive = EpubImageHelper.addOrReplaceFileSafe(
          archive,
          ArchiveFile(newCoverArchivePath, newCoverBytes.length, newCoverBytes),
        );
      }

      // 更新或创建 manifest 中的 cover item
      if (coverItem != null) {
        coverItem.setAttribute('href', newCoverHref);
        coverItem.setAttribute('media-type', mediaType);
      } else {
        // 创建新的 manifest item
        final newId = coverItemId ?? 'cover-image';
        final newItem = XmlElement.tag(
          'item',
          attributes: [
            XmlAttribute(XmlName.fromString('id'), newId),
            XmlAttribute(XmlName.fromString('href'), newCoverHref),
            XmlAttribute(XmlName.fromString('media-type'), mediaType),
            // EPUB3 cover-image 属性声明
            XmlAttribute(XmlName.fromString('properties'), 'cover-image'),
          ],
        );
        manifest.children.add(newItem);
        coverItemId = newId;
      }

      // 更新或创建 meta name="cover"
      if (coverMetas.isNotEmpty) {
        coverMetas.first.setAttribute('content', coverItemId!);
      } else {
        final newMeta = XmlElement.tag(
          'meta',
          attributes: [
            XmlAttribute(XmlName.fromString('name'), 'cover'),
            XmlAttribute(XmlName.fromString('content'), coverItemId!),
          ],
        );
        metadata.children.add(newMeta);
      }
    }
    // coverPath == null 且 removeCover == false：仅读取元数据，无文件变更
    return resultArchive;
  }

  /// 确保 mimetype 文件在打包时不被压缩
  ///
  /// EPUB 规范要求 mimetype 文件必须以 STORE 方式（不压缩）存储。
  /// 此方法找到 mimetype 文件并设置 compress 属性为 false。
  static void _ensureMimetypeUncompressed(Archive archive) {
    final mimetype = archive.findFile('mimetype');
    if (mimetype != null) {
      mimetype.compress = false;
    }
  }
}
