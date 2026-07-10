import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 字体加密页面
///
/// 对 EPUB 中的 TTF 字体进行字形混淆加密，实现防复制保护。
/// 可指定目标字体族和 XHTML 文件，留空则处理全部。
class EncryptFontPage extends StatefulWidget {
  const EncryptFontPage({super.key});

  @override
  State<EncryptFontPage> createState() => _EncryptFontPageState();
}

class _EncryptFontPageState extends State<EncryptFontPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _loading = false;
  bool _scanning = false;
  final OutputLogController _logController = OutputLogController();

  List<String> _availableFontFamilies = const [];
  List<String> _availableXhtmlFiles = const [];
  final Set<String> _selectedFontFamilies = {};
  final Set<String> _selectedXhtmlFiles = {};

  bool get _busy => _loading || _scanning;

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
    setState(() {
      _availableFontFamilies = const [];
      _availableXhtmlFiles = const [];
      _selectedFontFamilies.clear();
      _selectedXhtmlFiles.clear();
      _scanning = true;
    });
    await _autoFillOutputPath();
    await _scanTargets(path);
  }

  /// 导入 EPUB 后自动扫描可加密字体和正文文件。
  Future<void> _scanTargets(String path) async {
    _logController.clear();
    _logController.append('PROGRESS: 正在扫描可加密字体...');
    try {
      final result = await runEpubBackgroundOperation<Map>(
        EpubBackgroundOperation.scanFontTargets,
        {'epubPath': path},
      );
      if (!mounted || _epubPath != path) return;
      final fontFamilies = (result['fontFamilies'] as List).cast<String>();
      final xhtmlFiles = (result['xhtmlFiles'] as List).cast<String>();
      setState(() {
        _availableFontFamilies = fontFamilies;
        _availableXhtmlFiles = xhtmlFiles;
        _selectedFontFamilies
          ..clear()
          ..addAll(fontFamilies);
        _selectedXhtmlFiles
          ..clear()
          ..addAll(xhtmlFiles);
      });
      _logController.append(
        '扫描完成：${fontFamilies.length} 个字体族，${xhtmlFiles.length} 个正文文件',
      );
      if (fontFamilies.isEmpty) {
        context.read<ToastProvider>().showWarning('未发现可加密的字体');
      }
    } catch (e) {
      if (!mounted || _epubPath != path) return;
      _logController.append('ERROR: 扫描失败：$e');
      context.read<ToastProvider>().showError('扫描字体失败：$e');
    } finally {
      if (mounted && _epubPath == path) setState(() => _scanning = false);
    }
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

  /// 执行字体加密操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_scanning) {
      context.read<ToastProvider>().showWarning('请等待字体扫描完成');
      return;
    }
    if (_availableFontFamilies.isEmpty) {
      context.read<ToastProvider>().showWarning('当前 EPUB 中未发现可加密字体');
      return;
    }
    if (_selectedFontFamilies.isEmpty || _selectedXhtmlFiles.isEmpty) {
      context.read<ToastProvider>().showWarning('请至少选择一个字体族和一个正文文件');
      return;
    }
    if (_outputPath.isEmpty) {
      await _autoFillOutputPath();
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「字体加密」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.encryptFont,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'targetFontFamilies': _selectedFontFamilies.toList(),
          'targetXhtmlFiles': _selectedXhtmlFiles.toList(),
        },
      );
      _logAppendLines(result);
      await _copyToPublicDownload();
      if (mounted) context.read<ToastProvider>().showSuccess('字体加密完成');
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
            icon: Icons.security_outlined,
            iconColor: const Color(0xFFBE123C),
            title: '字体加密',
            subtitle: '字形混淆加密实现防复制保护',
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
                  onTap: _busy ? () {} : _pickEpub,
                  isComplete: _epubPath.isNotEmpty,
                ),
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '加密参数'),
                const SizedBox(height: 8),
                buildInfoBar(
                  context,
                  '对 TTF 字体进行字形混淆加密，复制出来为韩文乱码，实现防复制保护。仅支持含 glyf 表的 TTF 字体。',
                ),
                const SizedBox(height: 12),
                _buildScanResults(),
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.output, '输出路径'),
                const SizedBox(height: 8),
                buildFilePickerRow(
                  context,
                  icon: Icons.save_outlined,
                  label: '输出文件',
                  value: _outputPath,
                  hint: '点击选择输出路径',
                  onTap: _busy ? () {} : _pickOutput,
                  isComplete: _outputPath.isNotEmpty,
                ),
                const SizedBox(height: 8),
                OutputLog(controller: _logController),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _busy,
            onPressed: _busy ? () {} : _execute,
          ),
        ],
      ),
    );
  }

  Widget _buildScanResults() {
    final theme = Theme.of(context);
    if (_epubPath.isEmpty) {
      return buildInfoBar(context, '导入 EPUB 后将自动扫描可加密的字体和正文文件。');
    }
    if (_scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_availableFontFamilies.isEmpty) {
      return buildInfoBar(context, '未找到引用 EPUB 内字体文件的 @font-face 定义。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '字体族（${_selectedFontFamilies.length}/${_availableFontFamilies.length}）',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(
                      () =>
                          _selectedFontFamilies.addAll(_availableFontFamilies),
                    ),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(_selectedFontFamilies.clear),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final family in _availableFontFamilies)
              FilterChip(
                label: Text(family),
                selected: _selectedFontFamilies.contains(family),
                onSelected: _loading
                    ? null
                    : (selected) => setState(() {
                        if (selected) {
                          _selectedFontFamilies.add(family);
                        } else {
                          _selectedFontFamilies.remove(family);
                        }
                      }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: const Icon(Icons.article_outlined, size: 20),
          title: Text(
            '正文文件（${_selectedXhtmlFiles.length}/${_availableXhtmlFiles.length}）',
            style: theme.textTheme.titleSmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(
                        () => _selectedXhtmlFiles.addAll(_availableXhtmlFiles),
                      ),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(_selectedXhtmlFiles.clear),
                child: const Text('清空'),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            SizedBox(
              height: 240,
              child: ListView.builder(
                itemCount: _availableXhtmlFiles.length,
                itemBuilder: (context, index) {
                  final file = _availableXhtmlFiles[index];
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      file,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    value: _selectedXhtmlFiles.contains(file),
                    onChanged: _loading
                        ? null
                        : (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedXhtmlFiles.add(file);
                            } else {
                              _selectedXhtmlFiles.remove(file);
                            }
                          }),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
