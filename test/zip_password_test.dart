import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/zip_password/zip_password.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String inputPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zip_password_test_');
    inputPath = '${tempDir.path}/input.epub';
    await File(inputPath).writeAsBytes(_buildEpub());
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('添加密码后可用正确密码读取且无密码无法读取内容', () async {
    final encryptedPath = '${tempDir.path}/encrypted.epub';

    final log = await ZipPasswordOperation.addPassword(
      epubPath: inputPath,
      outputPath: encryptedPath,
      password: 'Strong#123',
    );

    expect(log, contains('AES-256'));
    final bytes = await File(encryptedPath).readAsBytes();
    expect(_uint16(bytes, 6) & 1, 1, reason: '首个 ZIP 条目应标记为加密');
    expect(_uint16(bytes, 8), 99, reason: 'WinZip AES 的压缩方法应为 99');

    expect(() {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      for (final file in archive.files) {
        if (file.isFile) file.content;
      }
    }, throwsA(anything));

    final decrypted = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      password: 'Strong#123',
    );
    expect(
      utf8.decode(decrypted.findFile('OEBPS/Text/章节一.xhtml')!.content),
      contains('加密测试正文'),
    );
  });

  test('添加后再解除密码可恢复逐文件内容和标准 mimetype', () async {
    final encryptedPath = '${tempDir.path}/encrypted.epub';
    final restoredPath = '${tempDir.path}/restored.epub';
    await ZipPasswordOperation.addPassword(
      epubPath: inputPath,
      outputPath: encryptedPath,
      password: 'Strong#123',
    );

    final log = await ZipPasswordOperation.removePassword(
      epubPath: encryptedPath,
      outputPath: restoredPath,
      password: 'Strong#123',
    );

    expect(log, contains('标准结构已恢复'));
    final original = _fileMap(await File(inputPath).readAsBytes());
    final restoredBytes = await File(restoredPath).readAsBytes();
    final restored = _fileMap(restoredBytes);
    expect(restored.keys, unorderedEquals(original.keys));
    for (final entry in original.entries) {
      expect(restored[entry.key], entry.value, reason: entry.key);
    }
    expect(_localHeaderName(restoredBytes), 'mimetype');
    expect(_uint16(restoredBytes, 6) & 1, 0);
    expect(_uint16(restoredBytes, 8), 0);
    expect(_uint16(restoredBytes, 28), 0);
  });

  test('错误密码失败且不产生输出文件', () async {
    final encryptedPath = '${tempDir.path}/encrypted.epub';
    final restoredPath = '${tempDir.path}/wrong.epub';
    await ZipPasswordOperation.addPassword(
      epubPath: inputPath,
      outputPath: encryptedPath,
      password: 'Strong#123',
    );

    await expectLater(
      ZipPasswordOperation.removePassword(
        epubPath: encryptedPath,
        outputPath: restoredPath,
        password: 'Wrong#123',
      ),
      throwsA(
        isA<ZipPasswordException>().having(
          (error) => error.message,
          'message',
          contains('密码错误'),
        ),
      ),
    );
    expect(await File(restoredPath).exists(), isFalse);
    expect(await File('$restoredPath.part').exists(), isFalse);
  });

  test('添加密码拒绝短密码、非 ASCII 密码和覆盖输入', () async {
    Future<void> add(String password, String output) {
      return ZipPasswordOperation.addPassword(
        epubPath: inputPath,
        outputPath: output,
        password: password,
      );
    }

    await expectLater(
      add('short', '${tempDir.path}/short.epub'),
      throwsA(anything),
    );
    await expectLater(
      add('中文密码123456', '${tempDir.path}/unicode.epub'),
      throwsA(anything),
    );
    await expectLater(add('Strong#123', inputPath), throwsA(anything));
  });

  final realEpubPath = Platform.environment['ZIP_PASSWORD_REAL_EPUB'];
  test(
    '真实 EPUB 添加并解除密码后逐文件内容一致',
    () async {
      final encryptedPath = '${tempDir.path}/real_encrypted.epub';
      final restoredPath = '${tempDir.path}/real_restored.epub';
      await ZipPasswordOperation.addPassword(
        epubPath: realEpubPath!,
        outputPath: encryptedPath,
        password: 'RealBook#102',
      );
      await ZipPasswordOperation.removePassword(
        epubPath: encryptedPath,
        outputPath: restoredPath,
        password: 'RealBook#102',
      );

      final original = _fileMap(await File(realEpubPath).readAsBytes());
      final restored = _fileMap(await File(restoredPath).readAsBytes());
      expect(restored.keys, unorderedEquals(original.keys));
      for (final entry in original.entries) {
        expect(restored[entry.key], entry.value, reason: entry.key);
      }
    },
    skip: realEpubPath == null ? '设置 ZIP_PASSWORD_REAL_EPUB 后运行' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

List<int> _buildEpub() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        Uint8List.fromList(utf8.encode('application/epub+zip')),
      ),
    )
    ..addFile(
      ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
</container>'''),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata/><manifest/><spine/>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/Text/章节一.xhtml',
        '<html><head><title>一</title></head><body>加密测试正文</body></html>',
      ),
    );
  return ZipEncoder().encode(archive)!;
}

Map<String, List<int>> _fileMap(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  return {
    for (final file in archive.files.where((file) => file.isFile))
      file.name: List<int>.from(file.content as List<int>),
  };
}

String _localHeaderName(List<int> bytes) {
  final nameLength = _uint16(bytes, 26);
  return utf8.decode(bytes.sublist(30, 30 + nameLength));
}

int _uint16(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}
