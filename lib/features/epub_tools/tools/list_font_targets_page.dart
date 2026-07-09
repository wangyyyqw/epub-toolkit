import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 列出字体目标页面
///
/// 扫描 EPUB 中的 CSS @font-face 规则和 HTML/XHTML 文件，
/// 列出所有可用的字体族名称和 HTML 文件路径，供字体加密操作选择目标使用。
class ListFontTargetsPage extends StatefulWidget {
  const ListFontTargetsPage({super.key});

  @override
  State<ListFontTargetsPage> createState() => _ListFontTargetsPageState();
}

class _ListFontTargetsPageState extends State<ListFontTargetsPage> {
  String _epubPath = '';
  bool _loading = false;
  final OutputLogController _logController = OutputLogController();

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
    if (mounted) setState(() {});
  }

  /// 将多行文本逐行追加到日志
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  /// 执行列出字体目标操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「列出字体目标」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.listFontTargets,
        {'epubPath': _epubPath},
      );
      _logAppendLines(result);
      if (mounted) context.read<ToastProvider>().showSuccess('扫描完成');
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
            icon: Icons.font_download_outlined,
            iconColor: const Color(0xFF9333EA),
            title: '列出字体目标',
            subtitle: '扫描 EPUB 中的字体族和 HTML 文件列表',
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
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 0),
                  dense: true,
                  title: Text(
                    '输出日志',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  leading: Icon(
                    Icons.terminal,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    SizedBox(
                      height: 150,
                      child: OutputLog(controller: _logController),
                    ),
                  ],
                ),
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
