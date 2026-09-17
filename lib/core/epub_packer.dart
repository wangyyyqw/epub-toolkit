import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// EPUB 打包工具。
///
/// 阅读器导入 EPUB 时通常会严格检查 OCF ZIP 结构：
/// - `mimetype` 必须是 ZIP 第一个 local file header
/// - `mimetype` 必须 STORED（压缩方式 0）
/// - `mimetype` local header 不能带 extra field
/// - 内容必须精确等于 `application/epub+zip`
class EpubPacker {
  EpubPacker._();

  static final Uint8List _mimetypeBytes = Uint8List.fromList(
    utf8.encode('application/epub+zip'),
  );

  static void ensureMimetype(Archive archive) {
    final existing = archive.findFile('mimetype');
    if (existing != null) {
      existing.compress = false;
      existing.comment = null;
      return;
    }

    archive.addFile(
      ArchiveFile(
        'mimetype',
        _mimetypeBytes.length,
        Uint8List.fromList(_mimetypeBytes),
      )..compress = false,
    );
  }

  static Future<void> pack({
    required Archive archive,
    required String outputPath,
  }) async {
    ensureMimetype(archive);

    final mimetype = archive.findFile('mimetype');
    if (mimetype == null) {
      throw StateError('EPUB 打包失败：缺少 mimetype 文件');
    }

    final content = utf8.decode(mimetype.content as List<int>);
    // 容忍 BOM / 尾随换行等合法变体(规范只要求第一行是 application/epub+zip)
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (trimmed != 'application/epub+zip') {
      throw StateError('EPUB 打包失败：mimetype 内容无效: $content');
    }

    final output = Archive();
    output.comment = archive.comment;
    output.addFile(
      ArchiveFile(
        'mimetype',
        _mimetypeBytes.length,
        Uint8List.fromList(_mimetypeBytes),
      )..compress = false,
    );

    for (final file in archive.files) {
      if (file.name.isEmpty || file.name == 'mimetype') continue;
      final content = _normalizedContent(file);
      output.addFile(
        ArchiveFile(file.name, content.length, content)
          ..compress = file.compress,
      );
    }

    final bytes = ZipEncoder().encode(output);
    if (bytes == null) {
      throw StateError('EPUB 打包失败：ZipEncoder 返回 null');
    }
    await File(outputPath).writeAsBytes(bytes);
  }

  /// Consumes lazy entries one at a time, without retaining a second archive or
  /// a complete ZIP buffer. The caller owns any shared input file streams.
  static Future<void> packStreaming({
    required Iterable<ArchiveFile> files,
    required String outputPath,
  }) async {
    final destination = File(outputPath).absolute;
    final temporary = await destination.parent.createTemp('.epub-pack-');
    OutputFileStream? output;
    try {
      final staged = File('${temporary.path}/output.epub');
      output = OutputFileStream(staged.path);
      final encoder = ZipEncoder()..startEncode(output);
      encoder.addFile(
        ArchiveFile('mimetype', _mimetypeBytes.length, _mimetypeBytes)
          ..compress = false,
      );
      final written = <String>{};
      for (final file in files) {
        if (file.name.isEmpty || !written.add(file.name)) continue;
        if (file.name == 'mimetype') {
          final content = utf8.decode(file.content as List<int>);
          if (content.replaceAll('\uFEFF', '').trim() !=
              'application/epub+zip') {
            throw StateError('EPUB 打包失败：mimetype 内容无效');
          }
          continue;
        }
        if (_isHtmlFile(file.name)) {
          final content = _normalizedContent(file);
          encoder.addFile(
            ArchiveFile(file.name, content.length, content)
              ..compress = file.compress,
          );
        } else {
          // Closing a ZIP slice also closes its shared InputFileStream.
          encoder.addFile(file, autoClose: false);
        }
      }
      encoder.endEncode();
      output.closeSync();
      output = null;
      await staged.rename(destination.path);
    } finally {
      output?.closeSync();
      await temporary.delete(recursive: true);
    }
  }

  static List<int> _normalizedContent(ArchiveFile file) {
    final content = file.content as List<int>;
    if (!_isHtmlFile(file.name)) return content;

    try {
      final text = utf8.decode(content);
      // Most reader-generated XHTML is already OCF-compatible. Avoid the
      // normalization regex pipeline when all required markers are present.
      if (_isAlreadyNormalizedXhtml(text)) return content;
      final normalized = _normalizeXhtml(text);
      if (normalized == text) return content;
      return utf8.encode(normalized);
    } catch (_) {
      return content;
    }
  }

