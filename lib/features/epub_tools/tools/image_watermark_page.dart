import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_background_operation.dart';
import '../epub_tool_widgets.dart';

enum _WatermarkMode { embed, inspect }

class ImageWatermarkPage extends StatefulWidget {
  const ImageWatermarkPage({super.key});

  @override
  State<ImageWatermarkPage> createState() => _ImageWatermarkPageState();
}

class _ImageWatermarkPageState extends State<ImageWatermarkPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _loading = false;
  _WatermarkMode _mode = _WatermarkMode.embed;

  final _watermarkController = TextEditingController();
  final _logController = OutputLogController();

  @override
  void dispose() {
    _watermarkController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _outputPath = '';
    await _autoFillOutputPath();
    if (mounted) setState(() {});
  }

  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final base = p.basenameWithoutExtension(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: '${base}_watermarked.epub',
    );
  }

  Future<void> _pickOutput() async {
    final base = _epubPath.isNotEmpty
        ? p.basenameWithoutExtension(_epubPath)
        : 'output';
    final path = await FileService.saveFile(
      defaultFileName: '${base}_watermarked.epub',
      initialDirectory: _epubPath.isNotEmpty ? p.dirname(_epubPath) : null,
    );
    if (path == null) return;
    setState(() => _outputPath = path);
  }

  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

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

  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_mode == _WatermarkMode.embed &&
        _watermarkController.text.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请输入水印文本');
      return;
    }
    if (_mode == _WatermarkMode.embed && _outputPath.isEmpty) {
      await _autoFillOutputPath();
    }

    setState(() => _loading = true);
    _logController.clear();
    final modeLabel = _mode == _WatermarkMode.embed ? '写入水印' : '查看水印';
    _logController.append('PROGRESS: 开始执行「$modeLabel」操作...');
    _logController.append('输入文件：$_epubPath');

    try {
      final result = await runEpubBackgroundOperation<String>(
        _mode == _WatermarkMode.embed
            ? EpubBackgroundOperation.embedImageWatermark
            : EpubBackgroundOperation.inspectImageWatermark,
        {
          'epubPath': _epubPath,
          if (_mode == _WatermarkMode.embed) ...{
            'outputPath': _outputPath,
            'watermarkText': _watermarkController.text,
          },
        },
      );
      _logAppendLines(result);
      if (_mode == _WatermarkMode.embed) {
        await _copyToPublicDownload();
      }
      if (mounted) context.read<ToastProvider>().showSuccess('操作完成');
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      if (mounted) context.read<ToastProvider>().showError('操作失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmbed = _mode == _WatermarkMode.embed;
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.fingerprint_outlined,
            iconColor: const Color(0xFF0F766E),
            title: '图片水印',
            subtitle: '将文本写入 EPUB 图片低位，并读取已写入信息',
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
                buildSectionLabel(context, Icons.tune, '操作模式'),
                const SizedBox(height: 8),
                SegmentedButton<_WatermarkMode>(
                  segments: const [
                    ButtonSegment(
                      value: _WatermarkMode.embed,
                      icon: Icon(Icons.edit_outlined),
                      label: Text('写入水印'),
                    ),
                    ButtonSegment(
                      value: _WatermarkMode.inspect,
                      icon: Icon(Icons.search_outlined),
                      label: Text('查看水印'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _loading
                      ? null
                      : (value) => setState(() => _mode = value.first),
                ),
                const SizedBox(height: 12),
                buildInfoBar(
                  context,
                  isEmbed
                      ? '为保证读取稳定，写入后图片会保存为 PNG，并自动更新 EPUB 内部引用。'
                      : '逐张扫描 EPUB 图片，读取由本工具写入的水印文本。',
                ),
                if (isEmbed) ...[
                  const SizedBox(height: 16),
                  buildSectionLabel(context, Icons.notes_outlined, '水印文本'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _watermarkController,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      hintText: '输入需要写入所有可处理图片的文本',
                      border: OutlineInputBorder(),
                    ),
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
          ),
        ],
      ),
    );
  }
}
