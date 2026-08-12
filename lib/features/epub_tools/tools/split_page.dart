import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 拆分 EPUB 页面
///
/// 扫描 EPUB 的 TOC 章节目录并列出，用户通过勾选章节手动插入分割点，
/// 每个被勾选的章节作为下一分卷的起点。保留原 EPUB 版本
/// （EPUB2 输出带 NCX，EPUB3 输出带 nav）。
class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

/// 拆分目标条目（与后台返回的 data 字段对应）
class _SplitTargetUi {
  final String title;
  final int level;
  final String href;

  const _SplitTargetUi({
    required this.title,
    required this.level,
    required this.href,
  });
}

class _SplitPageState extends State<SplitPage> {
  String _epubPath = '';
  bool _loading = false;

  /// 拆分输出目录
  String _splitOutputDir = '';
  bool _userPickedOutputDir = false;

  /// 章节目标列表
  List<_SplitTargetUi> _targets = [];
  bool _targetsLoading = false;

  /// 被勾选作为分割点的章节索引
  final Set<int> _selected = {};

  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 选择 EPUB 文件，随后自动扫描章节目录
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    setState(() {
      _epubPath = path;
      _targets = [];
      _selected.clear();
    });
    if (!_userPickedOutputDir) {
      _splitOutputDir = p.dirname(path);
    }
    await _loadTargets();
    if (mounted) setState(() {});
  }

  /// 扫描 EPUB 的 TOC 章节目录
  Future<void> _loadTargets() async {
    if (_epubPath.isEmpty || _targetsLoading) return;
    setState(() => _targetsLoading = true);
    try {
      final result = await runEpubBackgroundOperation<Map>(
        EpubBackgroundOperation.listSplitTargets,
        {'epubPath': _epubPath},
      );
      final data = (result['data'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _targets = data
            .map((e) => _SplitTargetUi(
                  title: (e as Map)['title'] as String? ?? '',
                  level: (e['level'] as num?)?.toInt() ?? 1,
                  href: e['href'] as String? ?? '',
                ))
            .toList();
        // 保留仍然有效的勾选
        _selected.removeWhere((i) => i < 0 || i >= _targets.length);
      });
      if (_targets.isEmpty) {
        context.read<ToastProvider>().showWarning('未解析到章节目录，无法设置分割点');
      }
    } catch (e) {
      if (!mounted) return;
      context.read<ToastProvider>().showError('读取章节目录失败：$e');
    } finally {
      if (mounted) setState(() => _targetsLoading = false);
    }
  }

  /// 选择拆分输出目录
  Future<void> _pickSplitOutputDir() async {
    final dir = await FileService.pickDirectory(title: '选择拆分输出目录');
    if (dir == null) return;
    _userPickedOutputDir = true;
    setState(() => _splitOutputDir = dir);
  }

  /// 将多行文本逐行追加到日志
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  /// 执行拆分 EPUB 操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_selected.isEmpty) {
      context.read<ToastProvider>().showWarning('请在章节目录中勾选至少 1 个分割点');
      return;
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「拆分 EPUB」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final points = _selected.toList()..sort();
      final outputDir = _splitOutputDir.isEmpty
          ? p.dirname(_epubPath)
          : _splitOutputDir;
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.split,
        {'epubPath': _epubPath, 'outputDir': outputDir, 'splitPoints': points},
      );
      _logAppendLines(result);
      if (mounted) context.read<ToastProvider>().showSuccess('拆分完成');
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      if (mounted) context.read<ToastProvider>().showError('操作失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.call_split,
            title: '拆分 EPUB',
            subtitle: '列出章节目录，勾选章节作为分割点拆分为多个 EPUB',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                // 输入 + 输出（桌面双列并排，移动端单列）
                ResponsiveRow(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildSectionLabel(context, Icons.folder_open, 'EPUB 文件'),
                        const SizedBox(height: 8),
                        buildFilePickerRow(
                          context,
                          icon: Icons.book_outlined,
                          label: 'EPUB 文件',
                          value: _epubPath,
                          hint: '点击选择 EPUB 文件',
                          onTap: _loading ? () {} : _pickEpub,
                          isComplete: _epubPath.isNotEmpty,
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildSectionLabel(context, Icons.folder_open, '输出目录'),
                        const SizedBox(height: 8),
                        buildFilePickerRow(
                          context,
                          icon: Icons.folder_open,
                          label: '输出目录',
                          value: _splitOutputDir,
                          hint: '点击选择拆分输出目录',
                          onTap: _loading ? () {} : _pickSplitOutputDir,
                          isComplete: _splitOutputDir.isNotEmpty,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 章节目录
                buildSectionLabel(context, Icons.list_alt_outlined, '章节目录'),
                const SizedBox(height: 8),
                buildInfoBar(
                  context,
                  '勾选章节作为分割点：每个被勾选的章节将作为下一分卷的起点（默认从第一段开始）。',
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline),
                  ),
                  child: _buildTargetList(),
                ),
                if (_targets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已勾选 ${_selected.length} 个分割点，可拆分为 ${_selected.length + 1} 卷',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => setState(_selected.clear),
                        child: const Text('清空勾选'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                OutputLog(controller: _logController),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
            label: '按分割点拆分',
            icon: Icons.call_split,
          ),
        ],
      ),
    );
  }

  /// 章节目标勾选列表
  Widget _buildTargetList() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_targetsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_targets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _epubPath.isEmpty ? '选择 EPUB 后自动扫描章节目录' : '未解析到章节目录',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _targets.length,
      itemBuilder: (context, index) {
        final target = _targets[index];
        final checked = _selected.contains(index);
        return CheckboxListTile(
          value: checked,
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: theme.colorScheme.primary,
          contentPadding: EdgeInsets.only(left: 12 + (target.level - 1) * 16),
          title: Text(
            target.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
              color: checked
                  ? theme.colorScheme.primary
                  : cs.onSurface,
            ),
          ),
          subtitle: target.href.isNotEmpty
              ? Text(
                  '${index + 1} · ${target.href}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.outline),
                )
              : null,
          onChanged: _loading
              ? null
              : (v) {
                  setState(() {
                    if (v ?? false) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  });
                },
        );
      },
    );
  }
}
