import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/core/epub_packer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EpubPacker 补齐 XHTML 的 doctype/html/head/body', () async {
    final outputPath = '/tmp/test_epub_packer_xhtml_normalize.epub';
    if (File(outputPath).existsSync()) File(outputPath).deleteSync();

    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'mimetype',
          'application/epub+zip'.length,
          utf8.encode('application/epub+zip'),
        )..compress = false,
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/Text/chapter.xhtml',
          '<p>正文</p>'.length,
          utf8.encode('<p>正文</p>'),
        ),
      );

    await EpubPacker.pack(archive: archive, outputPath: outputPath);

    final outArchive = ZipDecoder().decodeBytes(
      File(outputPath).readAsBytesSync(),
    );
    final chapter = utf8.decode(
      outArchive.findFile('OEBPS/Text/chapter.xhtml')!.content as List<int>,
    );

    expect(chapter, startsWith('<?xml version="1.0" encoding="utf-8"?>'));
    expect(chapter, contains('<!DOCTYPE html PUBLIC'));
    expect(chapter, contains('<html xmlns="http://www.w3.org/1999/xhtml">'));
    expect(chapter, contains('<head><title></title></head>'));
    expect(chapter, contains('<body>'));
    expect(chapter, contains('<p>正文</p>'));
    expect(chapter, contains('</body>'));
    expect(chapter, contains('</html>'));
  });
}
