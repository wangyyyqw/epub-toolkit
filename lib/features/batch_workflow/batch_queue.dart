import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../epub_tools/epub_background_operation.dart';
import 'batch_recipe.dart';

enum BatchJobStatus { queued, running, succeeded, failed, skipped, cancelled }

class BatchHealthSummary {
  final int errorCount;
  final int warningCount;
  final int suggestionCount;
  final int safeFixCount;

  const BatchHealthSummary({
    required this.errorCount,
    required this.warningCount,
    required this.suggestionCount,
    required this.safeFixCount,
  });

  factory BatchHealthSummary.fromReport(Map<String, Object?> report) {
    final summary = (report['summary'] as Map?)?.cast<String, Object?>();
    return BatchHealthSummary(
      errorCount: summary?['errors'] as int? ?? 0,
      warningCount: summary?['warnings'] as int? ?? 0,
      suggestionCount: summary?['suggestions'] as int? ?? 0,
      safeFixCount: summary?['safeFixes'] as int? ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'errors': errorCount,
    'warnings': warningCount,
    'suggestions': suggestionCount,
    'safeFixes': safeFixCount,
  };
}

class BatchJob {
  final String inputPath;
  BatchJobStatus status;
  String? currentOperationId;
  String? outputPath;
  String? error;
  int completedSteps;
  int attemptCount;
  BatchHealthSummary? healthSummary;
  final List<String> log;

  BatchJob({
    required this.inputPath,
    this.status = BatchJobStatus.queued,
    this.currentOperationId,
    this.outputPath,
    this.error,
    this.completedSteps = 0,
    this.attemptCount = 0,
    this.healthSummary,
    List<String>? log,
  }) : log = log ?? [];

  Map<String, Object?> toJson() => {
    'inputPath': inputPath,
    'status': status.name,
    'currentOperationId': currentOperationId,
    'outputPath': outputPath,
    'error': error,
    'completedSteps': completedSteps,
    'attemptCount': attemptCount,
    if (healthSummary != null) 'healthSummary': healthSummary!.toJson(),
    'log': log,
  };
}

typedef BatchOperationRunner =
    Future<Object?> Function(
      String operationId,
      Map<String, Object?> arguments,
    );

class BatchQueueController extends ChangeNotifier {
  final BatchOperationRunner operationRunner;
  final List<BatchJob> jobs = [];

  BatchRecipe recipe;
  String outputDirectory = '';
  int concurrency = 1;
  int maxRetries = 1;
  bool skipExisting = true;
  bool isRunning = false;
  bool isPaused = false;
  bool isCancelling = false;
  String? summaryJsonPath;
  String? summaryHtmlPath;

  int _nextJobIndex = 0;
  bool _cancelRequested = false;
  Completer<void>? _resumeCompleter;
  final Map<String, String> _artifactBaseNames = {};

  BatchQueueController({
    BatchRecipe? recipe,
    BatchOperationRunner? operationRunner,
  }) : recipe = recipe ?? BatchRecipe.standardOptimize,
       operationRunner = operationRunner ?? _defaultOperationRunner;

  int get completedCount => jobs
      .where(
        (job) =>
            job.status == BatchJobStatus.succeeded ||
            job.status == BatchJobStatus.skipped,
      )
      .length;

  int get failedCount =>
      jobs.where((job) => job.status == BatchJobStatus.failed).length;

  double get progress => jobs.isEmpty ? 0 : completedCount / jobs.length;

  void setInputs(Iterable<String> paths) {
    if (isRunning) return;
    final unique = <String>{};
    jobs
      ..clear()
      ..addAll(
        paths
            .map((path) => File(path).absolute.path)
            .where((path) => path.toLowerCase().endsWith('.epub'))
            .where(unique.add)
            .map((path) => BatchJob(inputPath: path)),
      );
    notifyListeners();
  }

  void removeInput(String path) {
    if (isRunning) return;
    jobs.removeWhere((job) => job.inputPath == path);
    notifyListeners();
  }

  void setRecipe(BatchRecipe value) {
    if (isRunning) return;
    recipe = value;
    notifyListeners();
  }

  Future<void> start() async {
    if (isRunning) return;
    if (jobs.isEmpty) throw StateError('请先添加 EPUB 文件');
    if (outputDirectory.trim().isEmpty) throw StateError('请选择输出目录');
    if (recipe.steps.where((step) => step.enabled).isEmpty) {
      throw StateError('配方至少需要一个启用步骤');
    }
    await Directory(outputDirectory).create(recursive: true);
    _assignArtifactBaseNames();
    for (final job in jobs) {
      job.status = BatchJobStatus.queued;
      job.currentOperationId = null;
      job.outputPath = null;
      job.error = null;
      job.completedSteps = 0;
      job.attemptCount = 0;
      job.healthSummary = null;
      job.log.clear();
    }
    summaryJsonPath = null;
    summaryHtmlPath = null;
    await _runJobs(jobs);
  }

