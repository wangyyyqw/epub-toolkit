import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 阅微转多看页面
///
/// 将阅微格式的弹窗脚注 span 转为多看标准脚注格式，
/// 自动注入 note.png 图标和 epub 命名空间。
class YueweiPage extends StatefulWidget {
  const YueweiPage({super.key});

  @override
  State<YueweiPage> createState() => _YueweiPageState();
}

class _YueweiPageState extends State<YueweiPage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// note.png 图标字节（从 assets 加载，用于注入脚注）
  Uint8List? _notePngBytes;

  /// 日志控制器
  final OutputLogController _logController = OutputLogController();

  @override
  void initState() {
    super.initState();
    _loadNotePng();
  }

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 从 assets 加载 note.png 图标字节
  Future<void> _loadNotePng() async {
    try {
      final data = await rootBundle.load('assets/note.png');
      _notePngBytes = data.buffer.asUint8List();
    } catch (_) {}
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

  /// 执行阅微转多看操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「阅微转多看」操作...');
    _logController.append('输入文件：$_epubPath');
    _logController.append('输出文件：$_outputPath');
    _logController.append('正在转换阅微脚注为多看格式...');

    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.yuewei,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'notePngBytes': _notePngBytes,
        },
      );
      _logAppendLines(result);
      if (mounted) {
        if (result.contains('错误')) {
          context.read<ToastProvider>().showError('阅微转多看失败');
        } else {
          context.read<ToastProvider>().showSuccess(
            '阅微转多看完成，已保存到 $_outputPath',
          );
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
      title: '阅微转多看说明',
      sections: const [
        ToolHelpSection(
          title: '识别的阅微弹窗脚注',
          content:
              '<span class="reader js_readerFooterNote" data-wr-footernote="脚注内容"></span>',
          isCode: true,
        ),
        ToolHelpSection(
          title: '转换后的正文引用',
          content: r'''<sup>
  <a class="duokan-footnote" epub:type="noteref" href="#note1" id="note_ref1">
    <img alt="note" class="zhangyue-footnote" src="../Images/note.png" zy-footnote="脚注内容"/>
  </a>
</sup>''',
          isCode: true,
        ),
        ToolHelpSection(
          title: '追加到正文末尾的多看脚注',
          content: r'''<aside epub:type="footnote" id="note1">
  <ol class="duokan-footnote-content" style="list-style:none">
    <li class="duokan-footnote-item" id="note1">
      <p><a href="#note_ref1">脚注内容</a></p>
    </li>
  </ol>
</aside>''',
          isCode: true,
        ),
        ToolHelpSection(
          title: '补充处理',
          content:
              '转换时会自动注入 note.png 图标和 epub 命名空间。若正文里已有 duokan-footnote 引用但缺少 aside，也会尝试收集 zy-footnote 或 alt 内容并补齐脚注区域。',
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
            icon: Icons.sync_alt_outlined,
            iconColor: const Color(0xFF0D9488),
            title: '阅微转多看',
            subtitle: '将阅微格式脚注转为多看标准格式',
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

                // 提示信息
                const SizedBox(height: 16),
                buildHelpInfoBar(
                  context,
                  text: '将阅微格式的弹窗脚注 span 转为多看标准脚注格式。点击查看结构说明。',
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
            label: '执行阅微转多看',
            icon: Icons.sync_alt_outlined,
          ),
        ],
      ),
    );
  }
}
