// 复现测试：宋慈洗冤笔记(1-4册) 简转繁失败 "Null check operator used on a null value"
//
// 通过真实字典 + 真实 Isolate.run 后台执行路径,构造 4 卷合一的大书特征
// (中文文件名、数百章节、超大章节、二进制图片)来复现空检查异常。

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/core/background_task.dart';
import 'package:epub_gadget/features/s2t/chinese_convert_base.dart';
import 'package:epub_gadget/features/s2t/chinese_converter.dart';
import 'package:epub_gadget/features/t2s/chinese_convert_base.dart' as t2s_base;
import 'package:epub_gadget/features/t2s/chinese_converter.dart' as t2s_conv;
import 'package:flutter_test/flutter_test.dart';

/// 模拟 S2tPage 的 State:在实例方法内调用 runBackgroundTask。
///
/// 回归点:若传闭包(会隐式捕获 this → 整棵 Widget 树),Isolate 会抛
/// "Illegal argument in isolate message: object is unsendable"。
class _FakeS2tPage {
  _FakeS2tPage(this.inputPath, this.outputPath);

  final String inputPath;
  final String outputPath;

  Future<String> execute() async {
    await ChineseConverter.initS2T();
    return runBackgroundTask(runS2tTask, [
      inputPath,
      outputPath,
      ChineseConverter.s2tPhrases,
      ChineseConverter.s2tCharacters,
      ChineseConverter.s2tPhraseMaxLen,
      ChineseConverter.s2tCharMaxLen,
    ]);
  }
}

/// 模拟 T2sPage 的 State(t2s 方向同构回归点)
class _FakeT2sPage {
  _FakeT2sPage(this.inputPath, this.outputPath);

  final String inputPath;
  final String outputPath;

  Future<String> execute() async {
    await t2s_conv.ChineseConverter.initT2S();
    return runBackgroundTask(t2s_base.runT2sTask, [
      inputPath,
      outputPath,
      t2s_conv.ChineseConverter.t2sPhrases,
      t2s_conv.ChineseConverter.t2sCharacters,
      t2s_conv.ChineseConverter.t2sPhraseMaxLen,
      t2s_conv.ChineseConverter.t2sCharMaxLen,
    ]);
  }
}

