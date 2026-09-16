import 'dart:io';

import 'package:epub_gadget/features/decrypt/decrypt.dart';

/// Name-obfuscation repair only; deliberately does not bypass DRM.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/decrypt_epub.dart input.epub output.epub',
    );
    exitCode = 64;
    return;
  }
  try {
    final output = File(args[1]);
    if (await output.exists()) {
      throw StateError('Output already exists: ${output.path}');
    }
    await output.parent.create(recursive: true);
    final result = await DecryptOperation.execute(
      epubPath: args[0],
      outputPath: args[1],
    );
    stdout.writeln(result);
    if (result == 'not_encrypted') return;
    if (!await output.exists()) {
      stderr.writeln('No output was generated.');
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
