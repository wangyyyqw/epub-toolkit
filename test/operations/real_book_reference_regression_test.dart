import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/core/epub_packer.dart';
import 'package:epub_gadget/features/encrypt_decrypt_base/encrypt_decrypt_base.dart';
import 'package:epub_gadget/features/font_subset/font_subset.dart';
import 'package:epub_gadget/features/merge/merge.dart';
import 'package:epub_gadget/features/epub_to_txt/epub_to_txt.dart';
import 'package:epub_gadget/features/yuewei/yuewei.dart';
import 'package:epub_gadget/features/zhangyue/zhangyue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

ArchiveFile textFile(String name, String text) {
  final bytes = utf8.encode(text);
  return ArchiveFile(name, bytes.length, bytes);
}

String readText(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content as List<int>);

void main() {
  test('TXT export decodes numeric entities exactly once', () async {
    final dir = await Directory.systemTemp.createTemp('text_entities_');
    addTearDown(() => dir.delete(recursive: true));
    final archive = Archive()
      ..addFile(textFile('mimetype', 'application/epub+zip'))
      ..addFile(
        textFile(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="content.opf"/>'
              '</rootfiles></container>',
        ),
      )
      ..addFile(
        textFile('content.opf', '''
<package><manifest><item id="c" href="chapter.xhtml"
media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c"/></spine></package>'''),
      )
      ..addFile(
        textFile(
          'chapter.xhtml',
          '''
<html><body><p>A&#160;B &#x4E2D;&#25991; &amp;#160; &#x20000;</p></body></html>''',
        ),
      );
    final input = '${dir.path}/src.epub';
    await EpubPacker.pack(archive: archive, outputPath: input);
    final text = await EpubToTxtOperation.execute(epubPath: input);
    expect(text, contains('A B 中文 &#160; ${String.fromCharCode(0x20000)}'));
  });

  test(
    'merging EPUB2 books produces EPUB3 and preserves volume-local links',
    () async {
      final dir = await Directory.systemTemp.createTemp('merge_references_');
      addTearDown(() => dir.delete(recursive: true));
      final archive = Archive()
        ..addFile(textFile('mimetype', 'application/epub+zip'))
        ..addFile(
          textFile(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
                '</rootfiles></container>',
          ),
        )
        ..addFile(
          textFile('OEBPS/content.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>Test</dc:title><dc:identifier>test</dc:identifier></metadata>
<manifest>
<item id="text" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="style" href="Styles/main.css" media-type="text/css"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
</manifest><spine toc="ncx"><itemref idref="text"/></spine></package>'''),
        )
        ..addFile(
          textFile('OEBPS/toc.ncx', '''
<ncx><navMap><navPoint><navLabel><text>Chapter</text></navLabel>
<content src="Text/chapter.xhtml#part"/></navPoint></navMap></ncx>'''),
        )
        ..addFile(textFile('OEBPS/Styles/main.css', 'p{color:green}'))
        ..addFile(
          textFile(
            'OEBPS/Text/chapter.xhtml',
            '''
<html><head><link rel="stylesheet" href="../Styles/main.css"/></head>
<body><p id="part">text</p><a href="chapter.xhtml#part">link</a></body></html>''',
          ),
        );
      final source = '${dir.path}/src.epub';
      final output = '${dir.path}/out.epub';
      await EpubPacker.pack(archive: archive, outputPath: source);
      await MergeOperation.execute(
        inputPaths: [source, source],
        outputPath: output,
      );
      final zip = ZipDecoder().decodeBytes(await File(output).readAsBytes());
      final opf = XmlDocument.parse(readText(zip, 'OEBPS/content.opf'));
      expect(opf.rootElement.getAttribute('version'), '3.0');
      expect(readText(zip, 'OEBPS/content.opf'), contains('dcterms:modified'));
      final chapter = readText(zip, 'OEBPS/Text/vol2_chapter.xhtml');
      expect(chapter, contains('../Styles/vol2_main.css'));
      expect(chapter, contains('vol2_chapter.xhtml#part'));
      expect(
        readText(zip, 'OEBPS/nav.xhtml'),
        contains('Text/vol2_chapter.xhtml#part'),
      );
    },
  );

  test(
    'popup to Duokan and Zhangyue preserve text and unique anchor IDs',
    () async {
      final dir = await Directory.systemTemp.createTemp('note_references_');
      addTearDown(() => dir.delete(recursive: true));
      final archive = Archive()
        ..addFile(textFile('mimetype', 'application/epub+zip'))
        ..addFile(
          textFile(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
                '</rootfiles></container>',
          ),
        )
        ..addFile(
          textFile('OEBPS/content.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
<manifest><item id="text" href="Text/chapter.xhtml"
media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="text"/></spine></package>'''),
        )
        ..addFile(
          textFile('OEBPS/Text/chapter.xhtml', '''
<html><body><p>text<span class="reader js_readerFooterNote"
data-wr-footernote="A &amp; B &lt;quoted&gt;"></span></p></body></html>'''),
        );
      final source = '${dir.path}/src.epub';
      final converted = '${dir.path}/yuewei.epub';
      final convertedAgain = '${dir.path}/zhangyue.epub';
      await EpubPacker.pack(archive: archive, outputPath: source);
      await YueweiOperation.execute(epubPath: source, outputPath: converted);
      await ZhangyueOperation.execute(
        epubPath: converted,
        outputPath: convertedAgain,
      );
      for (final path in [converted, convertedAgain]) {
        final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
        final doc = XmlDocument.parse(
          readText(zip, 'OEBPS/Text/chapter.xhtml'),
        );
        final ids = doc.descendants
            .whereType<XmlElement>()
            .map((e) => e.getAttribute('id'))
            .whereType<String>()
            .toList();
        expect(ids.toSet().length, ids.length);
        expect(
          doc.findAllElements('aside').single.innerText.trim(),
          'A & B <quoted>',
        );
      }
    },
  );

  test(
    'reference rewrite uses whole filenames and preserves query/fragment',
    () {
      final archive = Archive()
        ..addFile(
          textFile('Text/index.xhtml', '''
<html><body>
<a href="chapter.xhtml#note">chapter.xhtml</a>
<a href="../Text/v01-chapter.xhtml?x=1#note">long</a>
<a href="other-chapter.xhtml#note">untouched</a>
<img src="../Images/a%20b.png?x=1#pic"/>
</body></html>'''),
        )
        ..addFile(
          textFile(
            'Styles/style.css',
            'a{background:url("../Images/a%20b.png?x=1#pic")}',
          ),
        );
      EncryptDecryptBase.rewriteReferences(archive, {
        'chapter.xhtml': '_*:*.xhtml',
        'v01-chapter.xhtml': 'long.xhtml',
        'a b.png': 'image.png',
      }, 'content.opf');
      final text = readText(archive, 'Text/index.xhtml');
      expect(text, contains('href="_*%3A*.xhtml#note"'));
      expect(text, contains('href="../Text/long.xhtml?x=1#note"'));
      expect(text, contains('href="other-chapter.xhtml#note"'));
      expect(text, contains('>chapter.xhtml</a>'));
      expect(text, contains('src="../Images/image.png?x=1#pic"'));
      expect(
        readText(archive, 'Styles/style.css'),
        contains('../Images/image.png?x=1#pic'),
      );
    },
  );

  test(
    'encoded obfuscation roundtrip preserves manifest and navigation',
    () async {
      final dir = await Directory.systemTemp.createTemp('reference_roundtrip_');
      addTearDown(() => dir.delete(recursive: true));
      final archive = Archive()
        ..addFile(textFile('mimetype', 'application/epub+zip'))
        ..addFile(
          textFile(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
                '</rootfiles></container>',
          ),
        )
        ..addFile(
          textFile('OEBPS/content.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
<metadata/><manifest>
<item id="short" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="long" href="Text/v01-chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="image" href="Images/中文%20图片.png" media-type="image/png"/>
</manifest><spine toc="toc"><itemref idref="short"/><itemref idref="long"/></spine>
</package>'''),
        )
        ..addFile(
          textFile(
            'OEBPS/toc.ncx',
            '<ncx><content src="Text/v01-chapter.xhtml#note"/></ncx>',
          ),
        )
        ..addFile(ArchiveFile('OEBPS/Images/中文 图片.png', 2, [0, 0]))
        ..addFile(
          textFile(
            'OEBPS/Text/chapter.xhtml',
            '<html><body><a href="v01-chapter.xhtml#note">link</a></body></html>',
          ),
        )
        ..addFile(
          textFile(
            'OEBPS/Text/v01-chapter.xhtml',
            '<html><body><p id="note">keep me</p></body></html>',
          ),
        );
      var input = '${dir.path}/source.epub';
      await EpubPacker.pack(archive: archive, outputPath: input);
      for (final mode in ['encrypt', 'decrypt']) {
        final output = '${dir.path}/$mode.epub';
        await EncryptDecryptBase.process(
          epubPath: input,
          outputPath: output,
          mode: mode,
        );
        final zip = ZipDecoder().decodeBytes(await File(output).readAsBytes());
        final opf = readText(zip, 'OEBPS/content.opf');
        expect(EncryptDecryptBase.isEncrypted(opf), mode == 'encrypt');
        final doc = XmlDocument.parse(opf);
        for (final item in doc.findAllElements('item')) {
          final href = item.getAttribute('href')!;
          final path = Uri.decodeComponent(
            Uri.parse('OEBPS/content.opf').resolve(href).path,
          );
          expect(zip.findFile(path), isNotNull, reason: href);
        }
        for (final file in zip.files.where(
          (f) => f.name.endsWith('.xhtml') || f.name.endsWith('.ncx'),
        )) {
          final xml = XmlDocument.parse(readText(zip, file.name));
          for (final element in xml.descendants.whereType<XmlElement>()) {
            final ref =
                element.getAttribute('href') ?? element.getAttribute('src');
            if (ref == null) continue;
            final target = Uri(path: file.name).resolve(ref);
            final resolved = zip.findFile(Uri.decodeComponent(target.path));
            expect(resolved, isNotNull, reason: '${file.name}: $ref');
            expect(readText(zip, resolved!.name), contains('id="note"'));
          }
        }
        input = output;
      }
    },
  );

  test(
    'font subsetting retains CSS fonts in nested paths and fallback lists',
    () async {
      final dir = await Directory.systemTemp.createTemp('font_references_');
      addTearDown(() => dir.delete(recursive: true));
      final archive = Archive()
        ..addFile(textFile('mimetype', 'application/epub+zip'))
        ..addFile(
          textFile('OEBPS/content.opf', '''
<package><manifest>
<item id="a" href="Fonts/a.ttf" media-type="font/ttf"/>
<item id="b" href="Fonts/b.otf" media-type="font/otf"/>
</manifest></package>'''),
        )
        ..addFile(
          textFile('OEBPS/Styles/main.css', '''
@font-face {font-family: Primary;src:url("../Fonts/a.ttf")}
@font-face {font-family: Fallback;src:url("../Fonts/b.otf")}
body p.content {font-family: Primary, Fallback}
'''),
        )
        ..addFile(
          textFile(
            'OEBPS/Text/chapter.xhtml',
            '<html><body><p class="content">&#x4e2d; test</p></body></html>',
          ),
        )
        ..addFile(textFile('OEBPS/Fonts/a.ttf', 'unsupported font fixture'))
        ..addFile(textFile('OEBPS/Fonts/b.otf', 'unsupported font fixture'));
      final input = '${dir.path}/input.epub';
      final output = '${dir.path}/out.epub';
      await EpubPacker.pack(archive: archive, outputPath: input);
      final log = await FontSubsetOperation.execute(
        epubPath: input,
        outputPath: output,
      );
      final zip = ZipDecoder().decodeBytes(await File(output).readAsBytes());
      expect(zip.findFile('OEBPS/Fonts/a.ttf'), isNotNull);
      expect(zip.findFile('OEBPS/Fonts/b.otf'), isNotNull);
      expect(log, contains('移除 0 个'));
    },
  );
}
