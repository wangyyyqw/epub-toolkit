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

    // 确定封面格式
    final coverExt = coverPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final coverMediaType = coverExt == 'png' ? 'image/png' : 'image/jpeg';

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
      r'name="cover"\s+content="([^"]+)"',
    ).firstMatch(opfContent);
    String? existingCoverId;
    if (coverIdMatch != null) {
      existingCoverId = coverIdMatch.group(1);
    }

    // 查找 manifest 中含 cover 的图片项
    String? coverHref;
    String? coverManifestId;
    if (existingCoverId != null) {
      final itemMatch = RegExp(
        r'<item\s+[^>]*id="' +
            RegExp.escape(existingCoverId) +
            r'"[^>]*href="([^"]+)"[^>]*media-type="([^"]+)"',
      ).firstMatch(opfContent);
      if (itemMatch != null) {
        coverHref = itemMatch.group(1);
        coverManifestId = existingCoverId;
      }
    }
    // 降级搜索 manifest 中 href 含 cover 的图片项
    if (coverHref == null) {
      final itemMatch = RegExp(
        r'<item\s+[^>]*href="([^"]*cover[^"]*\.(?:jpg|jpeg|png))"[^>]*media-type="image/(?:jpeg|png)"[^>]*/?>',
        caseSensitive: false,
      ).firstMatch(opfContent);
      if (itemMatch != null) {
        coverHref = itemMatch.group(1);
      }
    }

    // 确定新封面的文件名
    final newCoverName = 'cover.$coverExt';
    final newCoverPath = opfDir + newCoverName;

    // 替换或添加封面文件（使用 replaceFile 避免 removeFile 的索引损坏 bug）
    if (coverHref != null) {
      final oldCoverPath = opfDir + coverHref;
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
      // 替换现有 manifest 项的 href 和 media-type
      opfContent = opfContent.replaceAll(
        RegExp(
          r'<item\s+[^>]*id="' + RegExp.escape(coverManifestId) + r'"[^>]*/?>',
        ),
        '<item id="$coverManifestId" href="$newCoverName" media-type="$coverMediaType"/>',
      );
    } else {
      // 添加新的 manifest 项
      final manifestEnd = opfContent.indexOf('</manifest>');
      if (manifestEnd != -1) {
        opfContent =
            '${opfContent.substring(0, manifestEnd)}'
            '\n    <item id="cover-image" href="$newCoverName" media-type="$coverMediaType"/>'
            '${opfContent.substring(manifestEnd)}';
      }
    }

    // 更新或添加 meta name="cover"
    if (RegExp(r'name="cover"\s+content=').hasMatch(opfContent)) {
      opfContent = opfContent.replaceAll(
        RegExp(r'name="cover"\s+content="[^"]*"'),
        'name="cover" content="cover-image"',
      );
    } else {
      opfContent = opfContent.replaceAll(
        '</metadata>',
        '    <meta name="cover" content="cover-image"/>\n  </metadata>',
      );
    }

    // 写回 OPF 文件（addFile 会自动替换同名文件）
    archive.addFile(
      ArchiveFile(opfPath, opfContent.length, utf8.encode(opfContent)),
    );

    // 保存 EPUB
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
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
      final fullPath = opfDir + href;
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
        ArchiveFile(filePath, newContent.length, utf8.encode(newContent)),
      );
    }

    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }
}
