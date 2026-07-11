import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

/// 下载网络图片操作
///
/// 检测 EPUB 中 HTML 文件引用的网络图片（http/https），
/// 下载到本地并替换引用为本地路径，同时更新 OPF manifest。
class DownloadImagesOperation {
  DownloadImagesOperation._();

  /// 避免大书逐张串行下载，同时不给图片源站施加过高压力。
  static const _maxConcurrentDownloads = 6;

  /// 图片扩展名与 MIME 类型的映射
  static const _extMimeMap = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
    '.svg': 'image/svg+xml',
  };

  /// 合法图片扩展名
  static const _validExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.svg',
  ];

  /// 执行下载网络图片
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) async {
    final archive = await EpubImageHelper.readArchive(epubPath);

    // 1. 查找 OPF 文件和 images 目录
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) {
      return '错误: 找不到 OPF 文件';
    }
    final opfDir = EpubImageHelper.opfDir(opfPath);

    // 优先复用书内已有图片目录，保留原目录的大小写（如 OEBPS/Images/）。
    final imagesDir = _findImagesDir(archive, opfDir);

    // 2. 扫描所有 HTML/XHTML/CSS 文件中的网络图片 URL。
    final htmlFiles = archive.files.where((f) {
      final lower = f.name.toLowerCase();
      return lower.endsWith('.html') ||
          lower.endsWith('.xhtml') ||
          lower.endsWith('.htm');
    }).toList();
    final cssFiles = archive.files
        .where((f) => f.name.toLowerCase().endsWith('.css'))
        .toList();

    final urlSet = <String>{};
    for (final htmlFile in htmlFiles) {
      final content = utf8.decode(
        htmlFile.content as List<int>,
        allowMalformed: true,
      );
      urlSet.addAll(_extractWebImageUrls(content));
    }
    for (final cssFile in cssFiles) {
      final content = utf8.decode(
        cssFile.content as List<int>,
        allowMalformed: true,
      );
      urlSet.addAll(_extractCssImageUrls(content));
    }

    if (urlSet.isEmpty) {
      return '未找到网络图片引用，无需下载。';
    }

    final log = StringBuffer();
    log.writeln('找到 ${urlSet.length} 个网络图片 URL，开始下载...');

    // 3. 下载图片
    final urlToLocal = <String, String>{}; // URL → 本地文件名
    final downloadedImages = <String, Uint8List>{}; // 本地文件名 → 数据
    final usedNames = archive.files
        .where((file) => file.name.startsWith(imagesDir))
        .map((file) => p.basename(file.name))
        .toSet();

    var downloadCount = 0;
    var failCount = 0;

    final client = http.Client();
    try {
      final urls = urlSet.toList(growable: false);
      for (
        var start = 0;
        start < urls.length;
        start += _maxConcurrentDownloads
      ) {
        final batch = urls.skip(start).take(_maxConcurrentDownloads);
        await Future.wait(
          batch.map((url) async {
            try {
              final data = await _downloadImage(client, url);
              if (data == null) {
                failCount++;
                log.writeln('  失败: $url');
                return;
              }

              final localName = _generateLocalFilename(url, data, usedNames);
              urlToLocal[url] = localName;
              downloadedImages[localName] = data;
              usedNames.add(localName);
              downloadCount++;
              log.writeln(
                '  下载: $url → $localName '
                '(${EpubImageHelper.sizeStr(data.length)})',
              );
            } catch (e) {
              failCount++;
              log.writeln('  失败: $url - $e');
            }
          }),
        );

        final completed = (start + _maxConcurrentDownloads).clamp(
          0,
          urls.length,
        );
        log.writeln('  进度: $completed/${urls.length}');
      }
    } finally {
      client.close();
    }

    if (downloadCount == 0) {
      log.writeln('\n所有图片下载失败，未生成新文件。');
      return log.toString();
    }

    // 4. 更新 HTML 引用和 OPF manifest
    for (final htmlFile in htmlFiles) {
      final content = utf8.decode(
        htmlFile.content as List<int>,
        allowMalformed: true,
      );
      final updated = _updateContentReferences(
        content,
        urlToLocal,
        imagesDir,
        htmlFile.name,
      );
      if (updated != content) {
        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile(htmlFile.name, updated.length, utf8.encode(updated)),
        );
      }
    }
    for (final cssFile in cssFiles) {
      final content = utf8.decode(
        cssFile.content as List<int>,
        allowMalformed: true,
      );
      final updated = _updateContentReferences(
        content,
        urlToLocal,
        imagesDir,
        cssFile.name,
      );
      if (updated != content) {
        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile(cssFile.name, updated.length, utf8.encode(updated)),
        );
      }
    }

    // 更新 OPF manifest：在 </manifest> 前插入新 item
    if (opfPath.isNotEmpty) {
      final opfFile = archive.findFile(opfPath);
      if (opfFile != null) {
        final opfContent = utf8.decode(opfFile.content as List<int>);
        final updatedOpf = _updateOpfManifest(
          opfContent,
          downloadedImages.keys.toList(),
          imagesDir,
          opfDir,
        );
        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile(opfPath, updatedOpf.length, utf8.encode(updatedOpf)),
        );
      }
    }

    // 5. 写入下载的图片文件
    for (final entry in downloadedImages.entries) {
      final imgPath = '$imagesDir${entry.key}';
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile(imgPath, entry.value.length, entry.value),
      );
    }

    // 6. 保存
    await EpubImageHelper.saveArchive(archive, outputPath);

    log.writeln('\n下载完成: 成功 $downloadCount 张, 失败 $failCount 张');
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 从 HTML 内容中提取网络图片 URL
  static Set<String> _extractWebImageUrls(String html) {
    final urls = <String>{};

    // 匹配 img/source 的 src 与常见懒加载属性。
    final imgPattern = RegExp(
      r"""<(?:img|source)\b[^>]*?\b(?:src|data-src|data-original|data-lazy-src)\s*=\s*["'](https?://[^"']+)["']""",
      caseSensitive: false,
    );
    for (final match in imgPattern.allMatches(html)) {
      urls.add(match.group(1)!);
    }

    // 匹配 SVG <image href/xlink:href="http...">。
    final imagePattern = RegExp(
      r"""<image\b[^>]*?\b(?:xlink:href|href)\s*=\s*["'](https?://[^"']+)["']""",
      caseSensitive: false,
    );
    for (final match in imagePattern.allMatches(html)) {
      urls.add(match.group(1)!);
    }

    return urls;
  }

  /// 提取样式表中的 background-image 等网络图片。
  static Set<String> _extractCssImageUrls(String css) {
    final urls = <String>{};
    final pattern = RegExp(
      r'''url\(\s*["']?(https?://[^\s'"\)]+)["']?\s*\)''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(css)) {
      urls.add(match.group(1)!);
    }
    return urls;
  }

  /// 下载图片
  ///
  /// 返回图片二进制数据，失败返回 null
  static Future<Uint8List?> _downloadImage(
    http.Client client,
    String url,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await client
            .get(
              Uri.parse(url),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/122.0.0.0 Safari/537.36',
                'Accept':
                    'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              },
            )
            .timeout(const Duration(seconds: 30));

        final data = response.bodyBytes;
        if (response.statusCode == 200 && _isImageResponse(response, data)) {
          return data;
        }

        // 只对临时错误重试，404/403 等明确拒绝不反复请求。
        if (response.statusCode != 429 && response.statusCode < 500) {
          return null;
        }
      } catch (_) {
        // 网络中断和超时可重试。
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return null;
  }

  static bool _isImageResponse(http.Response response, Uint8List data) {
    if (data.isEmpty) return false;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) return true;

    // 一些图床会返回 application/octet-stream，使用文件头兜底校验。
    if (data.length >= 8 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true;
    }
    if (data.length >= 3 &&
        data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF) {
      return true;
    }
    if (data.length >= 6 &&
        ascii
            .decode(data.sublist(0, 6), allowInvalid: true)
            .startsWith('GIF')) {
      return true;
    }
    if (data.length >= 12 &&
        ascii.decode(data.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return true;
    }
    final preview = ascii
        .decode(
          data.sublist(0, data.length.clamp(0, 256).toInt()),
          allowInvalid: true,
        )
        .toLowerCase();
    return preview.contains('<svg');
  }

  /// 生成本地文件名
  ///
  /// 从 URL 提取文件名，校验扩展名，处理重名
  static String _generateLocalFilename(
    String url,
    Uint8List data,
    Set<String> usedNames,
  ) {
    var name = '';

    try {
      final uri = Uri.parse(url);
      name = p.basename(uri.path);
      name = Uri.decodeComponent(name);
    } catch (_) {
      name = '';
    }

    // 文件名为空或过短，用 URL 哈希
    if (name.length < 3) {
      name = 'web_${url.hashCode.toRadixString(16).substring(0, 8)}';
    }

    // 清理非法字符
    name = name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');

    // 校验扩展名
    var ext = p.extension(name).toLowerCase();
    if (!_validExts.contains(ext)) {
      ext = '.jpg'; // 默认扩展名
    }
    name = '${p.basenameWithoutExtension(name)}$ext';

    // 重名处理
    if (usedNames.contains(name)) {
      var counter = 1;
      final baseName = p.basenameWithoutExtension(name);
      while (usedNames.contains('${baseName}_$counter$ext')) {
        counter++;
      }
      name = '${baseName}_$counter$ext';
    }

    return name;
  }

  /// 更新 HTML/CSS 中的网络图片引用为相对于当前文件的本地路径。
  static String _updateContentReferences(
    String content,
    Map<String, String> urlToLocal,
    String imagesDir,
    String sourcePath,
  ) {
    var result = content;

    for (final entry in urlToLocal.entries) {
      final url = entry.key;
      final localName = entry.value;
      final targetPath = '$imagesDir$localName';
      final localPath = p
          .relative(targetPath, from: p.dirname(sourcePath))
          .replaceAll('\\', '/');

      // 替换双引号和单引号引用
      result = result.replaceAll('"$url"', '"$localPath"');
      result = result.replaceAll("'$url'", "'$localPath'");
      result = result.replaceAll('url($url)', 'url($localPath)');

      // URL 编码的情况
      final encoded = Uri.encodeComponent(url);
      if (encoded != url) {
        result = result.replaceAll('"$encoded"', '"$localPath"');
        result = result.replaceAll("'$encoded'", "'$localPath'");
      }
    }

    return result;
  }

  static String _findImagesDir(Archive archive, String opfDir) {
    for (final file in archive.files) {
      final lower = file.name.toLowerCase();
      if (!lower.contains('/images/') && !lower.contains('/image/')) continue;
      final index = file.name.lastIndexOf('/');
      if (index >= 0) return file.name.substring(0, index + 1);
    }
    return '${opfDir}Images/';
  }

  /// 更新 OPF manifest：在 manifest 闭合标签前插入新 item
  static String _updateOpfManifest(
    String opfContent,
    List<String> imageNames,
    String imagesDir,
    String opfDir,
  ) {
    // 计算相对于 OPF 的 images 路径
    final relImagesDir = imagesDir.startsWith(opfDir)
        ? imagesDir.substring(opfDir.length)
        : imagesDir;

    final items = StringBuffer();
    for (final name in imageNames) {
      final ext = p.extension(name).toLowerCase();
      final mime = _extMimeMap[ext] ?? 'image/jpeg';
      final itemId = 'img_${p.basenameWithoutExtension(name)}';
      items.writeln(
        '    <item id="$itemId" href="$relImagesDir$name" '
        'media-type="$mime"/>',
      );
    }

    // 在 </manifest> 前插入
    final manifestEnd = opfContent.toLowerCase().indexOf('</manifest>');
    if (manifestEnd < 0) {
      return opfContent;
    }

    return '${opfContent.substring(0, manifestEnd)}'
        '${items.toString()}'
        '${opfContent.substring(manifestEnd)}';
  }
}
