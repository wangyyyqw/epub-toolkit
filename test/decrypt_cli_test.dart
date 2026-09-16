import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/decrypt_epub.dart' as cli;

void main() {
  late Directory directory;

  setUp(() async {
    exitCode = 0;
    directory = await Directory.systemTemp.createTemp('decrypt_cli_');
  });
  tearDown(() async {
    exitCode = 0;
    await directory.delete(recursive: true);
  });

  test('missing arguments return usage error', () async {
    await cli.main([]);
    expect(exitCode, 64);
  });

  test('existing output is never overwritten', () async {
    final output = await File(
      '${directory.path}/out.epub',
    ).writeAsString('keep');
    await cli.main(['${directory.path}/missing.epub', output.path]);
    expect(exitCode, 1);
    expect(await output.readAsString(), 'keep');
  });

  test('a ZIP without OPF cannot report successful decryption', () async {
    final source = File('${directory.path}/source.epub');
    await source.writeAsBytes(ZipEncoder().encode(Archive())!);
    final output = File('${directory.path}/out.epub');
    await cli.main([source.path, output.path]);
    expect(exitCode, 1);
    expect(await output.exists(), isFalse);
  });
}
