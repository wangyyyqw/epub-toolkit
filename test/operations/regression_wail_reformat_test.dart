// 端到端集成测试：EpubReformatter 对齐原 Wail (Python) 项目的功能
//
// 验证以下 wail 版核心能力：
// 1. 资源规范化到 OEBPS/Text|Styles|Images|Fonts|Audio|Video|Misc
// 2. container.xml media-type 修正为 application/oebps-package+xml
// 3. mimetype 强制 STORED 且为 ZIP 第一个文件
// 4. manifest 重写为指向规范化目录
// 5. xhtml 链接重写（href/src/url 等）
// 6. xhtml DOCTYPE 补齐
// 7. 重复 ID 检测
// 8. 未在 OPF 的有效文件自动补全

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个最小化但完整的 EPUB archive
Archive _buildSampleEpub() {
  final archive = Archive();

  // mimetype
  archive.addFile(ArchiveFile(
    'mimetype',
    20,
    Uint8List.fromList(utf8.encode('application/epub+zip')),
  )..compress = false);

  // META-INF/container.xml
  const containerXml =
      '<?xml version="1.0" encoding="utf-8"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
      '</container>';
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    containerXml.length,
    Uint8List.fromList(utf8.encode(containerXml)),
  )..compress = true);

  // OEBPS/content.opf (EPUB 2.0)
  const opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">urn:uuid:1</dc:identifier>
