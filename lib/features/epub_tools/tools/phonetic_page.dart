import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 拼音标注页面
///
/// 为 EPUB 中的中文文本添加拼音标注。
/// 支持声调模式选择（带音标 / 不带声调 / 数字声调）和全文注音开关。
class PhoneticPage extends StatefulWidget {
  const PhoneticPage({super.key});

  @override
  State<PhoneticPage> createState() => _PhoneticPageState();
}

class _PhoneticPageState extends State<PhoneticPage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 声调模式（mark=带音标, none=不带声调, number=数字声调）
  String _toneMode = 'mark';

  /// 是否全文注音（关闭则仅标注生僻字）
  bool _annotateAll = false;

  /// 日志控制器
  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 获取声调模式显示名称
  String _toneModeName(String mode) {
    switch (mode) {
      case 'mark':
        return '带音标';
      case 'number':
        return '数字声调';
      default:
        return '不带声调';
    }
  }

  /// 从显示名称获取声调模式值
  String _toneModeFromName(String name) {
    switch (name) {
      case '带音标':
        return 'mark';
      case '数字声调':
        return 'number';
      default:
        return 'none';
    }
  }

  /// 选择 EPUB 输入文件
  ///
  /// 选择成功后自动填充输出路径并刷新界面。
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _outputPath = '';
    await _autoFillOutputPath();
    if (mounted) setState(() {});
  }

  /// 自动填充输出路径
  ///
  /// 根据输入文件名生成默认输出文件名（${base}_output.epub）。
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final base = p.basenameWithoutExtension(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: '${base}_output.epub',
    );
  }

  /// 手动选择输出文件路径
  Future<void> _pickOutput() async {
    final base = _epubPath.isNotEmpty
        ? p.basenameWithoutExtension(_epubPath)
        : 'output';
    final path = await FileService.saveFile(
      defaultFileName: '${base}_output.epub',
      initialDirectory: _epubPath.isNotEmpty ? p.dirname(_epubPath) : null,
    );
    if (path == null) return;
    setState(() => _outputPath = path);
  }

  /// 将多行文本按行追加到日志面板
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  /// 执行拼音标注操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「拼音标注」操作...');
    _logController.append('输入文件：$_epubPath');
    _logController.append('声调模式: $_toneMode, 全文注音: $_annotateAll');
    _logController.append('输出文件：$_outputPath');
    _logController.append('正在进行拼音标注...');

    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.phonetic,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'toneMode': _toneMode,
          'annotateAll': _annotateAll,
        },
      );
      _logAppendLines(result);
      if (mounted) {
        context.read<ToastProvider>().showSuccess('拼音标注完成，已保存到 $_outputPath');
      }
      await _copyToPublicDownload();
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('操作失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 把生成的 EPUB 复制到公共 Download/books/ 目录
  ///
  /// 仅 Android 生效；大文件（>10MB）使用流式复制，否则直接写入字节。
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
        _logController.append('PROGRESS: 大文件，使用流式复制...');
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
        await File(_outputPath).delete();
      } catch (_) {}
      _outputPath = publicPath;
    } catch (e) {
      _logController.append('WARN: 复制到公共 Download 失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 精简页头
          buildToolHeader(
            context,
            icon: Icons.record_voice_over_outlined,
            iconColor: const Color(0xFF14B8A6),
            title: '拼音标注',
            subtitle: '为 EPUB 中的中文文本添加拼音标注',
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

                // 标注参数
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '标注参数'),
                const SizedBox(height: 8),
                buildCompactSelect(
                  context,
                  label: '声调模式',
                  value: _toneModeName(_toneMode),
                  items: const ['带音标', '不带声调', '数字声调'],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _toneMode = _toneModeFromName(v);
                    });
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('全文注音'),
                  subtitle: const Text('关闭则仅标注生僻字'),
                  value: _annotateAll,
                  onChanged: (v) => setState(() => _annotateAll = v),
                ),

                // 输出路径
                const SizedBox(height: 8),
                buildSectionLabel(context, Icons.save_outlined, '输出路径'),
                const SizedBox(height: 8),
                buildFilePickerRow(
                  context,
                  icon: Icons.save_outlined,
                  label: '输出 EPUB',
                  value: _outputPath,
                  hint: '点击选择输出文件位置',
                  onTap: _loading ? () {} : _pickOutput,
                  isComplete: _outputPath.isNotEmpty,
                ),

                // 日志面板
                const SizedBox(height: 16),
                buildLogPanel(context, OutputLog(controller: _logController)),
              ],
            ),
          ),

          // 底部操作栏
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
            label: '执行拼音标注',
            icon: Icons.record_voice_over_outlined,
          ),
        ],
      ),
    );
  }
}
