import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../img_to_webp/epub_image_helper.dart';

/// EPUB 图片隐形水印操作。
///
/// 水印以 UTF-8 文本写入图片 RGB 通道最低有效位。为保证读取稳定，写入后图片统一
/// 保存为 PNG，并同步更新 EPUB 内部引用。
class ImageWatermarkOperation {
  ImageWatermarkOperation._();

  static const List<int> _magic = [
    0x45,
    0x50,
    0x55,
    0x42,
    0x57,
    0x4d,
    0x31,
    0x00,
  ]; // EPUBWM1\0

  static const _headerLength = 16;
  static const _supportedExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.webp',
    '.gif',
  ];

  static Future<String> embed({
    required String epubPath,
    required String outputPath,
    required String watermarkText,
  }) async {
    final text = watermarkText.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(watermarkText, 'watermarkText', '水印文本不能为空');
    }

    final payload = _buildPayload(utf8.encode(text));
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(archive, _supportedExts);
    final renameMap = <String, String>{};
    final log = StringBuffer();
    var embeddedCount = 0;
    var skipCount = 0;
    var errorCount = 0;

    if (images.isEmpty) {
      return '未找到可写入水印的图片。';
    }

    log.writeln('找到 ${images.length} 张图片，开始写入隐形水印...');
    for (final imageFile in images) {
      final arcname = imageFile.name;
      try {
        final originalData = EpubImageHelper.readBytes(imageFile);
        final decoded = img.decodeImage(originalData);
        if (decoded == null) {
          skipCount++;
          log.writeln('  跳过: $arcname (图片解码失败)');
          continue;
        }

        final capacityBytes = _capacityBytes(decoded);
        if (capacityBytes < payload.length) {
          skipCount++;
          log.writeln(
            '  跳过: $arcname (容量 ${capacityBytes}B，小于所需 ${payload.length}B)',
          );
          continue;
        }

        final watermarked = _embedPayload(decoded, payload);
        final encoded = Uint8List.fromList(
          img.encodePng(watermarked, level: 9),
        );
        final newArcname = '${p.withoutExtension(arcname)}.png';
        if (newArcname != arcname) {
          renameMap[arcname] = newArcname;
        }
        EpubImageHelper.replaceFile(archive, arcname, newArcname, encoded);
        embeddedCount++;
        log.writeln(
          '  写入: $arcname'
          '${newArcname == arcname ? '' : ' → ${p.basename(newArcname)}'}',
        );
      } catch (e) {
        errorCount++;
        log.writeln('  错误: $arcname - $e');
      }
    }

    if (embeddedCount == 0) {
      return '$log\n未能写入任何图片，未生成输出文件。';
    }

    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: renameMap,
    );
    log.writeln(
      '\n写入完成: 写入 $embeddedCount 张, 跳过 $skipCount 张, 错误 $errorCount 张',
    );
    log.writeln('输出文件: $outputPath');
    return log.toString();
  }

  static Future<String> inspect({required String epubPath}) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final images = EpubImageHelper.findImages(archive, _supportedExts);
    final log = StringBuffer();
    var foundCount = 0;
    var noWatermarkCount = 0;
    var errorCount = 0;

    if (images.isEmpty) {
      return '未找到可读取的图片。';
    }

    log.writeln('找到 ${images.length} 张图片，开始读取隐形水印...');
    for (final imageFile in images) {
      final arcname = imageFile.name;
      try {
        final decoded = img.decodeImage(EpubImageHelper.readBytes(imageFile));
        if (decoded == null) {
          errorCount++;
          log.writeln('  错误: $arcname - 图片解码失败');
          continue;
        }

        final result = _extractText(decoded);
        if (result == null) {
          noWatermarkCount++;
          continue;
        }

        foundCount++;
        log.writeln('  $arcname: $result');
      } catch (e) {
        errorCount++;
        log.writeln('  错误: $arcname - $e');
      }
    }

    log.writeln(
      '\n读取完成: 找到 $foundCount 张, 无水印 $noWatermarkCount 张, 错误 $errorCount 张',
    );
    if (foundCount == 0) {
      log.writeln('未在 EPUB 图片中发现本工具写入的水印信息。');
    }
    return log.toString();
  }

  static Uint8List _buildPayload(List<int> textBytes) {
    final payload = BytesBuilder();
    payload.add(_magic);
    payload.add(_uint32Bytes(textBytes.length));
    payload.add(_uint32Bytes(getCrc32(textBytes)));
    payload.add(textBytes);
    return payload.toBytes();
  }

  static img.Image _embedPayload(img.Image source, Uint8List payload) {
    final image = img.Image.from(source);
    var bitIndex = 0;
    final totalBits = payload.length * 8;

    for (var y = 0; y < image.height && bitIndex < totalBits; y++) {
      for (var x = 0; x < image.width && bitIndex < totalBits; x++) {
        final pixel = image.getPixel(x, y);
        var r = img.getRed(pixel);
        var g = img.getGreen(pixel);
        var b = img.getBlue(pixel);
        final a = img.getAlpha(pixel);

        if (bitIndex < totalBits) {
          r = _withLsb(r, _bitAt(payload, bitIndex++));
        }
        if (bitIndex < totalBits) {
          g = _withLsb(g, _bitAt(payload, bitIndex++));
        }
        if (bitIndex < totalBits) {
          b = _withLsb(b, _bitAt(payload, bitIndex++));
        }
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return image;
  }

  static String? _extractText(img.Image image) {
    if (_capacityBytes(image) < _headerLength) return null;

    final reader = _LsbReader(image);
    final header = reader.readBytes(_headerLength);
    if (header == null) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) return null;
    }

    final length = _readUint32(header, 8);
    final expectedCrc = _readUint32(header, 12);
    if (length < 0 || length > _capacityBytes(image) - _headerLength) {
      return null;
    }

    final data = reader.readBytes(length);
    if (data == null || getCrc32(data) != expectedCrc) return null;
    return utf8.decode(data, allowMalformed: true);
  }

  static int _capacityBytes(img.Image image) =>
      (image.width * image.height * 3) ~/ 8;

  static int _withLsb(int value, int bit) => (value & 0xfe) | bit;

  static int _bitAt(Uint8List bytes, int bitIndex) {
    final byte = bytes[bitIndex ~/ 8];
    final shift = 7 - (bitIndex % 8);
    return (byte >> shift) & 1;
  }

  static List<int> _uint32Bytes(int value) => [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  static int _readUint32(List<int> bytes, int offset) =>
      ((bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3]) &
      0xffffffff;
}

class _LsbReader {
  _LsbReader(this.image);

  final img.Image image;
  var _bitIndex = 0;

  Uint8List? readBytes(int count) {
    final output = Uint8List(count);
    for (var i = 0; i < count; i++) {
      var value = 0;
      for (var bit = 0; bit < 8; bit++) {
        final next = _nextBit();
        if (next == null) return null;
        value = (value << 1) | next;
      }
      output[i] = value;
    }
    return output;
  }

  int? _nextBit() {
    final pixelIndex = _bitIndex ~/ 3;
    if (pixelIndex >= image.width * image.height) return null;
    final channel = _bitIndex % 3;
    final x = pixelIndex % image.width;
    final y = pixelIndex ~/ image.width;
    final pixel = image.getPixel(x, y);
    _bitIndex++;
    if (channel == 0) return img.getRed(pixel) & 1;
    if (channel == 1) return img.getGreen(pixel) & 1;
    return img.getBlue(pixel) & 1;
  }
}
