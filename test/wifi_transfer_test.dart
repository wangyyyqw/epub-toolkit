import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_book.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_book_library.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WifiBook', () {
    test('formattedSize 正确格式化不同量级', () {
      expect(WifiBook(
        id: '1', title: 'a', originalFilename: 'a.epub',
        storedFilename: '1.epub', format: 'EPUB',
        byteCount: 512, importedAt: DateTime(2026),
      ).formattedSize, '512 B');

      expect(WifiBook(
        id: '2', title: 'b', originalFilename: 'b.pdf',
        storedFilename: '2.pdf', format: 'PDF',
        byteCount: 2048, importedAt: DateTime(2026),
      ).formattedSize, '2.0 KB');

      expect(WifiBook(
        id: '3', title: 'c', originalFilename: 'c.mobi',
        storedFilename: '3.mobi', format: 'MOBI',
        byteCount: 5 * 1024 * 1024, importedAt: DateTime(2026),
      ).formattedSize, '5.0 MB');
    });

    test('toJson / fromJson 往返一致', () {
      final book = WifiBook(
        id: 'abc-123',
        title: '测试书名',
        originalFilename: '测试书名.epub',
        storedFilename: 'abc-123.epub',
        format: 'EPUB',
        byteCount: 10240,
        importedAt: DateTime(2026, 7, 17, 10, 30),
      );
      final json = book.toJson();
      final restored = WifiBook.fromJson(json);
      expect(restored.id, book.id);
      expect(restored.title, book.title);
      expect(restored.format, book.format);
      expect(restored.byteCount, book.byteCount);
    });

    test('copyWithTitle 保留原扩展名', () {
      final book = WifiBook(
        id: 'x', title: '旧名', originalFilename: '旧名.pdf',
        storedFilename: 'x.pdf', format: 'PDF',
        byteCount: 0, importedAt: DateTime(2026),
      );
      final renamed = book.copyWithTitle('新名');
      expect(renamed.title, '新名');
      expect(renamed.originalFilename, '新名.pdf');
      expect(renamed.format, 'PDF');
    });
  });

  group('KindleDownloadCompat', () {
    test('filename 生成纯 ASCII 短名', () {
      final book = WifiBook(
        id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        title: '中文标题',
        originalFilename: '中文标题.epub',
        storedFilename: 'a1b2c3d4.epub',
        format: 'EPUB',
        byteCount: 0, importedAt: DateTime(2026),
      );
      final name = KindleDownloadCompat.filename(book);
      expect(name, startsWith('ebook-'));
      expect(name, endsWith('.epub'));
      // 不含中文字符
      expect(RegExp(r'^[a-z0-9.\-]+$').hasMatch(name), isTrue);
    });

    test('downloadExtension 将 AZW3 映射为 azw', () {
      expect(KindleDownloadCompat.downloadExtension('AZW3'), 'azw');
      expect(KindleDownloadCompat.downloadExtension('EPUB'), 'epub');
      expect(KindleDownloadCompat.downloadExtension('PDF'), 'pdf');
    });

    test('contentType 返回正确 MIME', () {
      expect(KindleDownloadCompat.contentType('PDF'), 'application/pdf');
      expect(KindleDownloadCompat.contentType('EPUB'), 'application/epub+zip');
      expect(KindleDownloadCompat.contentType('TXT'), contains('text/plain'));
      expect(KindleDownloadCompat.contentType('MOBI'), 'application/octet-stream');
    });

    test('isSupportedPath 识别受支持扩展名', () {
      expect(KindleDownloadCompat.isSupportedPath('/a/b.epub'), isTrue);
      expect(KindleDownloadCompat.isSupportedPath('/a/b.pdf'), isTrue);
      expect(KindleDownloadCompat.isSupportedPath('/a/b.txt'), isTrue);
      expect(KindleDownloadCompat.isSupportedPath('/a/b.jpg'), isFalse);
      expect(KindleDownloadCompat.isSupportedPath('/a/b.zip'), isFalse);
    });
  });

  group('WifiBookLibrary', () {
    late Directory tempDir;
    late WifiBookLibrary library;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wifi_lib_test_');
      library = WifiBookLibrary(baseDirectory: tempDir);
    });

    tearDown(() async {
      library.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('导入文件后出现在书库列表', () async {
      // 创建测试文件
      final testFile = File(p.join(tempDir.path, '测试书.epub'));
      await testFile.writeAsString('fake epub content');

      // 初始化书库
      await library.init();
      final count = await library.importPaths([testFile.path]);

      expect(count, 1);
      expect(library.books.length, 1);
      expect(library.books.first.title, '测试书');
      expect(library.books.first.format, 'EPUB');
    });

    test('不支持格式的文件被跳过', () async {
      final testFile = File(p.join(tempDir.path, 'image.jpg'));
      await testFile.writeAsString('fake');

      await library.init();
      final count = await library.importPaths([testFile.path]);

      expect(count, 0);
      expect(library.books, isEmpty);
    });

    test('删除书籍后从列表移除', () async {
      final testFile = File(p.join(tempDir.path, 'delete_me.pdf'));
      await testFile.writeAsString('content');

      await library.init();
      await library.importPaths([testFile.path]);
      expect(library.books.length, 1);

      await library.delete(library.books.first);
      expect(library.books, isEmpty);
    });

    test('重命名修改标题但保留格式', () async {
      final testFile = File(p.join(tempDir.path, '原书名.txt'));
      await testFile.writeAsString('content');

      await library.init();
      await library.importPaths([testFile.path]);
      final book = library.books.first;

      await library.rename(book, '新名字');
      expect(library.books.first.title, '新名字');
      expect(library.books.first.format, 'TXT');
    });

    test('filter 按关键词过滤', () async {
      final f1 = File(p.join(tempDir.path, 'Python入门.epub'));
      final f2 = File(p.join(tempDir.path, 'Java进阶.pdf'));
      await f1.writeAsString('a');
      await f2.writeAsString('b');

      await library.init();
      await library.importPaths([f1.path, f2.path]);

      expect(library.filter('python').length, 1);
      expect(library.filter('java').length, 1);
      expect(library.filter('pdf').length, 1);
      expect(library.filter('').length, 2);
    });
  });
}
