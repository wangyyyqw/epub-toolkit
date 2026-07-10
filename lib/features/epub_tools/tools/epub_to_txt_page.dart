import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// EPUB 转 TXT 页面
///
/// 独立 StatefulWidget，将 EPUB 电子书转换为纯文本。
/// 既写入输出文件，又在页面中展示提取的文本内容。
class EpubToTxtPage extends StatefulWidget {
  const EpubToTxtPage({super.key});

  @override
  State<EpubToTxtPage> createState() => _EpubToTxtPageState();
}

class _EpubToTxtPageState extends State<EpubToTxtPage> {
  // ==================== 页面配置 ====================

  static const _title = 'EPUB 转 TXT';
  static const _subtitle = '将 EPUB 电子书转换为纯文本';
  static const _icon = Icons.article_outlined;
  static const _iconColor = Color(0xFFF59E0B);

  bool get _returnsText => true;
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

  /// 默认输出文件名：${base}.txt
  String _defaultOutputFilename(String inputPath) {
    final base = p.basenameWithoutExtension(inputPath);
    return '$base.txt';
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

  /// 具体操作逻辑（提取文本并写入文件，同时展示文本结果）
  Future<void> _executeOperation() async {
    _logAppend('PROGRESS: 输出文件：$_outputPath');
    _logAppend('正在提取文本...');
    // EpubToTxtOperation.execute 既写入 outputPath，又返回提取的文本
    final result = await runEpubBackgroundOperation<String>(
      EpubBackgroundOperation.epubToTxt,
      {'epubPath': _epubPath, 'outputPath': _outputPath},
    );
    _logAppend('文本提取完成');
    if (mounted) setState(() => _resultText = result);
    _showSuccess('TXT 提取成功');
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
      icon: Icons.description_outlined,
      label: '输出 TXT',
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
            label: '转换为 TXT',
            icon: Icons.article,
          ),
        ],
      ),
    );
  }
}
