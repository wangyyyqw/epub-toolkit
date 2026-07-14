import 'package:epub_gadget/core/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('拖入路径可作为单个 EPUB 选择结果', () async {
    FileService.primeDroppedPaths([
      '/tmp/readme.txt',
      '/tmp/book.epub',
      '/tmp/cover.png',
    ]);

    final path = await FileService.pickEpub();

    expect(path, '/tmp/book.epub');
  });

  test('拖入多个 EPUB 可作为多选结果', () async {
    FileService.primeDroppedPaths([
      '/tmp/a.epub',
      '/tmp/cover.jpg',
      '/tmp/b.epub',
    ]);

    final paths = await FileService.pickMultipleEpubs();

    expect(paths, ['/tmp/a.epub', '/tmp/b.epub']);
  });

  test('拖入路径可作为图片选择结果', () async {
    FileService.primeDroppedPaths(['/tmp/book.epub', '/tmp/cover.png']);

    final path = await FileService.pickImage();

    expect(path, '/tmp/cover.png');
  });
}
