// 回归测试：EPUB 重打包应符合 mimetype 规范
//
// EPUB 规范（OCF 3.1）强制要求：
// 1. mimetype 必须是 ZIP 第一个文件
// 2. 内容必须是 "application/epub+zip"
// 3. 必须用 STORED（不压缩）
//
// 之前的 bug：reformat 和 convert_version 直接用 ZipEncoder.encode()，
// 没有强制 mimetype 第一个 + STORED，导致重新打包的 EPUB
// 被 Kindle/多看/Sigil 严格模式拒绝导入。
//
// 修复：新增 EpubPacker 工具，强制 mimetype 第一个 + STORED。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/convert_version/epub_packer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 解析 ZIP Local File Header，提取文件名 + compression method
class ZipLocalHeader {
  final String name;
  final int compressionMethod;
  const ZipLocalHeader(this.name, this.compressionMethod);
}

ZipLocalHeader _readFirstLocalHeader(List<int> bytes) {
  // PK\x03\x04 (0x04034b50)
  expect(bytes.length >= 30, true, reason: 'ZIP 文件太短');
  // offset 4: version needed (2), gp bit flag (2), compression method (2)
  final compression = bytes[8] | (bytes[9] << 8);
  // offset 26: filename length (2), extra length (2)
  final nameLen = bytes[26] | (bytes[27] << 8);
  // offset 30: filename
  final name = utf8.decode(bytes.sublist(30, 30 + nameLen));
  return ZipLocalHeader(name, compression);
}

void main() {
  group('EpubPacker', () {
    test('重打包后 mimetype 必须是第一个文件 + STORED', () async {
      // 构造一个 archive 模拟 reformat 输出
      final archive = Archive();

      // 先加一些普通文件
      archive.addFile(
        ArchiveFile(
          'META-INF/container.xml',
          100,
          utf8.encode('<?xml version="1.0"?><container></container>'),
        ),
      );
      archive.addFile(
        ArchiveFile(
          'OEBPS/content.opf',
          50,
          utf8.encode('<?xml version="1.0"?><package version="2.0"></package>'),
        ),
      );

      // ensureMimetype + pack
      EpubPacker.ensureMimetype(archive);
      final outputPath = '${Directory.systemTemp.path}/test_packed.epub';
      await EpubPacker.pack(archive: archive, outputPath: outputPath);

      // 读取输出 ZIP 并验证第一个 Local Header
      final bytes = await File(outputPath).readAsBytes();
      final header = _readFirstLocalHeader(bytes);
      expect(header.name, 'mimetype', reason: 'mimetype 必须是 ZIP 第一个文件');
      expect(
        header.compressionMethod,
        0,
        reason: 'mimetype 必须是 STORED（压缩方式=0）',
      );

      // 验证 mimetype 内容
      final newArchive = ZipDecoder().decodeBytes(bytes);
      final mimetype = newArchive.findFile('mimetype');
      expect(mimetype, isNotNull);
      expect(
        utf8.decode(mimetype!.content as List<int>),
        'application/epub+zip',
      );
    });

    test('缺少 mimetype 文件时 pack 应自动补齐规范值', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('content.txt', 5, utf8.encode('hello')));
      final outputPath = '${Directory.systemTemp.path}/test_no_mimetype.epub';
      await EpubPacker.pack(archive: archive, outputPath: outputPath);

      final packed = ZipDecoder().decodeBytes(
        await File(outputPath).readAsBytes(),
      );
      final mimetype = packed.findFile('mimetype');
      expect(mimetype, isNotNull);
      expect(
        utf8.decode(mimetype!.content as List<int>),
        'application/epub+zip',
      );
    });

    test('ensureMimetype 是幂等的（已有 mimetype 时不覆盖）', () {
      final archive = Archive();
      final customMime = 'application/x-foo';
      final customBytes = utf8.encode(customMime);
      archive.addFile(
        ArchiveFile(
          'mimetype',
          customBytes.length,
          Uint8List.fromList(customBytes),
        ),
      );

      EpubPacker.ensureMimetype(archive);

      final mime = archive.findFile('mimetype')!;
      expect(
        utf8.decode(mime.content as List<int>),
        customMime,
        reason: 'ensureMimetype 不应覆盖已有 mimetype',
      );
    });

    test('ensureMimetype 后 findFile 能找到（_fileMap 已更新）', () {
      // 关键回归：直接操作 archive.files.insert(0) 不更新 _fileMap，
      // 会导致后续 findFile 找不到。用 addFile(ArchiveFile) 才能修复。
      final archive = Archive();
      archive.addFile(
        ArchiveFile('other.xml', 5, Uint8List.fromList(utf8.encode('hello'))),
      );

      EpubPacker.ensureMimetype(archive);

      // findFile 应该返回有效 ArchiveFile
      final mime = archive.findFile('mimetype');
      expect(mime, isNotNull, reason: 'ensureMimetype 后 findFile 应能找到');
      expect(utf8.decode(mime!.content as List<int>), 'application/epub+zip');
    });
  });
}
