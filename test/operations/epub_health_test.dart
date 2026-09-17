import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/epub_health/epub_health.dart';
import 'package:epub_gadget/features/epub_health/epub_health_repair.dart';
import 'package:epub_gadget/features/epub_health/epub_health_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('epub-health-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('valid EPUB reports no errors or warnings', () async {
    final input = '${temp.path}/valid.epub';
    await _writeEpub(input, broken: false);

    final report = await EpubHealthInspector.scan(input);

    expect(report.epubVersion, '3.0');
    expect(report.opfPath, 'OEBPS/content.opf');
    expect(report.errorCount, 0);
    expect(report.warningCount, 0);
    expect(report.manifestItemCount, 5);
    expect(report.spineItemCount, 1);
  });

  test(
    'detects package, navigation, reference, ID, cover, and font issues',
    () async {
      final input = '${temp.path}/broken.epub';
      await _writeEpub(input, broken: true);

      final report = await EpubHealthInspector.scan(input);
      final codes = report.issues.map((issue) => issue.code).toSet();

      expect(codes, contains('mimetype-order'));
      expect(codes, contains('manifest-resource-missing'));
      expect(codes, contains('manifest-media-type'));
      expect(codes, contains('spine-target-missing'));
      expect(codes, contains('nav-missing'));
      expect(codes, contains('cover-missing'));
      expect(codes, contains('duplicate-id'));
      expect(codes, contains('resource-link-broken'));
      expect(codes, contains('anchor-invalid'));
      expect(codes, contains('font-reference-missing'));
      expect(report.safeFixCount, greaterThanOrEqualTo(4));
      expect(
        report.issues
            .where((issue) => issue.fix?.kind == 'canonicalMimetype')
            .map((issue) => issue.fix!.id)
            .toSet(),
        {'canonicalMimetype'},
      );
    },
  );

  test('detects a compressed mimetype entry', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'mimetype',
          20,
          utf8.encode('application/epub+zip'),
          ArchiveFile.DEFLATE,
        ),
      );

    final report = EpubHealthInspector.scanArchive(archive);

    expect(
      report.issues.map((issue) => issue.code),
      contains('mimetype-compressed'),
    );
  });

  test('selected safe repairs are applied, rechecked, and exported', () async {
    final input = '${temp.path}/broken.epub';
    final output = '${temp.path}/repaired.epub';
    final reports = '${temp.path}/reports';
    await _writeEpub(input, broken: true);
    final before = await EpubHealthInspector.scan(input);

    final result = await EpubHealthRepairOperation.execute(
      epubPath: input,
      outputPath: output,
      reportDirectory: reports,
      selectedFixIds: before.fixes.map((fix) => fix.id).toList(),
    );

    final after = EpubHealthReport.fromJson(
      (result['after'] as Map).cast<String, Object?>(),
    );
    final codes = after.issues.map((issue) => issue.code).toSet();
    expect(await File(output).exists(), isTrue);
    expect(codes, isNot(contains('mimetype-order')));
    expect(codes, isNot(contains('mimetype-compressed')));
    expect(codes, isNot(contains('manifest-media-type')));
    expect(codes, isNot(contains('nav-missing')));
    expect(codes, isNot(contains('cover-missing')));
    expect(codes, contains('manifest-resource-missing'));

    for (final key in [
      'beforeJsonReportPath',
      'beforeHtmlReportPath',
      'afterJsonReportPath',
      'afterHtmlReportPath',
    ]) {
      final file = File(result[key] as String);
      expect(await file.exists(), isTrue, reason: key);
      expect(await file.length(), greaterThan(100), reason: key);
    }
  });

  test('container.xml can be rebuilt when exactly one OPF exists', () async {
    final input = '${temp.path}/missing-container.epub';
    final output = '${temp.path}/container-fixed.epub';
    await _writeEpub(input, broken: false, includeContainer: false);
    final before = await EpubHealthInspector.scan(input);
    final fix = before.fixes.singleWhere(
      (item) => item.kind == 'repairContainer',
    );

    await EpubHealthRepairOperation.execute(
      epubPath: input,
      outputPath: output,
      selectedFixIds: [fix.id],
    );
    final after = await EpubHealthInspector.scan(output);

    expect(
      after.issues.map((issue) => issue.code),
      isNot(contains('container-missing')),
    );
    expect(after.opfPath, 'OEBPS/content.opf');
  });
}

Future<void> _writeEpub(
  String path, {
  required bool broken,
  bool includeContainer = true,
}) async {
  final archive = Archive();
  final mimetype = ArchiveFile(
    'mimetype',
    20,
    utf8.encode('application/epub+zip'),
  )..compress = broken;

  if (!broken) archive.addFile(mimetype);
  if (includeContainer) {
    _addText(archive, 'META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  }
  if (broken) archive.addFile(mimetype);

  _addText(
    archive,
    'OEBPS/content.opf',
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:test</dc:identifier>
    <dc:title>Test</dc:title><dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>
    <item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"${broken ? '' : ' properties="nav"'}/>
    <item id="style" href="Styles/style.css" media-type="${broken ? 'application/octet-stream' : 'text/css'}"/>
    <item id="cover" href="Images/cover.jpg" media-type="image/jpeg"${broken ? '' : ' properties="cover-image"'}/>
    <item id="font" href="Fonts/font.ttf" media-type="font/ttf"/>
    ${broken ? '<item id="missing" href="Text/missing.xhtml" media-type="application/xhtml+xml"/>' : ''}
  </manifest>
  <spine>
    <itemref idref="chapter"/>
    ${broken ? '<itemref idref="ghost"/>' : ''}
  </spine>
</package>''',
  );
  _addText(
    archive,
    'OEBPS/Text/chapter.xhtml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<title>Chapter</title><link rel="stylesheet" href="../Styles/style.css"/>
</head><body>
<p id="p1">正文</p>${broken ? '<p id="p1"><a href="none.xhtml">断链</a><a href="#ghost">锚点</a></p>' : ''}
</body></html>''',
  );
  _addText(archive, 'OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head><body><nav epub:type="toc"><ol>
<li><a href="Text/chapter.xhtml#p1">章节</a></li>
</ol></nav></body></html>''');
  _addText(
    archive,
    'OEBPS/Styles/style.css',
    broken
        ? '@font-face { font-family: Demo; src: url(../Fonts/missing.ttf); } body { font-family: Demo; }'
        : '@font-face { font-family: Demo; src: url(../Fonts/font.ttf); } body { font-family: Demo; }',
  );
  archive.addFile(
    ArchiveFile('OEBPS/Images/cover.jpg', 4, [0xff, 0xd8, 0xff, 0xd9]),
  );
  archive.addFile(ArchiveFile('OEBPS/Fonts/font.ttf', 4, [0, 1, 0, 0]));

  final bytes = ZipEncoder().encode(archive);
  await File(path).writeAsBytes(bytes!);
}

void _addText(Archive archive, String path, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
