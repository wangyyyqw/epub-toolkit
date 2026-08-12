import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';
import 'epub_packer.dart';

/// EPUB 读写封装
///
/// 提供统一的 EPUB 加载、元数据读取、章节读取、文件操作和保存接口。
/// 内部使用 epubx 库处理 EPUB 解析，archive 库处理 ZIP 打包。
class EpubService {
  EpubService._();

  /// 从文件路径加载完整 EPUB（含所有内容和封面）
  static Future<EpubBook> loadBook(String path) async {
    final bytes = await File(path).readAsBytes();
    return await EpubReader.readBook(bytes);
  }

  /// 从文件路径快速加载 EPUB 元数据（不读取全部内容，速度快）
  static Future<EpubBookRef> openBook(String path) async {
    final bytes = await File(path).readAsBytes();
    return await EpubReader.openBook(bytes);
  }

  /// 获取 EPUB 的 OPF 文件原始内容
  ///
  /// [path] EPUB 文件路径
  /// 返回格式化后的 OPF XML 字符串
  static Future<String> readOpfContent(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 找到 container.xml 获取 OPF 路径
    const containerPath = 'META-INF/container.xml';
    final containerFile = archive.findFile(containerPath);
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 META-INF/container.xml');
    }

    final containerXml = utf8.decode(containerFile.content as List<int>);
    // 解析 container.xml 找到 OPF 路径
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
    ).firstMatch(containerXml);
    if (opfPathMatch == null) {
      throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
    }

    final opfPath = opfPathMatch.group(1)!;
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件 $opfPath');
    }

    return utf8.decode(opfFile.content as List<int>);
  }

  /// 替换 EPUB 封面图片
  ///
  /// [epubPath] EPUB 文件路径
  /// [coverPath] 新封面图片路径
  /// [outputPath] 输出 EPUB 路径
  static Future<void> replaceCover({
    required String epubPath,
    required String coverPath,
    required String outputPath,
  }) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final coverBytes = await File(coverPath).readAsBytes();

    // 确定封面格式（按真实扩展名，png/jpg/jpeg/webp/gif/bmp）
    final coverPathLower = coverPath.toLowerCase();
    final coverExt = coverPathLower.endsWith('.png')
        ? 'png'
        : coverPathLower.endsWith('.jpeg') || coverPathLower.endsWith('.jpg')
            ? 'jpg'
            : coverPathLower.endsWith('.webp')
                ? 'webp'
                : coverPathLower.endsWith('.gif')
                    ? 'gif'
                    : coverPathLower.endsWith('.bmp')
                        ? 'bmp'
                        : 'jpg';

    // 找到 OPF 文件路径
    const containerPath = 'META-INF/container.xml';
    final containerFile = archive.findFile(containerPath);
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 container.xml');
    }
    final containerXml = utf8.decode(containerFile.content as List<int>);
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
    ).firstMatch(containerXml);
    if (opfPathMatch == null) {
      throw Exception('EPUB 结构异常：无法确定 OPF 路径');
    }
    final opfPath = opfPathMatch.group(1)!;
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // 读取 OPF 内容
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件');
    }
    var opfContent = utf8.decode(opfFile.content as List<int>);

    // 查找现有封面在 manifest 中的 id 和 href
    final coverIdMatch = RegExp(
      r'\bname\s*=\s*"cover"\s+content\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(opfContent);
    String? existingCoverId;
    if (coverIdMatch != null) {
      existingCoverId = coverIdMatch.group(1);
    }

    // 查找 manifest 中含 cover 的图片项
    String? coverHref;
    String? coverManifestId;
    if (existingCoverId != null) {
      final itemMatch = _findManifestItem(opfContent, id: existingCoverId);
      if (itemMatch != null) {
        coverHref = itemMatch.href;
        coverManifestId = existingCoverId;
      }
    }
    // 降级搜索 manifest 中 href 含 cover 的图片项
    if (coverHref == null) {
      final itemMatch = _findManifestItem(opfContent, hrefContainsCover: true);
      if (itemMatch != null) {
        coverHref = itemMatch.href;
        coverManifestId = itemMatch.id;
      }
    }

    // 确定新封面的文件名与 media-type（按真实扩展名映射，避免 webp/gif 被当 jpg 写入）
    final coverMediaType = switch (coverExt) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
    final newCoverName = 'cover.$coverExt';
    final newCoverPath = opfDir + newCoverName;

    // 替换或添加封面文件（使用 replaceFile 避免 removeFile 的索引损坏 bug）
    if (coverHref != null) {
      final oldCoverPath = opfDir + Uri.decodeFull(coverHref);
      EpubImageHelper.replaceFile(
        archive,
        oldCoverPath,
        newCoverPath,
        coverBytes,
      );
    } else {
      archive.addFile(ArchiveFile(newCoverPath, coverBytes.length, coverBytes));
    }

    // 更新 OPF 中的 manifest
    if (coverManifestId != null) {
      // 只更新 href/media-type，保留 properties 等其他属性
      opfContent = _updateManifestItem(
        opfContent,
        coverManifestId,
        newName: newCoverName,
        mediaType: coverMediaType,
      );
    } else {
      // 添加新的 manifest 项
      final manifestEnd =
          RegExp(r'</[Mm][Aa][Nn][Ii][Ff][Ee][Ss][Tt]\s*>').firstMatch(opfContent);
      if (manifestEnd != null) {
        opfContent =
            '${opfContent.substring(0, manifestEnd.start)}'
            '\n    <item id="cover-image" href="$newCoverName" media-type="$coverMediaType"/>'
            '${opfContent.substring(manifestEnd.start)}';
      }
    }

    // 更新或添加 meta name="cover"（属性顺序无关）
    final coverMeta = RegExp(
      r'<meta\b[^>]*\bname\s*=\s*"cover"[^>]*>',
      caseSensitive: false,
    ).firstMatch(opfContent);
    if (coverMeta != null) {
      opfContent = opfContent.replaceAllMapped(
        RegExp(r'<meta\b[^>]*\bname\s*=\s*"cover"[^>]*>',
            caseSensitive: false),
        (m) {
          var tag = m.group(0)!;
          if (tag.contains(RegExp(r'\bcontent\s*=', caseSensitive: false))) {
            tag = tag.replaceAllMapped(
              RegExp(r'\bcontent\s*=\s*"[^"]*"', caseSensitive: false),
              (_) => 'content="cover-image"',
            );
          } else {
            tag = tag.replaceFirst(
              RegExp(r'\s*/?>\s*$'),
              ' content="cover-image"/>',
            );
          }
          return tag;
        },
      );
    } else {
      opfContent = opfContent.replaceAllMapped(
        RegExp(r'</[Mm][Ee][Tt][Aa][Dd][Aa][Tt][Aa]\s*>'),
        (m) => '    <meta name="cover" content="cover-image"/>\n  ${m.group(0)}',
      );
    }

    // 写回 OPF 文件（addFile 会自动替换同名文件）
    archive.addFile(
      ArchiveFile(opfPath, utf8.encode(opfContent).length, utf8.encode(opfContent)),
    );

    // 保存 EPUB
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }

  /// 在 OPF manifest 中查找 item 元素（属性顺序无关）
  ///
  /// [id] 按 id 精确匹配
  /// [hrefContainsCover] href 中含 "cover" 且为图片
  static ({String id, String href, String mediaType})? _findManifestItem(
    String opfContent, {
    String? id,
    bool hrefContainsCover = false,
  }) {
    final itemPattern = RegExp(r'<item\b[^>]*>', caseSensitive: false);
    for (final match in itemPattern.allMatches(opfContent)) {
      final tag = match.group(0)!;
      if (tag.contains('</item')) continue; // 跳过闭合标签起点
      if (id != null) {
        final idMatch =
            RegExp(r'\bid\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(tag);
        if (idMatch == null || idMatch.group(1) != id) continue;
      }
      final hrefMatch =
          RegExp(r'\bhref\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(tag);
      if (hrefMatch == null) continue;
      final href = hrefMatch.group(1)!;
      if (hrefContainsCover) {
        final isCoverImage = RegExp(
          r'cover[^"]*\.(?:jpg|jpeg|png|webp|gif|bmp)',
          caseSensitive: false,
        ).hasMatch(href);
        if (!isCoverImage) continue;
      }
      final mediaType = RegExp(
        r'\bmedia-type\s*=\s*"([^"]*)"',
        caseSensitive: false,
      ).firstMatch(tag)?.group(1) ?? '';
      return (id: id ?? '', href: href, mediaType: mediaType);
    }
    return null;
  }

  /// 更新 manifest 中指定 id 的 item 的 href/media-type（保留其他属性）
  static String _updateManifestItem(
    String opfContent,
    String itemId, {
    required String newName,
    required String mediaType,
  }) {
    return opfContent.replaceAllMapped(
      RegExp(
        r'<item\b[^>]*\bid="' + RegExp.escape(itemId) + r'"[^>]*>',
        caseSensitive: false,
      ),
      (m) {
        var tag = m.group(0)!;
        if (tag.contains('</item')) return tag;
        final selfClosing = tag.endsWith('/>');
        tag = tag.replaceFirst(RegExp(r'\s*/>$'), '>');
        tag = tag.replaceAllMapped(
          RegExp(r'\bhref\s*=\s*"[^"]*"', caseSensitive: false),
          (_) => 'href="$newName"',
        );
        if (tag.contains(RegExp(r'\bmedia-type\s*=', caseSensitive: false))) {
          tag = tag.replaceAllMapped(
            RegExp(r'\bmedia-type\s*=\s*"[^"]*"', caseSensitive: false),
            (_) => 'media-type="$mediaType"',
          );
        } else {
          tag = tag.replaceFirst(
            RegExp(r'\s*>\s*$'),
            ' media-type="$mediaType">',
          );
        }
        return selfClosing ? '$tag />' : tag;
      },
    );
  }

  /// 获取 EPUB 中所有 XHTML 文件的内容（按 spine 顺序）
  ///
  /// 返回 `List<MapEntry<文件名, HTML内容>>`
  static Future<List<MapEntry<String, String>>> readAllHtml(String path) async {
    final book = await loadBook(path);
    final result = <MapEntry<String, String>>[];
    if (book.Content?.Html != null) {
      book.Content!.Html!.forEach((key, file) {
        result.add(MapEntry(file.FileName ?? key, file.Content ?? ''));
      });
    }
    return result;
  }

  /// 中文安全版的 readAllHtml：直接读 OPF manifest 解析 XHTML，
  /// 避免 epubx 库对中文文件名触发 `Uri.decodeFull` 的 Illegal percent encoding 错误。
  ///
  /// 返回 `List<MapEntry<书内路径, HTML内容>>`
  static Future<List<MapEntry<String, String>>> readAllHtmlSafe(
    String path,
  ) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 定位 OPF
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 META-INF/container.xml');
    }
    final containerXml = utf8.decode(containerFile.content as List<int>);
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
    ).firstMatch(containerXml);
    if (opfPathMatch == null) {
      throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
    }
    final opfPath = opfPathMatch.group(1)!;
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // 读 OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件');
    }
    final opfContent = utf8.decode(opfFile.content as List<int>);

    // 解析 manifest 项：收集 XHTML/HTML/HTM 的 id → href
    final manifestItems = <String, String>{}; // id → href
    try {
      final doc = xml.XmlDocument.parse(opfContent);
      for (final item in doc.findAllElements('item', namespace: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (id.isEmpty || href.isEmpty) continue;
        if (mediaType.contains('html') || mediaType.contains('xhtml')) {
          manifestItems[id] = href;
        }
      }
    } catch (_) {
      // 解析失败则降级为扫所有 HTML 文件
    }

    // 解析 spine 顺序
    final spineOrder = <String>[];
    try {
      final doc = xml.XmlDocument.parse(opfContent);
      for (final itemref in doc.findAllElements('itemref', namespace: '*')) {
        final idref = itemref.getAttribute('idref') ?? '';
        if (idref.isNotEmpty) spineOrder.add(idref);
      }
    } catch (_) {}

    final result = <MapEntry<String, String>>[];

    // 按 spine 顺序解析
    for (final id in spineOrder) {
      final href = manifestItems[id];
      if (href == null) continue;
      final fullPath = resolveInnerPath(opfDir, href);
      if (fullPath.isEmpty) continue;
      final file = archive.findFile(fullPath);
      if (file == null) continue;
      final content = utf8.decode(file.content as List<int>);
      result.add(MapEntry(fullPath, content));
    }

    // 若 spine 为空则降级为所有 HTML 文件
    if (result.isEmpty) {
      for (final f in archive.files) {
        if (f.name.isEmpty) continue;
        final lower = f.name.toLowerCase();
        if (lower.endsWith('.html') ||
            lower.endsWith('.xhtml') ||
            lower.endsWith('.htm')) {
          final content = utf8.decode(f.content as List<int>);
          result.add(MapEntry(f.name, content));
        }
      }
    }

    return result;
  }

  /// 将 OPF 目录 + manifest href 解析为 ZIP 内完整路径
  ///
  /// 处理 URL 编码(%20/中文文件名)、./、../、以 / 开头的绝对路径
  /// 和 #fragment(仅 href 引用,zip 内路径无 fragment)。
  static String resolveInnerPath(String opfDir, String href) {
    var h = href;
    final fragIdx = h.indexOf('#');
    if (fragIdx >= 0) h = h.substring(0, fragIdx);
    if (h.isEmpty) return '';
    try {
      h = Uri.decodeFull(h);
    } catch (_) {
      // 解码失败保留原文
    }
    final combined = h.startsWith('/') ? h : '$opfDir$h';
    final parts = <String>[];
    for (final part in combined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  /// 将 EPUB 保存到指定路径
  static Future<void> saveBook(EpubBook book, String path) async {
    final bytes = EpubWriter.writeBook(book);
    await File(path).writeAsBytes(bytes!);
  }

  /// 获取 EPUB 内部文件列表
  ///
  /// 返回 ZIP 内所有文件的路径列表
  static Future<List<String>> listFiles(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.files.map((f) => f.name).where((n) => n.isNotEmpty).toList();
  }

  /// 读取 EPUB ZIP 中指定路径的文件内容
  static Future<String> readFileInEpub(
    String epubPath,
    String innerPath,
  ) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile(innerPath);
    if (file == null) {
      throw Exception('文件 $innerPath 在 EPUB 中不存在');
    }
    return utf8.decode(file.content as List<int>);
  }

  /// 修改 EPUB 内部指定文件并重新打包保存
  ///
  /// [epubPath] 原始 EPUB 路径
  /// [modifications] 要修改的文件路径 → 新内容
  /// [outputPath] 输出路径
  static Future<void> modifyAndSave({
    required String epubPath,
    required Map<String, String> modifications,
    required String outputPath,
  }) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in modifications.entries) {
      final filePath = entry.key;
      final newContent = entry.value;

      // addFile 会自动替换同名文件，无需先移除
      archive.addFile(
        ArchiveFile(filePath, utf8.encode(newContent).length, utf8.encode(newContent)),
      );
    }

    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }
}
