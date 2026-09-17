import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:epub_gadget/core/epub_packer.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_thought_operation.dart';
import 'package:flutter_test/flutter_test.dart';

String _quote(int chapter, int paragraph) =>
    '${chapter.toString().padLeft(4, '0')}-$paragraph 这是一段原创压力测试引文用于定位不同章节的读书想法。';

ArchiveFile _textFile(String name, String text) {
  final bytes = utf8.encode(text);
  return ArchiveFile(name, bytes.length, bytes);
}

Iterable<ArchiveFile> _bookFiles(int count) sync* {
  yield _textFile(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/content.opf"/></rootfiles></container>',
  );
  yield _textFile(
    'OPS/content.opf',
    '<package><metadata/><manifest>'
        '${List.generate(count, (i) => '<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>').join()}'
        '</manifest><spine>'
        '${List.generate(count, (i) => '<itemref idref="c$i"/>').join()}'
        '</spine></package>',
  );
  final filler = List.filled(90, '原创测试正文，章节数据在处理后不应驻留内存。').join();
  for (var i = 0; i < count; i++) {
    yield _textFile(
      'OPS/c$i.xhtml',
      '<html><head><title>测试章节编号$i</title></head><body>'
          '${List.generate(8, (j) => '<p>${_quote(i, j)}</p>').join()}'
          '<p>$filler</p></body></html>',
    );
  }
  // Exercise raw compressed pass-through and stored entries sharing one handle.
  yield ArchiveFile('OPS/font.bin', 1024 * 1024, Uint8List(1024 * 1024));
  yield _textFile('OPS/stored.txt', 'stored resource')..compress = false;
  yield _textFile('OPS/empty.txt', '');
}

