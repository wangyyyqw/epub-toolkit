import 'dart:convert';
import 'dart:io';

import 'package:epub_gadget/features/wifi_transfer/wifi_book.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_book_library.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_http_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WifiBook', () {
    test('formattedSize 正确格式化不同量级', () {
      expect(
        WifiBook(
          id: '1',
          title: 'a',
          originalFilename: 'a.epub',
          storedFilename: '1.epub',
          format: 'EPUB',
          byteCount: 512,
          importedAt: DateTime(2026),
        ).formattedSize,
        '512 B',
      );

      expect(
        WifiBook(
          id: '2',
          title: 'b',
          originalFilename: 'b.pdf',
          storedFilename: '2.pdf',
          format: 'PDF',
          byteCount: 2048,
          importedAt: DateTime(2026),
        ).formattedSize,
        '2.0 KB',
      );

      expect(
        WifiBook(
          id: '3',
          title: 'c',
          originalFilename: 'c.mobi',
          storedFilename: '3.mobi',
          format: 'MOBI',
          byteCount: 5 * 1024 * 1024,
          importedAt: DateTime(2026),
        ).formattedSize,
        '5.0 MB',
      );
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
        id: 'x',
        title: '旧名',
        originalFilename: '旧名.pdf',
        storedFilename: 'x.pdf',
        format: 'PDF',
        byteCount: 0,
        importedAt: DateTime(2026),
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
        byteCount: 0,
        importedAt: DateTime(2026),
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
      expect(
        KindleDownloadCompat.contentType('MOBI'),
        'application/octet-stream',
      );
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

    test('后续成功导入会清除上一次错误', () async {
      final unsupported = File(p.join(tempDir.path, 'image.jpg'));
      final supported = File(p.join(tempDir.path, 'book.epub'));
      await unsupported.writeAsString('image');
      await supported.writeAsString('book');

      await library.init();
      await library.importPaths(<String>[unsupported.path]);
      expect(library.errorMessage, isNotNull);

      final count = await library.importPaths(<String>[supported.path]);
      expect(count, 1);
      expect(library.errorMessage, isNull);
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

    test('主元数据损坏时从备份恢复并重写主文件', () async {
      // 先通过两次保存生成上一版有效备份，再模拟主文件写入中断。
      final source = File(p.join(tempDir.path, 'recover.epub'));
      await source.writeAsString('recoverable');
      await library.init();
      await library.importPaths([source.path]);
      await library.rename(library.books.first, '备份中的书名');
      await library.rename(library.books.first, '主文件中的书名');
      final expectedId = library.books.first.id;
      library.dispose();

      final metadata = File(p.join(tempDir.path, 'library.json'));
      final backup = File('${metadata.path}.bak');
      expect(await backup.exists(), isTrue);
      await metadata.writeAsString('{损坏');

      library = WifiBookLibrary(baseDirectory: tempDir);
      await library.init();

      expect(library.isReady, isTrue);
      expect(library.books.single.id, expectedId);
      expect(library.books.single.title, '备份中的书名');
      expect(library.errorMessage, contains('已从备份恢复'));
      expect(jsonDecode(await metadata.readAsString()), isA<List<dynamic>>());
    });

    test('元数据全部损坏时扫描现有书籍文件重建书库', () async {
      // 无可用备份时也不能丢弃 books 目录中仍完整的支持格式文件。
      final booksDir = Directory(p.join(tempDir.path, 'books'));
      await booksDir.create(recursive: true);
      await File(p.join(booksDir.path, 'orphan-id.pdf')).writeAsString('pdf');
      await File(
        p.join(tempDir.path, 'library.json'),
      ).writeAsString('not json');

      await library.init();

      expect(library.isReady, isTrue);
      expect(library.books.single.id, 'orphan-id');
      expect(library.books.single.format, 'PDF');
      expect(library.errorMessage, contains('已根据现有文件重建'));
    });

    test('恢复带点文件名时生成安全下载 ID', () async {
      final booksDir = Directory(p.join(tempDir.path, 'books'));
      await booksDir.create(recursive: true);
      await File(p.join(booksDir.path, 'my.book.pdf')).writeAsString('pdf');

      await library.init();

      final recovered = library.books.single;
      expect(recovered.storedFilename, 'my.book.pdf');
      expect(recovered.id, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(recovered.id, isNot(contains('.')));
    });
  });

  group('WifiHttpServer', () {
    late Directory tempDir;
    late WifiBookLibrary library;
    late WifiHttpServer server;
    late WifiBook book;
    const fileContent = '0123456789abcdef';

    setUp(() async {
      // 每条用例使用独立临时书库与动态端口，避免测试之间相互占用端口。
      tempDir = await Directory.systemTemp.createTemp('wifi_http_test_');
      final source = File(p.join(tempDir.path, '网络测试.epub'));
      await source.writeAsString(fileContent);
      library = WifiBookLibrary(baseDirectory: tempDir);
      await library.init();
      await library.importPaths([source.path]);
      book = library.books.single;
      server = WifiHttpServer(library, accessCode: 'testcode')..port = 20000;
      await server.start();
      expect(server.status, WifiServerStatus.running);
    });

    tearDown(() async {
      // 先停止监听再清理目录，避免仍在处理的请求访问已删除文件。
      await server.stop();
      server.dispose();
      library.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// 根据服务实际端口构造回环地址，避免局域网网卡地址在 CI 中不可达。
    Uri serverUri(String path, {required bool authorized}) {
      final relative = Uri.parse(path);
      final scopedPath = authorized
          ? (relative.path == '/'
                ? server.accessPath
                : '${server.accessPath}${relative.path.substring(1)}')
          : relative.path;
      return relative.replace(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: scopedPath,
      );
    }

    /// 发起请求并将响应体完整读取为字节，便于断言 HEAD 与 Range 行为。
    Future<_HttpTestResponse> request(
      String path, {
      String method = 'GET',
      Map<String, String> headers = const <String, String>{},
      bool authorized = true,
    }) async {
      final client = HttpClient();
      try {
        final httpRequest = await client.openUrl(
          method,
          serverUri(path, authorized: authorized),
        );
        headers.forEach(httpRequest.headers.set);
        final response = await httpRequest.close();
        final body = await response.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        return _HttpTestResponse(response.statusCode, response.headers, body);
      } finally {
        client.close(force: true);
      }
    }

    test('GET 首页返回中文书名和可下载链接', () async {
      // 首页必须以 UTF-8 正确传输中文，同时链接使用兼容 Kindle 的短文件名。
      final response = await request('/');
      final html = utf8.decode(response.body);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(response.headers.contentLength, response.body.length);
      expect(html, contains('网络测试'));
      expect(html, contains('${server.accessPath}books/${book.id}/'));
      expect(html, contains(KindleDownloadCompat.filename(book)));
      expect(html, contains('action="${server.accessPath}"'));
    });

    test('访问地址包含短会话路径且未授权首页不可见', () async {
      expect(server.addresses, isNotEmpty);
      expect(server.address, endsWith(server.accessPath));
      expect(server.addresses, everyElement(endsWith(server.accessPath)));

      final response = await request('/', authorized: false);
      expect(response.statusCode, HttpStatus.notFound);
      expect(utf8.decode(response.body), isNot(contains('网络测试')));
    });

    test('未知路径返回 404 且 HEAD 不返回正文', () async {
      // GET 404 提供错误页面，HEAD 404 仅保留与 GET 相同的正文长度信息。
      final getResponse = await request('/missing');
      final headResponse = await request('/missing', method: 'HEAD');

      expect(getResponse.statusCode, HttpStatus.notFound);
      expect(utf8.decode(getResponse.body), contains('未找到资源'));
      expect(headResponse.statusCode, HttpStatus.notFound);
      expect(headResponse.body, isEmpty);
      expect(
        headResponse.headers.contentLength,
        getResponse.headers.contentLength,
      );
    });

    test('HEAD 下载返回文件头但不传输正文', () async {
      // Kindle 可先用 HEAD 获取文件大小、Range 能力与下载文件名。
      final response = await request(
        '/books/${book.id}/book.epub',
        method: 'HEAD',
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, isEmpty);
      expect(response.headers.contentLength, utf8.encode(fileContent).length);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(
        response.headers.value('Content-Disposition'),
        contains('attachment'),
      );
      expect(response.headers.value(HttpHeaders.connectionHeader), 'close');
    });

    test('旧式 id.ext 下载路由仍然可用', () async {
      final response = await request('/books/${book.id}.epub');

      expect(response.statusCode, HttpStatus.ok);
      expect(utf8.decode(response.body), fileContent);
    });

    test('If-Modified-Since 命中时返回 304', () async {
      final first = await request('/books/${book.id}/book.epub');
      final lastModified = first.headers.value(HttpHeaders.lastModifiedHeader);
      expect(lastModified, isNotNull);

      final cached = await request(
        '/books/${book.id}/book.epub',
        headers: <String, String>{
          HttpHeaders.ifModifiedSinceHeader: lastModified!,
        },
      );

      expect(cached.statusCode, HttpStatus.notModified);
      expect(cached.body, isEmpty);
    });

    test('Range 下载返回指定字节和 206 响应', () async {
      // 单段闭区间 Range 必须返回准确正文、长度和 Content-Range。
      final response = await request(
        '/books/${book.id}/book.epub',
        headers: const {HttpHeaders.rangeHeader: 'bytes=3-7'},
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(utf8.decode(response.body), '34567');
      expect(response.headers.contentLength, 5);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 3-7/${utf8.encode(fileContent).length}',
      );
    });

    test('越界 Range 返回 416 与完整文件长度', () async {
      // 无法满足的 Range 不应退化为整文件下载，避免客户端断点续传拼接错误。
      final response = await request(
        '/books/${book.id}/book.epub',
        headers: const {HttpHeaders.rangeHeader: 'bytes=999-'},
      );

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(response.body, isEmpty);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */${utf8.encode(fileContent).length}',
      );
    });

    test('停止后可在同一实例重启并继续响应', () async {
      // 覆盖真实停止、释放端口、再次启动和恢复请求处理的完整生命周期。
      await server.stop();
      expect(server.status, WifiServerStatus.stopped);
      expect(server.address, isNull);

      await server.start();
      final response = await request('/health', authorized: false);

      expect(server.status, WifiServerStatus.running);
      expect(response.statusCode, HttpStatus.ok);
      expect(utf8.decode(response.body), 'ok');
    });
  });
}

/// HTTP 集成测试所需的最小响应快照。
class _HttpTestResponse {
  const _HttpTestResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> body;
}
