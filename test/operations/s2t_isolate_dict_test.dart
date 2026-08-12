// 回归测试：简繁转换后台 isolate 字典参数化
//
// 之前的 bug：s2t/t2s 放入后台 isolate 后，ChineseConverter.initS2T()
// 内部使用 rootBundle 加载字典——rootBundle 依赖 Flutter Binding，
// 在 isolate 中不可用，抛 "Null check operator used on a null value"。
//
// 修复：字典在 UI isolate 加载后作为参数传入后台 isolate，
// ChineseConvertBase.execute 支持外部字典参数，转换不再依赖
// 当前 isolate 的静态状态。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/s2t/chinese_convert_base.dart';
import 'package:epub_gadget/features/s2t/chinese_converter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个包含简体中文的最小 EPUB
Future<String> _buildEpub(String dir, String filename) async {
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
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>''';
  const chapterXml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章 测试</title></head>
<body>
<p>这里是简体中文内容,用于测试转换。</p>
</body>
</html>''';

  final archive = Archive();
  archive.addFile(
    ArchiveFile('mimetype', mimetype.length, utf8.encode(mimetype))
      ..compress = false,
  );
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

  final outputPath = '$dir/$filename';
  await File(outputPath).writeAsBytes(ZipEncoder().encode(archive)!);
  return outputPath;
}

void main() {
  // rootBundle 需要 Flutter Binding(测试 3 走自动加载路径)
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('s2t_isolate_test');

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('s2tWithDict 使用外部字典转换,不依赖静态初始化', () {
    // 模拟后台 isolate 场景:静态字典未初始化(null)
    final phrases = <String, String>{
      '简体中文': '簡體中文',
    };
    final characters = <String, String>{
      '测': '測',
      '试': '試',
      '这': '這',
      '里': '裡',
      '为': '為',
      '转': '轉',
      '换': '換',
    };
    final result = ChineseConverter.s2tWithDict(
      '这里是简体中文内容,用于测试转换。',
      phrases: phrases,
      characters: characters,
      phraseMaxLen: 4,
      charMaxLen: 1,
    );
    expect(result, contains('簡體中文'), reason: '词组应匹配');
    expect(result, contains('這裡'), reason: '字符级转换应生效');
    expect(result, contains('測試'), reason: '字符级转换应生效');
  });

  test('ChineseConvertBase.execute 支持外部字典(后台 isolate 场景)', () async {
    final inputPath = await _buildEpub(tempDir.path, 'input.epub');
    final outputPath = '${tempDir.path}/output.epub';

    final phrases = <String, String>{
      '简体中文': '簡體中文',
    };
    final characters = <String, String>{
      '测': '測',
      '试': '試',
      '这': '這',
      '里': '裡',
      '为': '為',
      '转': '轉',
      '换': '換',
    };

    final log = await ChineseConvertBase.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      mode: 's2t',
      phrases: phrases,
      characters: characters,
      phraseMaxLen: 4,
      charMaxLen: 1,
    );

    expect(log, contains('转换 2 个文件'),
        reason: '应转换 OPF 与章节两个文本文件');

    final bytes = await File(outputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapter = archive.findFile('OEBPS/chapter1.xhtml');
    expect(chapter, isNotNull);
    final content = utf8.decode(chapter!.content as List<int>);
    expect(content, contains('這裡是簡體中文内容'),
        reason: '正文应被转换为繁体(测试字典仅含部分映射)');
    expect(content, contains('測試'), reason: '标题中的测试应转换');
  });

  test('execute 不传字典时在 UI isolate 自动加载(rootBundle 路径)', () async {
    // 测试环境 rootBundle 可用,验证兼容路径
    final inputPath = await _buildEpub(tempDir.path, 'input2.epub');
    final outputPath = '${tempDir.path}/output2.epub';

    final log = await ChineseConvertBase.execute(
      epubPath: inputPath,
      outputPath: outputPath,
      mode: 's2t',
    );

    expect(log, contains('转换'), reason: '自动加载字典路径应可执行');

    final bytes = await File(outputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapter = archive.findFile('OEBPS/chapter1.xhtml');
    final content = utf8.decode(chapter!.content as List<int>);
    expect(content, isNot(contains('这里是简体中文内容')),
        reason: '完整字典转换后不应保留简体原文');
  });
}
