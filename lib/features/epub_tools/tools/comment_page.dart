import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 批注提取页面
///
/// 用正则从正文中提取批注转为悬浮脚注。
/// 正则中第一个捕获组将被作为批注内容提取。
class CommentPage extends StatefulWidget {
  const CommentPage({super.key});

  @override
  State<CommentPage> createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 批注提取正则表达式，默认匹配 [内容] 格式批注
  String _regexPattern = r'\[(.*?)\]';

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

  /// 执行批注提取操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_regexPattern.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请输入正则表达式');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「批注提取」操作...');
    _logController.append('输入文件：$_epubPath');
    _logController.append('正则表达式：$_regexPattern');
    _logController.append('输出文件：$_outputPath');
    _logController.append('正在提取批注...');

    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.comment,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'regexPattern': _regexPattern,
        },
      );
      _logAppendLines(result);
      if (mounted) {
        if (result.contains('错误')) {
          context.read<ToastProvider>().showError('批注提取失败');
        } else {
          context.read<ToastProvider>().showSuccess('批注提取完成，已保存到 $_outputPath');
        }
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
      title: '批注提取说明',
      sections: const [
        ToolHelpSection(
          title: '默认提取规则',
          content:
              r'默认正则是 \[(.*?)\]，会匹配正文里的 [批注内容]。第一个捕获组会作为弹窗内容；如果没有捕获组，则使用整段匹配内容。',
        ),
        ToolHelpSection(
          title: '输入示例',
          content: '<p>这是正文[这里是一条批注]后续正文。</p>',
          isCode: true,
        ),
        ToolHelpSection(
          title: '转换后的弹窗注释',
          content:
              '<p>这是正文<span class="reader js_readerFooterNote" data-wr-footernote="这里是一条批注"></span>后续正文。</p>',
          isCode: true,
        ),
        ToolHelpSection(
          title: '注入的弹窗 CSS',
          content: r'''span.reader {
    position: relative;
    display: inline-block;
    width: 19px;
    height: 19px;
    vertical-align: sub;
    cursor: pointer;
    margin: 0 3px;
    background-image: url("../Images/note.png");
    background-size: 100%;
    background-repeat: no-repeat;
}

span.reader:hover:after {
    content: attr(data-wr-footernote);
    position: fixed;
    left: 0;
    bottom: 0;
    margin: 1em;
    background: black;
    border-radius: 0.25em;
    color: white;
    padding: 0.5em;
    font-size: 1em;
    font-family: "南构明史稿鉴", sans-serif;
    z-index: 10;
    text-indent: 0em;
}''',
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
            icon: Icons.comment_bank_outlined,
            iconColor: const Color(0xFFF97316),
            title: '批注提取',
            subtitle: '用正则从正文中提取批注转为悬浮脚注',
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

                // 正则参数
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '提取规则'),
                const SizedBox(height: 8),
                buildCompactField(
                  context,
                  label: '正则表达式',
                  value: _regexPattern,
                  hint: r'默认 \[(.*?)\] 匹配 [内容] 格式批注',
                  icon: Icons.code,
                  onChanged: (v) => setState(() => _regexPattern = v),
                ),
                const SizedBox(height: 8),
                buildHelpInfoBar(
                  context,
                  text: '正则中第一个捕获组会作为批注内容，程序会自动将 (.*) 优化为 (.*?)。点击查看结构说明。',
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
            label: '执行批注提取',
            icon: Icons.comment_bank_outlined,
          ),
        ],
      ),
    );
  }
}
