import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 版本转换页面
///
/// 独立 StatefulWidget，实现 EPUB 2.0 与 3.0 之间的相互转换，
/// 输出转换后的 EPUB 文件。
class ConvertVersionPage extends StatefulWidget {
  const ConvertVersionPage({super.key});

  @override
  State<ConvertVersionPage> createState() => _ConvertVersionPageState();
}

class _ConvertVersionPageState extends State<ConvertVersionPage> {
  // ==================== 页面配置 ====================

  static const _title = '版本转换';
  static const _subtitle = 'EPUB 2.0 与 3.0 互转';
  static const _icon = Icons.swap_vert_outlined;
  static const _iconColor = Color(0xFF10B981);

  bool get _returnsText => false;
  String get _resultTitle => '提取的文本';

  /// 可选目标版本列表
  static const _versionOptions = ['3.0', '2.0'];

  // ==================== 状态 ====================

  String _epubPath = '';
  String _outputPath = '';

  /// 目标版本，默认 3.0
  String _targetVersion = '3.0';
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

  /// 默认输出文件名：${base}_v${targetVersion}.epub
  String _defaultOutputFilename(String inputPath) {
    final base = p
        .basenameWithoutExtension(inputPath)
        .replaceFirst(RegExp(r'_v[23](?:\.0)?$'), '');
    return '${base}_v$_targetVersion.epub';
  }

  Future<void> _setTargetVersion(String version) async {
    setState(() => _targetVersion = version);
    if (!_userPickedOutput && _epubPath.isNotEmpty) {
      await _autoFillOutputPath();
      if (mounted) setState(() {});
    }
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

  /// 具体操作逻辑（版本转换并输出 EPUB）
  Future<void> _executeOperation() async {
    _logAppend('PROGRESS: 目标版本：$_targetVersion');
    _logAppend('PROGRESS: 输出文件：$_outputPath');
    _logAppend('正在进行版本转换...');
    await runEpubBackgroundOperation<void>(
      EpubBackgroundOperation.convertVersion,
      {
        'epubPath': _epubPath,
        'outputPath': _outputPath,
        'targetVersion': _targetVersion,
      },
    );
    _logAppend('版本转换完成');
    _showSuccess('已转换为 EPUB $_targetVersion');
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

  /// 操作特定参数：目标版本下拉 + 输出路径选择
  List<Widget> _buildParams() => [
    // 目标版本
    buildSectionLabel(context, Icons.swap_vert, '目标版本'),
    const SizedBox(height: 8),
    buildCompactSelect(
      context,
      label: '转换为',
      value: _targetVersion,
      items: _versionOptions,
      onChanged: (v) {
        // 执行中禁用切换，避免状态错乱
        if (_loading) return;
        if (v != null) {
          _setTargetVersion(v);
        }
      },
    ),
    const SizedBox(height: 16),

    // 输出路径
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

          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _doExecute,
            label: '转换版本',
            icon: Icons.swap_vert,
          ),
        ],
      ),
    );
  }
}
