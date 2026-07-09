import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 字体子集化页面
///
/// 分析 EPUB 中的 CSS @font-face 规则和字体引用关系，
/// 提取每个字体实际使用的字符，对 TTF/OTF 字体进行子集化以减小体积。
/// 未被任何选择器引用的字体会从 OPF manifest 中移除。
class FontSubsetPage extends StatefulWidget {
  const FontSubsetPage({super.key});

  @override
  State<FontSubsetPage> createState() => _FontSubsetPageState();
}

class _FontSubsetPageState extends State<FontSubsetPage> {
  String _epubPath = '';
  String _outputPath = '';
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
    _outputPath = '';
    await _autoFillOutputPath();
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

  /// 手动选择输出路径
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

  /// 将多行文本逐行追加到日志
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  /// 把生成的 EPUB 复制到公共 Download 目录（仅 Android）
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

  /// 执行字体子集化操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_outputPath.isEmpty) {
      await _autoFillOutputPath();
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「字体子集化」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.fontSubset,
        {'epubPath': _epubPath, 'outputPath': _outputPath},
      );
      _logAppendLines(result);
      await _copyToPublicDownload();
      if (mounted) context.read<ToastProvider>().showSuccess('子集化完成');
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
            iconColor: const Color(0xFF7C3AED),
            title: '字体子集化',
            subtitle: '子集化 EPUB 中的字体文件以减小体积',
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
                buildSectionLabel(context, Icons.info_outline, '说明'),
                const SizedBox(height: 8),
                buildInfoBar(context, '仅支持 TTF/OTF 格式字体子集化，WOFF/WOFF2 将跳过'),
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.output, '输出路径'),
                const SizedBox(height: 8),
                buildFilePickerRow(
                  context,
                  icon: Icons.save_outlined,
                  label: '输出文件',
                  value: _outputPath,
                  hint: '点击选择输出路径',
                  onTap: _loading ? () {} : _pickOutput,
                  isComplete: _outputPath.isNotEmpty,
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
