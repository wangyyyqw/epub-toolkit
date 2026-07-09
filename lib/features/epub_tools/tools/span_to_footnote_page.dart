import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 弹窗转脚注页面
///
/// 将阅微弹窗注释转换为 EPUB3 末尾脚注。
/// 可自定义脚注文字颜色和脚注引用颜色。
class SpanToFootnotePage extends StatefulWidget {
  const SpanToFootnotePage({super.key});

  @override
  State<SpanToFootnotePage> createState() => _SpanToFootnotePageState();
}

class _SpanToFootnotePageState extends State<SpanToFootnotePage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 脚注文字颜色，默认 #004e1c
  String _footnoteColor = '#004e1c';

  /// 脚注引用颜色，默认 #b00020
  String _noterefColor = '#b00020';

  /// 日志控制器
  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
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

  /// 执行弹窗转脚注操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「弹窗转脚注」操作...');
    _logController.append('输入文件：$_epubPath');
    _logController.append(
      '脚注文字颜色：${_footnoteColor.isEmpty ? '默认' : _footnoteColor}',
    );
    _logController.append(
      '引用颜色：${_noterefColor.isEmpty ? '默认' : _noterefColor}',
    );
    _logController.append('输出文件：$_outputPath');

    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.spanToFootnote,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'footnoteColor': _footnoteColor,
          'noterefColor': _noterefColor,
        },
      );
      _logAppendLines(result);
      if (mounted) {
        context.read<ToastProvider>().showSuccess('弹窗转脚注完成，已保存到 $_outputPath');
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

  void _showStructureHelp() {
    showToolHelpDialog(
      context,
      title: '弹窗转脚注说明',
      sections: const [
        ToolHelpSection(
          title: '识别的弹窗注释',
          content:
              '<span class="reader js_readerFooterNote" data-wr-footernote="批注内容"></span>',
          isCode: true,
        ),
        ToolHelpSection(
          title: '识别条件',
          content:
              'span 的 class 中包含 reader 或 js_readerFooterNote，且带有 data-wr-footernote 属性时会被识别。class 顺序不限。',
        ),
        ToolHelpSection(
          title: '转换后的正文引用',
          content:
              '<sup><a class="fn-ref" epub:type="noteref" href="#fn1">[1]</a></sup>',
          isCode: true,
        ),
        ToolHelpSection(
          title: '追加到正文末尾的脚注',
          content: r'''<aside id="fn1" class="aside-fn" epub:type="footnote">
    <p>批注内容</p>
</aside>''',
          isCode: true,
        ),
        ToolHelpSection(
          title: '注入的脚注 CSS',
          content: r'''<style>
.aside-fn { font-size: 0.85em; margin-top: 1.5em; padding: 0.5em 0; text-indent: 0; line-height: 1.4; color: #004e1c; }
a.fn-ref { text-decoration: none; font-size: 0.75em; vertical-align: super; color: #b00020; }
</style>''',
          isCode: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 精简页头
          buildToolHeader(
            context,
            icon: Icons.format_quote_outlined,
            iconColor: const Color(0xFF6D28D9),
            title: '弹窗转脚注',
            subtitle: '将阅微弹窗注释转换为 EPUB3 末尾脚注',
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

                // 颜色参数
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '颜色设置'),
                const SizedBox(height: 8),
                buildCompactField(
                  context,
                  label: '脚注文字颜色',
                  value: _footnoteColor,
                  hint: '默认 #004e1c',
                  icon: Icons.format_color_text,
                  onChanged: (v) => setState(() => _footnoteColor = v),
                ),
                const SizedBox(height: 12),
                buildCompactField(
                  context,
                  label: '脚注引用颜色',
                  value: _noterefColor,
                  hint: '默认 #b00020',
                  icon: Icons.format_color_fill,
                  onChanged: (v) => setState(() => _noterefColor = v),
                ),
                const SizedBox(height: 8),
                buildHelpInfoBar(
                  context,
                  text:
                      '会把 reader/js_readerFooterNote 弹窗 span 转换为 EPUB3 脚注。点击查看结构说明。',
                  onTap: _showStructureHelp,
                ),

                // 输出路径
                const SizedBox(height: 16),
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
            label: '执行弹窗转脚注',
            icon: Icons.format_quote_outlined,
          ),
        ],
      ),
    );
  }
}