Future<String> _buildStressEpub(String dir) async {
  final archive = Archive();
  archive.addFile(
    ArchiveFile('mimetype', 'application/epub+zip'.length,
        utf8.encode('application/epub+zip'))
      ..compress = false,
  );
  archive.addFile(ArchiveFile.string(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
    '</rootfiles></container>',
  ));

  final items = StringBuffer();
  final spine = StringBuffer();
  final rand = Random(42);
  final chapterCount = 300;

  for (var i = 1; i <= chapterCount; i++) {
    final vol = (i - 1) ~/ 100 + 1;
    final name =
        '第$vol卷/第${i.toString().padLeft(3, '0')}章.xhtml';
    items.writeln(
        '    <item id="c$i" href="$name" media-type="application/xhtml+xml"/>');
    spine.writeln('    <itemref idref="c$i"/>');

    // 大章节:单个章节文本约 1.5MB,累计约 450MB 文本(不实际写这么多,取前 50 章大)
    final big = i <= 50;
    final paraCount = big ? 6000 : 20;
    final body = StringBuffer();
    for (var p = 0; p < paraCount; p++) {
      body.writeln(
          '<p>第$i章 这是简体中文内容用于测试转换。宋朝提刑官宋慈在洗冤集录中记载了验尸之道。'
          '${rand.nextInt(10000)}号现场发现线索。</p>');
    }
    final xhtml =
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head><title>第$i章 洗冤录</title>'
        '<style>p{margin:0;text-indent:2em;}</style></head>\n'
        '<body>\n$body</body>\n</html>';
    archive.addFile(ArchiveFile(
        name, utf8.encode(xhtml).length, utf8.encode(xhtml)));
  }

  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">\n'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
      '  <dc:identifier id="uid">stress-book</dc:identifier>\n'
      '  <dc:title>宋慈洗冤笔记</dc:title>\n'
      '  <dc:language>zh</dc:language>\n'
      '  <meta name="cover" content="cover"/>\n'
      '</metadata>\n'
      '<manifest>\n'
      '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n'
      '    <item id="cover" href="images/cover.jpg" media-type="image/jpeg"/>\n'
      '${items.toString()}'
      '</manifest>\n'
      '<spine toc="ncx">\n'
      '${spine.toString()}'
      '</spine>\n'
      '</package>';
  archive.addFile(ArchiveFile(
      'OEBPS/content.opf', utf8.encode(opf).length, utf8.encode(opf)));

  final navPoints = StringBuffer();
  for (var i = 1; i <= chapterCount; i++) {
    navPoints.writeln(
        '<navPoint id="np$i"><navLabel><text>第$i章 洗冤录</text></navLabel>'
        '<content src="第${(i - 1) ~/ 100 + 1}卷/第${i.toString().padLeft(3, '0')}章.xhtml"/></navPoint>');
  }
  final ncx =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
      '<head><meta name="dtb:uid" content="stress-book"/></head>\n'
      '<docTitle><text>宋慈洗冤笔记</text></docTitle>\n'
      '<navMap>\n${navPoints.toString()}</navMap>\n'
      '</ncx>';
  archive.addFile(
      ArchiveFile('OEBPS/toc.ncx', utf8.encode(ncx).length, utf8.encode(ncx)));
  // 二进制图片(模拟真实书籍的图)
  for (var i = 0; i < 120; i++) {
    final imgBytes =
        List<int>.generate(300000, (i) => (i * 7 + i % 13) % 251);
    archive.addFile(ArchiveFile(
      'OEBPS/images/img_${i.toString().padLeft(3, '0')}.jpg',
      imgBytes.length,
      Uint8List.fromList(imgBytes),
    ));
  }

  // 同一路径出现重复文件(模拟 4 卷合一时目录名冲突)
  archive.addFile(ArchiveFile('OEBPS/重复章.xhtml', 10, utf8.encode('<p>冲突</p>')));

  // 空文件与纯目录条目
  archive.addFile(ArchiveFile('OEBPS/empty.txt', 0, Uint8List(0)));
  archive.addFile(ArchiveFile('OEBPS/images/', 0, Uint8List(0))
    ..isFile = false);

  final outputPath = '$dir/stress.epub';
  await File(outputPath).writeAsBytes(ZipEncoder().encode(archive)!);
  return outputPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('s2t_stress');

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('复现:实例方法 + 顶层任务函数 + 大书特征(4卷合一)', () async {
    final inputPath = await _buildStressEpub(tempDir.path);
    final outPath = '${tempDir.path}/out.epub';
    // ignore: avoid_print
    print('输入文件大小: ${(await File(inputPath).length() / 1024 / 1024).toStringAsFixed(1)} MB');

    // 与 S2tPage._execute 完全一致的模式:实例方法内调用 runBackgroundTask,
    // 传顶层函数 runS2tTask + 消息数据(字典由 UI isolate 加载后随消息传递)。
    final page = _FakeS2tPage(inputPath, outPath);
    final result = await page.execute();

    // ignore: avoid_print
    print('转换结果: $result');
    expect(await File(outPath).exists(), true);
    final bytes = await File(outPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapter = archive.findFile('第1卷/第001章.xhtml');
    expect(chapter, isNotNull);
    final content = utf8.decode(chapter!.content as List<int>);
    expect(content, contains('簡體'), reason: '大章节正文应被转换');
  });

  test('t2s 同构回归:实例方法 + 顶层任务函数', () async {
    final archive = Archive();
    archive.addFile(ArchiveFile.string('mimetype', 'application/epub+zip')
      ..compress = false);
    archive.addFile(ArchiveFile.string(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles></container>',
    ));
    archive.addFile(ArchiveFile.string(
      'OEBPS/content.opf',
      '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>測試</dc:title></metadata>'
      '<manifest><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>',
    ));
    archive.addFile(ArchiveFile.string(
      'OEBPS/ch1.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">'
      '<head><title>第一章 測試</title></head>'
      '<body><p>這是繁體中文內容,用於測試轉換。</p></body></html>',
    ));
    final inputPath = '${tempDir.path}/trad.epub';
    await File(inputPath).writeAsBytes(ZipEncoder().encode(archive)!);
    final outPath = '${tempDir.path}/trad_out.epub';

    final page = _FakeT2sPage(inputPath, outPath);
    final result = await page.execute();

    // ignore: avoid_print
    print('t2s 转换结果: $result');
    final bytes = await File(outPath).readAsBytes();
    final outArchive = ZipDecoder().decodeBytes(bytes);
    final chapter = outArchive.findFile('OEBPS/ch1.xhtml');
    expect(chapter, isNotNull);
    final content = utf8.decode(chapter!.content as List<int>);
    expect(content, contains('这是'), reason: '繁体正文应转为简体');
  });
}
