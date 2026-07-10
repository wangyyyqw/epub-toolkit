import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 图片压缩页面
///
/// 对 EPUB 中的图片进行质量压缩，支持 JPEG 质量调整和 PNG 转 JPG。
class ImgCompressPage extends StatefulWidget {
  const ImgCompressPage({super.key});

  @override
  State<ImgCompressPage> createState() => _ImgCompressPageState();
}

class _ImgCompressPageState extends State<ImgCompressPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _loading = false;
  final OutputLogController _logController = OutputLogController();

  /// JPEG 压缩质量（10-100）
  double _jpegQuality = 85;

  /// 是否将无透明 PNG 转为 JPG
  bool _pngToJpg = true;

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

  /// 执行图片压缩操作
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
    _logController.append('PROGRESS: 开始执行「图片压缩」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.imgCompress,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'jpegQuality': _jpegQuality.round(),
          'pngToJpg': _pngToJpg,
        },
      );
      _logAppendLines(result);
      await _copyToPublicDownload();
      if (mounted) context.read<ToastProvider>().showSuccess('压缩完成');
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
            icon: Icons.compress_outlined,
            iconColor: const Color(0xFF059669),
            title: '图片压缩',
            subtitle: '压缩 EPUB 中的图片以减小体积',
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
                buildSectionLabel(context, Icons.tune, '压缩参数'),
                const SizedBox(height: 8),
                buildInfoBar(
                  context,
                  'JPEG 质量越低体积越小，但画质损失越大。PNG 有透明通道时保留为 PNG-8。',
                ),
                const SizedBox(height: 12),
                // JPEG 质量滑块
                Row(
                  children: [
                    Icon(
                      Icons.high_quality_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'JPEG 质量',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_jpegQuality.round()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _jpegQuality,
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '${_jpegQuality.round()}',
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _jpegQuality = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  title: Text(
                    'PNG 转 JPG（无透明通道时）',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  subtitle: Text(
                    '将不透明 PNG 转为 JPG 以获得更小体积',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  value: _pngToJpg,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _pngToJpg = v),
                ),
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
