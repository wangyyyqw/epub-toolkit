// 回归测试：merge EPUB3 副标题提取
//
// 验证 merge 时不会丢失 EPUB3 refines 风格的副标题
// （<dc:title id="...">...</dc:title> + <meta refines property="title-type">）

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:epub_gadget/features/merge/merge.dart';
import 'package:epub_gadget/core/epub_image_helper.dart';

/// 构造带自定义 OPF 的 EPUB（可指定任意 metadata 内容）
Archive _buildEpubWithOpf(
  String opfContent, {
  List<String> chapterTitles = const ['ch1'],
}) {
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'mimetype',
    20,
    utf8.encode('application/epub+zip'),
  )..compress = false);
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    100,
    utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
  ));
  final navItems = StringBuffer();
  for (var i = 0; i < chapterTitles.length; i++) {
    navItems.writeln(
        '    <li><a href="ch${i + 1}.xhtml">章节 ${i + 1}</a></li>');
  }
  final navContent = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc">
    <ol>
$navItems    </ol>
  </nav>
</body>
</html>''';
  archive.addFile(ArchiveFile(
    'OEBPS/nav.xhtml',
    navContent.length,
    utf8.encode(navContent),
  ));
  archive.addFile(ArchiveFile(
    'OEBPS/content.opf',
    opfContent.length,
    utf8.encode(opfContent),
  ));
  for (var i = 0; i < chapterTitles.length; i++) {
    final html = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${chapterTitles[i]}</title></head>
<body><h1>${chapterTitles[i]}</h1><p>测试</p></body>
</html>''';
    archive.addFile(ArchiveFile(
      'OEBPS/ch${i + 1}.xhtml',
      html.length,
      utf8.encode(html),
    ));
  }
  return archive;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_subtitle_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MergeOperation EPUB3 副标题', () {
    test('EPUB3 refines 风格的副标题应被合并保留', () async {
      // 第一本书带 EPUB3 风格副标题：
      //   <dc:title id="t1">活着</dc:title>
      //   <dc:title id="t2">一个平凡人的一生</dc:title>
      //   <meta refines="#t2" property="title-type">subtitle</meta>
      const opf1 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="b1" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b1">urn:uuid:1</dc:identifier>
    <dc:title id="t1">活着</dc:title>
    <dc:title id="t2">一个平凡人的一生</dc:title>
    <meta refines="#t2" property="title-type">subtitle</meta>
    <dc:creator>余华</dc:creator>
    <dc:language>zh</dc:language>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
      const opf2 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="b2" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b2">urn:uuid:2</dc:identifier>
    <dc:title>围城</dc:title>
    <dc:creator>钱钟书</dc:creator>
    <dc:language>zh</dc:language>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';

      final p1 = p.join(tempDir.path, 'a.epub');
      final p2 = p.join(tempDir.path, 'b.epub');
      final out = p.join(tempDir.path, 'merged.epub');

      await File(p1).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf1))!);
      await File(p2).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf2))!);

      await MergeOperation.execute(
        inputPaths: [p1, p2],
        outputPath: out,
      );

      final merged = await EpubImageHelper.readArchive(out);
      final opf = merged.findFile('OEBPS/content.opf');
      expect(opf, isNotNull);
      final text = utf8.decode(opf!.content as List<int>);

      // 主标题「活着」必须保留
      expect(text, contains('活着'));
      // 副标题「一个平凡人的一生」也必须保留（修复前会被丢弃）
      expect(text, contains('一个平凡人的一生'),
          reason: 'EPUB3 refines 风格的副标题应被合并保留');
      // 副标题应带 title-type 标记
      expect(text, contains('title-type'),
          reason: '副标题应使用 title-type refines 标记');
    });

    test('EPUB2 风格的 <meta name="title"> 降级路径', () async {
      // 第一本书有 dc:title + <meta name="title"> 两种来源，
      // 优先使用 dc:title。
      const opf1 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="b1" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b1">urn:uuid:1</dc:identifier>
    <dc:title>主标题</dc:title>
    <meta name="title" content="EPUB2 标题"/>
    <dc:creator>作者</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
      const opf2 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="b2" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b2">urn:uuid:2</dc:identifier>
    <dc:title>另一本</dc:title>
    <dc:creator>另作者</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
      final p1 = p.join(tempDir.path, 'a.epub');
      final p2 = p.join(tempDir.path, 'b.epub');
      final out = p.join(tempDir.path, 'merged.epub');

      await File(p1).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf1))!);
      await File(p2).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf2))!);

      await MergeOperation.execute(
        inputPaths: [p1, p2],
        outputPath: out,
      );

      final merged = await EpubImageHelper.readArchive(out);
      final opfFile = merged.findFile('OEBPS/content.opf');
      final text = utf8.decode(opfFile!.content as List<int>);
      expect(text, contains('主标题'));
    });

    test('第一本书无 dc:title 时降级到 <meta name="title">', () async {
      // 第一本书只有 <meta name="title">，应被识别为标题
      const opf1 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="b1" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b1">urn:uuid:1</dc:identifier>
    <meta name="title" content="EPUB2 only title"/>
    <dc:creator>作者</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
      const opf2 = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="b2" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b2">urn:uuid:2</dc:identifier>
    <dc:title>另一本</dc:title>
    <dc:creator>另作者</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
      final p1 = p.join(tempDir.path, 'a.epub');
      final p2 = p.join(tempDir.path, 'b.epub');
      final out = p.join(tempDir.path, 'merged.epub');

      await File(p1).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf1))!);
      await File(p2).writeAsBytes(ZipEncoder().encode(_buildEpubWithOpf(opf2))!);

      await MergeOperation.execute(
        inputPaths: [p1, p2],
        outputPath: out,
      );

      final merged = await EpubImageHelper.readArchive(out);
      final opfFile = merged.findFile('OEBPS/content.opf');
      final text = utf8.decode(opfFile!.content as List<int>);
      // 应识别「EPUB2 only title」为标题（而非默认值「合并 EPUB」）
      expect(text, contains('EPUB2 only title'),
          reason: '缺少 dc:title 时应降级到 <meta name="title">');
      expect(text.contains('合并 EPUB'), false,
          reason: '不应使用硬编码默认值');
    });
  });
}
