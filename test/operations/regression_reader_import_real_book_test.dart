import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/convert_version/convert_version.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';
import 'package:epub_gadget/features/s2t/s2t.dart';
import 'package:flutter_test/flutter_test.dart';

class _ZipLocalHeader {
  final String name;
  final int compressionMethod;

  const _ZipLocalHeader(this.name, this.compressionMethod);
}

_ZipLocalHeader _readFirstLocalHeader(List<int> bytes) {
  expect(bytes.length >= 30, true, reason: 'ZIP 文件太短');
  final compression = bytes[8] | (bytes[9] << 8);
  final nameLen = bytes[26] | (bytes[27] << 8);
  final extraLen = bytes[28] | (bytes[29] << 8);
  final name = utf8.decode(bytes.sublist(30, 30 + nameLen));
  expect(extraLen, 0, reason: 'mimetype local header 不能有 extra field');
  return _ZipLocalHeader(name, compression);
}

void _validateImportableEpub(String path) {
  final bytes = File(path).readAsBytesSync();
  final firstHeader = _readFirstLocalHeader(bytes);
  expect(firstHeader.name, 'mimetype');
  expect(firstHeader.compressionMethod, 0);

  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive.files) {
    if (file.name.isEmpty) continue;
    final content = file.content as List<int>;
    expect(
      file.size,
      content.length,
      reason: 'ZIP 条目的声明大小必须等于实际字节数: ${file.name}',
    );
  }
  expect(archive.files.first.name, 'mimetype');
  expect(
    utf8.decode(archive.findFile('mimetype')!.content as List<int>),
    'application/epub+zip',
  );
  expect(archive.findFile('META-INF/container.xml'), isNotNull);

  final container = utf8.decode(
    archive.findFile('META-INF/container.xml')!.content as List<int>,
  );
  final opfMatch = RegExp(r'full-path="([^"]+\.opf)"').firstMatch(container);
  expect(opfMatch, isNotNull, reason: 'container.xml 必须指向 OPF');
  final opfPath = opfMatch!.group(1)!;
  final opf = archive.findFile(opfPath);
  expect(opf, isNotNull, reason: 'container.xml 指向的 OPF 必须存在: $opfPath');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realBook = File('../C41-愤怒的葡萄-[美] 约翰·斯坦贝克-手机.epub').absolute.path;

  test('真实书籍经代表性 Flutter 操作输出后仍可被阅读器导入', () async {
    if (!File(realBook).existsSync()) {
      markTestSkipped('缺少真实测试书籍: $realBook');
      return;
    }

    final dir = Directory.systemTemp.createTempSync('epub_import_');

    final reformatOut = '${dir.path}/reformat.epub';
    await ReformatOperation.execute(
      epubPath: realBook,
      outputPath: reformatOut,
    );
    _validateImportableEpub(reformatOut);

    final convertOut = '${dir.path}/convert.epub';
    await ConvertVersionOperation.execute(
      epubPath: realBook,
      outputPath: convertOut,
      targetVersion: '3.0',
    );
    _validateImportableEpub(convertOut);

    final s2tOut = '${dir.path}/s2t.epub';
    await S2tOperation.execute(epubPath: realBook, outputPath: s2tOut);
    _validateImportableEpub(s2tOut);
  });
}
