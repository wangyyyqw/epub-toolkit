import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';

/// Converts reader/js_readerFooterNote popup spans into EPUB3 footnote asides.
class SpanToFootnoteOperation {
  SpanToFootnoteOperation._();

  static final RegExp _spanPattern = RegExp(
    r'<span\b[^>]*\bclass="[^"]*\b(?:reader|js_readerFooterNote)\b[^"]*"[^>]*\bdata-wr-footernote="([^"]*)"[^>]*>(?:</span>)?',
    caseSensitive: false,
  );
  static final RegExp _htmlTagPattern = RegExp(
    r'<html\b([^>]*)>',
    caseSensitive: false,
  );
  static final RegExp _headClosePattern = RegExp(
    r'(</head>)',
    caseSensitive: false,
  );
  static final RegExp _bodyClosePattern = RegExp(
    r'</body>',
    caseSensitive: false,
  );

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    String? footnoteColor,
    String? noterefColor,
  }) async {
    final inputBytes = await File(epubPath).readAsBytes();
    final inputArchive = ZipDecoder().decodeBytes(inputBytes);
    final outputArchive = Archive();
    final log = StringBuffer('开始弹窗转脚注...\n');
    final writtenFiles = <String>{};
    var changedChapters = 0;
    var skippedChapters = 0;

    for (final file in inputArchive.files) {
      if (file.name.isEmpty || writtenFiles.contains(file.name)) continue;
      final rawBytes = _readFileBytes(file);
      final lowerName = file.name.toLowerCase();

      if (file.name == 'mimetype') {
        final mimetype = ArchiveFile('mimetype', rawBytes.length, rawBytes);
        mimetype.compress = false;
        outputArchive.addFile(mimetype);
      } else if (_isHtml(lowerName)) {
        final html = _decodeText(rawBytes);
        final converted = _convertHtml(
          html,
          footnoteColor: footnoteColor,
          noterefColor: noterefColor,
        );
        final newHtml = _ensureEpubNamespace(converted.html);
        final bytes = Uint8List.fromList(utf8.encode(newHtml));
        outputArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
        if (converted.count > 0) {
          changedChapters++;
          log.writeln('  ${file.name}: 转换 ${converted.count} 条注释');
        } else {
          skippedChapters++;
        }
      } else {
        outputArchive.addFile(
          ArchiveFile(file.name, rawBytes.length, rawBytes),
        );
      }
      writtenFiles.add(file.name);
    }

    await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);

    log.writeln('完成: $changedChapters 章含注释, $skippedChapters 章无注释');
    log.writeln('输出: $outputPath');
    return log.toString();
  }

  static _ConvertResult _convertHtml(
    String html, {
    String? footnoteColor,
    String? noterefColor,
  }) {
    final footnotes = <String>[];
    var index = 0;
    final newHtml = html.replaceAllMapped(_spanPattern, (match) {
      final noteText = _unescapeAttribute(match.group(1) ?? '').trim();
      if (noteText.isEmpty) return match.group(0)!;
      index++;
      footnotes.add(
        '<aside id="fn$index" class="aside-fn" epub:type="footnote">\n'
        '        <p>${_escapeXml(noteText)}</p>\n'
        '    </aside>',
      );
      return '<sup><a class="fn-ref" epub:type="noteref" href="#fn$index">[$index]</a></sup>';
    });

    if (index == 0) return _ConvertResult(html, 0);

    final withStyle = _headClosePattern.hasMatch(newHtml)
        ? newHtml.replaceFirstMapped(
            _headClosePattern,
            (m) => '${_styleBlock(footnoteColor, noterefColor)}${m.group(1)}',
          )
        : '${_styleBlock(footnoteColor, noterefColor)}$newHtml';
    final asideBlock = '\n${footnotes.join('\n')}\n';
    final withAsides = _bodyClosePattern.hasMatch(withStyle)
        ? withStyle.replaceFirst(_bodyClosePattern, '$asideBlock</body>')
        : '$withStyle$asideBlock';
    return _ConvertResult(withAsides, index);
  }

  static String _styleBlock(String? footnoteColor, String? noterefColor) {
    final fnColor = footnoteColor?.trim().isNotEmpty == true
        ? footnoteColor!.trim()
        : '#004e1c';
    final nrColor = noterefColor?.trim().isNotEmpty == true
        ? noterefColor!.trim()
        : '#b00020';
    return '<style>\n'
        '.aside-fn { font-size: 0.85em; margin-top: 1.5em; padding: 0.5em 0; text-indent: 0; line-height: 1.4; color: $fnColor; }\n'
        'a.fn-ref { text-decoration: none; font-size: 0.75em; vertical-align: super; color: $nrColor; }\n'
        '</style>\n';
  }

  static String _ensureEpubNamespace(String html) {
    return html.replaceFirstMapped(_htmlTagPattern, (match) {
      final attrs = match.group(1) ?? '';
      if (attrs.contains('xmlns:epub')) return match.group(0)!;
      return '<html$attrs xmlns:epub="http://www.idpf.org/2007/ops">';
    });
  }

  static bool _isHtml(String name) =>
      name.endsWith('.html') ||
      name.endsWith('.xhtml') ||
      name.endsWith('.htm');

  static Uint8List _readFileBytes(ArchiveFile file) =>
      Uint8List.fromList(file.content as List<int>);

  static String _decodeText(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _unescapeAttribute(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class _ConvertResult {
  final String html;
  final int count;
  const _ConvertResult(this.html, this.count);
}
