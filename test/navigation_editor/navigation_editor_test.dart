import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/navigation_editor/navigation_editor.dart';
import 'package:epub_gadget/features/navigation_editor/navigation_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('navigation-editor-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('loads toc, landmarks, page-list, and nested levels', () async {
    final input = '${temp.path}/book.epub';
    await _writeBook(input);

    final document = await NavigationEditorOperation.load(input);

    expect(document.entries(NavigationSection.toc), hasLength(3));
    expect(
      document.entries(NavigationSection.toc).first.href,
      'OEBPS/Text/chapter.xhtml?mode=full#top',
    );
    expect(document.entries(NavigationSection.toc)[1].level, 2);
    expect(
      document.entries(NavigationSection.toc)[1].href,
      'OEBPS/Text/chapter.xhtml#part',
    );
    expect(document.entries(NavigationSection.landmarks), hasLength(1));
    expect(document.entries(NavigationSection.pageList), hasLength(1));
    expect(document.navPath, 'OEBPS/nav.xhtml');
    expect(document.ncxPath, 'OEBPS/toc.ncx');
  });

  test(
    'saves edited tree and synchronizes NAV and NCX without losing extras',
    () async {
      final input = '${temp.path}/book.epub';
      final output = '${temp.path}/edited.epub';
      await _writeBook(input);
      final document = await NavigationEditorOperation.load(input);
      final toc = [...document.entries(NavigationSection.toc)];
      toc[0] = toc[0].copyWith(title: '新章名');
      toc[2] = toc[2].copyWith(level: 2);
      final edited = document.copyWith(
        sections: {
          for (final section in NavigationSection.values)
            section: section == NavigationSection.toc
                ? toc
                : [...document.entries(section)],
        },
      );

      final result = await NavigationEditorOperation.save(
        epubPath: input,
        outputPath: output,
        navigation: edited,
      );

      expect(await File(result['outputPath'] as String).exists(), isTrue);
      final archive = ZipDecoder().decodeBytes(
        await File(output).readAsBytes(),
      );
      final nav = _text(archive, 'OEBPS/nav.xhtml');
      final ncx = _text(archive, 'OEBPS/toc.ncx');
      expect(nav, contains('新章名'));
      expect(ncx, contains('新章名'));
      expect(nav, contains('Text/chapter.xhtml?mode=full#top'));
      expect(ncx, contains('Text/chapter.xhtml?mode=full#top'));
      expect(nav, contains('epub:type="landmarks"'));
      expect(nav, contains('epub:type="page-list"'));
      expect(nav, contains('epub:type="cover"'));
      expect(nav, contains('封面'));
      expect(nav, contains('1'));

      final reloaded = await NavigationEditorOperation.load(output);
      expect(reloaded.entries(NavigationSection.toc)[2].level, 2);
      expect(
        reloaded.issues.where(
          (issue) => issue.severity == NavigationValidationSeverity.error,
        ),
        isEmpty,
      );
    },
  );

  test('regenerates from headings and adds stable IDs on save', () async {
    final input = '${temp.path}/book.epub';
    final output = '${temp.path}/generated.epub';
    await _writeBook(input);

    final generated = await NavigationEditorOperation.regenerateFromHeadings(
      input,
    );
    final toc = generated.entries(NavigationSection.toc);
    expect(toc.map((entry) => entry.title), ['第一章', '分节', '第二章']);
    expect(toc.map((entry) => entry.level), [1, 2, 1]);
    expect(toc[2].sourceHeadingIndex, 0);
    expect(toc[2].href, 'OEBPS/Text/chapter2.xhtml#epub-toolkit-heading-1-2');

    await NavigationEditorOperation.save(
      epubPath: input,
      outputPath: output,
      navigation: generated,
    );
    final archive = ZipDecoder().decodeBytes(await File(output).readAsBytes());
    final chapter2 = _text(archive, 'OEBPS/Text/chapter2.xhtml');
    expect(chapter2, contains('id="epub-toolkit-heading-1-2"'));
    final reloaded = await NavigationEditorOperation.load(output);
    expect(
      reloaded.entries(NavigationSection.toc).last.href,
      'OEBPS/Text/chapter2.xhtml#epub-toolkit-heading-1-2',
    );
  });

  test(
    'reports empty titles, duplicate items, invalid anchors and empty chapters',
    () async {
      final input = '${temp.path}/book.epub';
      await _writeBook(input);
      final archive = ZipDecoder().decodeBytes(await File(input).readAsBytes());
      final sections = {
        NavigationSection.toc: const [
          NavigationEntry(
            title: '',
            href: 'OEBPS/Text/chapter.xhtml#missing',
            level: 2,
          ),
          NavigationEntry(
            title: '',
            href: 'OEBPS/Text/chapter.xhtml#missing',
            level: 2,
          ),
          NavigationEntry(
            title: '空章',
            href: 'OEBPS/Text/empty.xhtml',
            level: 1,
          ),
        ],
        NavigationSection.landmarks: const <NavigationEntry>[],
        NavigationSection.pageList: const <NavigationEntry>[],
      };

      final issues = NavigationEditorOperation.validateArchive(
        archive,
        sections,
      );
      final codes = issues.map((issue) => issue.code).toSet();

      expect(codes, contains('empty-title'));
      expect(codes, contains('invalid-level'));
      expect(codes, contains('duplicate-entry'));
      expect(codes, contains('invalid-anchor'));
      expect(codes, contains('empty-chapter'));
    },
  );

  test('loads and synchronizes EPUB2 guide and NCX page-list', () async {
    final input = '${temp.path}/epub2.epub';
    final output = '${temp.path}/epub2-edited.epub';
    await _writeEpub2Book(input);

    final document = await NavigationEditorOperation.load(input);
    expect(document.navPath, isNull);
    expect(
      document.entries(NavigationSection.landmarks).single.semanticType,
      'cover',
    );
    expect(
      document.entries(NavigationSection.pageList).single.href,
      'OEBPS/Text/chapter.xhtml?mode=print#top',
    );

    final edited = document.copyWith(
      sections: {
        for (final section in NavigationSection.values)
          section: switch (section) {
            NavigationSection.landmarks => [
              document
                  .entries(section)
                  .single
                  .copyWith(title: '封面页', semanticType: 'title-page'),
            ],
            NavigationSection.pageList => [
              document
                  .entries(section)
                  .single
                  .copyWith(title: 'i', semanticType: 'front'),
            ],
            NavigationSection.toc => [...document.entries(section)],
          },
      },
    );
    await NavigationEditorOperation.save(
      epubPath: input,
      outputPath: output,
      navigation: edited,
    );

    final archive = ZipDecoder().decodeBytes(await File(output).readAsBytes());
    final opf = _text(archive, 'OEBPS/content.opf');
    final ncx = _text(archive, 'OEBPS/toc.ncx');
    expect(opf, contains('type="title-page"'));
    expect(opf, contains('title="封面页"'));
    expect(ncx, contains('type="front"'));
    expect(ncx, contains('<text>i</text>'));
    expect(ncx, contains('Text/chapter.xhtml?mode=print#top'));

    final reloaded = await NavigationEditorOperation.load(output);
    expect(reloaded.entries(NavigationSection.landmarks).single.title, '封面页');
    expect(reloaded.entries(NavigationSection.pageList).single.title, 'i');
    expect(
      reloaded.entries(NavigationSection.pageList).single.href,
      'OEBPS/Text/chapter.xhtml?mode=print#top',
    );
  });
}

