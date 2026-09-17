import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart';
import 'package:epub_gadget/core/epub_packer.dart';
import 'package:epub_gadget/features/download_images/download_images.dart';
import 'package:epub_gadget/features/download_images/safe_image_downloader.dart';
import 'package:epub_gadget/features/epub_to_txt/epub_to_txt.dart';
import 'package:epub_gadget/features/footnote_to_comment/footnote_to_comment.dart';
import 'package:epub_gadget/features/text_diff/text_diff_controller.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_book_library.dart';
import 'package:epub_gadget/features/wifi_transfer/wifi_http_server.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_thought_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xml/xml.dart';

void main() {
  final input = Platform.environment['REAL_EPUB_INPUT'];
  final output = Platform.environment['REAL_EPUB_OUTPUT'];
  if (input == null || output == null) {
    test(
      'real book workflows require explicit paths',
      () {},
      skip: 'Set REAL_EPUB_INPUT and REAL_EPUB_OUTPUT.',
    );
    return;
  }
  String operationOutput(String prefix) => Directory(output)
      .listSync()
      .whereType<Directory>()
      .singleWhere((d) => d.path.split('/').last.startsWith(prefix))
      .path;

  test(
    'independent epubx audit imports every real-book output',
    () async {
      final files = [
        File(input),
        ...Directory(output)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.epub') &&
                  ![
                    'src.epub',
                    'a.epub',
                    'b.epub',
                    'encrypted.epub',
                  ].contains(f.path.split('/').last),
            ),
      ];
      final results = <Map<String, Object>>[];
      for (final file in files) {
        try {
          final book = await EpubReader.readBook(await file.readAsBytes());
          expect(book.Content?.Html, isNotEmpty);
          expect(book.Schema?.Package?.Spine?.Items, isNotEmpty);
          results.add({
            'file': file.path,
            'ok': true,
            'html': book.Content!.Html!.length,
          });
        } catch (e) {
          results.add({'file': file.path, 'ok': false, 'error': '$e'});
        }
      }
      await File(
        '$output/READER_AUDIT.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      expect(results.where((r) => r['ok'] == false), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'real book text diff detects and reverses one edited line',
    () async {
      final text = await File(
        '${operationOutput('08_')}/out.txt',
      ).readAsString();
      final lines = text.split('\n');
      final index = lines.indexWhere((l) => l.trim().length > 50);
      expect(index, greaterThanOrEqualTo(0));
      final modified = [...lines];
      modified[index] = '${lines[index]} regression-marker';
      final controller = TextDiffController();
      addTearDown(controller.dispose);
      Future<void> settle() async {
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (controller.computing && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(controller.computing, isFalse);
      }

      controller.setTexts(left: text, right: modified.join('\n'));
      await settle();
      expect(controller.activeBlocks, hasLength(1));
      controller.copyBlock(0, toLeft: false);
      await settle();
      expect(controller.activeBlocks, isEmpty);
      expect(
        sha256.convert(utf8.encode(controller.rightText)),
        sha256.convert(utf8.encode(text)),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'real book WiFi library and HTTP download preserve exact bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('real_wifi_');
      final library = WifiBookLibrary(baseDirectory: dir);
      final server = WifiHttpServer(library);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        server.dispose();
        library.dispose();
        await dir.delete(recursive: true);
      });
      await library.init();
      expect(await library.importPaths([input]), 1);
      final book = library.books.single;
      await library.rename(book, 'C43 real regression');
      expect(library.filter('C43'), hasLength(1));
      final reloaded = WifiBookLibrary(baseDirectory: dir);
      await reloaded.init();
      expect(reloaded.books.single.title, 'C43 real regression');
      reloaded.dispose();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.port = probe.port;
      await probe.close();
      await server.start();
      expect(server.isRunning, isTrue);
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}'
        '${server.accessPath}books/${book.id}/book.epub',
      );
      final response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, HttpStatus.ok);
      final received = await sha256.bind(response).single;
      final original = await sha256.bind(File(input).openRead()).single;
      expect(received, original);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=1024-2047');
      final partial = await request.close();
      expect(partial.statusCode, HttpStatus.partialContent);
      final body = await partial.fold<List<int>>([], (a, b) => a..addAll(b));
      final originalBytes = await File(input).readAsBytes();
      expect(body, orderedEquals(originalBytes.sublist(1024, 2048)));
      await server.stop();
      await library.delete(library.books.single);
      expect(library.books, isEmpty);
      expect(await library.fileFor(book).exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('real book accepts offline WeRead review injection', () async {
    final dir = await Directory('$output/33_offline_weread').create();
    final destination = '${dir.path}/out.epub';
    final inputZip = ZipDecoder().decodeBytes(await File(input).readAsBytes());
    final target = _findReviewTarget(inputZip);
    final heading = target.heading;
    final quote = target.quote;
    final log = await WereadThoughtOperation.execute(
      epubPath: input,
      outputPath: destination,
      chapters: [
        ChapterData(
          chapterUid: '1',
          title: heading,
          underlines: [
            WereadUnderline(range: '1-60', markText: quote, chapterUid: '1'),
          ],
          reviewMap: {
            '1-60': [
              WereadReview(
                range: '1-60',
                content: 'offline-paragraph-regression-marker',
                abstract: quote,
                author: 'Offline test',
                chapterUid: '1',
              ),
            ],
          },
          chapterReviews: [
            WereadReview(
              content: 'offline-chapter-regression-marker',
              author: 'Offline test',
              chapterUid: '1',
              type: 'chapter',
            ),
          ],
        ),
      ],
      notePngBytes: await File('assets/note.png').readAsBytes(),
      bookTitle: 'C43 regression',
      bookReviews: [
        WereadReview(
          content: 'offline-review-regression-marker',
          author: 'Offline test',
          type: 'book',
        ),
      ],
    );
    await File('${dir.path}/result.log').writeAsString(log);
    expect(File(destination).existsSync(), isTrue, reason: log);
    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    final reviewPage = archive.files.singleWhere(
      (f) => f.name.endsWith('weread-book-reviews.xhtml'),
    );
    expect(
      utf8.decode(reviewPage.content as List<int>),
      contains('offline-review-regression-marker'),
    );
    final texts = archive.files
        .where((f) => f.name.endsWith('.xhtml'))
        .map((f) => utf8.decode(f.content as List<int>))
        .join();
    expect(texts.contains('offline-paragraph-regression-marker'), isTrue);
    expect(texts.contains('offline-chapter-regression-marker'), isTrue);
  });

  test('generated footnotes can convert back to popup comments', () async {
    final source = '${operationOutput('30_')}/out.epub';
    final dir = await Directory('$output/34_footnote_roundtrip').create();
    final destination = '${dir.path}/out.epub';
    final log = await FootnoteToCommentOperation.execute(
      epubPath: source,
      outputPath: destination,
      regexPattern: r'^#+',
      notePngBytes: await File('assets/note.png').readAsBytes(),
    );
    expect(log, isNot(contains('共转换 0 个链接')));
    final zip = ZipDecoder().decodeBytes(await File(destination).readAsBytes());
    expect(
      zip.files
          .where((f) => f.name.endsWith('.xhtml'))
          .any(
            (f) => utf8
                .decode(f.content as List<int>)
                .contains('js_readerFooterNote'),
          ),
      isTrue,
    );
    await File('${dir.path}/result.log').writeAsString(log);
  });

  test('encrypt/decrypt preserve visible book text', () async {
    final dir = await Directory('$output/35_text_roundtrip').create();
    final original = await File(
      '${operationOutput('08_')}/out.txt',
    ).readAsString();
    final restored = await EpubToTxtOperation.execute(
      epubPath: '${operationOutput('21_')}/out.epub',
      outputPath: '${dir.path}/out.txt',
    );
    expect(
      sha256.convert(utf8.encode(restored)),
      sha256.convert(utf8.encode(original)),
    );
  });

  test(
    'derived real book localizes a controlled remote image without network',
    () async {
      final dir = await Directory('$output/36_mock_remote_image').create();
      final archive = ZipDecoder().decodeBytes(await File(input).readAsBytes());
      final index = archive.files.indexWhere((f) => f.name.endsWith('.xhtml'));
      final original = archive.files[index];
      final text = utf8
          .decode(original.content as List<int>)
          .replaceFirst(
            '</body>',
            '<img src="https://images.example/c43-regression.png" alt="test"/>'
                '</body>',
          );
      final bytes = utf8.encode(text);
      archive[index] = ArchiveFile(original.name, bytes.length, bytes);
      final source = '${dir.path}/src.epub';
      final destination = '${dir.path}/out.epub';
      await EpubPacker.pack(archive: archive, outputPath: source);
      final image = await File('assets/note.png').readAsBytes();
      var requests = 0;
      final log = await DownloadImagesOperation.execute(
        epubPath: source,
        outputPath: destination,
        downloader: SafeImageDownloader(
          policy: PublicNetworkPolicy(
            lookup: (_) async => [InternetAddress('93.184.216.34')],
          ),
          clientFactory: () => MockClient((request) async {
            expect(
              request.url.toString(),
              'https://images.example/c43-regression.png',
            );
            requests++;
            return http.Response.bytes(
              image,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        ),
      );
      expect(requests, 1);
      expect(log, contains('成功 1 张'));
      final result = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      final rewritten = utf8.decode(
        result.findFile(original.name)!.content as List<int>,
      );
      expect(rewritten, isNot(contains('https://images.example')));
      final downloaded = result.files.singleWhere(
        (f) => f.name.endsWith('/c43-regression.png'),
      );
      expect(downloaded.content, orderedEquals(image));
      await File('${dir.path}/result.log').writeAsString(log);
    },
  );
}

({String heading, String quote}) _findReviewTarget(Archive archive) {
  for (final file in archive.files.where(
    (file) => file.isFile && file.name.toLowerCase().endsWith('.xhtml'),
  )) {
    try {
      final document = XmlDocument.parse(
        utf8.decode(file.content as List<int>),
      );
      final heading = document.descendants
          .whereType<XmlElement>()
          .where(
            (element) => RegExp(
              r'^h[1-6]$',
              caseSensitive: false,
            ).hasMatch(element.name.local),
          )
          .map((element) => element.innerText.trim())
          .where((text) => text.isNotEmpty)
          .firstOrNull;
      final quote = document
          .findAllElements('p')
          .map((element) => element.innerText.trim())
          .where((text) => text.length > 60)
          .firstOrNull;
      if (heading != null && quote != null) {
        return (heading: heading, quote: quote);
      }
    } catch (_) {
      // Continue until a parseable content document with usable text is found.
    }
  }
  throw StateError('真实 EPUB 中找不到可用于离线想法注入的正文段落');
}
