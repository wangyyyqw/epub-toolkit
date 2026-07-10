import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 重新格式化页面
///
/// 独立 StatefulWidget，规范化 EPUB 内部结构、清理冗余文件，
/// 输出重构后的 EPUB。操作返回日志字符串，逐行写入日志面板。
class ReformatPage extends StatefulWidget {
  const ReformatPage({super.key});

  @override
  State<ReformatPage> createState() => _ReformatPageState();
}

class _ReformatPageState extends State<ReformatPage> {
  // ==================== 页面配置 ====================

  static const _title = '重新格式化';
  static const _subtitle = '规范化 EPUB 内部结构，清理冗余文件';
  static const _icon = Icons.auto_fix_high_outlined;
  static const _iconColor = Color(0xFF8B5CF6);

  bool get _returnsText => false;
  String get _resultTitle => '提取的文本';

  // ==================== 状态 ====================

  String _epubPath = '';
  String _outputPath = '';
  bool _userPickedOutput = false;
  bool _loading = false;
  String _resultText = '';
  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  // ==================== 文件选择 ====================

  /// 选择 EPUB 文件，并在用户未手动指定输出路径时自动填充默认输出名
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path != null) {
      _epubPath = path;
      // 用户未手动选择输出路径时，重置并按新输入文件自动填充
      if (!_userPickedOutput) {
        _outputPath = '';
        await _autoFillOutputPath();
      }
      if (mounted) setState(() {});
    }
  }

  /// 手动选择输出路径，标记为用户自定义，后续不再自动覆盖
  Future<void> _pickOutput(String defaultName) async {
    final path = await FileService.saveFile(
      defaultFileName: defaultName,
      initialDirectory: _epubPath.isNotEmpty ? p.dirname(_epubPath) : null,
    );
    if (path != null) {
      _userPickedOutput = true;
      setState(() => _outputPath = path);
    }
  }

  /// 根据输入文件名自动生成输出路径
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final filename = _defaultOutputFilename(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: filename,
    );
  }

  /// 默认输出文件名：${base}_output.epub
  String _defaultOutputFilename(String inputPath) {
    final base = p.basenameWithoutExtension(inputPath);
    return '${base}_output.epub';
  }

  /// 执行前确保输出路径已填充
  Future<void> _ensureOutputPath() async {
    if (_outputPath.isEmpty && _epubPath.isNotEmpty) {
      await _autoFillOutputPath();
    }
  }

  // ==================== 日志 / Toast 辅助 ====================

  void _logAppend(String line) => _logController.append(line);

  /// 将多行文本逐行写入日志（跳过空行）
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  void _showSuccess(String msg) {
    if (mounted) context.read<ToastProvider>().showSuccess(msg);
  }

  void _showError(String msg) {
    if (mounted) context.read<ToastProvider>().showError(msg);
  }

  void _showWarning(String msg) {
    if (mounted) context.read<ToastProvider>().showWarning(msg);
  }

  // ==================== 执行 ====================

  /// 具体操作逻辑（重构 EPUB 结构并输出）
  Future<void> _executeOperation() async {
    _logAppend('PROGRESS: 输出文件：$_outputPath');
    _logAppend('正在重新格式化 EPUB...');
    // ReformatOperation.execute 返回日志字符串，逐行写入面板
    final log = await runEpubBackgroundOperation<String>(
      EpubBackgroundOperation.reformat,
      {'epubPath': _epubPath, 'outputPath': _outputPath},
    );
    _logAppendLines(log);
    _logAppend('重新格式化完成');
    _showSuccess('重新格式化成功');
  }

  /// 执行操作公共入口：封装加载状态、日志与错误处理
  Future<void> _doExecute() async {
    if (_epubPath.isEmpty) {
      _showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() {
      _loading = true;
      _resultText = '';
    });
    await _ensureOutputPath();
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「$_title」操作...');
    _logController.append('输入文件：$_epubPath');

    try {
      await _executeOperation();
      await _copyToPublicDownload();
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      _showError('操作失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 把生成的输出文件复制到公共 Download/books/ 目录（仅 Android）
  Future<void> _copyToPublicDownload() async {
    if (_outputPath.isEmpty) return;
    if (!Platform.isAndroid) return;
    if (!await File(_outputPath).exists()) return;

    const streamThreshold = 10 * 1024 * 1024;
    final fileSize = await File(_outputPath).length();
    final useStream = fileSize > streamThreshold;

    try {
      final filename = p.basename(_outputPath);
      String publicPath;

      if (useStream) {
        _logController.append(
          'PROGRESS: 大文件（${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB），使用流式复制...',
        );
        publicPath = await FileService.copyFileToPublicDownload(
          sourcePath: _outputPath,
          filename: filename,
        );
      } else {
        final bytes = await File(_outputPath).readAsBytes();
        publicPath = await FileService.writeToPublicDownload(
          filename: filename,
          bytes: bytes,
        );
      }

      _logController.append('PROGRESS: 已复制到公共 Download: $publicPath');

      try {
        final tempFile = File(_outputPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        _logController.append('WARN: 清理临时文件失败：$e');
      }

      _outputPath = publicPath;
    } catch (e) {
      _logController.append('WARN: 复制到公共 Download 失败：$e');
    }
  }

  // ==================== 参数 UI ====================

  /// 操作特定参数：输出路径选择
  List<Widget> _buildParams() => [
    buildSectionLabel(context, Icons.output_outlined, '输出文件'),
    const SizedBox(height: 8),
    buildFilePickerRow(
      context,
      icon: Icons.file_present_outlined,
      label: '输出 EPUB',
      value: _outputPath,
      hint: '点击选择输出位置（默认自动填充）',
      onTap: _loading
          ? () {}
          : () => _pickOutput(_defaultOutputFilename(_epubPath)),
      isComplete: _outputPath.isNotEmpty,
    ),
  ];

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: _icon,
            iconColor: _iconColor,
            title: _title,
            subtitle: _subtitle,
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                // EPUB 文件选择
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

                // 操作特定参数
                if (_buildParams().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ..._buildParams(),
                ],

                // 文本结果
                if (_returnsText && _resultText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  buildSectionLabel(context, Icons.text_snippet, _resultTitle),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _resultText,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],

                // 日志
                const SizedBox(height: 8),
                buildLogPanel(context, OutputLog(controller: _logController)),
              ],
            ),
          ),

          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _doExecute,
            label: '重新格式化',
            icon: Icons.auto_fix_high,
          ),
        ],
      ),
    );
  }
}
