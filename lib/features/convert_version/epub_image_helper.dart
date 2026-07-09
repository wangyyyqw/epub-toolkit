import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/epub_packer.dart';

/// EPUB 图片处理共享工具类
///
/// 提供 EPUB 内图片文件的遍历、处理、回写和引用更新等通用功能，
/// 供 img_compress 和 img_to_webp 操作共用。
class EpubImageHelper {
  EpubImageHelper._();

  /// 支持的图片扩展名（用于压缩操作）
  static const compressExts = [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.gif',
  ];

  /// 可转 WebP 的图片扩展名（不含 webp 和 gif）
  static const webpConvertExts = ['.jpg', '.jpeg', '.png', '.bmp'];

  /// MIME 类型映射
  static const mimeMap = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
    '.gif': 'image/gif',
  };

  /// 格式化文件大小
  static String sizeStr(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }

  /// 读取 EPUB 为 Archive 对象
  static Future<Archive> readArchive(String epubPath) async {
    final bytes = await File(epubPath).readAsBytes();
    return ZipDecoder().decodeBytes(bytes);
  }

  /// 查找 EPUB 中的 OPF 文件路径
  static String? findOpfPath(Archive archive) {
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith('.opf')) {
        return file.name;
      }
    }
    return null;
  }

  /// 获取 OPF 文件所在目录
  static String opfDir(String opfPath) {
    final idx = opfPath.lastIndexOf('/');
    return idx > 0 ? opfPath.substring(0, idx + 1) : '';
  }

  /// 遍历 EPUB 中的图片文件
  ///
  /// [extensions] 要匹配的扩展名列表
  /// 返回图片文件的 ArchiveFile 列表
  static List<ArchiveFile> findImages(
    Archive archive,
    List<String> extensions,
  ) {
    return archive.files.where((f) {
      if (f.name.isEmpty) return false;
      final ext = f.name.toLowerCase();
      return extensions.any((e) => ext.endsWith(e));
    }).toList();
  }

  /// 读取 ArchiveFile 的二进制内容
  static Uint8List readBytes(ArchiveFile file) {
    return Uint8List.fromList(file.content as List<int>);
  }

  /// 将处理后的 EPUB 保存到文件
  ///
  /// 确保 mimetype 文件为第一个且不压缩（符合 EPUB 规范）。
  /// EPUB 规范要求：
  /// 1. mimetype 必须是 ZIP 中的第一个文件
  /// 2. mimetype 必须以 STORE 方式存储（不压缩）
  /// 3. mimetype 内容为 "application/epub+zip"
  static Future<void> saveArchive(
    Archive archive,
    String outputPath, {
    Map<String, String>? renameMap,
  }) async {
    // 如果有文件重命名，更新引用
    if (renameMap != null && renameMap.isNotEmpty) {
      _updateReferences(archive, renameMap);
    }

    // 确保 mimetype 文件为第一个且不压缩（可能返回新的 Archive 对象）
    archive = _ensureMimetypeFirstAndUncompressed(archive);

    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }

  /// 确保 mimetype 文件是 ZIP 中的第一个文件且不压缩
  ///
  /// EPUB 规范要求 mimetype 文件必须：
  /// 1. 是 ZIP 归档中的第一个文件
  /// 2. 以 STORE 方式存储（不压缩）
  ///
  /// 注意：archive.files 返回 UnmodifiableListView，不支持 insert/removeAt，
  /// 因此通过重建 Archive 来实现文件重排序。
  static Archive _ensureMimetypeFirstAndUncompressed(Archive archive) {
    // 查找 mimetype 文件（可能在根目录或带路径）
    ArchiveFile? mimetypeFile;
    int? mimetypeIndex;
    for (var i = 0; i < archive.files.length; i++) {
      final f = archive.files[i];
      if (f.name == 'mimetype' || f.name.endsWith('/mimetype')) {
        mimetypeFile = f;
        mimetypeIndex = i;
        break;
      }
    }

    if (mimetypeFile == null) {
      // mimetype 不存在，创建一个并放到首位
      final content = utf8.encode('application/epub+zip');
      mimetypeFile = ArchiveFile('mimetype', content.length, content)
        ..compress = false;
      final newArchive = Archive();
      newArchive.comment = archive.comment;
      newArchive.addFile(mimetypeFile);
      for (final file in archive.files) {
        if (file.name.isEmpty) continue;
        newArchive.addFile(
          ArchiveFile(file.name, file.size, file.content as List<int>)
            ..compress = file.compress,
        );
      }
      return newArchive;
    }

    // 设置为不压缩
    mimetypeFile.compress = false;

    // 如果 mimetype 已经是第一个文件，无需重排
    if (mimetypeIndex == null || mimetypeIndex == 0) {
      return archive;
    }

    // mimetype 不是第一个文件，通过重建 Archive 来重排序
    // （archive.files 是 UnmodifiableListView，不支持 insert/removeAt）
    final newArchive = Archive();
    newArchive.comment = archive.comment;
    newArchive.addFile(
      ArchiveFile(
        mimetypeFile.name,
        mimetypeFile.size,
        mimetypeFile.content as List<int>,
      )..compress = false,
    );
    for (var i = 0; i < archive.files.length; i++) {
      if (i == mimetypeIndex) continue;
      final file = archive.files[i];
      if (file.name.isEmpty) continue;
      newArchive.addFile(
        ArchiveFile(file.name, file.size, file.content as List<int>)
          ..compress = file.compress,
      );
    }
    return newArchive;
  }

  /// 替换或添加文件到 Archive
  ///
  /// archive 包的 addFile() 已内置同名替换功能（通过 _fileMap 索引实现就地替换）。
  /// 注意：不能先调用 removeFile 再 addFile，因为 archive 包的 removeFile
  /// 不更新 _fileMap 中其他文件的索引，会导致后续 addFile 抛出 RangeError。
  ///
  /// 本方法对 addFile 做了防御式处理：当 archive 内部 _fileMap 因先前的
  /// removeFile/removeAt 而索引漂移时，addFile 会抛 RangeError；此时我们
  /// 通过 archive 的私有 _fileMap 字段（同包内可见）进行清理后重试。
  /// 这样调用方无需感知 archive 包索引 bug，所有现有调用代码无需修改。
  static void addOrReplaceFile(Archive archive, ArchiveFile newFile) {
    try {
      archive.addFile(newFile);
      return;
    } on RangeError {
      // 继续走修复逻辑
    } catch (_) {
      // 其他异常也走修复逻辑（防御式）
    }

    // 修复路径：通过 archive 私有 _fileMap 重建（archive 包内部有 _fileMap
    // 字段存储 filename -> index 映射）。当 addFile 抛 RangeError 时，
    // 通常是 _fileMap 中残留了已被删除的条目。最简单的修复是清空 _fileMap
    // 并基于当前 files 列表重建。
    _repairFileMap(archive);

    try {
      archive.addFile(newFile);
    } on RangeError {
      // 若仍失败，升级为更明确异常，提示用户重新实现 addOrReplaceFile
      throw StateError(
        'archive 索引无法自动修复，建议改用 addOrReplaceFileSafe() '
        '（返回新 Archive 对象，调用方接住并继续使用）。'
        '文件: ${newFile.name}',
      );
    }
  }

  /// 安全版本的 addOrReplaceFile：返回（可能）新的 Archive 对象
  ///
  /// 当 [addOrReplaceFile] 因 archive 内部 _fileMap 损坏而无法原地修复时，
  /// 调用方可使用本方法：返回一个全新的 Archive 实例，调用方应使用返回值
  /// 继续后续操作（用新 archive 替换原 archive 变量）。
  ///
  /// 推荐在循环中大量调用 addOrReplaceFile 时使用本方法。
  static Archive addOrReplaceFileSafe(Archive archive, ArchiveFile newFile) {
    try {
      archive.addFile(newFile);
      return archive;
    } on RangeError {
      // 重建
    } catch (_) {
      // 重建
    }
    return _rebuildWithReplacement(archive, newFile);
  }

  /// 重建 archive 并替换/添加目标文件
  static Archive _rebuildWithReplacement(Archive archive, ArchiveFile newFile) {
    final newArchive = Archive();
    newArchive.comment = archive.comment;
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      if (file.name == newFile.name) continue; // 跳过旧版本
      final cloned = ArchiveFile(
        file.name,
        file.size,
        file.content as List<int>,
      )..compress = file.compress;
      newArchive.addFile(cloned);
    }
    newArchive.addFile(newFile);
    return newArchive;
  }

  /// 尝试通过清理 _fileMap 修复 archive 索引
  ///
  /// archive 包内部有一个 _fileMap 字段（`Map<String, ArchiveFile>`），
  /// 当 removeFile 之后该 map 未同步清理，会导致 addFile 抛 RangeError。
  /// 我们通过反射读取并清理该字段。
  static void _repairFileMap(Archive archive) {
    try {
      // archive 3.6.x 中 _fileMap 是私有 Map<String, ArchiveFile>
      // 通过 noSuchMethod / dynamic 调用访问
      final dynamic dyn = archive;
      final fileMap = dyn._fileMap;
      if (fileMap is Map) {
        // 清空 _fileMap 让 archive.addFile 重建索引
        fileMap.clear();
      }
    } catch (_) {
      // 反射失败也无所谓，下一步 addFile 会失败抛 StateError 提示
    }
  }

  /// 替换 Archive 中的文件内容（可同时重命名）
  ///
  /// 如果 [newName] 与 [oldName] 相同，直接用 addFile 就地替换。
  /// 如果不同，通过索引运算符 archive[i] = newFile 重命名，
  /// 该运算符会正确更新 _fileMap（移除旧名、添加新名），避免索引损坏。
  static void replaceFile(
    Archive archive,
    String oldName,
    String newName,
    Uint8List data,
  ) {
    if (oldName == newName) {
      archive.addFile(ArchiveFile(newName, data.length, data));
      return;
    }
    // 通过索引查找旧文件（不依赖 findFile，避免 _fileMap 可能过期）
    for (var i = 0; i < archive.files.length; i++) {
      if (archive.files[i].name == oldName) {
        archive[i] = ArchiveFile(newName, data.length, data);
        return;
      }
    }
    // 未找到旧文件，直接添加新文件
    archive.addFile(ArchiveFile(newName, data.length, data));
  }

  /// 重建 Archive 对象，修复 _fileMap 索引损坏
  ///
  /// archive 包的 removeFile/removeAt 方法在删除文件后不更新 _fileMap
  /// 中其他文件的索引，导致后续 addFile/findFile 使用过期索引而抛出 RangeError。
  /// 此方法通过创建新 Archive 来重建正确的索引映射。
  static Archive rebuildArchive(Archive archive) {
    final newArchive = Archive();
    newArchive.comment = archive.comment;
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      final newFile = ArchiveFile(
        file.name,
        file.size,
        file.content as List<int>,
      )..compress = file.compress;
      newArchive.addFile(newFile);
    }
    return newArchive;
  }

  /// 安全地从 Archive 中移除多个文件
  ///
  /// 通过重建 Archive 来避免 removeFile 的索引损坏 bug。
  /// [namesToRemove] 要移除的文件名集合
  static Archive removeFiles(Archive archive, Set<String> namesToRemove) {
    final newArchive = Archive();
    newArchive.comment = archive.comment;
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      if (namesToRemove.contains(file.name)) continue;
      final newFile = ArchiveFile(
        file.name,
        file.size,
        file.content as List<int>,
      )..compress = file.compress;
      newArchive.addFile(newFile);
    }
    return newArchive;
  }

  /// 更新 EPUB 中的文件引用（OPF/XHTML/HTML/CSS/NCX）
  ///
  /// [renameMap] 旧文件名 → 新文件名（仅 basename）
  static void _updateReferences(
    Archive archive,
    Map<String, String> renameMap,
  ) {
    // 构建 basename 映射和扩展名变更映射
    final basenameMap = <String, String>{};
    final extChangeMap = <String, (String, String, String)>{};

    for (final entry in renameMap.entries) {
      final oldBn = p.basename(entry.key);
      final newBn = p.basename(entry.value);
      basenameMap[oldBn] = newBn;

      final oldExt = p.extension(oldBn).toLowerCase();
      final newExt = p.extension(newBn).toLowerCase();
      if (oldExt != newExt) {
        extChangeMap[oldBn] = (newBn, oldExt, newExt);
      }
    }

    // 遍历需要更新引用的文本文件
    // 先快照 file 列表，避免循环中 archive.addFile() 触发 ConcurrentModificationError
    final filesToUpdate = <ArchiveFile>[];
    for (final file in archive.files) {
      if (file.name.isEmpty) continue;
      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.opf') &&
          !lowerName.endsWith('.xhtml') &&
          !lowerName.endsWith('.html') &&
          !lowerName.endsWith('.css') &&
          !lowerName.endsWith('.ncx')) {
        continue;
      }
      filesToUpdate.add(file);
    }
    for (final file in filesToUpdate) {
      if (file.name.isEmpty) continue;
      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.opf') &&
          !lowerName.endsWith('.xhtml') &&
          !lowerName.endsWith('.html') &&
          !lowerName.endsWith('.css') &&
          !lowerName.endsWith('.ncx')) {
        continue;
      }

      var content = utf8.decode(file.content as List<int>);
      var modified = false;
      // 替换文件名引用
      for (final entry in basenameMap.entries) {
        final oldBn = entry.key;
        final newBn = entry.value;
        // 直接匹配 basename
        if (content.contains(oldBn)) {
          content = content.replaceAll(oldBn, newBn);
          modified = true;
        }
        // URL 编码的 basename
        final encoded = Uri.encodeComponent(oldBn);
        if (encoded != oldBn && content.contains(encoded)) {
          content = content.replaceAll(encoded, Uri.encodeComponent(newBn));
          modified = true;
        }
      }

      // 更新 media-type（仅针对 OPF 文件中的 <item media-type="..." href="..."> 元素）
      for (final entry in extChangeMap.entries) {
        final (newBn, oldExt, newExt) = entry.value;
        final oldMime = mimeMap[oldExt];
        final newMime = mimeMap[newExt];
        if (oldMime == null || newMime == null || oldMime == newMime) continue;
        if (!lowerName.endsWith('.opf')) continue; // 只处理 OPF 文件

        // 用 XML 解析精确替换 item 元素的 media-type
        try {
          final doc = XmlDocument.parse(content);
          var opfModified = false;
          for (final item in doc.findAllElements('item')) {
            final href = item.getAttribute('href');
            if (href == null) continue;
            final hrefBase = p.basename(href);
            // 匹配：在 extChangeMap 中、且当前 href 的 basename 与新名相同
            if (hrefBase == newBn &&
                item.getAttribute('media-type') == oldMime) {
              item.setAttribute('media-type', newMime);
              opfModified = true;
            }
          }
          if (opfModified) {
            content = doc.toXmlString(pretty: true, indent: '  ');
            modified = true;
          }
        } catch (e) {
          // XML 解析失败时回退到原来的简单替换
          if (content.contains(oldMime) && content.contains(newBn)) {
            content = content.replaceAll(oldMime, newMime);
            modified = true;
          }
        }
      }

      if (modified) {
        addOrReplaceFile(
          archive,
          ArchiveFile(file.name, content.length, utf8.encode(content)),
        );
      }
    }
  }

  /// 检查当前平台是否支持 WebP 编码
  ///
  /// flutter_image_compress 仅在 Android 和 iOS 上支持 WebP 编码
  static bool get supportsWebPEncoding => Platform.isAndroid || Platform.isIOS;
}
