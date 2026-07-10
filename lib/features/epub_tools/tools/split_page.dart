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
/// 按 TOC 章节拆分点将一个 EPUB 拆分为多个 EPUB。
/// 保留原 EPUB 版本（EPUB2 输出带 NCX，EPUB3 输出带 nav）。
class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

class _SplitPageState extends State<SplitPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _loading = false;
  final OutputLogController _logController = OutputLogController();

  /// 拆分点索引（逗号分隔，如 2,5,8）
  String _splitPoints = '';

  /// 拆分输出目录
  String _splitOutputDir = '';
  bool _userPickedOutputDir = false;

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 选择 EPUB 文件
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _outputPath = '';
    await _autoFillOutputPath();
    if (!_userPickedOutputDir) {
      _splitOutputDir = p.dirname(path);
    }
    if (mounted) setState(() {});
  }

  /// 自动填充输出路径
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final base = p.basenameWithoutExtension(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: '${base}_output.epub',
    );
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
    if (_splitPoints.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请输入拆分点索引');
      return;
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「拆分 EPUB」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      // 解析拆分点索引
      final points = _splitPoints
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? -1)
          .where((i) => i >= 0)
          .toList();
      // 输出目录：优先用用户选择的目录，否则用输出文件所在目录
      final outputDir = _splitOutputDir.isEmpty
          ? p.dirname(_outputPath)
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
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.call_split,
            iconColor: const Color(0xFFCA8A04),
            title: '拆分 EPUB',
            subtitle: '按章节拆分点将 EPUB 拆分为多个',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
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
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '拆分参数'),
                const SizedBox(height: 8),
                buildInfoBar(
                  context,
                  '按 TOC 章节拆分点将 EPUB 拆分为多个，保留原版本格式。可先用「列出拆分目标」查看章节索引。',
                ),
                const SizedBox(height: 12),
                buildCompactField(
                  context,
                  label: '拆分点索引（逗号分隔）',
                  value: _splitPoints,
                  hint: '拆分点索引，如 2,5,8',
                  icon: Icons.format_list_numbered,
                  onChanged: _loading ? (_) {} : (v) => _splitPoints = v,
                ),
                const SizedBox(height: 12),
                buildFilePickerRow(
                  context,
                  icon: Icons.folder_open,
                  label: '输出目录',
                  value: _splitOutputDir,
                  hint: '点击选择拆分输出目录',
                  onTap: _loading ? () {} : _pickSplitOutputDir,
                  isComplete: _splitOutputDir.isNotEmpty,
                ),
                const SizedBox(height: 8),
                OutputLog(controller: _logController),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
          ),
        ],
      ),
    );
  }
}
