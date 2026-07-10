import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 合并 EPUB 页面
///
/// 将多个 EPUB 合并为一个，处理 manifest 冲突、spine 合并、
/// TOC 重新生成和内部引用更新。合并输出为 EPUB3 格式（含 nav）。
class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  String _outputPath = '';
  bool _loading = false;
  final OutputLogController _logController = OutputLogController();

  /// 待合并的 EPUB 文件路径列表
  List<String> _mergeInputPaths = [];
  String _bookTitle = '';
  String _author = '';
  String _language = 'zh';
  String _publisher = '';
  String _description = '';
  String _coverPath = '';

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 自动填充输出路径
  Future<void> _autoFillOutputPath() async {
    _outputPath = await FileService.getDefaultOutputPathInDirectory(
      directoryPath: _mergeInputPaths.isNotEmpty
          ? p.dirname(_mergeInputPaths.first)
          : '',
      filename: 'merged.epub',
    );
  }

  /// 手动选择输出路径
  Future<void> _pickOutput() async {
    final path = await FileService.saveFile(
      defaultFileName: 'merged.epub',
      initialDirectory: _mergeInputPaths.isNotEmpty
          ? p.dirname(_mergeInputPaths.first)
          : null,
    );
    if (path == null) return;
    setState(() => _outputPath = path);
  }

  Future<void> _pickCover() async {
    final path = await FileService.pickImage();
    if (path == null) return;
    setState(() => _coverPath = path);
  }

  void _clearCover() {
    setState(() => _coverPath = '');
  }

  /// 选择多个 EPUB 文件用于合并
  Future<void> _pickMergeFiles() async {
    final paths = await FileService.pickMultipleEpubs();
    if (paths == null) return;
    _mergeInputPaths = paths;
    _outputPath = '';
    await _autoFillOutputPath();
    if (mounted) setState(() {});
  }

  /// 清空已选文件列表
  void _clearMergeFiles() {
    setState(() {
      _mergeInputPaths = [];
      _outputPath = '';
    });
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

  /// 执行合并 EPUB 操作
  Future<void> _execute() async {
    if (_mergeInputPaths.length < 2) {
      context.read<ToastProvider>().showWarning('合并至少需要选择 2 个 EPUB 文件');
      return;
    }
    if (_outputPath.isEmpty) {
      await _autoFillOutputPath();
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「合并 EPUB」操作...');
    _logController.append('输入文件：${_mergeInputPaths.length} 个');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.merge,
        {
          'inputPaths': _mergeInputPaths,
          'outputPath': _outputPath,
          'title': _bookTitle,
          'author': _author,
          'language': _language,
          'publisher': _publisher,
          'description': _description,
          'coverPath': _coverPath,
        },
      );
      _logAppendLines(result);
      await _copyToPublicDownload();
      if (mounted) context.read<ToastProvider>().showSuccess('合并完成');
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      if (mounted) context.read<ToastProvider>().showError('操作失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.call_merge_outlined,
            iconColor: const Color(0xFF16A34A),
            title: '合并 EPUB',
            subtitle: '将多个 EPUB 合并为一个',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                buildSectionLabel(context, Icons.folder_open, 'EPUB 文件'),
                const SizedBox(height: 8),
                // 文件选择与清空按钮
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _pickMergeFiles,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('选择文件'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_mergeInputPaths.isNotEmpty)
                      TextButton.icon(
                        onPressed: _loading ? null : _clearMergeFiles,
                        icon: Icon(Icons.clear_all, size: 18, color: cs.error),
                        label: Text('清空', style: TextStyle(color: cs.error)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 文件列表
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline),
                  ),
                  child: _mergeInputPaths.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              '请选择至少 2 个 EPUB 文件',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _mergeInputPaths.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: cs.primary.withValues(
                                  alpha: 0.12,
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                truncatePath(
                                  _mergeInputPaths[index],
                                  maxLen: 45,
                                ),
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                p.basenameWithoutExtension(
                                  _mergeInputPaths[index],
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.outline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
                if (_mergeInputPaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '已选择 ${_mergeInputPaths.length} 个文件',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.edit_note, '书籍信息'),
                const SizedBox(height: 8),
                buildCompactField(
                  context,
                  label: '书名',
                  value: _bookTitle,
                  hint: '留空则使用第一本书的书名',
                  icon: Icons.title,
                  onChanged: (v) => _bookTitle = v,
                ),
                const SizedBox(height: 10),
                buildCompactField(
                  context,
                  label: '作者',
                  value: _author,
                  hint: '留空则使用第一本书的作者',
                  icon: Icons.person_outline,
                  onChanged: (v) => _author = v,
                ),
                const SizedBox(height: 10),
                buildCompactField(
                  context,
                  label: '语言',
                  value: _language,
                  hint: '如 zh、en、ja',
                  icon: Icons.language,
                  onChanged: (v) => _language = v,
                ),
                const SizedBox(height: 10),
                buildCompactField(
                  context,
                  label: '出版社',
                  value: _publisher,
                  hint: '可选',
                  icon: Icons.business_outlined,
                  onChanged: (v) => _publisher = v,
                ),
                const SizedBox(height: 10),
                buildCompactField(
                  context,
                  label: '简介',
                  value: _description,
                  hint: '可选',
                  icon: Icons.notes_outlined,
                  maxLines: 3,
                  onChanged: (v) => _description = v,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: buildFilePickerRow(
                        context,
                        icon: Icons.image_outlined,
                        label: '封面图片',
                        value: _coverPath,
                        hint: '可选，留空则沿用原书封面信息',
                        onTap: _loading ? () {} : _pickCover,
                        isComplete: _coverPath.isNotEmpty,
                      ),
                    ),
                    if (_coverPath.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '清除封面',
                        onPressed: _loading ? null : _clearCover,
                        icon: Icon(Icons.close, color: cs.error),
                      ),
                    ],
                  ],
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
