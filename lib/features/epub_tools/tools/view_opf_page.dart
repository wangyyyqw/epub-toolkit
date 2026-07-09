import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 查看 OPF 元数据页面
///
/// 独立 StatefulWidget，读取并格式化显示 EPUB 的 OPF 文件内容。
/// 仅展示文本结果，不产生输出文件。
class ViewOpfPage extends StatefulWidget {
  const ViewOpfPage({super.key});

  @override
  State<ViewOpfPage> createState() => _ViewOpfPageState();
}

class _ViewOpfPageState extends State<ViewOpfPage> {
  // ==================== 页面配置 ====================

  static const _title = '查看 OPF 元数据';
  static const _subtitle = '读取并格式化显示 EPUB 的 OPF 文件内容';
  static const _icon = Icons.code_outlined;
  static const _iconColor = Color(0xFF0EA5E9);

  /// 是否返回文本结果（需要显示结果区域）
  bool get _returnsText => true;

  /// 文本结果标题
  String get _resultTitle => 'OPF 元数据';

  /// 是否需要输出文件（影响输出路径管理与公共目录复制）
  bool get _usesOutputFile => false;

  // ==================== 状态 ====================

  String _epubPath = '';
  String _outputPath = '';
  final bool _userPickedOutput = false;
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

  /// 根据输入文件名自动生成输出路径（落入应用专属目录）
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final filename = _defaultOutputFilename(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: filename,
    );
  }

  /// 默认输出文件名
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

  /// 具体操作逻辑（读取 OPF 并展示文本结果）
  Future<void> _executeOperation() async {
    _logAppend('正在读取 OPF 元数据...');
    final result = await runEpubBackgroundOperation<String>(
      EpubBackgroundOperation.viewOpf,
      {'epubPath': _epubPath},
    );
    _logAppend('OPF 元数据读取完成');
    if (mounted) setState(() => _resultText = result);
    _showSuccess('OPF 元数据读取成功');
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
    if (_usesOutputFile) {
      await _ensureOutputPath();
    }
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「$_title」操作...');
    _logController.append('输入文件：$_epubPath');

    try {
      await _executeOperation();
      if (_usesOutputFile) {
        await _copyToPublicDownload();
      }
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

      // 复制成功后清理临时文件
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

  /// 操作特定参数（本页无额外参数）
  List<Widget> _buildParams() => [];

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // 精简页头
          buildToolHeader(
            context,
            icon: _icon,
            iconColor: _iconColor,
            title: _title,
            subtitle: _subtitle,
          ),

          // 内容区
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
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

          // 底部操作栏
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _doExecute,
            label: '读取 OPF',
            icon: Icons.search,
          ),
        ],
      ),
    );
  }
}
