// 回归测试：addOrReplaceFile / addOrReplaceFileSafe 在 archive._fileMap
// 因 removeFile 损坏后能自动恢复，确保循环内大量 addFile 不再触发 RangeError
//
// 这个 bug 在生产环境的真实表现：merge / phonetic / chinese_convert 等循环内
// addOrReplaceFile 的操作在第 3~5 个文件后随机报
// "RangeError (length): Invalid value: Not in inclusive range 0..N: -1"，
// 被 catch 后只 print 一行日志，用户感知不到但功能实际失败。

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epub_gadget/core/epub_image_helper.dart';

Archive _buildArchiveWithFiles(List<String> names) {
  final archive = Archive();
  for (final name in names) {
    final bytes = utf8.encode('content-of-$name');
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return archive;
}

void main() {
  group('EpubImageHelper.addOrReplaceFileSafe', () {
    test('正常路径：连续 addOrReplaceFileSafe 不报错', () {
      final archive = _buildArchiveWithFiles([
        'mimetype',
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/chapter1.xhtml',
        'OEBPS/chapter2.xhtml',
      ]);

      var working = archive;
      for (var i = 1; i <= 10; i++) {
        final name = 'OEBPS/dyn_$i.xhtml';
        final bytes = utf8.encode('chapter $i content');
        working = EpubImageHelper.addOrReplaceFileSafe(
          working,
          ArchiveFile(name, bytes.length, bytes),
        );
      }

      // 验证新文件全部能找到
      for (var i = 1; i <= 10; i++) {
        final f = working.findFile('OEBPS/dyn_$i.xhtml');
        expect(f, isNotNull, reason: 'dyn_$i 应该存在');
      }
    });

    test('替换路径：同名文件 addOrReplaceFileSafe 后内容更新', () {
      final archive = _buildArchiveWithFiles(['OEBPS/chapter1.xhtml']);
      final newBytes = utf8.encode('updated content');
      final working = EpubImageHelper.addOrReplaceFileSafe(
        archive,
        ArchiveFile('OEBPS/chapter1.xhtml', newBytes.length, newBytes),
      );
      final f = working.findFile('OEBPS/chapter1.xhtml');
      expect(f, isNotNull);
      expect(String.fromCharCodes(f!.content as List<int>), 'updated content');
    });

    test('破坏 _fileMap 后 addOrReplaceFileSafe 仍能继续', () {
      // 1) 构造一个 archive
      final archive = _buildArchiveWithFiles([
        'OEBPS/a.xhtml',
        'OEBPS/b.xhtml',
        'OEBPS/c.xhtml',
        'OEBPS/d.xhtml',
        'OEBPS/e.xhtml',
      ]);

      // 2) 调用 removeFile 模拟 archive 包的索引 bug
      final cFile = archive.findFile('OEBPS/c.xhtml')!;
      archive.removeFile(cFile);

      // 3) 接下来用 addOrReplaceFileSafe 添加 3 个新文件
      var working = archive;
      for (final name in ['new1.xhtml', 'new2.xhtml', 'new3.xhtml']) {
        final bytes = utf8.encode(name);
        working = EpubImageHelper.addOrReplaceFileSafe(
          working,
          ArchiveFile(name, bytes.length, bytes),
        );
      }

      // 4) 全部新文件应能找到
      for (final name in ['new1.xhtml', 'new2.xhtml', 'new3.xhtml']) {
        expect(working.findFile(name), isNotNull,
            reason: 'removeFile 后 $name 仍应能被添加');
      }
    });

    test('在 50+ 个文件循环中稳定工作', () {
      final archive = _buildArchiveWithFiles(['mimetype']);
      var working = archive;
      for (var i = 0; i < 50; i++) {
        final name = 'file_$i.xhtml';
        final bytes = utf8.encode('content $i');
        working = EpubImageHelper.addOrReplaceFileSafe(
          working,
          ArchiveFile(name, bytes.length, bytes),
        );
      }
      expect(working.files.length, 51); // 1 mimetype + 50 new
      for (var i = 0; i < 50; i++) {
        expect(working.findFile('file_$i.xhtml'), isNotNull);
      }
    });
  });

  group('EpubImageHelper.addOrReplaceFile (void 版)', () {
    test('正常 addFile 路径不受影响', () {
      final archive = _buildArchiveWithFiles(['OEBPS/x.xhtml']);
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile('OEBPS/y.xhtml', 4, utf8.encode('test')),
      );
      expect(archive.findFile('OEBPS/y.xhtml'), isNotNull);
    });

    test('removeFile 后 addOrReplaceFile 内部自动修复后重试', () {
      final archive = _buildArchiveWithFiles([
        'OEBPS/a.xhtml',
        'OEBPS/b.xhtml',
        'OEBPS/c.xhtml',
      ]);
      archive.removeFile(archive.findFile('OEBPS/b.xhtml')!);
      // 不会抛 RangeError；可能内部清空 _fileMap 后重建
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile('OEBPS/d.xhtml', 1, utf8.encode('d')),
      );
      expect(archive.findFile('OEBPS/d.xhtml'), isNotNull);
    });
  });
}