Future<void> _writeBook(String path) async {
  final archive = Archive();
  archive.addFile(
    ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')),
  );
  _add(
    archive,
    'META-INF/container.xml',
    '''<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
  );
  _add(
    archive,
    'OEBPS/content.opf',
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:test</dc:identifier><dc:title>Test</dc:title><dc:language>zh-CN</dc:language></metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="c1" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml"/>
<item id="empty" href="Text/empty.xhtml" media-type="application/xhtml+xml"/>
<item id="cover" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
</manifest><spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/><itemref idref="empty"/></spine></package>''',
  );
  _add(archive, 'OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>导航</title></head><body>
<nav epub:type="toc" id="toc"><h1>目录</h1><ol>
<li><a href="Text/chapter.xhtml?mode=full#top">第一章</a><ol><li><a href="Text/chapter.xhtml#part">分节</a></li></ol></li>
<li><a href="Text/chapter2.xhtml">第二章</a></li></ol></nav>
<nav epub:type="landmarks"><ol><li><a epub:type="cover" href="Images/cover.jpg">封面</a></li></ol></nav>
<nav epub:type="page-list"><ol><li><a href="Text/chapter.xhtml#top">1</a></li></ol></nav>
</body></html>''');
  _add(
    archive,
    'OEBPS/toc.ncx',
    '''<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:test"/><meta name="dtb:depth" content="2"/></head><docTitle><text>Test</text></docTitle><navMap><navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="Text/chapter.xhtml#top"/><navPoint id="n2" playOrder="2"><navLabel><text>分节</text></navLabel><content src="Text/chapter.xhtml#part"/></navPoint></navPoint><navPoint id="n3" playOrder="3"><navLabel><text>第二章</text></navLabel><content src="Text/chapter2.xhtml"/></navPoint></navMap><pageList><pageTarget><navLabel><text>1</text></navLabel><content src="Text/chapter.xhtml#top"/></pageTarget></pageList></ncx>''',
  );
  _add(
    archive,
    'OEBPS/Text/chapter.xhtml',
    '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>一</title></head><body><h1 id="top">第一章</h1><p>正文</p><h2 id="part">分节</h2><p>内容</p></body></html>''',
  );
  _add(
    archive,
    'OEBPS/Text/chapter2.xhtml',
    '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>二</title></head><body><h2>第二章</h2><p id="epub-toolkit-heading-1">正文</p></body></html>''',
  );
  _add(
    archive,
    'OEBPS/Text/empty.xhtml',
    '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>空</title></head><body></body></html>''',
  );
  archive.addFile(
    ArchiveFile('OEBPS/Images/cover.jpg', 4, [0xff, 0xd8, 0xff, 0xd9]),
  );
  await File(path).writeAsBytes(ZipEncoder().encode(archive)!);
}

