import 'dart:io';

import 'package:epub_gadget/features/epub_health/epub_health.dart';
import 'package:epub_gadget/features/navigation_editor/navigation_editor.dart';
import 'package:epub_gadget/features/navigation_editor/navigation_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final fixtureDirectory = Directory('测试文件');
  final fixtures = fixtureDirectory.existsSync()
      ? fixtureDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.epub'))
            .toList()
      : <File>[];

  test('真实 EPUB 可体检且目录原样保存后保持一致', () async {
    final output = await Directory.systemTemp.createTemp(
      'real-health-navigation-',
    );
    try {
      for (final fixture in fixtures) {
        final beforeHealth = await EpubHealthInspector.scan(fixture.path);
        expect(
          beforeHealth.issues.map((issue) => issue.code),
          isNot(contains('zip-invalid')),
          reason: fixture.path,
        );
        expect(beforeHealth.opfPath, isNotNull, reason: fixture.path);

        final beforeNavigation = await NavigationEditorOperation.load(
          fixture.path,
        );
        expect(
          beforeNavigation.entries(NavigationSection.toc),
          isNotEmpty,
          reason: fixture.path,
        );
        final saved = p.join(output.path, p.basename(fixture.path));
        await NavigationEditorOperation.save(
          epubPath: fixture.path,
          outputPath: saved,
          navigation: beforeNavigation,
        );
        final afterNavigation = await NavigationEditorOperation.load(saved);
        for (final section in NavigationSection.values) {
          expect(
            afterNavigation
                .entries(section)
                .map((entry) => entry.toJson())
                .toList(),
            beforeNavigation
                .entries(section)
                .map((entry) => entry.toJson())
                .toList(),
            reason: '${fixture.path} ${section.name}',
          );
        }
        final afterHealth = await EpubHealthInspector.scan(saved);
        expect(
          afterHealth.issues.map((issue) => issue.code),
          isNot(contains('zip-invalid')),
          reason: fixture.path,
        );
        expect(afterHealth.opfPath, isNotNull, reason: fixture.path);
      }
    } finally {
      await output.delete(recursive: true);
    }
  }, skip: fixtures.isEmpty ? '缺少测试文件目录中的真实 EPUB' : false);
}
