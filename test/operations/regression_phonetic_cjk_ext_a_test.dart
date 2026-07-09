// 回归测试：phonetic 仅生僻字模式对 CJK 扩展 A 区字符的处理
//
// 之前的 bug: `runes[i] <= commonCharEnd` (0x5535) 会把 CJK 扩展 A 区
// 字符（U+3400-U+4DBF，码点全部 ≤ 0x4DBF < 0x5535）当作「常用字」跳过。
//
// 修复：必须同时判断 `>= 0x4E00` 才能算 GB2312 一级字，
// 扩展 A 区字符属于生僻字应被标注。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:epub_gadget/features/phonetic/phonetic.dart';

/// 构造一个含 CJK 扩展 A 区字符的 EPUB
Archive _buildPhoneticTestEpub() {
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
  final opfContent = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="b1" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b1">urn:uuid:1</dc:identifier>
    <dc:title>拼音测试</dc:title>
    <dc:creator>测试</dc:creator>
    <dc:language>zh</dc:language>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''';
  archive.addFile(ArchiveFile(
    'OEBPS/content.opf',
    opfContent.length,
    utf8.encode(opfContent),
  ));

  // 章节内容包含：
  // - GB2312 一级常用字：「中国」
  // - CJK 扩展 A 区生僻字：「㐀」（U+3400）— 修复前会被错误跳过
  final html = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>ch1</title></head>
<body>
  <h1>测试</h1>
  <p>中国常用字。</p>
  <p>扩展A区生僻字：㐀。</p>
</body>
</html>''';
  archive.addFile(ArchiveFile(
    'OEBPS/ch1.xhtml',
    html.length,
    utf8.encode(html),
  ));
  return archive;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_phonetic_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('phonetic 仅生僻字模式 CJK 扩展 A 区', () {
    test('扩展 A 区字符「㐀」（U+3400）应被标注为生僻字', () async {
      final inputPath = p.join(tempDir.path, 'in.epub');
      final outputPath = p.join(tempDir.path, 'out.epub');

      await File(inputPath)
          .writeAsBytes(ZipEncoder().encode(_buildPhoneticTestEpub())!);

      // 仅生僻字模式
      final log = await PhoneticOperation.execute(
        epubPath: inputPath,
        outputPath: outputPath,
        annotateAll: false,
      );

      // 读取输出，验证扩展 A 区字符被标注
      final outputBytes = await File(outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(outputBytes);
      final ch1 = archive.findFile('OEBPS/ch1.xhtml');
      expect(ch1, isNotNull);
      final text = utf8.decode(ch1!.content as List<int>);

      // 「㐀」是 CJK 扩展 A 区生僻字，应被 ruby 标签包裹
      expect(text, contains('㐀'),
          reason: '扩展 A 区字符必须保留在文本中');
      // 关键验证：「㐀」必须被 <ruby> 包裹（之前修复前的 bug 会跳过它）
      expect(text, contains('<ruby>㐀<rt>'),
          reason: 'CJK 扩展 A 区字符「㐀」应被标注为生僻字（修复前会被错误跳过）');
      // 关键验证：「中」(U+4E2D) 在 [0x4E00, 0x5535] 范围内，是 GB2312 一级字，
      // 仅生僻字模式下不应被标注
      expect(text.contains('<ruby>中<rt>'), false,
          reason: '「中」(U+4E2D) 是 GB2312 一级字，仅生僻字模式下不应标注');

      // 整个流程应正常完成
      expect(log, isNotEmpty);
    });

    test('全文模式（annotateAll=true）应标注所有中文字符', () async {
      final inputPath = p.join(tempDir.path, 'in.epub');
      final outputPath = p.join(tempDir.path, 'out.epub');

      await File(inputPath)
          .writeAsBytes(ZipEncoder().encode(_buildPhoneticTestEpub())!);

      await PhoneticOperation.execute(
        epubPath: inputPath,
        outputPath: outputPath,
        annotateAll: true,
      );

      final outputBytes = await File(outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(outputBytes);
      final ch1 = archive.findFile('OEBPS/ch1.xhtml');
      final text = utf8.decode(ch1!.content as List<int>);

      // 全文模式下，所有中文字符都应被 ruby 标签包裹
      // 「中」是 GB2312 一级字，全文模式下也必须被标注
      final rubyCount = '<ruby>'.allMatches(text).length;
      expect(rubyCount, greaterThan(0),
          reason: '全文模式下应至少有 1 个 ruby 标签');
    });
  });
}
