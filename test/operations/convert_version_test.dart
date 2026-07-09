// 测试 EPUB 2 ↔ EPUB 3 版本转换功能
//
// 用真实 EPUB 文件验证：
// 1. EPUB 2 → EPUB 3：version 改为 3.0，添加 dcterms:modified，生成 nav.xhtml
// 2. EPUB 3 → EPUB 2：version 改为 2.0，移除 dcterms:modified，移除 nav.xhtml
// 3. 往返转换：2→3→2 后结构应与原始基本一致
// 4. ZIP 结构合法性：mimetype 第一个 + STORED

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:epub_gadget/features/convert_version/convert_version.dart';

/// 输入 EPUB 路径（EPUB 2.0 格式）
const inputEpubPath =
    '/Users/aaa/.trae-cn/attachments/6a4d974cf98b9d1c4f971a45/53ad1b9a-b6a8-4736-bc7f-2d4f709cb700_我的智商逐年递增.epub';

/// 提取 EPUB 的关键结构信息
class EpubInfo {
  final String opfPath;
  final String opfDir;
  final String packageVersion;
  final bool hasDctermsModified;
  final bool hasNavXhtml;
  final bool hasNcxInManifest;
  final int fileCount;
  final bool mimetypeFirst;
  final bool mimetypeStored;

  EpubInfo({
    required this.opfPath,
    required this.opfDir,
    required this.packageVersion,
    required this.hasDctermsModified,
    required this.hasNavXhtml,
    required this.hasNcxInManifest,
    required this.fileCount,
    required this.mimetypeFirst,
    required this.mimetypeStored,
  });

  @override
  String toString() =>
      '''EpubInfo(
  opfPath: $opfPath
  opfDir: $opfDir
  packageVersion: $packageVersion
  hasDctermsModified: $hasDctermsModified
  hasNavXhtml: $hasNavXhtml
  hasNcxInManifest: $hasNcxInManifest
  fileCount: $fileCount
  mimetypeFirst: $mimetypeFirst
  mimetypeStored: $mimetypeStored
)''';
}

/// 从 EPUB 文件路径提取结构信息
EpubInfo inspectEpub(String path) {
  final bytes = File(path).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  // 定位 OPF
  final containerFile = archive.findFile('META-INF/container.xml')!;
  final containerXml = utf8.decode(containerFile.content as List<int>);
  final opfPath = RegExp(
    r'full-path="([^"]+)"',
  ).firstMatch(containerXml)!.group(1)!;
  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  // 读取 OPF
  final opfFile = archive.findFile(opfPath)!;
  final opfContent = utf8.decode(opfFile.content as List<int>);

  // 提取 package version
  final versionMatch = RegExp(
    r'<package[^>]*?\sversion="([^"]*)"',
  ).firstMatch(opfContent);
  final packageVersion = versionMatch?.group(1) ?? 'unknown';

  // 检查 dcterms:modified
  final hasDctermsModified = opfContent.contains('dcterms:modified');

  // 检查 nav.xhtml 文件是否存在
  final navPath = '${opfDir}nav.xhtml';
  final hasNavXhtml = archive.findFile(navPath) != null;

  // 检查 NCX 在 manifest 中
  final hasNcxInManifest = opfContent.contains('application/x-dtbncx+xml');

  // 检查 mimetype 位置和压缩方式
  bool mimetypeFirst = false;
  bool mimetypeStored = false;
  for (var i = 0; i < archive.files.length; i++) {
    if (archive.files[i].name == 'mimetype') {
      mimetypeFirst = (i == 0);
      mimetypeStored =
          !archive.files[i].compress; // compress=false means STORED
      break;
    }
  }

  return EpubInfo(
    opfPath: opfPath,
    opfDir: opfDir,
    packageVersion: packageVersion,
    hasDctermsModified: hasDctermsModified,
    hasNavXhtml: hasNavXhtml,
    hasNcxInManifest: hasNcxInManifest,
    fileCount: archive.files.length,
    mimetypeFirst: mimetypeFirst,
    mimetypeStored: mimetypeStored,
  );
}

