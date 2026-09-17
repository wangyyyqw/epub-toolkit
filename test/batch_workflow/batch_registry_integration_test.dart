import 'dart:io';

import 'package:epub_gadget/features/batch_workflow/batch_queue.dart';
import 'package:epub_gadget/features/batch_workflow/batch_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtureDirectory = Directory('测试文件');
  final fixtures = fixtureDirectory.existsSync()
      ? fixtureDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.epub'))
            .toList()
      : <File>[];

  test(
    'default runner executes a real-book quick-check recipe',
    () async {
      final output = await Directory.systemTemp.createTemp(
        'batch-registry-integration-',
      );
      try {
        final controller = BatchQueueController(recipe: BatchRecipe.quickCheck)
          ..outputDirectory = output.path
          ..setInputs([fixtures.first.path]);

        await controller.start();

        final job = controller.jobs.single;
        expect(
          job.status,
          BatchJobStatus.succeeded,
          reason: '${job.error}\n${job.log.join('\n')}',
        );
        expect(job.healthSummary, isNotNull);
        expect(job.completedSteps, 1);
        expect(job.outputPath, isNull);
        expect(await File(controller.summaryJsonPath!).exists(), isTrue);
        expect(await File(controller.summaryHtmlPath!).exists(), isTrue);
        expect(
          output.listSync().whereType<File>().where(
            (file) => file.path.endsWith('_health.json'),
          ),
          isNotEmpty,
        );
        expect(
          output.listSync().whereType<File>().where(
            (file) => file.path.endsWith('_health.html'),
          ),
          isNotEmpty,
        );
      } finally {
        await output.delete(recursive: true);
      }
    },
    skip: fixtures.isEmpty ? '缺少测试文件目录中的真实 EPUB' : false,
  );
}
