import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:epub_gadget/core/epub_service.dart' as core;
import 'package:epub_gadget/features/replace_cover/epub_service.dart'
    as feature;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

List<int> makeBook({
  required bool epub3,
  required String name,
  bool raw = false,
}) {
  final archive = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final encoded = raw ? name : Uri.encodeComponent(name);
  const base = '书库/OPS';
  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="%E4%B9%A6%E5%BA%93/OPS/book.opf"/></rootfiles>
</container>''');
  add('$base/book.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="${epub3 ? '3.0' : '2.0'}" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">test</dc:identifier><dc:title>Paths</dc:title><dc:language>zh</dc:language>
<meta name="cover" content="cover"/>
</metadata><manifest>
<item id="chapter" href="Text/./$encoded.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="导航/${epub3 ? '目%3A录.xhtml' : '目%3A录.ncx'}" media-type="${epub3 ? 'application/xhtml+xml' : 'application/x-dtbncx+xml'}" ${epub3 ? 'properties="nav scripted"' : ''}/>
<item id="cover" href="Images/封面%20图.png" media-type="image/png"/>
</manifest><spine toc="nav"><itemref idref="chapter"/></spine></package>''');
  add(
    '$base/Text/$name.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title></head><body><p id="节">正文</p></body></html>',
  );
  final src = '../Text/$encoded.xhtml?rev=1#%E8%8A%82';
  if (epub3) {
    add('$base/导航/目:录.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>TOC</title></head><body>
<nav><ol><li><a href="$src">Chapter</a></li></ol></nav></body></html>''');
  } else {
    add('$base/导航/目:录.ncx', '''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head/><docTitle><text>Paths</text></docTitle><navMap>
<navPoint id="n1"><navLabel><text>Chapter</text></navLabel><content src="$src"/></navPoint>
</navMap></ncx>''');
  }
  final png = image.encodePng(image.Image(2, 2));
  archive.addFile(ArchiveFile('$base/Images/封面 图.png', png.length, png));
  return ZipEncoder().encode(archive)!;
}

void main() {
  for (final replace in [
    core.EpubService.replaceCover,
    feature.EpubService.replaceCover,
  ]) {
    test(
      'cover replacement preserves its manifest ID and Unicode paths $replace',
      () async {
        final dir = await Directory.systemTemp.createTemp('cover_path_test_');
        addTearDown(() => dir.delete(recursive: true));
        final input = File('${dir.path}/source.epub');
        await input.writeAsBytes(makeBook(epub3: false, name: '章节'));
        final cover = File('${dir.path}/cover.png');
        await cover.writeAsBytes(image.encodePng(image.Image(3, 3)));
        final output = File('${dir.path}/out.epub');
        await replace(
          epubPath: input.path,
          coverPath: cover.path,
          outputPath: output.path,
        );
        final book = await EpubReader.readBook(await output.readAsBytes());
        expect(book.CoverImage!.width, 3);
        expect(
          book.Schema!.Package!.Metadata!.MetaItems!
              .singleWhere((m) => m.Name == 'cover')
              .Content,
          'cover',
        );
        final archive = ZipDecoder().decodeBytes(await output.readAsBytes());
        expect(archive.findFile('书库/OPS/Images/封面 图.png'), isNull);
      },
    );
  }
  for (final epub3 in [false, true]) {
    for (final name in ['中文 空格', 'a%20字', 'a#b?c', '百分%字', '星*:号']) {
      test(
        'EPUB${epub3 ? 3 : 2} resolves $name with nested navigation',
        () async {
          final book = await EpubReader.readBook(
            makeBook(epub3: epub3, name: name),
          );
          expect(
            book.Content!.Html!['Text/$name.xhtml']!.Content,
            contains('正文'),
          );
          expect(book.Chapters!.single.ContentFileName, 'Text/$name.xhtml');
          expect(book.Chapters!.single.Anchor, '节');
          expect(book.Content!.Images!['Images/封面 图.png']!.Content, isNotEmpty);
          if (!epub3) expect(book.CoverImage, isNotNull);
        },
      );
    }
  }
  test('raw Unicode and mixed encoded paths are accepted', () async {
    final book = await EpubReader.readBook(
      makeBook(epub3: false, name: '中文 空格', raw: true),
    );
    expect(book.Chapters!.single.ContentFileName, 'Text/中文 空格.xhtml');
  });
  test('parallel navigation reads do not share path state', () async {
    final books = await Future.wait([
      EpubReader.readBook(makeBook(epub3: true, name: '甲')),
      EpubReader.readBook(makeBook(epub3: false, name: '乙')),
    ]);
    expect(books[0].Chapters!.single.ContentFileName, 'Text/甲.xhtml');
    expect(books[1].Chapters!.single.ContentFileName, 'Text/乙.xhtml');
  });
}
