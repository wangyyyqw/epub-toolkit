import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/download_images/download_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('下载网络图片会保留 Images 目录大小写并写入正确相对路径', () async {
    final tempDir = await Directory.systemTemp.createTemp('download_images_');
    addTearDown(() => tempDir.delete(recursive: true));

    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9NwAAAABJRU5ErkJggg==',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/formula.png' ||
          request.uri.path == '/lazy.png') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(imageBytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final baseUrl = 'http://${server.address.address}:${server.port}';
    final source = File('${tempDir.path}/source.epub');
    final output = '${tempDir.path}/output.epub';
    final archive = Archive()
      ..addFile(
        ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/content.opf',
          100,
          utf8.encode('''<package><manifest></manifest></package>'''),
        ),
      )
      ..addFile(ArchiveFile('OEBPS/Images/cover.jpg', 1, [0]))
      ..addFile(
        ArchiveFile(
          'OEBPS/Text/part001.html',
          300,
          utf8.encode('''<html><body>
            <img src="$baseUrl/formula.png"/>
            <img data-src="$baseUrl/lazy.png"/>
          </body></html>'''),
        ),
      );
    await source.writeAsBytes(ZipEncoder().encode(archive)!);

    final log = await DownloadImagesOperation.execute(
      epubPath: source.path,
      outputPath: output,
    );

    expect(log, contains('成功 2 张'));
    final result = ZipDecoder().decodeBytes(await File(output).readAsBytes());
    final html = utf8.decode(
      result.findFile('OEBPS/Text/part001.html')!.content as List<int>,
    );
    expect(html, contains('../Images/formula.png'));
    expect(html, contains('../Images/lazy.png'));
    expect(html, isNot(contains(baseUrl)));
    expect(result.findFile('OEBPS/Images/formula.png'), isNotNull);
    expect(result.findFile('OEBPS/Images/lazy.png'), isNotNull);

    final opf = utf8.decode(
      result.findFile('OEBPS/content.opf')!.content as List<int>,
    );
    expect(opf, contains('href="Images/formula.png"'));
    expect(opf, contains('href="Images/lazy.png"'));
  });

  test(
    '真实微信读书 EPUB 的网络图片可全部本地化',
    () async {
      final epubPath = Platform.environment['DOWNLOAD_IMAGES_REAL_EPUB'];
      if (epubPath == null ||
          epubPath.isEmpty ||
          !await File(epubPath).exists()) {
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'download_images_real_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final output = '${tempDir.path}/localized.epub';

      final log = await DownloadImagesOperation.execute(
        epubPath: epubPath,
        outputPath: output,
      );

      expect(await File(output).exists(), isTrue, reason: log);
      final archive = ZipDecoder().decodeBytes(
        await File(output).readAsBytes(),
      );
      var remainingNetworkImageRefs = 0;
      for (final file in archive.files) {
        final name = file.name.toLowerCase();
        if (!name.endsWith('.html') && !name.endsWith('.xhtml')) continue;
        final content = utf8.decode(
          file.content as List<int>,
          allowMalformed: true,
        );
        remainingNetworkImageRefs += RegExp(
          r'''<(?:img|source|image)\b[^>]*?\b(?:src|data-src|data-original|data-lazy-src|href|xlink:href)\s*=\s*["']https?://''',
          caseSensitive: false,
        ).allMatches(content).length;
      }
      expect(remainingNetworkImageRefs, 0, reason: log);
    },
    skip: Platform.environment['DOWNLOAD_IMAGES_REAL_EPUB'] == null
        ? '设置 DOWNLOAD_IMAGES_REAL_EPUB 后运行真实网络图片下载验证'
        : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
