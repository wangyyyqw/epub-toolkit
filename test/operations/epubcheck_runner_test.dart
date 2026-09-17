import 'dart:io';

import 'package:epub_gadget/features/epub_health/epubcheck_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'runs EPUBCheck with input before the JSON report option',
    () async {
      final temp = await Directory.systemTemp.createTemp('epubcheck-test-');
      try {
        final epub = File('${temp.path}/book.epub')..writeAsStringSync('epub');
        final report = File('${temp.path}/report.json');
        final executable = File('${temp.path}/fake-epubcheck.sh');
        await executable.writeAsString('''#!/bin/sh
printf '%s\n' "\$@" > "\$(dirname "\$0")/arguments.txt"
printf '{"messages":[]}' > "\$3"
exit 0
''');
        await Process.run('chmod', ['+x', executable.path]);

        final result = await EpubCheckRunner.run(
          epub.path,
          reportPath: report.path,
          environment: {
            ...Platform.environment,
            'EPUBCHECK_JAR': '',
            'EPUBCHECK_COMMAND': executable.path,
          },
        );

        expect(result['exitCode'], 0);
        expect(result['report'], {'messages': <Object?>[]});
        expect(await File('${temp.path}/arguments.txt').readAsLines(), [
          epub.path,
          '--json',
          report.absolute.path,
        ]);
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'Uses a POSIX test executable.' : false,
  );
}