  Future<void> retryFailed() async {
    if (isRunning) return;
    final failed = jobs
        .where((job) => job.status == BatchJobStatus.failed)
        .toList();
    if (failed.isEmpty) return;
    for (final job in failed) {
      job.status = BatchJobStatus.queued;
      job.error = null;
      job.currentOperationId = null;
      job.completedSteps = 0;
      job.attemptCount = 0;
      job.log.add('重新加入队列');
    }
    await _runJobs(failed);
  }

  void pause() {
    if (!isRunning || isPaused) return;
    isPaused = true;
    _resumeCompleter = Completer<void>();
    notifyListeners();
  }

  void resume() {
    if (!isPaused) return;
    isPaused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    notifyListeners();
  }

  void cancel() {
    if (!isRunning || _cancelRequested) return;
    _cancelRequested = true;
    isCancelling = true;
    if (isPaused) resume();
    for (final job in jobs.where(
      (job) => job.status == BatchJobStatus.queued,
    )) {
      job.status = BatchJobStatus.cancelled;
      job.log.add('任务已取消');
    }
    notifyListeners();
  }

  Future<void> _runJobs(List<BatchJob> targetJobs) async {
    isRunning = true;
    isPaused = false;
    isCancelling = false;
    _cancelRequested = false;
    _nextJobIndex = 0;
    notifyListeners();
    try {
      final workerCount = concurrency.clamp(1, 4);
      await Future.wait(List.generate(workerCount, (_) => _worker(targetJobs)));
      await _writeSummary();
    } finally {
      isRunning = false;
      isPaused = false;
      isCancelling = false;
      _resumeCompleter = null;
      notifyListeners();
    }
  }

  Future<void> _worker(List<BatchJob> targetJobs) async {
    while (true) {
      await _waitIfPaused();
      if (_cancelRequested) return;
      final index = _nextJobIndex++;
      if (index >= targetJobs.length) return;
      final job = targetJobs[index];
      if (job.status != BatchJobStatus.queued) continue;
      await _process(job);
    }
  }

  Future<void> _process(BatchJob job) async {
    final input = File(job.inputPath);
    if (!await input.exists()) {
      job.status = BatchJobStatus.failed;
      job.error = '输入文件不存在';
      notifyListeners();
      return;
    }

    final enabledSteps = recipe.steps.where((step) => step.enabled).toList();
    final hasTransform = enabledSteps.any(
      (step) => _operationMode(step.operationId) == 'transform',
    );
    final artifactBase =
        _artifactBaseNames[job.inputPath] ??
        p.basenameWithoutExtension(job.inputPath);
    final finalPath = hasTransform
        ? p.join(outputDirectory, _outputFileName(artifactBase, recipe.name))
        : null;
    final healthBase = '${artifactBase}_health';
    if (skipExisting &&
        ((finalPath != null && await File(finalPath).exists()) ||
            (finalPath == null &&
                await File(
                  p.join(outputDirectory, '$healthBase.json'),
                ).exists()))) {
      job.status = BatchJobStatus.skipped;
      job.outputPath = finalPath;
      job.log.add('已跳过：输出已存在');
      notifyListeners();
      return;
    }

    job.status = BatchJobStatus.running;
    job.log.add('开始处理 ${p.basename(job.inputPath)}');
    notifyListeners();
    final workspace = await Directory.systemTemp.createTemp('epub-batch-');
    var currentPath = job.inputPath;
    try {
      for (var index = 0; index < enabledSteps.length; index++) {
        await _waitIfPaused();
        if (_cancelRequested) {
          job.status = BatchJobStatus.cancelled;
          job.log.add('完成当前步骤后取消');
          return;
        }
        final step = enabledSteps[index];
        job.currentOperationId = step.operationId;
        job.log.add(
          '步骤 ${index + 1}/${enabledSteps.length}：${_displayName(step.operationId)}',
        );
        notifyListeners();

        final mode = _operationMode(step.operationId);
        final arguments = <String, Object?>{
          ...step.arguments,
          'epubPath': currentPath,
        };
        String? stepOutput;
        if (mode == 'transform') {
          stepOutput = p.join(
            workspace.path,
            '${index.toString().padLeft(2, '0')}_${step.operationId}.epub',
          );
          arguments['outputPath'] = stepOutput;
        }

        final result = await _runWithRetry(job, step.operationId, arguments);
        if (stepOutput != null) {
          if (!await File(stepOutput).exists()) {
            if (_isPassThroughResult(step.operationId, result)) {
              await File(currentPath).copy(stepOutput);
              job.log.add('${_displayName(step.operationId)}无需修改，沿用当前 EPUB');
            } else {
              throw StateError('${_displayName(step.operationId)}未生成输出文件');
            }
          }
          currentPath = stepOutput;
        } else if (step.operationId == 'healthScan' && result is Map) {
          final report = result.cast<String, Object?>();
          final summary = BatchHealthSummary.fromReport(report);
          job.healthSummary = summary;
          await _writeHealthReport(report: report, baseName: healthBase);
          job.log.add(
            '体检：错误 ${summary.errorCount}，警告 ${summary.warningCount}，建议 ${summary.suggestionCount}',
          );
        }
        job.completedSteps++;
        notifyListeners();
        if (_cancelRequested) {
          job.status = BatchJobStatus.cancelled;
          job.currentOperationId = null;
          job.log.add('当前步骤已完成，任务已取消');
          return;
        }
      }

      if (finalPath != null) {
        final destination = File(finalPath);
        if (await destination.exists()) await destination.delete();
        await File(currentPath).copy(finalPath);
        job.outputPath = finalPath;
      }
      job.status = BatchJobStatus.succeeded;
      job.currentOperationId = null;
      job.log.add('处理完成');
    } catch (error, stack) {
      job.status = _cancelRequested
          ? BatchJobStatus.cancelled
          : BatchJobStatus.failed;
      job.error = '$error';
      job.log.add('失败：$error');
      if (kDebugMode) job.log.add('$stack');
    } finally {
      if (await workspace.exists()) await workspace.delete(recursive: true);
      notifyListeners();
    }
  }