  static bool _isHtmlFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  static bool _isAlreadyNormalizedXhtml(String text) {
    if (!text.startsWith('<?xml')) return false;
    if (!text.contains('xmlns="http://www.w3.org/1999/xhtml"')) return false;
    if (!text.contains('<!DOCTYPE html')) return false;
    if (!text.contains('<head') || !text.contains('<body')) return false;
    return text.contains('</head>') && text.contains('</body>');
  }

  static String _normalizeXhtml(String input) {
    var text = input.replaceFirst('\uFEFF', '').trimLeft();

    // 纯 SVG 文件（如封面 SVG）不应被包裹为 HTML，避免破坏阅读
    final trimmedNoDecl = text
        .replaceFirst(
          RegExp(r'^\s*<\?xml[^>]*\?>\s*', caseSensitive: false),
          '',
        )
        .trimLeft();
    if (trimmedNoDecl.toLowerCase().startsWith('<svg')) {
      // 仅确保 XML 声明，不做 HTML 包装
      return _ensureXmlDeclaration(text);
    }

    final hasHtml = RegExp(
      r'<html(?:\s|>)',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasHtml) {
      // 前导注释/处理指令可能导致 hasHtml 误判，需先剥离注释再判断
      final noComment = text
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
          .trimLeft();
      final stillNoHtml = !RegExp(
        r'<html(?:\s|>)',
        caseSensitive: false,
      ).hasMatch(noComment);
      if (stillNoHtml && noComment.toLowerCase().startsWith('<svg')) {
        return _ensureXmlDeclaration(text);
      }
      text =
          '<html xmlns="http://www.w3.org/1999/xhtml">\n'
          '<head><title></title></head>\n'
          '<body>\n$text\n</body>\n'
          '</html>';
    } else {
      text = _ensureHtmlNamespace(text);
      text = _ensureHead(text);
      text = _ensureBody(text);
    }

    text = _ensureDoctype(text);
    text = _ensureXmlDeclaration(text);
    return text;
  }

  static String _ensureHtmlNamespace(String text) {
    final htmlOpen = RegExp(
      r'<html\b([^>]*)>',
      caseSensitive: false,
    ).firstMatch(text);
    if (htmlOpen == null || htmlOpen.group(0)!.contains('xmlns=')) {
      return text;
    }
    return text.replaceFirstMapped(
      RegExp(r'<html\b([^>]*)>', caseSensitive: false),
      (match) => '<html${match.group(1)} xmlns="http://www.w3.org/1999/xhtml">',
    );
  }

  static String _ensureHead(String text) {
    if (RegExp(r'<head(?:\s|>)', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    return text.replaceFirstMapped(
      RegExp(r'<html\b[^>]*>', caseSensitive: false),
      (match) => '${match.group(0)}\n<head><title></title></head>',
    );
  }

  static String _ensureBody(String text) {
    if (RegExp(r'<body(?:\s|>)', caseSensitive: false).hasMatch(text)) {
      return text;
    }

    final headEnd = RegExp(
      r'</head\s*>',
      caseSensitive: false,
    ).firstMatch(text);
    final htmlEnd = RegExp(
      r'</html\s*>',
      caseSensitive: false,
    ).firstMatch(text);
    if (headEnd == null || htmlEnd == null || headEnd.end > htmlEnd.start) {
      return text.replaceFirst(
        RegExp(r'</html\s*>', caseSensitive: false),
        '<body></body>\n</html>',
      );
    }

    final beforeBody = text.substring(0, headEnd.end);
    final bodyContent = text.substring(headEnd.end, htmlEnd.start).trim();
    final afterHtml = text.substring(htmlEnd.end);
    return '$beforeBody\n<body>\n$bodyContent\n</body>\n</html>$afterHtml';
  }

  static String _ensureXmlDeclaration(String text) {
    if (text.startsWith('<?xml')) return text;
    return '<?xml version="1.0" encoding="utf-8"?>\n$text';
  }

  static String _ensureDoctype(String text) {
    if (RegExp(r'<!DOCTYPE\s+html', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    const doctype =
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n'
        '  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">';
    if (text.startsWith('<?xml')) {
      return text.replaceFirstMapped(
        RegExp(r'(<\?xml[^>]*\?>)\s*', caseSensitive: false),
        (match) => '${match.group(1)}\n$doctype\n',
      );
    }
    return '$doctype\n$text';
  }
}
