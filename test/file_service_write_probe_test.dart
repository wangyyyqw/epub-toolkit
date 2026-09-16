import 'dart:io';

import 'package:epub_gadget/core/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'write probe preserves existing files and removes its own directory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'write_probe_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final existing = await File(
        '${directory.path}/.write_test',
      ).writeAsString('keep');
      await Future.wait(
        List.generate(
          4,
          (_) => FileService.ensureWritableDirectory(directory.path),
        ),
      );
      expect(await existing.readAsString(), 'keep');
      expect(await directory.list().length, 1);
    },
  );

  test('write probe reports unusable paths', () async {
    final directory = await Directory.systemTemp.createTemp(
      'write_probe_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/file').writeAsString('keep');
    await expectLater(
      FileService.ensureWritableDirectory(file.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'keep');
  });
}
