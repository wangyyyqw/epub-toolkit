import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory tempDir;
  late String headerPngPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('txt2epub_header_');
    headerPngPath = '${tempDir.path}/my-header.png';
    await File(
      headerPngPath,
    ).writeAsBytes(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('阅微头图写入 Images、manifest、每章标题前和样式表', () async {
    final outputPath = '${tempDir.path}/yuewei-header.epub';
    final (log, _) = await EpubGenerator.generate(
      outputPath: outputPath,
      title: '头图测试',
      author: '作者',
      chapters: const [
        Chapter(title: '第1章 开始', content: '正文一'),
        Chapter(title: '第2章 继续', content: '正文二', level: 2),
      ],
      headerImagePath: headerPngPath,
      headerImageStyle: ChapterHeaderImageStyle.yuewei,
    );

    final archive = _readArchive(outputPath);
    expect(log, contains('阅微章节头图'));
    expect(archive.findFile('OEBPS/Images/logo.png'), isNotNull);

    final opf = _text(archive, 'OEBPS/content.opf');
    expect(
      opf,
      contains(
        'id="chapter-header-image" href="Images/logo.png" media-type="image/png"',
      ),
    );

    final css = _text(archive, 'OEBPS/style.css');
    _expectNoInjectedBodyStyle(css);
    expect(css, contains('duokan-text-indent: 0;'));
    expect(css, contains('duokan-bleed: lefttopright;'));
    expect(css, contains('.logo .responsive-image {\n  width: 100%;'));
    expect(css, isNot(contains('width: 122%;')));

    final chapters = archive.files
        .where(
          (file) =>
              file.isFile &&
              file.name.startsWith('OEBPS/Chapter') &&
              file.name.endsWith('.xhtml'),
        )
        .toList();
    expect(chapters, hasLength(2));
    for (final file in chapters) {
      final xhtml = utf8.decode(file.content as List<int>);
      expect(
        xhtml,
        contains(
          '<div class="logo">\n'
          '    <img class="responsive-image" alt="logo" src="Images/logo.png"/>\n'
          '  </div>',
        ),
      );
      final heading = RegExp(r'<h[1-6]>').firstMatch(xhtml);
      expect(heading, isNotNull);
      expect(xhtml.indexOf('<div class="logo">'), lessThan(heading!.start));
    }
  });

  test('Kindle 头图使用越过页边距的响应式样式', () async {
    final jpgPath = '${tempDir.path}/header.jpeg';
    await File(jpgPath).writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    final outputPath = '${tempDir.path}/kindle.epub';

    await EpubGenerator.generate(
      outputPath: outputPath,
      title: 'Kindle 头图测试',
      author: '作者',
      chapters: const [Chapter(title: '第一章', content: '正文')],
      headerImagePath: jpgPath,
      headerImageStyle: ChapterHeaderImageStyle.kindle,
    );

    final archive = _readArchive(outputPath);
    expect(archive.findFile('OEBPS/Images/logo.jpg'), isNotNull);
    expect(
      _text(archive, 'OEBPS/content.opf'),
      contains('href="Images/logo.jpg" media-type="image/jpeg"'),
    );
    final css = _text(archive, 'OEBPS/style.css');
    _expectNoInjectedBodyStyle(css);
    expect(css, contains('div.logo {'));
    expect(css, contains('width: 122%;'));
    expect(css, contains('margin: -8% -11% 0;'));
    expect(css, contains('img.responsive-image {'));
    expect(css, contains('height: auto;'));
    expect(css, contains('display: block;'));
    expect(css, isNot(contains('duokan-bleed')));
  });

  test('未选择头图时保持现有 EPUB 输出，不添加头图资源或样式', () async {
    final outputPath = '${tempDir.path}/plain.epub';
    await EpubGenerator.generate(
      outputPath: outputPath,
      title: '普通测试',
      author: '作者',
      chapters: const [Chapter(title: '第一章', content: '正文')],
    );

    final archive = _readArchive(outputPath);
    expect(archive.findFile('OEBPS/Images/logo.png'), isNull);
    expect(archive.findFile('OEBPS/Text/fullscreen-cover.xhtml'), isNull);
    expect(archive.findFile('OEBPS/Styles/main.css'), isNull);
    expect(
      _text(archive, 'OEBPS/content.opf'),
      isNot(contains('chapter-header-image')),
    );
    final css = _text(archive, 'OEBPS/style.css');
    _expectNoInjectedBodyStyle(css);
    expect(css, isNot(contains('duokan-bleed')));
    expect(
      _text(archive, 'OEBPS/Chapter0001.xhtml'),
      isNot(contains('class="logo"')),
    );
  });

  test('拒绝不适合阅微和 Kindle 的头图格式', () async {
    final webpPath = '${tempDir.path}/header.webp';
    await File(webpPath).writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);

    await expectLater(
      EpubGenerator.generate(
        outputPath: '${tempDir.path}/invalid.epub',
        title: '格式测试',
        author: '作者',
        chapters: const [Chapter(title: '第一章', content: '正文')],
        headerImagePath: webpPath,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('仅支持 PNG、JPG 或 JPEG'),
        ),
      ),
    );
  });

  test('阅微全屏首页使用根目录背景图并位于 spine 第一项', () async {
    final coverPath = await _writePng(tempDir, 'yuewei-cover.png', 1080, 2400);
    final outputPath = '${tempDir.path}/yuewei-fullscreen.epub';

    final (log, _) = await EpubGenerator.generate(
      outputPath: outputPath,
      title: '阅微首页测试',
      author: '作者',
      chapters: const [Chapter(title: '第一章', content: '正文')],
      fullScreenCoverImagePath: coverPath,
      fullScreenCoverStyle: FullScreenCoverStyle.yuewei,
    );

    final archive = _readArchive(outputPath);
    _expectNoInjectedBodyStyle(_text(archive, 'OEBPS/style.css'));
    expect(log, contains('阅微全屏首页（1080×2400）'));
    expect(archive.findFile('cover~slim.png'), isNotNull);
    final xhtml = _text(archive, 'OEBPS/Text/fullscreen-cover.xhtml');
    expect(xhtml, contains('<body class="cover-page">'));
    expect(xhtml, contains('<div class="fm">'));
    expect(xhtml, contains('<p>&#160;</p>'));
    expect(xhtml, contains('<h2 class="none">封面</h2>'));
    expect(xhtml, contains('href="../Styles/main.css"'));
    expect(xhtml, contains('overflow: hidden;'));

    final css = _text(archive, 'OEBPS/Styles/main.css');
    expect(css, contains('background-image: url("../../cover~slim.png");'));
    expect(css, contains('background-size: cover;'));
    expect(css, contains('.fm p {'));
    expect(css, contains('.none {\n  display: none;'));

    final opf = _text(archive, 'OEBPS/content.opf');
    expect(opf, contains('href="Text/fullscreen-cover.xhtml"'));
    expect(opf, contains('href="Styles/main.css"'));
    expect(opf, contains('href="../cover~slim.png"'));
    expect(_firstSpineId(opf), 'fullscreen-cover');
    expect(
      opf.indexOf('<itemref idref="fullscreen-cover"/>'),
      lessThan(opf.indexOf('<itemref idref="chapter1"/>')),
    );
  });

  test('Kindle 全屏首页使用独立图片和响应式居中样式', () async {
    final coverPath = await _writePng(tempDir, 'kindle-cover.png', 1536, 2048);
    final outputPath = '${tempDir.path}/kindle-fullscreen.epub';

    await EpubGenerator.generate(
      outputPath: outputPath,
      title: 'Kindle 首页测试',
      author: '作者',
      chapters: const [Chapter(title: '第一章', content: '正文')],
      fullScreenCoverImagePath: coverPath,
      fullScreenCoverStyle: FullScreenCoverStyle.kindle,
    );

    final archive = _readArchive(outputPath);
    _expectNoInjectedBodyStyle(_text(archive, 'OEBPS/style.css'));
    expect(archive.findFile('OEBPS/Images/fullscreen-cover.png'), isNotNull);
    expect(archive.findFile('OEBPS/Images/cover.png'), isNull);
    final xhtml = _text(archive, 'OEBPS/Text/fullscreen-cover.xhtml');
    expect(xhtml, contains('<body class="epub-cover">'));
    expect(xhtml, contains('<div class="cover-image-container">'));
    expect(xhtml, contains('src="../Images/fullscreen-cover.png"'));

    final css = _text(archive, 'OEBPS/Styles/main.css');
    expect(css, contains('body.epub-cover {'));
    expect(css, contains('height: 100vh;'));
    expect(css, contains('max-height: 95vh;'));
    expect(css, contains('justify-content: center;'));

    final opf = _text(archive, 'OEBPS/content.opf');
    expect(opf, contains('<itemref idref="fullscreen-cover"/>'));
    expect(
      opf,
      contains(
        'id="fullscreen-cover-image" href="Images/fullscreen-cover.png"',
      ),
    );
    expect(_firstSpineId(opf), 'fullscreen-cover');
    expect(
      opf.indexOf('<itemref idref="fullscreen-cover"/>'),
      lessThan(opf.indexOf('<itemref idref="chapter1"/>')),
    );
  });

  test('普通封面与全屏首页可使用两张不同图片', () async {
    final coverPath = await _writePng(tempDir, 'regular-cover.png', 600, 800);
    final firstPagePath = await _writePng(
      tempDir,
      'first-page.png',
      1536,
      2048,
    );
    final outputPath = '${tempDir.path}/separate-cover-images.epub';

    await EpubGenerator.generate(
      outputPath: outputPath,
      title: '独立图片测试',
      author: '作者',
      chapters: const [Chapter(title: '第一章', content: '正文')],
      coverPath: coverPath,
      fullScreenCoverImagePath: firstPagePath,
      fullScreenCoverStyle: FullScreenCoverStyle.kindle,
    );

    final archive = _readArchive(outputPath);
    expect(archive.findFile('OEBPS/Images/cover.png'), isNotNull);
    expect(archive.findFile('OEBPS/Images/fullscreen-cover.png'), isNotNull);
    final coverBytes =
        archive.findFile('OEBPS/Images/cover.png')!.content as List<int>;
    final firstPageBytes =
        archive.findFile('OEBPS/Images/fullscreen-cover.png')!.content
            as List<int>;
    expect(listEquals(coverBytes, firstPageBytes), isFalse);
    final opf = _text(archive, 'OEBPS/content.opf');
    expect(opf, contains('id="cover-image" href="Images/cover.png"'));
    expect(
      opf,
      contains(
        'id="fullscreen-cover-image" href="Images/fullscreen-cover.png"',
      ),
    );
  });

  test('全屏首页拒绝与模板不匹配的封面尺寸', () async {
    final coverPath = await _writePng(tempDir, 'wrong-size.png', 100, 200);

    await expectLater(
      EpubGenerator.generate(
        outputPath: '${tempDir.path}/wrong-size.epub',
        title: '尺寸测试',
        author: '作者',
        chapters: const [Chapter(title: '第一章', content: '正文')],
        fullScreenCoverImagePath: coverPath,
        fullScreenCoverStyle: FullScreenCoverStyle.yuewei,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('必须为 1080×2400'),
        ),
      ),
    );
  });
}

void _expectNoInjectedBodyStyle(String css) {
  expect(css, isNot(contains('body {')));
  expect(css, isNot(contains('margin: 5%;')));
  expect(css, isNot(contains('Noto Serif CJK SC')));
  expect(css, isNot(contains('line-height: 1.8;')));
}

Archive _readArchive(String path) {
  return ZipDecoder().decodeBytes(File(path).readAsBytesSync(), verify: true);
}

String _text(Archive archive, String path) {
  return utf8.decode(archive.findFile(path)!.content as List<int>);
}

Future<String> _writePng(
  Directory directory,
  String filename,
  int width,
  int height,
) async {
  final path = '${directory.path}/$filename';
  final image = img.Image(width, height);
  await File(path).writeAsBytes(img.encodePng(image, level: 9));
  return path;
}

String? _firstSpineId(String opf) {
  return RegExp(
    r'<spine[^>]*>\s*<itemref idref="([^"]+)"',
  ).firstMatch(opf)?.group(1);
}
