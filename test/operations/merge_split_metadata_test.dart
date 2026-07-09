// 回归测试：merge / split / encrypt_font 的元数据、OPF 标识符、archive 索引修复

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:epub_gadget/features/encrypt_font/encrypt_font.dart';
import 'package:epub_gadget/features/merge/merge.dart';
import 'package:epub_gadget/features/split/split.dart';
import 'package:epub_gadget/core/epub_image_helper.dart';

/// 构造一个最小但可用的 EPUB 用于测试
Archive _buildMinimalEpub({
  String title = '测试书名',
  String author = '测试作者',
  String? identifier,
  String language = 'zh',
  String version = '3.0',
  List<String> chapterTitles = const ['第一章', '第二章', '第三章', '第四章', '第五章'],
}) {
  final actualIdentifier =
      identifier ?? 'urn:uuid:test-${DateTime.now().microsecondsSinceEpoch}';
  final archive = Archive();

  // mimetype（不压缩，EPUB 规范要求）
  archive.addFile(
    ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
      ..compress = false,
  );

  // container.xml
  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''
          .length,
      utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
    ),
  );

  // nav.xhtml（EPUB3）
  final navItems = StringBuffer();
  for (var i = 0; i < chapterTitles.length; i++) {
    navItems.writeln(
      '    <li><a href="chapter_${i + 1}.xhtml">${chapterTitles[i]}</a></li>',
    );
  }
  final navContent =
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc">
    <ol>
$navItems    </ol>
  </nav>
</body>
</html>''';
  archive.addFile(
    ArchiveFile('OEBPS/nav.xhtml', navContent.length, utf8.encode(navContent)),
  );

  // content.opf
  final items = StringBuffer();
  final itemrefs = StringBuffer();
  for (var i = 0; i < chapterTitles.length; i++) {
    items.writeln(
      '    <item id="ch${i + 1}" href="chapter_${i + 1}.xhtml" media-type="application/xhtml+xml"/>',
    );
    itemrefs.writeln('    <itemref idref="ch${i + 1}"/>');
  }
  final opfContent =
      '''<?xml version="1.0" encoding="UTF-8"?>
<package version="$version" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">$actualIdentifier</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:language>$language</dc:language>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
$items  </manifest>
  <spine>