  Future<Object?> _runWithRetry(
    BatchJob job,
    String operationId,
    Map<String, Object?> arguments,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      job.attemptCount++;
      try {
        return await operationRunner(operationId, arguments);
      } catch (error) {
        lastError = error;
        if (attempt >= maxRetries || _cancelRequested) rethrow;
        job.log.add(
          '${_displayName(operationId)}失败，正在重试 ${attempt + 1}/$maxRetries：$error',
        );
        notifyListeners();
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw StateError('$lastError');
  }

  Future<void> _waitIfPaused() async {
    while (isPaused && !_cancelRequested) {
      await _resumeCompleter?.future;
    }
  }

  Future<void> _writeSummary() async {
    if (outputDirectory.trim().isEmpty) return;
    final now = DateTime.now();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final base = 'batch_summary_$stamp';
    final jsonFile = File(p.join(outputDirectory, '$base.json'));
    final htmlFile = File(p.join(outputDirectory, '$base.html'));
    final data = {
      'schemaVersion': 1,
      'createdAt': now.toIso8601String(),
      'recipe': recipe.toJson(),
      'settings': {
        'concurrency': concurrency,
        'maxRetries': maxRetries,
        'skipExisting': skipExisting,
      },
      'summary': {
        'total': jobs.length,
        for (final status in BatchJobStatus.values)
          status.name: jobs.where((job) => job.status == status).length,
      },
      'jobs': jobs.map((job) => job.toJson()).toList(),
    };
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    await htmlFile.writeAsString(_summaryHtml(now), flush: true);
    summaryJsonPath = jsonFile.path;
    summaryHtmlPath = htmlFile.path;
  }

  Future<void> _writeHealthReport({
    required Map<String, Object?> report,
    required String baseName,
  }) async {
    final jsonFile = File(p.join(outputDirectory, '$baseName.json'));
    final htmlFile = File(p.join(outputDirectory, '$baseName.html'));
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await htmlFile.writeAsString(_healthReportHtml(report), flush: true);
  }

  String _healthReportHtml(Map<String, Object?> report) {
    final summary = BatchHealthSummary.fromReport(report);
    final issues = (report['issues'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((issue) {
          final value = issue.cast<String, Object?>();
          return '<tr><td>${_escape(value['severity']?.toString() ?? '')}</td>'
              '<td>${_escape(value['title']?.toString() ?? '')}</td>'
              '<td>${_escape(value['message']?.toString() ?? '')}</td>'
              '<td>${_escape(value['location']?.toString() ?? '')}</td></tr>';
        })
        .join();
    return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EPUB 体检报告</title><style>
body{font-family:system-ui,sans-serif;margin:0;background:#f5f5f4;color:#18181b}main{max-width:1000px;margin:auto;padding:32px 20px}h1{font-size:26px}.meta{color:#71717a;overflow-wrap:anywhere}.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin:20px 0}.metric{border:1px solid #d4d4d8;background:#fff;padding:12px}.metric strong{display:block;font-size:22px}table{width:100%;border-collapse:collapse;background:#fff}th,td{text-align:left;padding:10px;border:1px solid #d4d4d8;font-size:13px;overflow-wrap:anywhere}@media(max-width:700px){main{padding:20px 10px}.summary{grid-template-columns:repeat(2,1fr)}table{display:block;overflow:auto}}
</style></head><body><main><h1>EPUB 体检报告</h1>
<div class="meta">${_escape(report['sourcePath']?.toString() ?? '')}</div>
<div class="meta">${_escape(report['scannedAt']?.toString() ?? '')}</div>
<section class="summary"><div class="metric"><strong>${summary.errorCount}</strong>错误</div><div class="metric"><strong>${summary.warningCount}</strong>警告</div><div class="metric"><strong>${summary.suggestionCount}</strong>建议</div><div class="metric"><strong>${summary.safeFixCount}</strong>可安全修复</div></section>
<table><thead><tr><th>级别</th><th>问题</th><th>说明</th><th>位置</th></tr></thead><tbody>$issues</tbody></table>
</main></body></html>''';
  }

  String _summaryHtml(DateTime now) {
    final rows = jobs.map((job) {
      final health = job.healthSummary == null
          ? ''
          : '错误 ${job.healthSummary!.errorCount} / 警告 ${job.healthSummary!.warningCount}';
      return '<tr><td>${_escape(p.basename(job.inputPath))}</td>'
          '<td>${_escape(job.status.name)}</td>'
          '<td>${_escape(job.outputPath ?? '')}</td>'
          '<td>${_escape(health)}</td>'
          '<td>${_escape(job.error ?? '')}</td></tr>';
    }).join();
    return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EPUB 批量处理报告</title><style>
body{font-family:system-ui,sans-serif;margin:0;background:#f5f5f4;color:#18181b}main{max-width:1100px;margin:auto;padding:32px 20px}h1{font-size:26px}p{color:#71717a}table{width:100%;border-collapse:collapse;background:#fff}th,td{text-align:left;padding:10px;border:1px solid #d4d4d8;font-size:13px;overflow-wrap:anywhere}th{background:#f4f4f5}@media(max-width:700px){main{padding:20px 10px}table{display:block;overflow:auto}}
</style></head><body><main><h1>EPUB 批量处理报告</h1>
<p>${_escape(recipe.name)} · ${_escape(now.toIso8601String())} · 共 ${jobs.length} 本</p>
<table><thead><tr><th>文件</th><th>状态</th><th>输出</th><th>体检</th><th>错误</th></tr></thead><tbody>$rows</tbody></table>
</main></body></html>''';
  }

  static Future<Object?> _defaultOperationRunner(
    String operationId,
    Map<String, Object?> arguments,
  ) {
    return runRegisteredEpubOperation<Object?>(operationId, arguments);
  }

  String _operationMode(String operationId) {
    final description = describeRegisteredEpubOperations().firstWhere(
      (item) => item['id'] == operationId,
      orElse: () => throw ArgumentError('配方包含未知操作：$operationId'),
    );
    return description['mode'] as String;
  }

  String _displayName(String operationId) {
    final descriptions = describeRegisteredEpubOperations();
    return descriptions
            .where((item) => item['id'] == operationId)
            .firstOrNull?['displayName']
            ?.toString() ??
        operationId;
  }

  bool _isPassThroughResult(String operationId, Object? result) {
    if (result is! String) return false;
    final description = describeRegisteredEpubOperations()
        .where((item) => item['id'] == operationId)
        .firstOrNull;
    if (description == null) return false;
    final markers = (description['passThroughMessages'] as List? ?? const [])
        .whereType<String>();
    return markers.any(result.contains);
  }

  void _assignArtifactBaseNames() {
    _artifactBaseNames.clear();
    final used = <String>{};
    for (final job in jobs) {
      final base = p.basenameWithoutExtension(job.inputPath);
      var candidate = base;
      var suffix = 2;
      while (!used.add(candidate.toLowerCase())) {
        candidate = '${base}_${suffix++}';
      }
      _artifactBaseNames[job.inputPath] = candidate;
    }
  }

  static String _outputFileName(String base, String recipeName) {
    final suffix = recipeName
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${base}_${suffix.isEmpty ? 'batch' : suffix}.epub';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
