import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

/// 图片压缩操作
///
/// 对 EPUB 中的图片进行质量压缩：
/// - JPEG：按质量参数重新编码
/// - PNG 有透明：量化为 PNG-8 二值透明
/// - PNG 无透明：可选转为 JPG
/// - BMP：转为 JPG
/// - WebP/GIF：跳过
///
/// 压缩后若体积未减小则保留原图。
class ImgCompressOperation {
  ImgCompressOperation._();

  /// 执行图片压缩
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// [jpegQuality] JPEG 压缩质量（1-100，默认 85）
  /// [pngToJpg] 是否将无透明 PNG 转为 JPG（默认 true）
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    int jpegQuality = 85,
    bool pngToJpg = true,
  }) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(
      archive,
      EpubImageHelper.compressExts,
    );

    var processedCount = 0;
    var skipCount = 0;
    var errorCount = 0;
    var totalSaved = 0;
    final renameMap = <String, String>{};
    final log = StringBuffer();

    log.writeln('找到 ${images.length} 张图片，开始压缩...');

    for (final imageFile in images) {
      final arcname = imageFile.name;
      final ext = p.extension(arcname).toLowerCase();
      final originalData = EpubImageHelper.readBytes(imageFile);
      final originalSize = originalData.length;

      try {
        final result = _processImage(
          originalData,
          arcname,
          ext,
          jpegQuality: jpegQuality,
          pngToJpg: pngToJpg,
        );

        if (result == null) {
          // 跳过（GIF/WebP 或已优化）
          skipCount++;
          log.writeln('  跳过: $arcname (不支持或已优化)');
          continue;
        }

        final newData = result.data;
        final newExt = result.newExt;

        if (newData.length >= originalSize) {
          // 压缩后更大，保留原图
          skipCount++;
          log.writeln('  跳过: $arcname (压缩后无改善)');
          continue;
        }

        final saved = originalSize - newData.length;
        totalSaved += saved;
        processedCount++;

        // 确定新文件名
        final newArcname = ext != '.$newExt'
            ? '${p.withoutExtension(arcname)}.$newExt'
            : arcname;

        if (newArcname != arcname) {
          renameMap[arcname] = newArcname;
        }

        // 替换文件
        EpubImageHelper.replaceFile(archive, arcname, newArcname, newData);

        final reduction = (saved / originalSize * 100).toStringAsFixed(1);
        log.writeln(
          '  $arcname: ${EpubImageHelper.sizeStr(originalSize)} → '
          '${EpubImageHelper.sizeStr(newData.length)} (-$reduction%)',
        );
      } catch (e) {
        errorCount++;
        log.writeln('  错误: $arcname - $e');
      }
    }

    // 保存
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: renameMap,
    );

    log.writeln(
      '\n压缩完成: 处理 $processedCount 张, 跳过 $skipCount 张, '
      '错误 $errorCount 张',
    );
    if (totalSaved > 0) {
      log.writeln('总计节省: ${EpubImageHelper.sizeStr(totalSaved)}');
    }
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 处理单张图片
  static _ProcessResult? _processImage(
    Uint8List data,
    String filename,
    String ext, {
    required int jpegQuality,
    required bool pngToJpg,
  }) {
    final decoded = img.decodeImage(data);
    if (decoded == null) {
      return null;
    }

    switch (ext) {
      case '.jpg':
      case '.jpeg':
        // JPEG 质量压缩
        final encoded = img.encodeJpg(decoded, quality: jpegQuality);
        return _ProcessResult(Uint8List.fromList(encoded), 'jpg');

      case '.png':
        final hasAlpha = _hasTransparency(decoded);
        if (hasAlpha) {
          // 有透明度：量化为 PNG-8
          final quantized = img.quantize(decoded, numberOfColors: 255);
          final encoded = img.encodePng(quantized, level: 9);
          return _ProcessResult(Uint8List.fromList(encoded), 'png');
        } else if (pngToJpg) {
          // 无透明度：转为 JPG
          final encoded = img.encodeJpg(decoded, quality: jpegQuality);
          return _ProcessResult(Uint8List.fromList(encoded), 'jpg');
        } else {
          // 仅 PNG 优化
          final encoded = img.encodePng(decoded, level: 9);
          return _ProcessResult(Uint8List.fromList(encoded), 'png');
        }

      case '.bmp':
        // BMP 转 JPG
        final encoded = img.encodeJpg(decoded, quality: jpegQuality);
        return _ProcessResult(Uint8List.fromList(encoded), 'jpg');

      case '.webp':
      case '.gif':
        // WebP 和 GIF 跳过
        return null;

      default:
        return null;
    }
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

/// 图片处理结果
class _ProcessResult {
  final Uint8List data;
  final String newExt;

  _ProcessResult(this.data, this.newExt);
}
