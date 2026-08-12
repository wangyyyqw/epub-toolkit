
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_version.dart';
import '../../../core/background_task.dart';
import '../../../core/file_service.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../../t2s/chinese_convert_base.dart';
import '../../t2s/chinese_converter.dart';
import '../epub_tool_widgets.dart';

/// 繁体转简体页面
///
/// 将 EPUB 中的繁体中文转换为简体中文。
/// 执行后将转换结果按行输出到日志面板。
class T2sPage extends StatefulWidget {
  const T2sPage({super.key});

  @override
  State<T2sPage> createState() => _T2sPageState();
}

class _T2sPageState extends State<T2sPage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

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

  /// 执行繁体转简体操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「繁体转简体」操作...');
    _logController.append('APP VERSION: $appVersion');
    _logController.append('输入文件：$_epubPath');
    _logController.append('输出文件：$_outputPath');
    _logController.append('正在进行繁体转简体...');

    try {
      // 简繁转换是 CPU 密集操作,放到后台 isolate 避免大书卡死 UI。
      // 注意:传给 runBackgroundTask 的必须是顶层函数而非闭包——
      // 实例方法内定义的闭包会隐式捕获 this(State 及整棵 Widget 树),
      // Isolate 序列化时抛 "Illegal argument in isolate message: object is unsendable"。
      // 字典在 UI isolate 加载(依赖 rootBundle),通过消息传入后台 isolate
      // (后台 isolate 中静态字典字段为 null,不能读取 getter)。
      await ChineseConverter.initT2S();
      final result = await runBackgroundTask(runT2sTask, [
        _epubPath,
        _outputPath,
        ChineseConverter.t2sPhrases,
        ChineseConverter.t2sCharacters,
        ChineseConverter.t2sPhraseMaxLen,
        ChineseConverter.t2sCharMaxLen,
      ]);
      _logAppendLines(result);
      if (mounted) {
        context.read<ToastProvider>().showSuccess('繁转简完成，已保存到 $_outputPath');
      }
      await _copyToPublicDownload();
    } catch (e, st) {
      _logController.append('ERROR: 操作失败：$e');
      _logController.append('STACK: $st');
      if (mounted) {
        context.read<ToastProvider>().showError('操作失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

    /// 把生成的 EPUB 复制到公共 Download 目录（仅 Android，大文件流式复制）
  Future<void> _copyToPublicDownload() async {
    if (!mounted) return;
    _outputPath = await FileService.copyGeneratedFileToPublicDownload(
      sourcePath: _outputPath,
      log: (line) {
        if (mounted) _logController.append(line);
      },
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
            icon: Icons.translate_outlined,
            title: '繁体转简体',
            subtitle: '将 EPUB 中的繁体中文转换为简体中文',
          ),

          // 内容区
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                // EPUB 文件选择
                ResponsiveRow(
                  children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                    ],
                  ),
                  ],
                ),

                // 输出路径
                const SizedBox(height: 16),

                // 日志面板
                const SizedBox(height: 16),
                OutputLog(controller: _logController),
              ],
            ),
          ),

          // 底部操作栏
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
            label: '执行繁转简',
            icon: Icons.translate_outlined,
          ),
        ],
      ),
    );
  }
}
