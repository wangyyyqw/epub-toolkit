import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

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
      return;
    }

    archive.addFile(
      ArchiveFile('mimetype', _mimetypeBytes.length, _mimetypeBytes)
        ..compress = false,
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
    if (content != 'application/epub+zip') {
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

  static List<int> _normalizedContent(ArchiveFile file) {
    final content = file.content as List<int>;
    if (!_isHtmlFile(file.name)) return content;

    try {
      final text = utf8.decode(content);
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

  static String _normalizeXhtml(String input) {
    var text = input.replaceFirst('\uFEFF', '').trimLeft();

    final hasHtml = RegExp(
      r'<html(?:\s|>)',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasHtml) {
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