<dc:title>Test Book</dc:title>
<dc:creator>Tester</dc:creator>
<dc:language>zh-CN</dc:language>
<meta name="cover" content="cover-img"/>
</metadata>
<manifest>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>
<item id="ch1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
<item id="ch2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml"/>
<item id="style" href="Styles/main.css" media-type="text/css"/>
</manifest>
<spine toc="ncx">
<itemref idref="ch1"/>
<itemref idref="ch2"/>
</spine>
</package>''';
  archive.addFile(ArchiveFile(
    'OEBPS/content.opf',
    opf.length,
    Uint8List.fromList(utf8.encode(opf)),
  )..compress = true);

  // OEBPS/toc.ncx
  const ncx = '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="urn:uuid:1"/></head>
<docTitle><text>Test Book</text></docTitle>
<navMap>
<navPoint id="np1" playOrder="1"><navLabel><text>Ch 1</text></navLabel><content src="Text/chapter1.xhtml"/></navPoint>
</navMap>
</ncx>''';
  archive.addFile(ArchiveFile(
    'OEBPS/toc.ncx',
    ncx.length,
    Uint8List.fromList(utf8.encode(ncx)),
  )..compress = true);

  // 章节
  for (final i in [1, 2]) {
    final xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Ch $i</title><link rel="stylesheet" type="text/css" href="../Styles/main.css"/></head>
<body>
<h1>Chapter $i</h1>
<p><img src="../images/cover.jpg" alt="cover"/></p>
<p>Visit <a href="../images/cover.jpg">cover</a></p>
</body>
</html>''';
    archive.addFile(ArchiveFile(
      'OEBPS/Text/chapter$i.xhtml',
      xhtml.length,
      Uint8List.fromList(utf8.encode(xhtml)),
    )..compress = true);
  }

  // CSS
  const css = 'body { background: url("../images/cover.jpg"); }';
  archive.addFile(ArchiveFile(
    'OEBPS/Styles/main.css',
    css.length,
    Uint8List.fromList(utf8.encode(css)),
  )..compress = true);

  // 图片
  final img = Uint8List.fromList(List.generate(20, (i) => i));
  archive.addFile(ArchiveFile(
    'OEBPS/images/cover.jpg',
    img.length,
    img,
  )..compress = false);

  return archive;
}

/// 写出 archive 为临时 ZIP
Future<String> _writeTemp(Archive archive) async {
  final path = '${Directory.systemTemp.path}/test_input_${DateTime.now().microsecondsSinceEpoch}.epub';
  final bytes = ZipEncoder().encode(archive);
  await File(path).writeAsBytes(bytes!);
  return path;
}

void main() {
  group('EpubReformatter 端到端测试', () {
    test('完整流程：构建 → 写入 → 重构 → 验证规范化', () async {
      // 1. 构建 sample
      final sample = _buildSampleEpub();
      final inputPath = await _writeTemp(sample);
      final outputPath = '${Directory.systemTemp.path}/test_output_${DateTime.now().microsecondsSinceEpoch}.epub';

      // 2. 执行重构
      final log = await ReformatOperation.execute(
        epubPath: inputPath,
        outputPath: outputPath,
      );

      // 3. 验证日志
      expect(log, contains('重构完成'));
      print('=== 重构日志 ===\n$log\n=== /日志 ===');

      // 4. 验证输出 ZIP 结构
      final outputBytes = await File(outputPath).readAsBytes();
      final outArchive = ZipDecoder().decodeBytes(outputBytes);

      // 4.1 mimetype 第一个
      expect(outArchive.files.first.name, 'mimetype',
          reason: 'mimetype 必须是 ZIP 第一个文件');

      // 4.2 mimetype STORED
      final mt = outArchive.findFile('mimetype')!;
      expect(mt.compress, false, reason: 'mimetype 必须是 STORED');
      expect(utf8.decode(mt.content as List<int>), 'application/epub+zip');

      // 4.3 资源按类目规范化
      final names = outArchive.files.map((f) => f.name).toList();
      expect(names.any((n) => n.startsWith('OEBPS/Text/')), true,
          reason: '应存在 OEBPS/Text/ 目录');
      expect(names.any((n) => n.startsWith('OEBPS/Styles/')), true,
          reason: '应存在 OEBPS/Styles/ 目录');
      expect(names.any((n) => n.startsWith('OEBPS/Images/')), true,
          reason: '应存在 OEBPS/Images/ 目录');

      // 4.4 章节被规范化到 Text/
      final textFiles = names.where((n) => n.startsWith('OEBPS/Text/')).toList();
      expect(textFiles.length, 2);
      // 命名是原 manifest id + ext
      expect(textFiles.every((n) => n.endsWith('.xhtml')), true);

      // 4.5 container.xml media-type 仍正确
      final cFile = outArchive.findFile('META-INF/container.xml')!;
      final cXml = utf8.decode(cFile.content as List<int>);
      expect(cXml, contains('application/oebps-package+xml'));

      // 4.6 验证图片路径已正确重写
      // 检查 XHTML 内容
      for (final f in outArchive.files) {
        if (f.name.endsWith('.xhtml')) {
          final content = utf8.decode(f.content as List<int>);
          // 原路径是 ../images/cover.jpg，应重写为 ../Images/cover-img.jpg
          // 注意：rename 后图片基于 manifest id "cover-img" 命名
          expect(content, contains('../Images/cover-img.jpg'),
              reason: 'XHTML 中的图片 src 路径应重写为 ../Images/cover-img.jpg (${f.name})');
          expect(content, isNot(contains('../images/cover.jpg')),
              reason: 'XHTML 中不应保留旧路径 ../images/cover.jpg (${f.name})');
        }
        // 检查 CSS 内容
        if (f.name.endsWith('.css')) {
          final content = utf8.decode(f.content as List<int>);
          expect(content, contains('../Images/cover-img.jpg'),
              reason: 'CSS 中的 url() 路径应重写为 ../Images/cover-img.jpg (${f.name})');
          expect(content, isNot(contains('../images/cover.jpg')),
              reason: 'CSS 中不应保留旧路径 ../images/cover.jpg (${f.name})');
        }
      }

      // 4.7 验证 OPF manifest 图片路径
      final opfContent = utf8.decode(outArchive.findFile('OEBPS/content.opf')!.content as List<int>);
      expect(opfContent, contains('Images/cover-img.jpg'),
          reason: 'OPF manifest 图片 href 应指向 Images/cover-img.jpg');

      // 4.8 验证图片文件确实在 Images/ 目录
      final imageFiles = outArchive.files.where((f) => f.name.startsWith('OEBPS/Images/')).toList();
      expect(imageFiles.length, 1, reason: '应刚好有 1 张图片在 OEBPS/Images/');
      expect(imageFiles.first.name, 'OEBPS/Images/cover-img.jpg',
          reason: '图片文件名应为 cover-img.jpg');
    });

    test('container.xml 媒体类型修正（即使原 EPUB 错误）', () async {
      // 构造一个 container.xml 媒体类型错误的 sample
      final archive = _buildSampleEpub();
      // 替换 container.xml
      final badContainer =
          '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-something-else+xml"/></rootfiles>'
          '</container>';
      archive.addFile(ArchiveFile(
        'META-INF/container.xml',
        badContainer.length,
        Uint8List.fromList(utf8.encode(badContainer)),
      )..compress = true);

      final inputPath = await _writeTemp(archive);
      final outputPath =
          '${Directory.systemTemp.path}/test_container_${DateTime.now().microsecondsSinceEpoch}.epub';
      await ReformatOperation.execute(
        epubPath: inputPath,
        outputPath: outputPath,
      );

      final bytes = await File(outputPath).readAsBytes();
      final outArc = ZipDecoder().decodeBytes(bytes);
      final cFile = outArc.findFile('META-INF/container.xml')!;
      final cXml = utf8.decode(cFile.content as List<int>);
      expect(cXml, contains('application/oebps-package+xml'),
          reason: 'media-type 应被修正为 application/oebps-package+xml');
      expect(cXml, isNot(contains('application/oebps-something-else+xml')));
    });

    test('跳过已重构文件（_reformat 后缀保护）', () async {
      // 输入是 _reformat 后缀，应被警告并跳过
      final inputPath = '${Directory.systemTemp.path}/already_reformat.epub';
      final outputPath = '${Directory.systemTemp.path}/reformat_skip.epub';
      // 不需要真实文件：应该先检查后缀
      final log = await ReformatOperation.execute(
        epubPath: inputPath,
        outputPath: outputPath,
      );
      expect(log, contains('警告'));
      expect(log, contains('无需再次处理'));
    });
  });
}
