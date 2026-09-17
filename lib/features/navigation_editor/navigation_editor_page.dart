import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/file_service.dart';
import '../../core/theme.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../../shared/widgets/output_log.dart';
import '../epub_tools/epub_background_operation.dart';
import '../epub_tools/epub_tool_widgets.dart';
import 'navigation_editor.dart';
import 'navigation_model.dart';

class NavigationEditorPage extends StatefulWidget {
  const NavigationEditorPage({super.key});

  @override
  State<NavigationEditorPage> createState() => _NavigationEditorPageState();
}

class _NavigationEditorPageState extends State<NavigationEditorPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _userPickedOutput = false;
  bool _loading = false;
  bool _validating = false;
  NavigationSection _section = NavigationSection.toc;
  EpubNavigationDocument? _document;
  Timer? _validationTimer;
  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _validationTimer?.cancel();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _document = null;
    if (!_userPickedOutput) {
      _outputPath = await FileService.getDefaultOutputPathForInput(
        inputPath: path,
        filename: '${p.basenameWithoutExtension(path)}_navigation.epub',
      );
    }
    if (mounted) setState(() {});
    await _load();
  }

  Future<void> _pickOutput() async {
    final path = await FileService.saveFile(
      defaultFileName: _epubPath.isEmpty
          ? 'navigation.epub'
          : '${p.basenameWithoutExtension(_epubPath)}_navigation.epub',
      initialDirectory: _epubPath.isEmpty ? null : p.dirname(_epubPath),
    );
    if (path == null) return;
    _userPickedOutput = true;
    if (mounted) setState(() => _outputPath = path);
  }

  Future<void> _load() async {
    if (_epubPath.isEmpty) return;
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 正在读取 NAV、NCX 和特殊导航...');
    try {
      final data = await runRegisteredEpubOperation<Map<String, Object?>>(
        'navigationLoad',
        {'epubPath': _epubPath},
      );
      _document = EpubNavigationDocument.fromJson(data);
      _appendSummary();
      _success('目录导航已加载');
    } catch (error) {
      _logController.append('ERROR: 读取失败：$error');
      _error('读取失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerate() async {
    setState(() => _loading = true);
    _logController.append('PROGRESS: 正在按 spine 顺序扫描 H1-H6...');
    try {
      final data = await runRegisteredEpubOperation<Map<String, Object?>>(
        'navigationRegenerate',
        {'epubPath': _epubPath},
      );
      _document = EpubNavigationDocument.fromJson(data);
      _section = NavigationSection.toc;
      _appendSummary();
      _success('已从正文标题重建目录');
    } catch (error) {
      _error('重建失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final document = _document;
    if (document == null) return;
    if (_outputPath.isEmpty) await _pickOutput();
    if (_outputPath.isEmpty) return;
    await _validateNow();
    final errors = _document!.issues.where(
      (issue) => issue.severity == NavigationValidationSeverity.error,
    );
    if (errors.isNotEmpty) {
      _warning('请先修正 ${errors.length} 个目录错误');
      return;
    }

    setState(() => _loading = true);
    _logController.append('PROGRESS: 正在同步写入 NAV 与 NCX...');
    try {
      final result = await runRegisteredEpubOperation<Map<String, Object?>>(
        'navigationSave',
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'navigation': _document!.toJson(),
        },
      );
      _outputPath = await FileService.copyGeneratedFileToPublicDownload(
        sourcePath: result['outputPath'] as String,
        log: _logController.append,
      );
      _document = EpubNavigationDocument.fromJson(
        (result['navigation'] as Map).cast<String, Object?>(),
      );
      _logController.append('输出文件：$_outputPath');
      _appendSummary();
      _success('目录导航已保存并复检');
    } catch (error) {
      _logController.append('ERROR: 保存失败：$error');
      _error('保存失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _appendSummary() {
    final document = _document;
    if (document == null) return;
    _logController.append(
      'RESULT: 目录 ${document.entries(NavigationSection.toc).length} · '
      '地标 ${document.entries(NavigationSection.landmarks).length} · '
      '页码 ${document.entries(NavigationSection.pageList).length} · '
      '检查项 ${document.issues.length}',
    );
  }

  void _setEntries(List<NavigationEntry> entries) {
    final document = _document!;
    final sections = {
      for (final section in NavigationSection.values)
        section: section == _section ? entries : [...document.entries(section)],
    };
    setState(() {
      _document = document.copyWith(
        sections: sections,
        issues: NavigationEditorOperation.validateStructure(sections),
      );
    });
    _scheduleValidation();
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    _validationTimer = Timer(const Duration(milliseconds: 350), _validateNow);
  }

  Future<void> _validateNow() async {
    final document = _document;
    if (document == null || _validating) return;
    _validationTimer?.cancel();
    _validating = true;
    if (mounted) setState(() {});
    try {
      final raw = await runRegisteredEpubOperation<List<Object?>>(
        'navigationValidate',
        {'epubPath': _epubPath, 'navigation': document.toJson()},
      );
      if (!mounted || _document != document) return;
      setState(() {
        _document = document.copyWith(
          issues: raw
              .map(
                (item) => NavigationValidationIssue.fromJson(
                  (item as Map).cast<String, Object?>(),
                ),
              )
              .toList(),
        );
      });
    } catch (error) {
      if (mounted) _logController.append('ERROR: 目录检查失败：$error');
    } finally {
      _validating = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _addEntry() async {
    final result = await _editDialog(
      NavigationEntry(
        title: '',
        href: '',
        level: _document!.entries(_section).isEmpty
            ? 1
            : _document!.entries(_section).last.level,
      ),
      isNew: true,
    );
    if (result == null) return;
    _setEntries([..._document!.entries(_section), result]);
  }

  Future<void> _editEntry(int index) async {
    final entries = [..._document!.entries(_section)];
    final result = await _editDialog(entries[index]);
    if (result == null) return;
    entries[index] = result;
    _setEntries(entries);
  }

  Future<NavigationEntry?> _editDialog(
    NavigationEntry entry, {
    bool isNew = false,
  }) async {
    final title = TextEditingController(text: entry.title);
    final href = TextEditingController(text: entry.href);
    final semanticType = TextEditingController(text: entry.semanticType);
    final result = await showDialog<NavigationEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? '新增${_section.label}项' : '编辑${_section.label}项'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: href,
                decoration: const InputDecoration(
                  labelText: 'ZIP 内路径与锚点',
                  hintText: 'OEBPS/Text/chapter.xhtml#part',
                ),
              ),
              if (_section == NavigationSection.landmarks) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: semanticType,
                  decoration: const InputDecoration(
                    labelText: '地标语义类型',
                    hintText: 'cover / bodymatter / toc / titlepage',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              entry.copyWith(
                title: title.text.trim(),
                href: href.text.trim(),
                semanticType: semanticType.text.trim(),
                clearSourceHeadingIndex: href.text.trim() != entry.href,
              ),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    title.dispose();
    href.dispose();
    semanticType.dispose();
    return result;
  }

  void _entryAction(int index, String action) {
    final entries = [..._document!.entries(_section)];
    final entry = entries[index];
    switch (action) {
      case 'up':
        if (index == 0) return;
        entries[index] = entries[index - 1];
        entries[index - 1] = entry;
      case 'down':
        if (index >= entries.length - 1) return;
        entries[index] = entries[index + 1];
        entries[index + 1] = entry;
      case 'indent':
        if (index == 0 || entry.level >= entries[index - 1].level + 1) return;
        entries[index] = entry.copyWith(level: entry.level + 1);
      case 'outdent':
        if (entry.level <= 1) return;
        entries[index] = entry.copyWith(level: entry.level - 1);
        var child = index + 1;
        while (child < entries.length && entries[child].level > entry.level) {
          entries[child] = entries[child].copyWith(
            level: entries[child].level - 1,
          );
          child++;
        }
      case 'delete':
        final removedLevel = entry.level;
        entries.removeAt(index);
        var child = index;
        while (child < entries.length && entries[child].level > removedLevel) {
          entries[child] = entries[child].copyWith(
            level: entries[child].level - 1,
          );
          child++;
        }
    }
    _setEntries(entries);
  }

  void _reorder(int oldIndex, int newIndex) {
    final entries = [..._document!.entries(_section)];
    final entry = entries.removeAt(oldIndex);
    entries.insert(newIndex, entry);
    _setEntries(entries);
  }

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
            title: '目录与导航编辑器',
            subtitle: '树状编辑目录，同步维护 NAV、NCX、地标与页码导航',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                ResponsiveRow(
                  children: [
                    buildFilePickerRow(
                      context,
                      icon: Icons.book_outlined,
                      label: 'EPUB 文件',
                      value: _epubPath,
                      hint: '点击选择 EPUB 文件',
                      onTap: _loading ? () {} : _pickEpub,
                      isComplete: _epubPath.isNotEmpty,
                    ),
                    buildFilePickerRow(
                      context,
                      icon: Icons.save_outlined,
                      label: '输出 EPUB',
                      value: _outputPath,
                      hint: '点击选择输出位置',
                      onTap: _loading ? () {} : _pickOutput,
                      isComplete: _outputPath.isNotEmpty,
                    ),
                  ],
                ),
                if (_document != null) ...[
                  const SizedBox(height: 12),
                  _buildEditor(context),
                  const SizedBox(height: 12),
                  _buildValidation(context),
                ],
                const SizedBox(height: 12),
                OutputLog(controller: _logController),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading
                ? () {}
                : _document == null
                ? _load
                : _save,
            label: _document == null ? '读取目录' : '保存并复检',
            icon: _document == null ? Icons.list_alt : Icons.save_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final entries = _document!.entries(_section);
    return BaseCard(
      title: '导航结构',
      trailing: Wrap(
        spacing: 4,
        children: [
          if (_section == NavigationSection.toc)
            BaseButton(
              label: '从标题重建',
              icon: Icons.auto_fix_high_outlined,
              size: BaseButtonSize.sm,
              variant: BaseButtonVariant.secondary,
              onPressed: _loading ? null : _regenerate,
            ),
          IconButton(
            tooltip: '新增条目',
            onPressed: _loading ? null : _addEntry,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<NavigationSection>(
            segments: [
              for (final section in NavigationSection.values)
                ButtonSegment(
                  value: section,
                  label: Text(
                    '${section.label} ${_document!.entries(section).length}',
                  ),
                ),
            ],
            selected: {_section},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _section = value.first),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '${_section.label}没有条目',
                style: TextStyle(color: context.themeTextTertiary),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: entries.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) => _entryRow(
                context,
                entries[index],
                index,
                key: ValueKey('${_section.name}-$index-${entries[index].href}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryRow(
    BuildContext context,
    NavigationEntry entry,
    int index, {
    required Key key,
  }) {
    final issueCount = _document!.issues
        .where(
          (issue) => issue.section == _section && issue.entryIndex == index,
        )
        .length;
    return Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.themeDividerLight)),
      ),
      child: Row(
        children: [
          SizedBox(width: (entry.level - 1) * 18.0),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _editEntry(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title.isEmpty ? '未命名条目' : entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: entry.title.isEmpty
                                  ? const Color(0xFFB91C1C)
                                  : context.themeTextPrimary,
                            ),
                          ),
                        ),
                        if (issueCount > 0)
                          Text(
                            '$issueCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      entry.href.isEmpty ? '无链接分组' : entry.href,
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
            ),
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: () => _editEntry(index),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (action) => _entryAction(index, action),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'up', child: Text('上移')),
              PopupMenuItem(value: 'down', child: Text('下移')),
              PopupMenuItem(value: 'indent', child: Text('增加层级')),
              PopupMenuItem(value: 'outdent', child: Text('减少层级')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValidation(BuildContext context) {
    final issues = _document!.issues;
    final errors = issues
        .where((issue) => issue.severity == NavigationValidationSeverity.error)
        .length;
    final warnings = issues.length - errors;
    return BaseCard(
      title: '导航检查',
      trailing: _validating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text('$errors 个错误 · $warnings 个警告'),
      child: issues.isEmpty
          ? const Text('未发现空标题、重复条目、空章节或无效链接锚点')
          : Column(
              children: [
                for (final issue in issues)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      issue.severity == NavigationValidationSeverity.error
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      color:
                          issue.severity == NavigationValidationSeverity.error
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFFA16207),
                    ),
                    title: Text(issue.message),
                    subtitle: Text(issue.section.label),
                    onTap: issue.entryIndex == null
                        ? null
                        : () => setState(() => _section = issue.section),
                  ),
              ],
            ),
    );
  }
}
