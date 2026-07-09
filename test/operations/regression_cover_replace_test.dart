// 回归测试：MetadataService 封面替换不触发 archive _fileMap 索引损坏
//
// 之前的 bug: 替换封面时直接用 archive.addFile()，在某些路径下
// （特别是 addFile 同名时或 removeFile 之后 addFile）会触发
// archive 库 _fileMap 索引漂移的 RangeError。
//
// 修复：统一走 addOrReplaceFileSafe，必要时重建 archive。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:epub_gadget/features/metadata/metadata_service.dart';

/// 构造一个带封面的 EPUB
Archive _buildEpubWithCover({
  String title = '测试',
  String? coverHref = 'OEBPS/Images/cover.jpg',
  List<int>? coverBytes,
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

  // 占位 nav（确保 manifest 完整）
  final navContent = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc">
    <ol><li><a href="ch1.xhtml">ch1</a></li></ol>
  </nav>
</body>
</html>''';
  archive.addFile(ArchiveFile(
    'OEBPS/nav.xhtml',
    navContent.length,
    utf8.encode(navContent),
  ));

  // content.opf（带 cover meta）
  final coverBytesB64 = coverBytes != null
      ? '<!-- cover present -->'
      : '<!-- no cover -->';
  final opfContent = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="b1" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b1">urn:uuid:1</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:creator>作者</dc:creator>
    <dc:language>zh</dc:language>
    <meta name="cover" content="cover-img"/>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>
$coverBytesB64''';
  archive.addFile(ArchiveFile(
    'OEBPS/content.opf',
    opfContent.length,
    utf8.encode(opfContent),
  ));

  if (coverBytes != null) {
    archive.addFile(ArchiveFile(
      coverHref!,
      coverBytes.length,
      coverBytes,
    ));
  }

  // 章节
  final html = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>ch1</title></head>
<body><h1>ch1</h1><p>测试</p></body>
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
    tempDir = await Directory.systemTemp.createTemp('epub_cover_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MetadataService.write 封面替换 archive 索引安全', () {
    test('替换封面不应触发 archive 索引损坏', () async {
      // 1. 准备带旧封面的 EPUB
      final inputPath = p.join(tempDir.path, 'in.epub');
      final outputPath = p.join(tempDir.path, 'out.epub');

      // 旧封面（10KB JPEG-like bytes）
      final oldCover = List<int>.generate(10240, (i) => i % 256);
      final epub = _buildEpubWithCover(
        title: '封面替换测试',
        coverBytes: oldCover,
      );
      await File(inputPath).writeAsBytes(ZipEncoder().encode(epub)!);

      // 2. 准备新封面图片（存为文件）
      final newCoverPath = p.join(tempDir.path, 'new_cover.png');
      // 最小 PNG 1x1 像素
      const pngBytes = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xFC, 0xCF, 0xC0, 0xF0,
        0x9F, 0x81, 0x01, 0x00, 0x05, 0x00, 0x01, 0x5A, 0x4F, 0xCB, 0x07, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ];
      await File(newCoverPath).writeAsBytes(pngBytes);

      // 3. 写入新元数据 + 替换封面
      final metadata = MetadataData(
        title: '封面替换测试（已更新）',
        author: '新作者',
        language: 'zh',
        identifier: 'urn:uuid:new',
      );

      // 不应抛 RangeError
      await MetadataService.write(
        epubPath: inputPath,
        outputPath: outputPath,
        metadata: metadata,
        coverPath: newCoverPath,
      );

      // 4. 验证输出文件存在且可被 archive 正常读取
      expect(await File(outputPath).exists(), true);

      // 5. 读取输出 EPUB 验证内容
      final outputBytes = await File(outputPath).readAsBytes();
      final outputArchive = ZipDecoder().decodeBytes(outputBytes);

      // OPF 中应包含新标题
      final opf = outputArchive.findFile('OEBPS/content.opf');
      expect(opf, isNotNull);
      final opfText = utf8.decode(opf!.content as List<int>);
      expect(opfText, contains('封面替换测试（已更新）'),
          reason: '新标题应被写入 OPF');
      expect(opfText, contains('新作者'),
          reason: '新作者应被写入 OPF');

      // 新封面应在 archive 中
      final newCoverInArchive = outputArchive.findFile('OEBPS/Images/cover.png');
      expect(newCoverInArchive, isNotNull,
          reason: '新封面应被写入 archive');
      expect(newCoverInArchive!.size, pngBytes.length);

      // 旧封面不应在 archive 中
      final oldCoverInArchive = outputArchive.findFile('OEBPS/Images/cover.jpg');
      expect(oldCoverInArchive, isNull,
          reason: '旧封面应被移除（避免 100KB+ 旧封面泄漏到新 EPUB）');
    });

    test('仅更新元数据（不替换封面）不应损坏 archive', () async {
      // 边界情况：removeCover=false, coverPath=null
      // 应该走「无文件变更」分支，archive 保持原状
      final inputPath = p.join(tempDir.path, 'in.epub');
      final outputPath = p.join(tempDir.path, 'out.epub');

      final epub = _buildEpubWithCover(title: '原标题');
      await File(inputPath).writeAsBytes(ZipEncoder().encode(epub)!);

      final metadata = MetadataData(
        title: '新标题',
        author: '新作者',
        language: 'en',
        identifier: 'urn:uuid:new',
      );

      await MetadataService.write(
        epubPath: inputPath,
        outputPath: outputPath,
        metadata: metadata,
      );

      // 输出应包含新标题
      final outputBytes = await File(outputPath).readAsBytes();
      final outputArchive = ZipDecoder().decodeBytes(outputBytes);
      final opf = outputArchive.findFile('OEBPS/content.opf');
      final opfText = utf8.decode(opf!.content as List<int>);
      expect(opfText, contains('新标题'));
    });
  });
}
