import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/file_service.dart';
import '../../core/theme.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../epub_tools/epub_background_operation.dart';
import '../epub_tools/epub_tool_widgets.dart';
import 'batch_queue.dart';
import 'batch_recipe.dart';
import 'batch_recipe_store.dart';

class BatchWorkflowPage extends StatefulWidget {
  const BatchWorkflowPage({super.key});

  @override
  State<BatchWorkflowPage> createState() => _BatchWorkflowPageState();
}

class _BatchWorkflowPageState extends State<BatchWorkflowPage> {
  late final BatchQueueController _queue;
  final BatchRecipeStore _store = BatchRecipeStore();
  List<BatchRecipe> _recipes = [...BatchRecipe.builtIns];
  late final List<Map<String, Object?>> _operations;

  @override
  void initState() {
    super.initState();
    _queue = BatchQueueController()..addListener(_onQueueChanged);
    _operations = describeRegisteredEpubOperations(batchOnly: true);
    _loadRecipes();
  }

  @override
  void dispose() {
    _queue
      ..removeListener(_onQueueChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecipes() async {
    final recipes = await _store.load();
    if (!mounted) return;
    setState(() => _recipes = recipes);
  }

  Future<void> _pickFiles() async {
    final paths = await FileService.pickMultipleEpubs();
    if (paths == null) return;
    _queue.setInputs([..._queue.jobs.map((job) => job.inputPath), ...paths]);
  }

  Future<void> _pickInputDirectory() async {
    final path = await FileService.pickDirectory(title: '选择 EPUB 文件夹');
    if (path == null) return;
    final files = <String>[];
    await for (final entity in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
        files.add(entity.path);
      }
    }
    files.sort();
    _queue.setInputs([..._queue.jobs.map((job) => job.inputPath), ...files]);
    if (files.isEmpty) _warning('所选目录中没有 EPUB 文件');
  }

  Future<void> _pickOutputDirectory() async {
    final path = await FileService.pickDirectory(title: '选择批量输出目录');
    if (path == null) return;
    setState(() => _queue.outputDirectory = path);
  }

  void _selectRecipe(String? id) {
    if (id == null) return;
    final recipe = _recipes.firstWhere((item) => item.id == id);
    _queue.setRecipe(
      recipe.copyWith(
        steps: recipe.steps.map((step) => step.copyWith()).toList(),
      ),
    );
  }

  void _updateSteps(List<BatchRecipeStep> steps) {
    _queue.setRecipe(_queue.recipe.copyWith(steps: steps));
  }

  void _toggleStep(int index, bool enabled) {
    final steps = [..._queue.recipe.steps];
    steps[index] = steps[index].copyWith(enabled: enabled);
    _updateSteps(steps);
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _queue.recipe.steps.length) return;
    final steps = [..._queue.recipe.steps];
    final step = steps.removeAt(index);
    steps.insert(target, step);
    _updateSteps(steps);
  }

