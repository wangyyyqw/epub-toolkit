import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:path/path.dart' as p;

import 'comment.dart';

/// Converts internal footnote links into reader/js_readerFooterNote popup spans.
class FootnoteToCommentOperation {
  FootnoteToCommentOperation._();

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required String regexPattern,
    Uint8List? notePngBytes,
  }) async {
    final log = StringBuffer('开始脚注转弹窗...\n');
    final hrefPattern = _buildHrefPattern(regexPattern);
    final inputBytes = await File(epubPath).readAsBytes();
    final inputArchive = ZipDecoder().decodeBytes(inputBytes);
    final outputArchive = Archive();
    final htmlFiles = <String, String>{};
    final originalBytes = <String, Uint8List>{};
    final writtenFiles = <String>{};
    var totalConverted = 0;
    String? opfPath;

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

    final convertedHtml = <String, String>{};
    for (final entry in htmlFiles.entries) {
      final converted = _convertHtml(entry.value, hrefPattern);
      convertedHtml[entry.key] = converted.html;
      totalConverted += converted.count;
      if (converted.count > 0) {
        log.writeln('  ${entry.key}: 转换 ${converted.count} 个脚注链接');
      }
    }

    for (final file in inputArchive.files) {
      if (file.name.isEmpty) continue;
      final lowerName = file.name.toLowerCase();
      final bytes = originalBytes[file.name]!;

      if (file.name == 'mimetype') {
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
        final css = utf8.decode(bytes, allowMalformed: true);
        final newCss = css.contains(CommentOperation.cssMarker)
            ? css
            : '$css\n${CommentOperation.commentCss}';
        final newBytes = Uint8List.fromList(utf8.encode(newCss));
        outputArchive.addFile(
          ArchiveFile(file.name, newBytes.length, newBytes),
        );
      } else if (lowerName.endsWith('.opf') && notePngBytes != null) {
        final opf = utf8.decode(bytes, allowMalformed: true);
        final newOpf = _injectNoteManifest(opf);
        final newBytes = Uint8List.fromList(utf8.encode(newOpf));
        outputArchive.addFile(
          ArchiveFile(file.name, newBytes.length, newBytes),
        );
      } else {
        outputArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }
    }

    if (notePngBytes != null && opfPath != null) {
      final opfDir = p.posix.dirname(opfPath);
      final notePath = opfDir == '.'
          ? 'Images/note.png'
          : '$opfDir/Images/note.png';
      if (!outputArchive.files.any((f) => f.name == notePath)) {
        outputArchive.addFile(
          ArchiveFile(notePath, notePngBytes.length, notePngBytes),
        );
      }
    }

    await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);

    log.writeln('脚注链接转换完成，共转换 $totalConverted 个链接');
    log.writeln('输出: $outputPath');
    return log.toString();
  }

  static RegExp _buildHrefPattern(String regexPattern) {
    final pattern = regexPattern.trim().isEmpty ? r'^#+' : regexPattern.trim();
    return RegExp(pattern);
  }

  static _FootnoteConvertResult _convertHtml(String html, RegExp hrefPattern) {
    final idsToRemove = <String>{};
    var count = 0;
    final linkPattern = RegExp(
      r'<a\b([^>]*\bhref="(#[^"]+)"[^>]*)>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    final newHtml = html.replaceAllMapped(linkPattern, (match) {
      final href = match.group(2)!;
      if (!hrefPattern.hasMatch(href)) return match.group(0)!;
      final targetId = Uri.decodeComponent(href.substring(1));
      final noteText = _extractNoteText(html, targetId);
      if (noteText.trim().isEmpty) return match.group(0)!;
      idsToRemove.add(targetId);
      count++;
      return '<span class="reader js_readerFooterNote" data-wr-footernote="${_escapeAttr(noteText.trim())}"></span>';
    });

    var cleaned = newHtml;
    for (final id in idsToRemove) {
      cleaned = _removeElementWithId(cleaned, id);
    }
    return _FootnoteConvertResult(cleaned, count);
  }

  static String _extractNoteText(String html, String id) {
    final idPattern = RegExp(
      r'<([a-zA-Z0-9:_-]+)\b[^>]*\bid="' +
          RegExp.escape(id) +
          r'"[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = idPattern.firstMatch(html);
    if (match == null) return '';
    var content = match.group(2) ?? '';
    content = content.replaceAll(RegExp(r'<[^>]+>'), '');
    return _unescapeHtml(content).trim();
  }

  static String _removeElementWithId(String html, String id) {
    final blockPattern = RegExp(
      r'<(p|li|div|dd|aside)\b[^>]*\bid="' +
          RegExp.escape(id) +
          r'"[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    );
    if (blockPattern.hasMatch(html)) return html.replaceFirst(blockPattern, '');
    final anyPattern = RegExp(
      r'<([a-zA-Z0-9:_-]+)\b[^>]*\bid="' +
          RegExp.escape(id) +
          r'"[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    );
    return html.replaceFirst(anyPattern, '');
  }

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

  static Uint8List _readFileBytes(ArchiveFile file) =>
      Uint8List.fromList(file.content as List<int>);

  static String _escapeAttr(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _unescapeHtml(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class _FootnoteConvertResult {
  final String html;
  final int count;
  const _FootnoteConvertResult(this.html, this.count);
}