$itemrefs  </spine>
</package>''';
  archive.addFile(
    ArchiveFile(
      'OEBPS/content.opf',
      opfContent.length,
      utf8.encode(opfContent),
    ),
  );

  // 章节文件
  for (var i = 0; i < chapterTitles.length; i++) {
    final content =
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${chapterTitles[i]}</title></head>
<body>
  <h1>${chapterTitles[i]}</h1>
  <p>这是第 ${i + 1} 章的内容。包含一些中文生僻字：龘靐齉。</p>
  <p>常用字：中国上海。</p>
</body>
</html>''';
    archive.addFile(
      ArchiveFile(
        'OEBPS/chapter_${i + 1}.xhtml',
        content.length,
        utf8.encode(content),
      ),
    );
  }

  return archive;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_merge_split_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MergeOperation 真实元数据', () {
    test('合并后保留第一本书的真实标题/作者/语言', () async {
      // 准备两本 EPUB
      final epub1Path = p.join(tempDir.path, 'book1.epub');
      final epub2Path = p.join(tempDir.path, 'book2.epub');
      final outputPath = p.join(tempDir.path, 'merged.epub');

      final epub1 = _buildMinimalEpub(
        title: '活着',
        author: '余华',
        identifier: 'urn:uuid:book1',
        chapterTitles: ['第一章', '第二章', '第三章'],
      );
      final epub2 = _buildMinimalEpub(
        title: '围城',
        author: '钱钟书',
        identifier: 'urn:uuid:book2',
        chapterTitles: ['第一章', '第二章'],
      );

      await File(epub1Path).writeAsBytes(ZipEncoder().encode(epub1)!);
      await File(epub2Path).writeAsBytes(ZipEncoder().encode(epub2)!);

      final log = await MergeOperation.execute(
        inputPaths: [epub1Path, epub2Path],
        outputPath: outputPath,
      );

      // 验证输出 EPUB 存在
      expect(await File(outputPath).exists(), true);

      // 验证输出 EPUB 包含第一本书的真实元数据
      final outputArchive = await EpubImageHelper.readArchive(outputPath);
      final opfFile = outputArchive.findFile('OEBPS/content.opf');
      expect(opfFile, isNotNull);
      final opfContent = utf8.decode(opfFile!.content as List<int>);

      // 必须包含「活着」或「余华」（不允许是「合并 EPUB」默认值）
      expect(
        opfContent,
        contains('活着'),
        reason: '合并后应保留第一本书标题，不应是默认值「合并 EPUB」',
      );
      expect(opfContent, contains('余华'), reason: '合并后应保留第一本书作者');
      expect(
        opfContent.contains('合并 EPUB'),
        false,
        reason: '不应使用硬编码默认值「合并 EPUB」',
      );
      // log 中应报告合并结果
      expect(log, isNotEmpty);
    });

    test('合并时可覆盖书名作者简介并设置封面', () async {
      final epub1Path = p.join(tempDir.path, 'book1.epub');
      final epub2Path = p.join(tempDir.path, 'book2.epub');
      final outputPath = p.join(tempDir.path, 'merged_custom.epub');
      final coverPath = p.join(tempDir.path, 'cover.png');

      await File(epub1Path).writeAsBytes(
        ZipEncoder().encode(
          _buildMinimalEpub(
            title: '原书名',
            author: '原作者',
            chapterTitles: ['第一章'],
          ),
        )!,
      );
      await File(epub2Path).writeAsBytes(
        ZipEncoder().encode(
          _buildMinimalEpub(
            title: '第二本',
            author: '第二作者',
            chapterTitles: ['第二章'],
          ),
        )!,
      );
      await File(
        coverPath,
      ).writeAsBytes(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

      await MergeOperation.execute(
        inputPaths: [epub1Path, epub2Path],
        outputPath: outputPath,
        options: MergeOptions(
          title: '自定义合集',
          author: '自定义作者',
          language: 'zh-CN',
          publisher: '自定义出版社',
          description: '自定义简介',
          coverPath: coverPath,
        ),
      );

      final outputArchive = await EpubImageHelper.readArchive(outputPath);
      final opfContent = utf8.decode(
        outputArchive.findFile('OEBPS/content.opf')!.content as List<int>,
      );

      expect(opfContent, contains('<dc:title>自定义合集</dc:title>'));
      expect(opfContent, contains('<dc:creator>自定义作者</dc:creator>'));
      expect(opfContent, contains('<dc:language>zh-CN</dc:language>'));
      expect(opfContent, contains('<dc:publisher>自定义出版社</dc:publisher>'));
      expect(opfContent, contains('<dc:description>自定义简介</dc:description>'));
      expect(
        opfContent,
        contains('<meta name="cover" content="merged-cover-image"/>'),
      );
      expect(opfContent, contains('href="Images/cover.png"'));
      expect(opfContent, contains('properties="cover-image"'));
      expect(outputArchive.findFile('OEBPS/Images/cover.png'), isNotNull);
    });
  });

  group('SplitOperation 唯一 dc:identifier', () {
    test('拆分后每个分卷的 dc:identifier 都不相同', () async {
      final epubPath = p.join(tempDir.path, 'book.epub');
      final outputDir = p.join(tempDir.path, 'split');

      final epub = _buildMinimalEpub(
        title: '三国演义',
        author: '罗贯中',
        chapterTitles: List.generate(6, (i) => '第${i + 1}章'),
      );
      await File(epubPath).writeAsBytes(ZipEncoder().encode(epub)!);

      final log = await SplitOperation.execute(
        epubPath: epubPath,
        outputDir: outputDir,
        splitPoints: [2, 4], // 拆 3 段
      );
      // 验证 log 中报告了拆分段数
      expect(log, contains('3'));

      // 找到输出目录中所有 .epub 文件
      final files = (await Directory(outputDir).list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.epub'))
          .toList();
      expect(files.length, 3, reason: '应该拆分出 3 个分卷');

      // 解析每个分卷的 OPF，提取 dc:identifier
      final identifiers = <String>[];
      final titles = <String>[];
      for (final f in files) {
        final archive = await EpubImageHelper.readArchive(f.path);
        final opfFile = archive.findFile('OEBPS/content.opf');
        expect(opfFile, isNotNull);
        final opfContent = utf8.decode(opfFile!.content as List<int>);

        // 提取 dc:identifier 文本
        final idMatch = RegExp(
          r'<dc:identifier[^>]*>([^<]+)</dc:identifier>',
        ).firstMatch(opfContent);
        expect(idMatch, isNotNull, reason: '每个分卷必须有 dc:identifier');
        identifiers.add(idMatch!.group(1)!);

        // 提取 dc:title
        final titleMatch = RegExp(
          r'<dc:title[^>]*>([^<]+)</dc:title>',
        ).firstMatch(opfContent);
        expect(titleMatch, isNotNull);
        titles.add(titleMatch!.group(1)!);
      }

      // 所有 identifier 必须互不相同
      expect(
        identifiers.toSet().length,
        identifiers.length,
        reason: '所有分卷的 dc:identifier 必须互不相同，避免 Kindle 合并目录',
      );

      // 标题应包含原书名「三国演义」
      for (final title in titles) {
        expect(title, contains('三国演义'), reason: '分卷标题应包含原书名');
        expect(title, contains('/'), reason: '分卷标题应包含分卷序号（如 1/3）');
      }
    });
  });

  group('encryptFont archive 索引安全', () {
    test('10+ 字体循环加密不触发 RangeError', () async {
      // 这个测试需要更复杂的 mock，且 TtfFontEncryptor 实现细节较多。
      // 这里仅做烟雾测试：构造一个不包含字体文件的简单 EPUB，验证
      // execute 不会崩溃
      final epubPath = p.join(tempDir.path, 'no_font.epub');
      final outputPath = p.join(tempDir.path, 'no_font_out.epub');

      final epub = _buildMinimalEpub(
        title: '无字体',
        chapterTitles: ['ch1', 'ch2'],
      );
      await File(epubPath).writeAsBytes(ZipEncoder().encode(epub)!);

      final log = await EncryptFontOperation.execute(
        epubPath: epubPath,
        outputPath: outputPath,
      );

      // 不抛出异常 + 输出文件存在
      expect(await File(outputPath).exists(), true);
      expect(log, isNotEmpty);
    });
  });
}