  Future<void> _addStep() async {
    final existing = _queue.recipe.steps
        .map((step) => step.operationId)
        .toSet();
    final candidates = _operations
        .where((operation) => !existing.contains(operation['id']))
        .toList();
    if (candidates.isEmpty) {
      _warning('没有更多可添加的批量操作');
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加处理步骤'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final operation in candidates)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(operation['displayName'] as String),
                  subtitle: Text(operation['description'] as String),
                  onTap: () => Navigator.pop(context, operation['id']),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final operation = _operation(selected);
    _updateSteps([
      ..._queue.recipe.steps,
      BatchRecipeStep(
        operationId: selected,
        arguments: (operation['defaultArguments'] as Map)
            .cast<String, Object?>(),
      ),
    ]);
  }

  Future<void> _editStep(int index) async {
    final step = _queue.recipe.steps[index];
    if (step.operationId == 'imgCompress') {
      var quality = step.arguments['jpegQuality'] as int? ?? 82;
      var pngToJpg = step.arguments['pngToJpg'] as bool? ?? false;
      final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('图片压缩参数'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('JPEG 质量：$quality'),
                  Slider(
                    value: quality.toDouble(),
                    min: 40,
                    max: 100,
                    divisions: 60,
                    label: '$quality',
                    onChanged: (value) =>
                        setDialogState(() => quality = value.round()),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('将无透明通道 PNG 转为 JPEG'),
                    value: pngToJpg,
                    onChanged: (value) =>
                        setDialogState(() => pngToJpg = value ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'jpegQuality': quality,
                  'pngToJpg': pngToJpg,
                }),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      );
      if (result != null) _replaceStep(index, step.copyWith(arguments: result));
      return;
    }
    if (step.operationId == 'convertVersion') {
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('目标 EPUB 版本'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '3.0'),
              child: const Text('EPUB 3.0'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '2.0'),
              child: const Text('EPUB 2.0'),
            ),
          ],
        ),
      );
      if (selected != null) {
        _replaceStep(
          index,
          step.copyWith(arguments: {'targetVersion': selected}),
        );
      }
      return;
    }
    if (step.operationId == 'phonetic') {
      var toneMode = step.arguments['toneMode'] as String? ?? 'symbol';
      var annotateAll = step.arguments['annotateAll'] as bool? ?? false;
      final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('拼音标注参数'),
            content: RadioGroup<String>(
              groupValue: toneMode,
              onChanged: (value) {
                if (value != null) setDialogState(() => toneMode = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile(title: Text('声调符号'), value: 'symbol'),
                  const RadioListTile(title: Text('数字声调'), value: 'number'),
                  CheckboxListTile(
                    title: const Text('标注全部汉字'),
                    value: annotateAll,
                    onChanged: (value) =>
                        setDialogState(() => annotateAll = value ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'toneMode': toneMode,
                  'annotateAll': annotateAll,
                }),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      );
      if (result != null) _replaceStep(index, step.copyWith(arguments: result));
      return;
    }
    _warning('此步骤没有可调整参数');
  }

  void _replaceStep(int index, BatchRecipeStep step) {
    final steps = [..._queue.recipe.steps];
    steps[index] = step;
    _updateSteps(steps);
  }

  Future<void> _saveRecipe() async {
    final controller = TextEditingController(text: '${_queue.recipe.name}副本');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存处理配方'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '配方名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final recipe = BatchRecipe(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      steps: _queue.recipe.steps.map((step) => step.copyWith()).toList(),
    );
    setState(() => _recipes = [..._recipes, recipe]);
    _queue.setRecipe(recipe);
    await _store.saveCustom(_recipes);
    _success('配方已保存');
  }

  Future<void> _deleteRecipe() async {
    if (_queue.recipe.builtIn) return;
    final id = _queue.recipe.id;
    setState(() => _recipes = _recipes.where((item) => item.id != id).toList());
    _queue.setRecipe(BatchRecipe.standardOptimize);
    await _store.saveCustom(_recipes);
    _success('配方已删除');
  }

  Future<void> _start() async {
    try {
      await _queue.start();
      if (!mounted) return;
      if (_queue.failedCount == 0) {
        _success('批量处理完成');
      } else {
        _warning('批量处理完成，${_queue.failedCount} 个任务失败');
      }
    } catch (error) {
      _error('$error');
    }
  }

  Future<void> _retryFailed() async {
    await _queue.retryFailed();
    if (!mounted) return;
    if (_queue.failedCount == 0) _success('失败任务重试完成');
  }

  Map<String, Object?> _operation(String id) {
    return _operations.firstWhere((operation) => operation['id'] == id);
  }

  String _operationName(String id) =>
      _operations
          .where((operation) => operation['id'] == id)
          .firstOrNull?['displayName']
          ?.toString() ??
      id;

  void _success(String message) {
    if (mounted) context.read<ToastProvider>().showSuccess(message);
  }

  void _warning(String message) {
    if (mounted) context.read<ToastProvider>().showWarning(message);
  }

  void _error(String message) {
    if (mounted) context.read<ToastProvider>().showError(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.account_tree_outlined,
            title: '批量任务与处理配方',
            subtitle: '组合 EPUB 操作，按受控并发处理多个文件',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                _buildFilesCard(context),
                const SizedBox(height: 12),
                _buildRecipeCard(context),
                const SizedBox(height: 12),
                _buildSettingsCard(context),
                if (_queue.jobs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildQueueCard(context),
                ],
              ],
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  Widget _buildFilesCard(BuildContext context) {
    return BaseCard(
      title: '输入与输出',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          BaseButton(
            label: '选择文件',
            icon: Icons.file_open_outlined,
            size: BaseButtonSize.sm,
            variant: BaseButtonVariant.secondary,
            onPressed: _queue.isRunning ? null : _pickFiles,
          ),
          BaseButton(
            label: '导入目录',
            icon: Icons.folder_open_outlined,
            size: BaseButtonSize.sm,
            variant: BaseButtonVariant.secondary,
            onPressed: _queue.isRunning ? null : _pickInputDirectory,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _queue.isRunning ? null : _pickOutputDirectory,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: context.themeDividerLight),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.output_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _queue.outputDirectory.isEmpty
                          ? '选择输出目录'
                          : _queue.outputDirectory,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _queue.outputDirectory.isEmpty
                            ? context.themeTextTertiary
                            : context.themeTextPrimary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          if (_queue.jobs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '已添加 ${_queue.jobs.length} 本 EPUB',
              style: TextStyle(fontSize: 12, color: context.themeTextTertiary),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _queue.jobs.length,
                itemBuilder: (context, index) {
                  final job = _queue.jobs[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.book_outlined, size: 18),
                    title: Text(
                      p.basename(job.inputPath),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      job.inputPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _queue.isRunning
                        ? null
                        : IconButton(
                            tooltip: '移除',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _queue.removeInput(job.inputPath),
                          ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecipeCard(BuildContext context) {
    return BaseCard(
      title: '处理配方',
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(
            tooltip: '添加步骤',
            onPressed: _queue.isRunning ? null : _addStep,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '保存为新配方',
            onPressed: _queue.isRunning ? null : _saveRecipe,
            icon: const Icon(Icons.save_outlined),
          ),
          if (!_queue.recipe.builtIn)
            IconButton(
              tooltip: '删除配方',
              onPressed: _queue.isRunning ? null : _deleteRecipe,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _recipes.any((item) => item.id == _queue.recipe.id)
                ? _queue.recipe.id
                : null,
            decoration: const InputDecoration(labelText: '已保存配方'),
            items: [
              for (final recipe in _recipes)
                DropdownMenuItem(value: recipe.id, child: Text(recipe.name)),
            ],
            onChanged: _queue.isRunning ? null : _selectRecipe,
          ),
          const SizedBox(height: 12),
          if (_queue.recipe.steps.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '尚未添加步骤',
                style: TextStyle(color: context.themeTextTertiary),
              ),
            )
          else
            for (var index = 0; index < _queue.recipe.steps.length; index++)
              _buildStep(context, index),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, int index) {
    final step = _queue.recipe.steps[index];
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.themeDividerLight)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: step.enabled,
            onChanged: _queue.isRunning
                ? null
                : (value) => _toggleStep(index, value ?? false),
          ),
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.themeTextTertiary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _operationName(step.operationId),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (step.arguments.isNotEmpty)
                  Text(
                    step.arguments.entries
                        .map((entry) => '${entry.key}=${entry.value}')
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeTextTertiary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '参数',
            icon: const Icon(Icons.tune, size: 18),
            onPressed: _queue.isRunning ? null : () => _editStep(index),
          ),
          IconButton(
            tooltip: '上移',
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: _queue.isRunning || index == 0
                ? null
                : () => _moveStep(index, -1),
          ),
          IconButton(
            tooltip: '下移',
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed:
                _queue.isRunning || index == _queue.recipe.steps.length - 1
                ? null
                : () => _moveStep(index, 1),
          ),
          IconButton(
            tooltip: '删除步骤',
            icon: const Icon(Icons.close, size: 18),
            onPressed: _queue.isRunning
                ? null
                : () {
                    final steps = [..._queue.recipe.steps]..removeAt(index);
                    _updateSteps(steps);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    return BaseCard(
      title: '队列设置',
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('并发'),
              const SizedBox(width: 10),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {_queue.concurrency},
                showSelectedIcon: false,
                onSelectionChanged: _queue.isRunning
                    ? null
                    : (value) =>
                          setState(() => _queue.concurrency = value.first),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('失败重试'),
              IconButton(
                tooltip: '减少重试次数',
                onPressed: _queue.isRunning || _queue.maxRetries == 0
                    ? null
                    : () => setState(() => _queue.maxRetries--),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${_queue.maxRetries}'),
              IconButton(
                tooltip: '增加重试次数',
                onPressed: _queue.isRunning || _queue.maxRetries == 5
                    ? null
                    : () => setState(() => _queue.maxRetries++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          CheckboxMenuButton(
            value: _queue.skipExisting,
            onChanged: _queue.isRunning
                ? null
                : (value) =>
                      setState(() => _queue.skipExisting = value ?? true),
            child: const Text('跳过已有输出'),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(BuildContext context) {
    return BaseCard(
      title: '任务队列',
      trailing: Text(
        '${_queue.completedCount}/${_queue.jobs.length}',
        style: TextStyle(color: context.themeTextTertiary),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _queue.jobs.isEmpty ? 0 : _queue.progress,
            minHeight: 4,
          ),
          const SizedBox(height: 10),
          for (final job in _queue.jobs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _jobIcon(job.status),
              title: Text(
                p.basename(job.inputPath),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                job.error ??
                    (job.currentOperationId == null
                        ? job.status.name
                        : _operationName(job.currentOperationId!)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: job.completedSteps == 0
                  ? null
                  : Text(
                      '${job.completedSteps}/${_queue.recipe.steps.where((step) => step.enabled).length}',
                    ),
            ),
          if (_queue.summaryJsonPath != null) ...[
            Divider(color: context.themeDividerLight),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                'JSON：${_queue.summaryJsonPath}\nHTML：${_queue.summaryHtmlPath}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeTextTertiary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobIcon(BatchJobStatus status) {
    return switch (status) {
      BatchJobStatus.queued => const Icon(Icons.schedule_outlined),
      BatchJobStatus.running => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      BatchJobStatus.succeeded => const Icon(
        Icons.check_circle_outline,
        color: Color(0xFF166534),
      ),
      BatchJobStatus.failed => const Icon(
        Icons.error_outline,
        color: Color(0xFFB91C1C),
      ),
      BatchJobStatus.skipped => const Icon(
        Icons.skip_next_outlined,
        color: Color(0xFFA16207),
      ),
      BatchJobStatus.cancelled => const Icon(Icons.cancel_outlined),
    };
  }

  Widget _buildActionBar(BuildContext context) {
    if (!_queue.isRunning) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_queue.failedCount > 0) ...[
                BaseButton(
                  label: '重试失败任务',
                  icon: Icons.refresh,
                  variant: BaseButtonVariant.secondary,
                  onPressed: _retryFailed,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: BaseButton(
                  label: '开始批量处理',
                  icon: Icons.play_arrow,
                  size: BaseButtonSize.lg,
                  expanded: MediaQuery.sizeOf(context).width < 720,
                  onPressed: _start,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            BaseButton(
              label: _queue.isPaused ? '继续' : '暂停',
              icon: _queue.isPaused ? Icons.play_arrow : Icons.pause,
              variant: BaseButtonVariant.secondary,
              onPressed: _queue.isPaused ? _queue.resume : _queue.pause,
            ),
            const SizedBox(width: 8),
            BaseButton(
              label: _queue.isCancelling ? '正在取消' : '取消',
              icon: Icons.stop,
              variant: BaseButtonVariant.danger,
              onPressed: _queue.isCancelling ? null : _queue.cancel,
            ),
          ],
        ),
      ),
    );
  }
}