void _add(Archive archive, String path, String text) {
  final bytes = utf8.encode(text);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}

String _text(Archive archive, String path) => utf8.decode(
  archive.findFile(path)!.content as List<int>,
  allowMalformed: true,
);

Future<void> _writeEpub2Book(String path) async {
  final archive = Archive();
  archive.addFile(
    ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')),
  );
  _add(
    archive,
    'META-INF/container.xml',
    '''<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
  );
  _add(archive, 'OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:test-epub2</dc:identifier><dc:title>EPUB2</dc:title><dc:language>zh-CN</dc:language></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="c1" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="Images/cover.jpg" media-type="image/jpeg"/></manifest>
<spine toc="ncx"><itemref idref="c1"/></spine>
<guide><reference type="cover" title="封面" href="Images/cover.jpg"/></guide>
</package>''');
  _add(
    archive,
    'OEBPS/toc.ncx',
    '''<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:test-epub2"/><meta name="dtb:depth" content="1"/></head><docTitle><text>EPUB2</text></docTitle><navMap><navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="Text/chapter.xhtml#top"/></navPoint></navMap><pageList><navLabel><text>页码</text></navLabel><pageTarget id="p1" playOrder="2" type="normal" value="1"><navLabel><text>1</text></navLabel><content src="Text/chapter.xhtml?mode=print#top"/></pageTarget></pageList></ncx>''',
  );
  _add(
    archive,
    'OEBPS/Text/chapter.xhtml',
    '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>一</title></head><body><h1 id="top">第一章</h1><p>正文</p></body></html>''',
  );
  archive.addFile(
    ArchiveFile('OEBPS/Images/cover.jpg', 4, [0xff, 0xd8, 0xff, 0xd9]),
  );
  await File(path).writeAsBytes(ZipEncoder().encode(archive)!);
}
