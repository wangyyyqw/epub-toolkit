import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

import 'epub_image_helper.dart';

/// 图片转 WebP 操作
///
/// 将 EPUB 中的 JPEG/PNG/BMP 图片转换为 WebP 格式以减小体积。
///
/// 平台支持：
/// - Android/iOS：优先使用 flutter_image_compress 原生 WebP 编码
/// - macOS/Windows/Linux：优先调用随 App 打包的 cwebp，找不到时再查找系统 cwebp
class ImgToWebpOperation {
  ImgToWebpOperation._();

  /// WebP 编码质量（0-100）
  static const int webpQuality = 80;

  /// 执行图片转 WebP
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
    final images = EpubImageHelper.findImages(
      archive,
      EpubImageHelper.webpConvertExts,
    );

    if (images.isEmpty) {
      return '未找到可转换的图片（支持 JPG/PNG/BMP）。';
    }

    var convertedCount = 0;
    var skipCount = 0;
    var errorCount = 0;
    var totalSaved = 0;
    final renameMap = <String, String>{};
    final log = StringBuffer();

    log.writeln('找到 ${images.length} 张可转换图片，开始转换为 WebP...');

    for (final imageFile in images) {
      final arcname = imageFile.name;
      final originalData = EpubImageHelper.readBytes(imageFile);
      final originalSize = originalData.length;

      try {
        final webpData = await _encodeWebP(originalData, arcname);

        if (webpData.isEmpty) {
          skipCount++;
          log.writeln('  跳过: $arcname (转换返回空)');
          continue;
        }

        // 确定新文件名
        final newArcname = '${p.withoutExtension(arcname)}.webp';
        renameMap[arcname] = newArcname;

        // 替换文件
        EpubImageHelper.replaceFile(
          archive,
          arcname,
          newArcname,
          Uint8List.fromList(webpData),
        );

        convertedCount++;
        final saved = originalSize - webpData.length;
        if (saved > 0) {
          totalSaved += saved;
          final reduction = (saved / originalSize * 100).toStringAsFixed(1);
          log.writeln(
            '  $arcname → ${p.basename(newArcname)}: '
            '${EpubImageHelper.sizeStr(originalSize)} → '
            '${EpubImageHelper.sizeStr(webpData.length)} (-$reduction%)',
          );
        } else {
          log.writeln(
            '  $arcname → ${p.basename(newArcname)}: '
            '${EpubImageHelper.sizeStr(originalSize)} → '
            '${EpubImageHelper.sizeStr(webpData.length)} '
            '(体积未减小但已转为 WebP)',
          );
        }
      } on UnsupportedError catch (e) {
        // 平台不支持 WebP 编码
        errorCount++;
        log.writeln('  错误: $arcname - 平台不支持: $e');
      } catch (e) {
        errorCount++;
        log.writeln('  错误: $arcname - $e');
      }
    }

    if (convertedCount == 0) {
      return '未能转换任何图片。$log';
    }

    // 保存
    await EpubImageHelper.saveArchive(
      archive,
      outputPath,
      renameMap: renameMap,
    );

    log.writeln(
      '\n转换完成: 转换 $convertedCount 张, 跳过 $skipCount 张, '
      '错误 $errorCount 张',
    );
    if (totalSaved > 0) {
      log.writeln('总计节省: ${EpubImageHelper.sizeStr(totalSaved)}');
    }
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  static Future<Uint8List> _encodeWebP(
    Uint8List originalData,
    String arcname,
  ) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 使用 flutter_image_compress 转换为 WebP。
      // 设置极大的 minWidth/minHeight 防止图片被缩放。
      final webpData = await FlutterImageCompress.compressWithList(
        originalData,
        quality: webpQuality,
        format: CompressFormat.webp,
        minWidth: 100000,
        minHeight: 100000,
      );
      if (webpData.isNotEmpty) return Uint8List.fromList(webpData);
      throw StateError('原生 WebP 编码返回空数据');
    }

    final cwebp = await _findCwebpExecutable();
    if (cwebp == null) {
      throw StateError(
        '未找到 cwebp。打包版会内置 cwebp；源码运行时请先安装 WebP 工具。'
        'macOS: brew install webp，Windows: 安装 libwebp 或将 cwebp.exe 放到程序 bin 目录。',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('epub_webp_');
    try {
      final ext = p.extension(arcname).toLowerCase();
      final input = File(p.join(tempDir.path, 'input$ext'));
      final output = File(p.join(tempDir.path, 'output.webp'));
      await input.writeAsBytes(originalData);

      final result = await Process.run(cwebp, [
        '-quiet',
        '-q',
        '$webpQuality',
        input.path,
        '-o',
        output.path,
      ]);
      if (result.exitCode != 0 || !await output.exists()) {
        final stderrText = '${result.stderr}'.trim();
        throw StateError(
          stderrText.isEmpty ? 'cwebp 编码失败' : 'cwebp 编码失败: $stderrText',
        );
      }
      final bytes = await output.readAsBytes();
      if (bytes.isEmpty) throw StateError('cwebp 输出空文件');
      return bytes;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // 忽略临时目录清理失败
      }
    }
  }

  static Future<String?> _findCwebpExecutable() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      if (Platform.isMacOS)
        p.normalize(p.join(exeDir, '..', 'Resources', 'bin', 'cwebp')),
      if (Platform.isWindows) p.join(exeDir, 'bin', 'cwebp.exe'),
      if (Platform.isLinux) p.join(exeDir, 'bin', 'cwebp'),
      'cwebp',
      'cwebp.exe',
      '/opt/homebrew/bin/cwebp',
      '/usr/local/bin/cwebp',
      '/usr/bin/cwebp',
      r'C:\Program Files\WebP\bin\cwebp.exe',
      r'C:\Program Files (x86)\WebP\bin\cwebp.exe',
      r'C:\ProgramData\chocolatey\bin\cwebp.exe',
    ];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, ['-version']);
        if (result.exitCode == 0) return candidate;
      } catch (_) {
        // 继续尝试下一个路径
      }
    }
    return null;
  }
}