List<ChapterData> _chapters(int count) => List.generate(
  count,
  (i) => ChapterData(
    chapterUid: '$i',
    title: '测试章节编号$i',
    underlines: List.generate(
      8,
      (j) => WereadUnderline(
        range: '${j * 100}-${j * 100 + 40}',
        markText: _quote(i, j),
        chapterUid: '$i',
      ),
    ),
    reviewMap: {
      for (var j = 0; j < 8; j++)
        '${j * 100}-${j * 100 + 40}': List.generate(
          4,
          (k) => WereadReview(
            range: '${j * 100}-${j * 100 + 40}',
            content: '想法[$i/$j/$k]，完整保留这条公开段评。',
            abstract: _quote(i, j),
            chapterUid: '$i',
            author: '测试读者$k',
            likes: k,
          ),
        ),
    },
  ),
);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('weread-large-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    '3200 chapters / 102400 thoughts stream in a responsive worker',
    () async {
      const count = 3200;
      final input = '${directory.path}/input.epub';
      final output = '${directory.path}/output.epub';
      await EpubPacker.packStreaming(
        files: _bookFiles(count),
        outputPath: input,
      );
      final originalHash = await sha256.bind(File(input).openRead()).first;
      final chapters = _chapters(count);
      var ticks = 0;
      var peakRss = ProcessInfo.currentRss;
      final startRss = peakRss;
      final clock = Stopwatch()..start();
      final heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
        ticks++;
        if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
      });
      final phases = <String>{};
      var progressEvents = 0;
      final unsendable = ReceivePort();
      late String result;
      try {
        result = await WereadThoughtOperation.execute(
          epubPath: input,
          outputPath: output,
          chapters: chapters,
          notePngBytes: Uint8List.fromList([1, 2, 3]),
          bookTitle: '原创大书压力夹具',
          bookReviews: [WereadReview(content: '书评测试', type: 'book')],
          onProgress: (phase, current, total, text) {
            // Prove the worker does not capture the caller's callback context.
            expect(unsendable.sendPort, isNotNull);
            phases.add(phase);
            progressEvents++;
          },
        );
      } finally {
        heartbeat.cancel();
        unsendable.close();
      }
      clock.stop();
      expect(
        ticks,
        greaterThan(10),
        reason: 'UI isolate must keep servicing events',
      );
      expect(phases, containsAll(['map', 'inject', 'pack']));
      expect(progressEvents, lessThan(clock.elapsedMilliseconds ~/ 150 + 30));
      expect(result, contains('25600 个想法锚点'));
      expect(result, isNot(contains('错误')));
      expect(result.length, lessThan(8000));
      expect(await sha256.bind(File(input).openRead()).first, originalHash);

      final stream = InputFileStream(output);
      try {
        final archive = ZipDecoder().decodeBuffer(stream);
        expect(archive.files.first.name, 'mimetype');
        expect(archive.files.first.compressionType, ArchiveFile.STORE);
        expect(
          utf8.decode(archive.files.first.content),
          'application/epub+zip',
        );
        expect(
          archive.findFile('OPS/font.bin')!.content,
          Uint8List(1024 * 1024),
        );
        expect(
          utf8.decode(archive.findFile('OPS/stored.txt')!.content),
          'stored resource',
        );
        expect(archive.findFile('OPS/empty.txt')!.size, 0);
        expect(archive.findFile('OPS/empty.txt')!.content, isEmpty);
        for (var i = 0; i < count; i++) {
          final file = archive.findFile('OPS/c$i.xhtml')!;
          final text = utf8.decode(file.content);
          expect(
            'class="reader js_readerFooterNote"'.allMatches(text).length,
            8,
          );
          for (var j = 0; j < 8; j++) {
            for (var k = 0; k < 4; k++) {
              expect(text, contains('想法[$i/$j/$k]'));
            }
          }
          file.clear();
        }
        expect(
          utf8.decode(
            archive.findFile('OPS/weread-book-reviews.xhtml')!.content,
          ),
          contains('书评测试'),
        );
      } finally {
        stream.closeSync();
      }
      // Diagnostics, not a platform-dependent RSS assertion.
      // ignore: avoid_print
      print(
        'STRESS: chapters=$count thoughts=${count * 32} '
        'elapsedMs=${clock.elapsedMilliseconds} heartbeat=$ticks '
        'rssStartMiB=${startRss ~/ (1024 * 1024)} '
        'rssPeakMiB=${peakRss ~/ (1024 * 1024)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('worker errors propagate and cannot overwrite the source', () async {
    final input = '${directory.path}/input.epub';
    await EpubPacker.packStreaming(files: _bookFiles(1), outputPath: input);
    final original = File(input).readAsBytesSync();
    await expectLater(
      WereadThoughtOperation.execute(
        epubPath: input,
        outputPath: input,
        chapters: _chapters(1),
        notePngBytes: Uint8List(0),
      ),
      throwsArgumentError,
    );
    expect(File(input).readAsBytesSync(), original);
    await expectLater(
      WereadThoughtOperation.execute(
        epubPath: '${directory.path}/missing.epub',
        outputPath: '${directory.path}/output.epub',
        chapters: _chapters(1),
        notePngBytes: Uint8List(0),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'streaming replaces output with canonical ZIP and normalized XHTML',
    () async {
      final output = File('${directory.path}/existing.epub')
        ..writeAsStringSync('old output');
      await EpubPacker.packStreaming(
        files: [
          _textFile('chapter.xhtml', '<p>new body</p>'),
          _textFile('mimetype', '\uFEFFapplication/epub+zip\n'),
          _textFile('chapter.xhtml', '<p>duplicate</p>'),
          _textFile('cover.xhtml', '<svg xmlns="http://www.w3.org/2000/svg"/>'),
        ],
        outputPath: output.path,
      );
      final bytes = output.readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(0, Endian.little), 0x04034b50);
      expect(header.getUint16(8, Endian.little), 0, reason: 'STORED');
      expect(header.getUint16(28, Endian.little), 0, reason: 'no extra field');
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(archive.files.map((f) => f.name), [
        'mimetype',
        'chapter.xhtml',
        'cover.xhtml',
      ]);
      expect(utf8.decode(archive.files.first.content), 'application/epub+zip');
      final chapter = utf8.decode(archive.findFile('chapter.xhtml')!.content);
      expect(chapter, contains('<!DOCTYPE html'));
      expect(chapter, contains('<body>'));
      expect(chapter, contains('<p>new body</p>'));
      final cover = utf8.decode(archive.findFile('cover.xhtml')!.content);
      expect(cover, contains('<svg'));
      expect(cover, isNot(contains('<html')));
      expect(directory.listSync().map((entry) => entry.path), [output.path]);
    },
  );

  test('invalid mimetype leaves existing output intact', () async {
    final output = File('${directory.path}/existing.epub')
      ..writeAsStringSync('old output');
    await expectLater(
      EpubPacker.packStreaming(
        files: [_textFile('mimetype', 'application/zip')],
        outputPath: output.path,
      ),
      throwsStateError,
    );
    expect(output.readAsStringSync(), 'old output');
    expect(directory.listSync().map((entry) => entry.path), [output.path]);
  });

  test(
    'streaming failure preserves existing output and cleans temporary files',
    () async {
      final output = File('${directory.path}/existing.epub')
        ..writeAsStringSync('existing output');
      Iterable<ArchiveFile> brokenFiles() sync* {
        yield _textFile('chapter.xhtml', '<p>partial output</p>');
        throw StateError('injection failed');
      }

      await expectLater(
        EpubPacker.packStreaming(files: brokenFiles(), outputPath: output.path),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'existing output');
      expect(directory.listSync().map((entry) => entry.path), [output.path]);
    },
  );
}