/// 验证 EPUB ZIP 结构合法性
void validateZipStructure(String path) {
  final bytes = File(path).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  // 1. 必须以 PK 签名开头
  expect(bytes[0], equals(0x50), reason: '文件应以 PK 签名开头');
  expect(bytes[1], equals(0x4B), reason: '文件应以 PK 签名开头');

  // 2. mimetype 第一个
  expect(
    archive.files[0].name,
    equals('mimetype'),
    reason: 'mimetype 必须是第一个文件',
  );

  // 3. mimetype 不压缩
  expect(archive.files[0].compress, isFalse, reason: 'mimetype 必须 STORED（不压缩）');

  // 4. mimetype 内容
  final mimetypeContent = utf8.decode(archive.files[0].content as List<int>);
  expect(
    mimetypeContent,
    equals('application/epub+zip'),
    reason: 'mimetype 内容必须是 application/epub+zip',
  );

  // 5. container.xml 存在
  expect(
    archive.findFile('META-INF/container.xml'),
    isNotNull,
    reason: '必须存在 META-INF/container.xml',
  );
}

void main() {
  // 检查输入文件是否存在
  final inputFile = File(inputEpubPath);
  final hasInputFile = inputFile.existsSync();

  group('EPUB 版本转换', () {
    test('1. 检查原始 EPUB 是 EPUB 2.0', () {
      if (!hasInputFile) {
        print('SKIP: 输入文件不存在');
        return;
      }
      final info = inspectEpub(inputEpubPath);
      print('=== 原始 EPUB 信息 ===');
      print(info);

      expect(info.packageVersion, equals('2.0'), reason: '原始 EPUB 应该是 2.0 版本');
      expect(info.hasNcxInManifest, isTrue, reason: 'EPUB 2.0 应有 NCX');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('2. EPUB 2.0 → EPUB 3.0', () async {
      if (!hasInputFile) {
        print('SKIP: 输入文件不存在');
        return;
      }

      final outputPath = '/tmp/test_convert_2to3.epub';
      final oldFile = File(outputPath);
      if (oldFile.existsSync()) oldFile.deleteSync();

      await ConvertVersionOperation.execute(
        epubPath: inputEpubPath,
        outputPath: outputPath,
        targetVersion: '3.0',
      );

      // 验证输出文件存在
      expect(File(outputPath).existsSync(), isTrue, reason: '输出文件应存在');

      // 验证 ZIP 结构
      validateZipStructure(outputPath);

      // 验证版本信息
      final info = inspectEpub(outputPath);
      print('=== 转换后 EPUB 3.0 信息 ===');
      print(info);

      expect(info.packageVersion, equals('3.0'), reason: '转换后 version 应为 3.0');
      expect(
        info.hasDctermsModified,
        isTrue,
        reason: 'EPUB 3.0 应包含 dcterms:modified',
      );
      expect(info.hasNavXhtml, isTrue, reason: 'EPUB 3.0 应包含 nav.xhtml');
      expect(info.mimetypeFirst, isTrue, reason: 'mimetype 应为第一个文件');
      expect(info.mimetypeStored, isTrue, reason: 'mimetype 应 STORED');
      expect(info.hasNcxInManifest, isTrue, reason: 'EPUB 3.0 保留 NCX（向后兼容）');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('3. EPUB 3.0 → EPUB 2.0', () async {
      if (!hasInputFile) {
        print('SKIP: 输入文件不存在');
        return;
      }

      // 先转成 3.0
      final epub3Path = '/tmp/test_convert_2to3.epub';
      if (!File(epub3Path).existsSync()) {
        await ConvertVersionOperation.execute(
          epubPath: inputEpubPath,
          outputPath: epub3Path,
          targetVersion: '3.0',
        );
      }

      final outputPath = '/tmp/test_convert_3to2.epub';
      final oldFile = File(outputPath);
      if (oldFile.existsSync()) oldFile.deleteSync();

      await ConvertVersionOperation.execute(
        epubPath: epub3Path,
        outputPath: outputPath,
        targetVersion: '2.0',
      );

      // 验证输出文件存在
      expect(File(outputPath).existsSync(), isTrue, reason: '输出文件应存在');

      // 验证 ZIP 结构
      validateZipStructure(outputPath);

      // 验证版本信息
      final info = inspectEpub(outputPath);
      print('=== 转换后 EPUB 2.0 信息 ===');
      print(info);

      expect(info.packageVersion, equals('2.0'), reason: '转换后 version 应为 2.0');
      expect(
        info.hasDctermsModified,
        isFalse,
        reason: 'EPUB 2.0 不应有 dcterms:modified',
      );
      expect(info.hasNavXhtml, isFalse, reason: 'EPUB 2.0 不应有 nav.xhtml');
      expect(info.mimetypeFirst, isTrue, reason: 'mimetype 应为第一个文件');
      expect(info.mimetypeStored, isTrue, reason: 'mimetype 应 STORED');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('4. 往返转换 2→3→2 后结构一致性', () async {
      if (!hasInputFile) {
        print('SKIP: 输入文件不存在');
        return;
      }

      final originalInfo = inspectEpub(inputEpubPath);

      // 2→3
      final epub3Path = '/tmp/test_roundtrip_3.epub';
      if (File(epub3Path).existsSync()) File(epub3Path).deleteSync();
      await ConvertVersionOperation.execute(
        epubPath: inputEpubPath,
        outputPath: epub3Path,
        targetVersion: '3.0',
      );

      // 3→2
      final epub2Path = '/tmp/test_roundtrip_2.epub';
      if (File(epub2Path).existsSync()) File(epub2Path).deleteSync();
      await ConvertVersionOperation.execute(
        epubPath: epub3Path,
        outputPath: epub2Path,
        targetVersion: '2.0',
      );

      final roundtripInfo = inspectEpub(epub2Path);
      print('=== 原始 EPUB ===');
      print(originalInfo);
      print('=== 往返后 EPUB ===');
      print(roundtripInfo);

      // 版本应回到 2.0
      expect(roundtripInfo.packageVersion, equals('2.0'));
      // dcterms:modified 应被移除
      expect(roundtripInfo.hasDctermsModified, isFalse);
      // nav.xhtml 应被移除
      expect(roundtripInfo.hasNavXhtml, isFalse);
      // NCX 应保留
      expect(roundtripInfo.hasNcxInManifest, isTrue);
      // 文件数应该相同（nav.xhtml 被移除，与原始一致）
      expect(
        roundtripInfo.fileCount,
        equals(originalInfo.fileCount),
        reason: '往返后文件数应与原始一致（nav.xhtml 添加后又移除）',
      );
      // mimetype 结构
      expect(roundtripInfo.mimetypeFirst, isTrue);
      expect(roundtripInfo.mimetypeStored, isTrue);

      print('=== 往返转换验证通过 ===');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('5. nav.xhtml 内容验证', () async {
      if (!hasInputFile) {
        print('SKIP: 输入文件不存在');
        return;
      }

      final epub3Path = '/tmp/test_convert_2to3.epub';
      if (!File(epub3Path).existsSync()) {
        await ConvertVersionOperation.execute(
          epubPath: inputEpubPath,
          outputPath: epub3Path,
          targetVersion: '3.0',
        );
      }

      final bytes = File(epub3Path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 找 nav.xhtml
      final containerFile = archive.findFile('META-INF/container.xml')!;
      final containerXml = utf8.decode(containerFile.content as List<int>);
      final opfPath = RegExp(
        r'full-path="([^"]+)"',
      ).firstMatch(containerXml)!.group(1)!;
      final opfDir = opfPath.contains('/')
          ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
          : '';
      final navPath = '${opfDir}nav.xhtml';
      final navFile = archive.findFile(navPath);
      expect(navFile, isNotNull, reason: 'nav.xhtml 应存在');

      final navContent = utf8.decode(navFile!.content as List<int>);
      print('=== nav.xhtml 前 500 字符 ===');
      print(
        navContent.substring(
          0,
          navContent.length > 500 ? 500 : navContent.length,
        ),
      );

      // 验证 nav.xhtml 结构
      expect(navContent.contains('<nav'), isTrue, reason: '应有 <nav> 元素');
      expect(
        navContent.contains('epub:type="toc"'),
        isTrue,
        reason: '应有 epub:type="toc"',
      );
      expect(navContent.contains('<ol>'), isTrue, reason: '应有 <ol> 列表');
      expect(navContent.contains('<a href='), isTrue, reason: '应有章节链接');

      // 统计链接数
      final linkCount = RegExp(r'<a href=').allMatches(navContent).length;
      print('nav.xhtml 中链接数: $linkCount');
      expect(linkCount, greaterThan(0), reason: '至少应有1个链接');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
      '6. OPF manifest 验证（升级后应有 nav item）',
      () async {
        if (!hasInputFile) {
          print('SKIP: 输入文件不存在');
          return;
        }

        final epub3Path = '/tmp/test_convert_2to3.epub';
        if (!File(epub3Path).existsSync()) {
          await ConvertVersionOperation.execute(
            epubPath: inputEpubPath,
            outputPath: epub3Path,
            targetVersion: '3.0',
          );
        }

        final bytes = File(epub3Path).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        final containerFile = archive.findFile('META-INF/container.xml')!;
        final containerXml = utf8.decode(containerFile.content as List<int>);
        final opfPath = RegExp(
          r'full-path="([^"]+)"',
        ).firstMatch(containerXml)!.group(1)!;
        final opfFile = archive.findFile(opfPath)!;
        final opfContent = utf8.decode(opfFile.content as List<int>);

        // 验证 OPF 包含 nav item
        expect(
          opfContent.contains('href="nav.xhtml"'),
          isTrue,
          reason: 'OPF manifest 应包含 nav.xhtml item',
        );
        expect(
          opfContent.contains('properties="nav"'),
          isTrue,
          reason: 'nav item 应有 properties="nav"',
        );
        expect(
          opfContent.contains('dcterms:modified'),
          isTrue,
          reason: '应有 dcterms:modified',
        );

        // 验证 version
        expect(
          opfContent.contains('version="3.0"'),
          isTrue,
          reason: 'version 应为 3.0',
        );

        print('=== OPF manifest 验证通过 ===');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      '7. EPUB3 → EPUB2 应删除子目录 nav.xhtml 及 spine 引用',
      () async {
        final inputPath = '/tmp/test_convert_nested_nav_input.epub';
        final outputPath = '/tmp/test_convert_nested_nav_output.epub';
        if (File(inputPath).existsSync()) File(inputPath).deleteSync();
        if (File(outputPath).existsSync()) File(outputPath).deleteSync();

        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'mimetype',
              'application/epub+zip'.length,
              utf8.encode('application/epub+zip'),
            )..compress = false,
          )
          ..addFile(
            ArchiveFile(
              'META-INF/container.xml',
              0,
              utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/content.opf',
              0,
              utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">nested-nav</dc:identifier>
    <dc:title>Nested Nav</dc:title>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="Text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="nav"/>
    <itemref idref="chapter"/>
  </spine>
</package>
'''),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/Text/nav.xhtml',
              0,
              utf8.encode(
                '<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Chapter</a></li></ol></nav></body></html>',
              ),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/Text/chapter.xhtml',
              0,
              utf8.encode(
                '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Chapter</p></body></html>',
              ),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/toc.ncx',
              0,
              utf8.encode(
                '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap/></ncx>',
              ),
            ),
          );
        await File(inputPath).writeAsBytes(ZipEncoder().encode(archive)!);

        await ConvertVersionOperation.execute(
          epubPath: inputPath,
          outputPath: outputPath,
          targetVersion: '2.0',
        );

        final outArchive = ZipDecoder().decodeBytes(
          File(outputPath).readAsBytesSync(),
        );
        expect(
          outArchive.findFile('OEBPS/Text/nav.xhtml'),
          isNull,
          reason: '子目录中的 nav.xhtml 实体文件应被删除',
        );

        final opfContent = utf8.decode(
          outArchive.findFile('OEBPS/content.opf')!.content as List<int>,
        );
        expect(opfContent, contains('version="2.0"'));
        expect(opfContent, isNot(contains('dcterms:modified')));
        expect(opfContent, isNot(contains('Text/nav.xhtml')));
        expect(opfContent, isNot(contains('properties="nav"')));
        expect(
          opfContent,
          isNot(contains('idref="nav"')),
          reason: 'spine 中不应保留指向已删除 nav 的 itemref',
        );
        validateZipStructure(outputPath);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '8. EPUB3 → EPUB2 无 NCX 时应从 nav 生成 toc.ncx',
      () async {
        final inputPath = '/tmp/test_convert_epub3_without_ncx_input.epub';
        final outputPath = '/tmp/test_convert_epub3_without_ncx_output.epub';
        if (File(inputPath).existsSync()) File(inputPath).deleteSync();
        if (File(outputPath).existsSync()) File(outputPath).deleteSync();

        ArchiveFile textFile(String name, String text) {
          final bytes = utf8.encode(text);
          return ArchiveFile(name, bytes.length, bytes);
        }

        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'mimetype',
              'application/epub+zip'.length,
              utf8.encode('application/epub+zip'),
            )..compress = false,
          )
          ..addFile(
            textFile('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
          )
          ..addFile(
            textFile('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">epub3-no-ncx</dc:identifier>
    <dc:title>EPUB3 No NCX</dc:title>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="Text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="chapter"/>
  </spine>
</package>
'''),
          )
          ..addFile(
            textFile(
              'OEBPS/Text/nav.xhtml',
              '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">第一章</a></li></ol></nav></body></html>',
            ),
          )
          ..addFile(
            textFile(
              'OEBPS/Text/chapter.xhtml',
              '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Chapter</p></body></html>',
            ),
          );
        await File(inputPath).writeAsBytes(ZipEncoder().encode(archive)!);

        await ConvertVersionOperation.execute(
          epubPath: inputPath,
          outputPath: outputPath,
          targetVersion: '2.0',
        );

        final outArchive = ZipDecoder().decodeBytes(
          File(outputPath).readAsBytesSync(),
        );
        expect(outArchive.findFile('OEBPS/Text/nav.xhtml'), isNull);
        final ncxFile = outArchive.findFile('OEBPS/toc.ncx');
        expect(ncxFile, isNotNull, reason: '纯 EPUB3 降级 EPUB2 时应生成 toc.ncx');
        final ncxContent = utf8.decode(ncxFile!.content as List<int>);
        expect(
          ncxContent,
          contains('<docTitle><text>EPUB3 No NCX</text></docTitle>'),
        );
        expect(ncxContent, contains('<content src="Text/chapter.xhtml"/>'));

        final opfContent = utf8.decode(
          outArchive.findFile('OEBPS/content.opf')!.content as List<int>,
        );
        expect(opfContent, contains('version="2.0"'));
        expect(opfContent, contains('application/x-dtbncx+xml'));
        expect(opfContent, contains('<spine toc="ncx">'));
        expect(opfContent, isNot(contains('Text/nav.xhtml')));
        validateZipStructure(outputPath);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
