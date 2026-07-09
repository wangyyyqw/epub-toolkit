import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

/// WebP 转图片操作
///
/// 将 EPUB 中的 WebP 图片转换为 JPEG 或 PNG 格式：
/// - 有透明通道的 WebP → PNG
/// - 无透明通道的 WebP → JPEG
///
/// 使用 image 包的 WebP 解码器（纯 Dart，全平台支持）。
/// 转换后自动更新 OPF/HTML/CSS 中的引用和 media-type。
class WebpToImgOperation {
  WebpToImgOperation._();

  /// 执行 WebP 转图片
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
    final webpFiles = archive.files.where((f) {
      if (f.name.isEmpty) return false;
      return f.name.toLowerCase().endsWith('.webp');
    }).toList();

    if (webpFiles.isEmpty) {
      return '未找到 WebP 图片，无需转换。';
    }

    var convertedCount = 0;
    var errorCount = 0;
    final renameMap = <String, String>{};
    final log = StringBuffer();

    log.writeln('找到 ${webpFiles.length} 张 WebP 图片，开始转换...');

    for (final webpFile in webpFiles) {
      final arcname = webpFile.name;
      final originalData = EpubImageHelper.readBytes(webpFile);

      try {
        // 解码 WebP
        final decoded = img.decodeWebP(originalData);
        if (decoded == null) {
          errorCount++;
          log.writeln('  错误: $arcname - WebP 解码失败');
          continue;
        }

        // 根据是否有透明通道选择目标格式
        final hasAlpha = _hasTransparency(decoded);
        final Uint8List encoded;
        final String newExt;

        if (hasAlpha) {
          // 有透明 → PNG
          encoded = Uint8List.fromList(img.encodePng(decoded, level: 9));
          newExt = 'png';
        } else {
          // 无透明 → JPEG
          encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
          newExt = 'jpg';
        }

        // 确定新文件名
        final newArcname = '${p.withoutExtension(arcname)}.$newExt';
        renameMap[arcname] = newArcname;

        // 替换文件
        EpubImageHelper.replaceFile(archive, arcname, newArcname, encoded);

        convertedCount++;
        log.writeln(
          '  $arcname → ${p.basename(newArcname)} '
          '(${EpubImageHelper.sizeStr(originalData.length)} → '
          '${EpubImageHelper.sizeStr(encoded.length)})',
        );
      } catch (e) {
        errorCount++;
        log.writeln('  错误: $arcname - $e');
      }
    }

    if (convertedCount == 0) {
      return '未能转换任何 WebP 图片。$log';
    }

    // 保存（自动更新引用）
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: renameMap,
    );

    log.writeln('\n转换完成: 转换 $convertedCount 张, 错误 $errorCount 张');
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 检查图片是否有透明像素
  static bool _hasTransparency(img.Image image) {
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (img.getAlpha(pixel) < 255) {
          return true;
        }
      }
    }
    return false;
  }
}
