import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/encrypt_font/encrypt_font.dart';
import 'package:epub_gadget/features/list_font_targets/list_font_targets.dart';
import 'package:flutter_test/flutter_test.dart';

const _wailsReferenceFont =
    '/Users/aaa/Documents/github/epub-gadget/epub-gadget/frontend/src/assets/fonts/SourceHanSerifSC.ttf';

void main() {
  test('字体加密按 Wails 行为定向替换正文为真实韩文混淆字符', () async {
    final tempDir = await Directory.systemTemp.createTemp('font_encrypt_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final fontBytes = await File(_wailsReferenceFont).readAsBytes();
    final inputPath = '${tempDir.path}/input.epub';
    final outputPath = '${tempDir.path}/output.epub';
    await File(inputPath).writeAsBytes(_buildEpub(fontBytes));

    final targets = await ListFontTargetsOperation.execute(epubPath: inputPath);
    expect(targets, contains('Source Han Serif SC'));
    expect(targets, contains('OEBPS/Text/ch1.xhtml'));

    final log = await EncryptFontOperation.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      targetFontFamilies: ['Source Han Serif SC'],
      targetXhtmlFiles: ['ch1.xhtml'],
    );
    expect(log, contains('字体加密完成'));

    final outputArchive = ZipDecoder().decodeBytes(
      await File(outputPath).readAsBytes(),
    );
    final ch1 = utf8.decode(
      outputArchive.findFile('OEBPS/Text/ch1.xhtml')!.content as List<int>,
    );
    final ch2 = utf8.decode(
      outputArchive.findFile('OEBPS/Text/ch2.xhtml')!.content as List<int>,
    );

    expect(ch1, isNot(contains('甲')));
    expect(ch1, isNot(contains('乙')));
    expect(ch1, contains('普通丙'));
    expect(ch1, contains('&#160;'));
    expect(ch1, isNot(contains('&#x')));
    expect(ch1.runes.any((r) => r >= 0xAC00 && r < 0xD7AF), isTrue);

    expect(ch2, contains('丁戊'));
    expect(ch2.runes.any((r) => r >= 0xAC00 && r < 0xD7AF), isFalse);
  }, skip: !File(_wailsReferenceFont).existsSync());
}

List<int> _buildEpub(List<int> fontBytes) {
  List<int> bytes(String value) => utf8.encode(value);
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        bytes('application/epub+zip'),
      )..compress = false,
    )
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        0,
        bytes('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/content.opf',
        0,
        bytes('''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">font-test</dc:identifier>
    <dc:title>font-test</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="css" href="Styles/style.css" media-type="text/css"/>
    <item id="font" href="Fonts/SourceHanSerifSC.ttf" media-type="font/ttf"/>
    <item id="ch1" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="Text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
'''),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/Styles/style.css',
        0,
        bytes('''
@font-face {
  font-family: "Source Han Serif SC";
  src: url("../Fonts/SourceHanSerifSC.ttf");
}
.fonted { font-family: "Source Han Serif SC"; }
'''),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/Text/ch1.xhtml',
        0,
        bytes('''
<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="../Styles/style.css" rel="stylesheet" type="text/css"/></head><body><p class="fonted">甲&#160;1&#160;<strong>乙</strong>丙</p><p>普通丙</p></body></html>
'''),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/Text/ch2.xhtml',
        0,
        bytes('''
<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="../Styles/style.css" rel="stylesheet" type="text/css"/></head><body><p class="fonted">丁戊</p></body></html>
'''),
      ),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/Fonts/SourceHanSerifSC.ttf',
        fontBytes.length,
        fontBytes,
      ),
    );
  return ZipEncoder().encode(archive)!;
}
