import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = Platform.environment['REAL_EPUB_INPUT'];
  final directory = Platform.environment['REAL_EPUB_OUTPUT'];
  test('epubx imports the real book and every existing output', () async {
    final files = [
      File(input!),
      if (directory != null)
        ...Directory(directory).listSync(recursive: true).whereType<File>().where(
          (file) => file.path.endsWith('.epub') &&
              !['src.epub', 'a.epub', 'b.epub', 'encrypted.epub']
                  .contains(file.uri.pathSegments.last),
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
      } catch (error) {
        results.add({'file': file.path, 'ok': false, 'error': '$error'});
      }
    }
    if (directory != null) {
      await File('$directory/READER_AUDIT.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(results),
      );
    }
    expect(results.where((result) => result['ok'] == false), isEmpty);
  }, skip: input == null ? 'Set REAL_EPUB_INPUT.' : false,
      timeout: const Timeout(Duration(minutes: 10)));
}
