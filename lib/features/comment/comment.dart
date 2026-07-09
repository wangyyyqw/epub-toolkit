import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';

/// 批注提取操作（B12）
///
/// 用正则表达式从 EPUB 的 XHTML/HTML 正文中提取批注片段
/// （如 `[...]` 方括号批注），转换为微信读书风格的悬浮批注 span，
/// 并在 CSS 文件中追加悬浮样式。
///
/// 生成的批注 span 格式：
/// ```html
/// <span class="reader js_readerFooterNote" data-wr-footernote="批注内容"></span>
/// ```
class CommentOperation {
  CommentOperation._();

  /// 批注 CSS 样式标记（用于检测是否已注入）
  static const cssMarker = '/* ========== 正则注释样式 ========== */';

  /// 批注 CSS 样式内容
  static const commentCss =
      '''
$cssMarker
span.reader {
    position: relative;
    display: inline-block;
    width: 19px;
    height: 19px;
    vertical-align: sub;
    cursor: pointer;
    margin: 0 3px;
    background-image: url("../Images/note.png");
    background-size: 100%;
    background-repeat: no-repeat;
}

span.reader:hover:after {
    content: attr(data-wr-footernote);
    position: fixed;
    left: 0;
    bottom: 0;
    margin: 1em;
    background: black;
    border-radius: 0.25em;
    color: white;
    padding: 0.5em;
    font-size: 1em;
    font-family: "南构明史稿鉴", sans-serif;
    z-index: 10;
    text-indent: 0em;
}
''';

  /// 执行批注提取
  ///
  /// [epubPath] 输入 EPUB 文件路径
  /// [outputPath] 输出 EPUB 文件路径
  /// [regexPattern] 用于匹配批注内容的正则表达式（如 `\[(.*?)\]`）
  ///
  /// 返回处理结果日志字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required String regexPattern,
  }) async {
    final log = StringBuffer();
    log.writeln('开始批注提取...');

    if (regexPattern.trim().isEmpty) {
      log.writeln('错误: 正则表达式为空');
      return log.toString();
    }

    // 优化正则：将 (.*) 自动替换为非贪婪的 (.*?)
    var optimized = regexPattern.replaceAll('(.*)', '(.*?)');
    if (optimized != regexPattern) {
      log.writeln('自动优化正则: $regexPattern -> $optimized');
    }

    final RegExp pattern;
    try {
      pattern = RegExp(optimized, dotAll: true);
    } catch (e) {
      log.writeln('错误: 无效的正则表达式: $e');
      return log.toString();
    }

    try {
      final inputBytes = await File(epubPath).readAsBytes();
      final inputArchive = ZipDecoder().decodeBytes(inputBytes);
      final outputArchive = Archive();
      final writtenFiles = <String>{};
      var totalReplaced = 0;

      for (final file in inputArchive.files) {
        if (file.name.isEmpty) continue;
        if (writtenFiles.contains(file.name)) continue;

        final lowerName = file.name.toLowerCase();
        final rawBytes = _readFileBytes(file);

        if (file.name == 'mimetype') {
          // mimetype 不压缩
          final mf = ArchiveFile('mimetype', rawBytes.length, rawBytes);
          mf.compress = false;
          outputArchive.addFile(mf);
          writtenFiles.add(file.name);
        } else if (lowerName.endsWith('.html') ||
            lowerName.endsWith('.xhtml') ||
            lowerName.endsWith('.htm')) {
          // HTML 文件：正则匹配并替换
          String text;
          try {
            text = utf8.decode(rawBytes);
          } catch (_) {
            text = utf8.decode(rawBytes, allowMalformed: true);
          }

          final matches = pattern.allMatches(text).toList();
          if (matches.isNotEmpty) {
            final buf = StringBuffer();
            var lastIdx = 0;
            for (final match in matches) {
              buf.write(text.substring(lastIdx, match.start));
              // 取捕获组 1，若无则取整段匹配
              final matchedText = match.groupCount >= 1
                  ? (match.group(1) ?? '')
                  : match.group(0)!;
              buf.write(
                '<span class="reader js_readerFooterNote" '
                'data-wr-footernote="$matchedText"></span>',
              );
              lastIdx = match.end;
            }
            buf.write(text.substring(lastIdx));

            final newBytes = Uint8List.fromList(utf8.encode(buf.toString()));
            outputArchive.addFile(
              ArchiveFile(file.name, newBytes.length, newBytes),
            );
            totalReplaced += matches.length;
            log.writeln('  ${file.name}: 替换 ${matches.length} 处');
          } else {
            outputArchive.addFile(
              ArchiveFile(file.name, rawBytes.length, rawBytes),
            );
          }
          writtenFiles.add(file.name);
        } else if (lowerName.endsWith('.css')) {
          // CSS 文件：追加批注样式
          String css;
          try {
            css = utf8.decode(rawBytes);
          } catch (_) {
            css = utf8.decode(rawBytes, allowMalformed: true);
          }

          if (!css.contains(cssMarker)) {
            css = '$css\n$commentCss';
            final newBytes = Uint8List.fromList(utf8.encode(css));
            outputArchive.addFile(
              ArchiveFile(file.name, newBytes.length, newBytes),
            );
            log.writeln('  ${file.name}: 追加批注样式');
          } else {
            outputArchive.addFile(
              ArchiveFile(file.name, rawBytes.length, rawBytes),
            );
          }
          writtenFiles.add(file.name);
        } else {
          outputArchive.addFile(
            ArchiveFile(file.name, rawBytes.length, rawBytes),
          );
          writtenFiles.add(file.name);
        }
      }

      // 保存
      await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);

      log.writeln('批注提取完成，共替换 $totalReplaced 处');
      log.writeln('输出: $outputPath');
      return log.toString();
    } catch (e) {
      log.writeln('错误: 批注提取失败: $e');
      return log.toString();
    }
  }

  /// 读取 ArchiveFile 的二进制内容
  static Uint8List _readFileBytes(ArchiveFile file) {
    return Uint8List.fromList(file.content as List<int>);
  }
}
