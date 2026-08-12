// 回归测试：章评/书评注入
//
// 验证 WereadThoughtOperation 对章评(每章末尾区块)与书评(独立页面)的注入:
// 1. 章评区块出现在章节 HTML 末尾,并携带 CSS 样式链接
// 2. 书评生成独立 XHTML,OPF 中注册 manifest 条目 + spine itemref
// 3. 关闭开关后不注入

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_thought_operation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个最小 EPUB(单个章节)
Future<String> _buildMinimalEpub(String dir, String filename) async {
  const mimetype = 'application/epub+zip';
  const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
  const opfXml = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">test-book</dc:identifier>
    <dc:title>测试书</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>''';
  const chapterXml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章 测试章节</title></head>
<body>
<p>第一章的开头段落,包含一段可以匹配的引文内容用于定位划线。</p>
<p>这是第二段正文,继续补充一些文字,让引文可以匹配到唯一的段落位置。</p>
</body>
</html>''';
  const navXml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>目录</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">第一章</a></li></ol></nav></body>
</html>''';

  final archive = Archive();
  final mf = ArchiveFile('mimetype', mimetype.length, utf8.encode(mimetype))
    ..compress = false;
  archive.addFile(mf);
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    containerXml.length,
    utf8.encode(containerXml),
  ));
  archive.addFile(
    ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)),
  );
  archive.addFile(ArchiveFile(
    'OEBPS/chapter1.xhtml',
    chapterXml.length,
    utf8.encode(chapterXml),
  ));
  archive.addFile(
    ArchiveFile('OEBPS/nav.xhtml', navXml.length, utf8.encode(navXml)),
  );

  final zipBytes = ZipEncoder().encode(archive)!;
  final outputPath = '$dir/$filename';
  await File(outputPath).writeAsBytes(zipBytes);
  return outputPath;
}

/// 构造带段评/章评/书评的章节数据
List<ChapterData> _buildChapters({bool withChapterReviews = true}) {
  final underline = WereadUnderline(
    range: '1-25',
    markText: '第一章的开头段落,包含一段可以匹配的引文内容用于定位划线',
    chapterUid: '1',
  );
  final reviewMap = <String, List<WereadReview>>{
    '1-25': [
      WereadReview(
        range: '1-25',
        content: '这段写得真不错',
        abstract: '第一章的开头段落',
        author: '读者甲',
        likes: 12,
        createTime: 1700000000,
        chapterUid: '1',
      ),
    ],
  };
  return [
    ChapterData(
      chapterUid: '1',
      title: '第一章 测试章节',
      underlines: [underline],
      reviewMap: reviewMap,
      chapterReviews: withChapterReviews
          ? [
              WereadReview(
                content: '本章好评,剧情紧凑',
                author: '读者乙',
                likes: 8,
                createTime: 1700000001,
                chapterUid: '1',
                type: 'chapter',
              ),
            ]
          : [],
    ),
  ];
}

List<WereadReview> _buildBookReviews() => [
      WereadReview(
        content: '年度最佳推理小说,值得反复阅读',
        author: '读者丙',
        likes: 99,
        createTime: 1700000002,
        type: 'book',
      ),
      WereadReview(
        content: '结尾反转精彩',
        author: '读者丁',
        likes: 3,
        type: 'book',
      ),
    ];

/// 读取输出 EPUB 中的文件内容
Future<Map<String, String>> _readOutput(String outputPath) async {
  final bytes = await File(outputPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final result = <String, String>{};
  for (final f in archive.files) {
    if (f.name.isNotEmpty) {
      result[f.name] = utf8.decode(f.content as List<int>, allowMalformed: true);
    }
  }
  return result;
}

void main() {
  final tempDir = Directory.systemTemp.createTempSync('weread_reviews_test');

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('章评区块注入到章节末尾 + 书评生成独立页面', () async {
    final inputPath = await _buildMinimalEpub(tempDir.path, 'input.epub');
    final outputPath = '${tempDir.path}/output.epub';

    final result = await WereadThoughtOperation.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      chapters: _buildChapters(),
      notePngBytes: Uint8List.fromList([1, 2, 3, 4]),
      bookTitle: '测试书',
      bookReviews: _buildBookReviews(),
    );

    // 操作日志包含章评和书评统计
    expect(result, contains('1 条章评'));
    expect(result, contains('书评页'));

    final files = await _readOutput(outputPath);

    // 1. 章节 HTML:含想法锚点 + 章评区块 + CSS 链接
    final chapter1 = files['OEBPS/chapter1.xhtml']!;
    expect(chapter1, contains('js_readerFooterNote'),
        reason: '段评锚点应注入');
    expect(chapter1, contains('wr-reviews-block'),
        reason: '章评区块应注入');
    expect(chapter1, contains('本章好评,剧情紧凑'),
        reason: '章评内容应出现');
    expect(chapter1, contains('读者乙'),
        reason: '章评作者应出现');
    expect(chapter1, contains('赞 8'), reason: '章评点赞数应出现');
    expect(chapter1, contains('weread-thoughts.css'),
        reason: '章节应引用注入的 CSS');

    // 2. 书评独立页面
    expect(files.containsKey('OEBPS/weread-book-reviews.xhtml'), true,
        reason: '书评页文件应生成');
    final bookReviewsPage = files['OEBPS/weread-book-reviews.xhtml']!;
    expect(bookReviewsPage, contains('书评 · 测试书'));
    expect(bookReviewsPage, contains('年度最佳推理小说,值得反复阅读'));
    expect(bookReviewsPage, contains('结尾反转精彩'));
    expect(bookReviewsPage, contains('赞 99'));
    expect(RegExp(r'20\d\d-\d\d-\d\d').hasMatch(bookReviewsPage), true,
        reason: '时间戳应格式化为 YYYY-MM-DD 日期');

    // 3. OPF 注册书评页
    final opf = files['OEBPS/content.opf']!;
    expect(opf, contains('weread-book-reviews.xhtml'),
        reason: 'OPF manifest 应注册书评页');
    expect(opf, contains('<itemref idref="weread-book-reviews"'),
        reason: 'OPF spine 应追加书评页 itemref');
  });

  test('关闭章评/书评开关后不注入', () async {
    final inputPath = await _buildMinimalEpub(tempDir.path, 'input2.epub');
    final outputPath = '${tempDir.path}/output2.epub';

    final result = await WereadThoughtOperation.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      chapters: _buildChapters(withChapterReviews: true),
      notePngBytes: Uint8List.fromList([1, 2, 3, 4]),
      bookTitle: '测试书',
      bookReviews: _buildBookReviews(),
      enableChapterReviews: false,
      enableBookReviews: false,
    );

    final files = await _readOutput(outputPath);

    // 段评锚点仍然注入(默认行为不变)
    expect(files['OEBPS/chapter1.xhtml']!, contains('js_readerFooterNote'));
    // 章评区块不注入
    expect(files['OEBPS/chapter1.xhtml']!, isNot(contains('wr-reviews-block')),
        reason: '关闭开关后不应注入章评区块');
    // 书评页不生成
    expect(files.containsKey('OEBPS/weread-book-reviews.xhtml'), false,
        reason: '关闭开关后不应生成书评页');
    expect(files['OEBPS/content.opf']!,
        isNot(contains('weread-book-reviews.xhtml')));
    // 日志不含章评统计
    expect(result, isNot(contains('条章评')));
  });

  test('章评对齐失败时仍保留章评区块', () async {
    // 引文与正文完全不匹配 → 段评锚点 0 个,但章评仍应注入
    final inputPath = await _buildMinimalEpub(tempDir.path, 'input3.epub');
    final outputPath = '${tempDir.path}/output3.epub';

    final chapters = [
      ChapterData(
        chapterUid: '1',
        title: '第一章 测试章节',
        underlines: [
          WereadUnderline(
            range: '1-25',
            markText: '完全无法匹配到的引文内容',
            chapterUid: '1',
          ),
        ],
        reviewMap: {},
        chapterReviews: [
          WereadReview(
            content: '即使锚点失败章评也应该出现',
            author: '读者戊',
            type: 'chapter',
            chapterUid: '1',
          ),
        ],
      ),
    ];

    final result = await WereadThoughtOperation.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      chapters: chapters,
      notePngBytes: Uint8List.fromList([1, 2, 3, 4]),
      bookTitle: '测试书',
      bookReviews: const [],
      enableBookReviews: false,
    );

    final files = await _readOutput(outputPath);
    final chapter1 = files['OEBPS/chapter1.xhtml']!;
    expect(chapter1, isNot(contains('js_readerFooterNote')),
        reason: '引文不匹配时无段评锚点');
    expect(chapter1, contains('wr-reviews-block'),
        reason: '章评区块不依赖引文匹配,应仍然注入');
    expect(chapter1, contains('即使锚点失败章评也应该出现'));
    expect(result, contains('1 条章评'));
  });
}
