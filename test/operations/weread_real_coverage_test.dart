import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_thought_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  final path = Platform.environment['WEREAD_REAL_EPUB'];
  test(
    'real book paragraph coverage with controlled offline reviews',
    () async {
      final input = File(path!);
      final originalHash = await sha256.bind(input.openRead()).first;
      final dir = await Directory.systemTemp.createTemp(
        'weread-real-coverage-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final stream = InputFileStream(input.path);
      final chapters = <ChapterData>[];
      final expected = <String, List<String>>{};
      try {
        final archive = ZipDecoder().decodeBuffer(stream);
        for (final file in archive.files) {
          if (!RegExp(r'/chapter\d+\.html$').hasMatch(file.name)) continue;
          final document = XmlDocument.parse(utf8.decode(file.content));
          final quotes = document.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'p')
              .map((element) => element.innerText.trim())
              .where((text) => text.length >= 40 && text.length <= 300)
              .take(3)
              .toList();
          file.clear();
          if (quotes.length < 2) continue;
          final uid = '${chapters.length + 1}';
          final markers = [
            for (var i = 0; i < quotes.length; i++) 'OFFLINE-COVERAGE-$uid-$i',
          ];
          expected[file.name] = markers;
          chapters.add(
            ChapterData(
              chapterUid: uid,
              title: document.descendants
                  .whereType<XmlElement>()
                  .firstWhere((e) => e.name.local == 'title')
                  .innerText,
              underlines: [
                for (var i = 0; i < quotes.length; i++)
                  WereadUnderline(
                    range: '${i * 1000}-${i * 1000 + 100}',
                    markText: quotes[i],
                    chapterUid: uid,
                  ),
              ],
              reviewMap: {
                for (var i = 0; i < quotes.length; i++)
                  '${i * 1000}-${i * 1000 + 100}': [
                    WereadReview(content: markers[i], abstract: quotes[i]),
                  ],
              },
            ),
          );
        }
      } finally {
        stream.closeSync();
      }
      expect(chapters.length, greaterThan(3000));
      final output = '${dir.path}/controlled-output.epub';
      final log = await WereadThoughtOperation.execute(
        epubPath: input.path,
        outputPath: output,
        chapters: chapters,
        notePngBytes: await File('assets/note.png').readAsBytes(),
      );
      final outputStream = InputFileStream(output);
      var found = 0;
      final missing = <String>[];
      try {
        final archive = ZipDecoder().decodeBuffer(outputStream);
        for (final entry in expected.entries) {
          final file = archive.findFile(entry.key)!;
          final text = utf8.decode(file.content);
          for (final marker in entry.value) {
            if (text.contains(marker)) {
              found++;
            } else {
              missing.add('${entry.key}:$marker');
            }
          }
          file.clear();
        }
      } finally {
        outputStream.closeSync();
      }
      expect(missing, isEmpty, reason: log);
      expect(await sha256.bind(input.openRead()).first, originalHash);
      // ignore: avoid_print
      print(
        'REAL COVERAGE: chapters=${chapters.length}, '
        'paragraphs=$found, missing=${missing.length}; source unchanged',
      );
    },
    skip: path == null ? 'Set WEREAD_REAL_EPUB to a local book.' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
