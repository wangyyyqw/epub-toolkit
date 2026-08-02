import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/epub_packer.dart';

/// 批注提取操作（B12）
///
/// 用正则表达式从 EPUB 的 XHTML/HTML 正文中提取批注片段
/// （如 `[...]` 方括号批注），转换为悬浮批注 span，
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

  /// 生成批注 CSS 样式内容
  ///
  /// [notePngRelPath] note.png 相对于 CSS 文件所在目录的路径。
  /// CSS 中 url() 路径是相对于 CSS 文件自身位置的,
  /// 不能写死 ../Images/note.png,必须根据每个 CSS 文件的实际位置计算。
  static String buildCommentCss(String notePngRelPath) {
    return '''
$cssMarker
span.reader {
    position: relative;
    display: inline-block;
    width: 19px;
    height: 19px;
    vertical-align: sub;
    cursor: pointer;
    margin: 0 3px;
    background-image: url("$notePngRelPath");
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
  }

  /// 执行批注提取
  ///
  /// [epubPath] 输入 EPUB 文件路径
  /// [outputPath] 输出 EPUB 文件路径
  /// [regexPattern] 用于匹配批注内容的正则表达式（如 `\[(.*?)\]`）
  /// [notePngBytes] note.png 图标字节（从 assets 加载，为 null 则不注入图片）
  ///
  /// 返回处理结果日志字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required String regexPattern,
    Uint8List? notePngBytes,
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
      final originalBytes = <String, Uint8List>{};
      final htmlFiles = <String, String>{};
      var totalReplaced = 0;
      String? opfPath;

      // 第一轮：读取所有文件，检测 OPF 路径
      for (final file in inputArchive.files) {
        if (file.name.isEmpty || writtenFiles.contains(file.name)) continue;
        final bytes = _readFileBytes(file);
        originalBytes[file.name] = bytes;
        final lowerName = file.name.toLowerCase();
        if (_isHtml(lowerName)) {
          htmlFiles[file.name] = utf8.decode(bytes, allowMalformed: true);
        } else if (lowerName.endsWith('.opf')) {
          opfPath = file.name;
        }
        writtenFiles.add(file.name);
      }

      // 正则匹配并替换
      final convertedHtml = <String, String>{};
      for (final entry in htmlFiles.entries) {
        final matches = pattern.allMatches(entry.value).toList();
        if (matches.isNotEmpty) {
          final buf = StringBuffer();
          var lastIdx = 0;
          for (final match in matches) {
            buf.write(entry.value.substring(lastIdx, match.start));
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
          buf.write(entry.value.substring(lastIdx));
          convertedHtml[entry.key] = buf.toString();
          totalReplaced += matches.length;
          log.writeln('  ${entry.key}: 替换 ${matches.length} 处');
        }
      }

      // 计算 note.png 在 EPUB 中的绝对路径(放在 OPF 同级目录下)
      final opfDir = opfPath != null ? p.posix.dirname(opfPath) : '.';
      final noteAbsPath =
          opfDir == '.' ? 'Images/note.png' : '$opfDir/Images/note.png';

      // 第二轮：写入输出
      for (final file in inputArchive.files) {
        if (file.name.isEmpty) continue;
        final lowerName = file.name.toLowerCase();
        final bytes = originalBytes[file.name]!;

        if (file.name == 'mimetype') {
          // mimetype 不压缩
          final mimetype = ArchiveFile('mimetype', bytes.length, bytes);
          mimetype.compress = false;
          outputArchive.addFile(mimetype);
        } else if (convertedHtml.containsKey(file.name)) {
          final newBytes = Uint8List.fromList(
            utf8.encode(convertedHtml[file.name]!),
          );
          outputArchive.addFile(
            ArchiveFile(file.name, newBytes.length, newBytes),
          );
        } else if (lowerName.endsWith('.css')) {
          // CSS 文件:追加批注样式,路径根据 CSS 文件位置动态计算
          String css;
          try {
            css = utf8.decode(bytes);
          } catch (_) {
            css = utf8.decode(bytes, allowMalformed: true);
          }
          if (!css.contains(cssMarker)) {
            // 计算 note.png 相对于当前 CSS 文件所在目录的路径
            final cssDir = p.posix.dirname(file.name);
            final noteRel = p.posix.relative(noteAbsPath, from: cssDir);
            css = '$css\n${buildCommentCss(noteRel)}';
            final newBytes = Uint8List.fromList(utf8.encode(css));
            outputArchive.addFile(
              ArchiveFile(file.name, newBytes.length, newBytes),
            );
            log.writeln('  ${file.name}: 追加批注样式');
          } else {
            outputArchive.addFile(
              ArchiveFile(file.name, bytes.length, bytes),
            );
          }
        } else if (lowerName.endsWith('.opf') && notePngBytes != null) {
          // OPF 文件:注入 note.png manifest 项
          final opf = utf8.decode(bytes, allowMalformed: true);
          final newOpf = _injectNoteManifest(opf);
          final newBytes = Uint8List.fromList(utf8.encode(newOpf));
          outputArchive.addFile(
            ArchiveFile(file.name, newBytes.length, newBytes),
          );
        } else {
          outputArchive.addFile(
            ArchiveFile(file.name, bytes.length, bytes),
          );
        }
      }

      // 注入 note.png 图片
      if (notePngBytes != null) {
        if (!outputArchive.files.any((f) => f.name == noteAbsPath)) {
          outputArchive.addFile(
            ArchiveFile(noteAbsPath, notePngBytes.length, notePngBytes),
          );
          log.writeln('注入 note.png 到 $noteAbsPath');
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

  /// 在 OPF 中注入 note.png manifest 项
  static String _injectNoteManifest(String opf) {
    if (opf.contains('href="Images/note.png"')) return opf;
    final item =
        '<item id="note_png_res" href="Images/note.png" media-type="image/png"/>';
    return opf.replaceFirst('</manifest>', '$item\n</manifest>');
  }

  static bool _isHtml(String name) =>
      name.endsWith('.html') ||
      name.endsWith('.xhtml') ||
      name.endsWith('.htm');

  /// 读取 ArchiveFile 的二进制内容
  static Uint8List _readFileBytes(ArchiveFile file) {
    return Uint8List.fromList(file.content as List<int>);
  }
}
