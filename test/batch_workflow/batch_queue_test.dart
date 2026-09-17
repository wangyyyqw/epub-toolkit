import 'dart:async';
import 'dart:io';

import 'package:epub_gadget/features/batch_workflow/batch_queue.dart';
import 'package:epub_gadget/features/batch_workflow/batch_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('batch-queue-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'runs multiple books with bounded concurrency and writes summaries',
    () async {
      final inputs = <String>[];
      for (var index = 0; index < 4; index++) {
        final file = File('${temp.path}/book$index.epub');
        await file.writeAsString('book-$index');
        inputs.add(file.path);
      }
      final output = Directory('${temp.path}/out');
      var active = 0;
      var maximumActive = 0;
      final controller =
          BatchQueueController(
              recipe: const BatchRecipe(
                id: 'test',
                name: '测试配方',
                steps: [
                  BatchRecipeStep(operationId: 'reformat'),
                  BatchRecipeStep(operationId: 'healthScan'),
                ],
              ),
              operationRunner: (operationId, arguments) async {
                active++;
                if (active > maximumActive) maximumActive = active;
                await Future<void>.delayed(const Duration(milliseconds: 25));
                try {
                  if (operationId == 'reformat') {
                    await File(
                      arguments['epubPath'] as String,
                    ).copy(arguments['outputPath'] as String);
                    return 'ok';
                  }
                  return _health(arguments['epubPath'] as String);
                } finally {
                  active--;
                }
              },
            )
            ..outputDirectory = output.path
            ..concurrency = 2
            ..setInputs(inputs);

      await controller.start();

      expect(maximumActive, 2);
      expect(
        controller.jobs.map((job) => job.status),
        everyElement(BatchJobStatus.succeeded),
      );
      expect(controller.summaryJsonPath, isNotNull);
      expect(await File(controller.summaryJsonPath!).exists(), isTrue);
      expect(await File(controller.summaryHtmlPath!).exists(), isTrue);
      for (final job in controller.jobs) {
        expect(await File(job.outputPath!).exists(), isTrue);
        expect(job.healthSummary, isNotNull);
        final base = job.inputPath
            .split(Platform.pathSeparator)
            .last
            .replaceFirst(RegExp(r'\.epub$', caseSensitive: false), '');
        expect(
          await File('${output.path}/${base}_health.json').exists(),
          isTrue,
        );
        expect(
          await File('${output.path}/${base}_health.html').exists(),
          isTrue,
        );
      }
    },
  );

  test('retries a failed step and can skip an existing output', () async {
    final input = File('${temp.path}/book.epub');
    await input.writeAsString('book');
    final output = Directory('${temp.path}/out')..createSync();
    var calls = 0;
    final controller =
        BatchQueueController(
            recipe: const BatchRecipe(
              id: 'retry',
              name: '重试',
              steps: [BatchRecipeStep(operationId: 'reformat')],
            ),
            operationRunner: (operationId, arguments) async {
              calls++;
              if (calls == 1) throw StateError('temporary');
              await input.copy(arguments['outputPath'] as String);
              return 'ok';
            },
          )
          ..outputDirectory = output.path
          ..maxRetries = 1
          ..setInputs([input.path]);

    await controller.start();
    expect(calls, 2);
    expect(controller.jobs.single.status, BatchJobStatus.succeeded);

    controller.setInputs([input.path]);
    await controller.start();
    expect(controller.jobs.single.status, BatchJobStatus.skipped);
    expect(calls, 2);
  });

  test('keeps outputs distinct for books with the same file name', () async {
    final firstDirectory = Directory('${temp.path}/first')..createSync();
    final secondDirectory = Directory('${temp.path}/second')..createSync();
    final first = File('${firstDirectory.path}/book.epub')
      ..writeAsStringSync('first');
    final second = File('${secondDirectory.path}/book.epub')
      ..writeAsStringSync('second');
    final output = Directory('${temp.path}/out');
    final controller =
        BatchQueueController(
            recipe: const BatchRecipe(
              id: 'duplicates',
              name: '同名测试',
              steps: [
                BatchRecipeStep(operationId: 'reformat'),
                BatchRecipeStep(operationId: 'healthScan'),
              ],
            ),
            operationRunner: (operationId, arguments) async {
              if (operationId == 'reformat') {
                await File(
                  arguments['epubPath'] as String,
                ).copy(arguments['outputPath'] as String);
                return 'ok';
              }
              return _health(arguments['epubPath'] as String);
            },
          )
          ..outputDirectory = output.path
          ..concurrency = 2
          ..setInputs([first.path, second.path]);

    await controller.start();

    final outputPaths = controller.jobs.map((job) => job.outputPath).toSet();
    expect(outputPaths, hasLength(2));
    expect(
      output.listSync().whereType<File>().map((file) => file.path),
      containsAll([
        '${output.path}/book_health.json',
        '${output.path}/book_2_health.json',
      ]),
    );
  });

  test('passes through a registered no-op transform result', () async {
    final input = File('${temp.path}/book.epub')
      ..writeAsStringSync('unchanged');
    final controller =
        BatchQueueController(
            recipe: const BatchRecipe(
              id: 'no-op',
              name: '无操作',
              steps: [BatchRecipeStep(operationId: 'webpToImg')],
            ),
            operationRunner: (operationId, arguments) async {
              return '未找到 WebP 图片，无需转换。';
            },
          )
          ..outputDirectory = '${temp.path}/out'
          ..setInputs([input.path]);

    await controller.start();

    final job = controller.jobs.single;
    expect(
      job.status,
      BatchJobStatus.succeeded,
      reason: '${job.error}\n${job.log.join('\n')}',
    );
    expect(await File(job.outputPath!).readAsString(), 'unchanged');
    expect(job.log, contains('WebP 转图片无需修改，沿用当前 EPUB'));
  });

  test('pause holds queued work and cancel marks remaining jobs', () async {
    final inputs = <String>[];
    for (var index = 0; index < 3; index++) {
      final file = File('${temp.path}/cancel$index.epub');
      await file.writeAsString('book');
      inputs.add(file.path);
    }
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final controller =
        BatchQueueController(
            recipe: const BatchRecipe(
              id: 'cancel',
              name: '取消',
              steps: [BatchRecipeStep(operationId: 'reformat')],
            ),
            operationRunner: (operationId, arguments) async {
              if (!firstStarted.isCompleted) firstStarted.complete();
              await releaseFirst.future;
              await File(
                arguments['epubPath'] as String,
              ).copy(arguments['outputPath'] as String);
              return 'ok';
            },
          )
          ..outputDirectory = '${temp.path}/out'
          ..concurrency = 1
          ..setInputs(inputs);

    final running = controller.start();
    await firstStarted.future;
    controller.pause();
    controller.cancel();
    releaseFirst.complete();
    await running;

    expect(
      controller.jobs.map((job) => job.status),
      everyElement(BatchJobStatus.cancelled),
    );
    expect(controller.isRunning, isFalse);
  });
}

Map<String, Object?> _health(String path) => {
  'sourcePath': path,
  'scannedAt': DateTime(2026, 9, 17).toIso8601String(),
  'epubVersion': '3.0',
  'opfPath': 'OEBPS/content.opf',
  'fileCount': 4,
  'manifestItemCount': 2,
  'spineItemCount': 1,
  'summary': {'errors': 0, 'warnings': 0, 'suggestions': 0, 'safeFixes': 0},
  'issues': <Object?>[],
};
