import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 广告清理页面
///
/// 按正则规则批量清理 EPUB 中的广告内容。
/// 用户输入清理规则（格式：正则1|||替换1|||正则2|||替换2），
/// 执行后生成清理后的 EPUB 文件。
class AdCleanPage extends StatefulWidget {
  const AdCleanPage({super.key});

  @override
  State<AdCleanPage> createState() => _AdCleanPageState();
}

class _AdCleanPageState extends State<AdCleanPage> {
  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 清理规则（格式：正则1|||替换1|||正则2|||替换2）
  String _patterns = '';

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

  /// 执行广告清理操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_patterns.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请输入清理规则');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「广告清理」操作...');
    _logController.append('输入文件：$_epubPath');
    _logController.append('清理规则：$_patterns');
    _logController.append('输出文件：$_outputPath');
    _logController.append('正在清理广告内容...');

    try {
      await runEpubBackgroundOperation<void>(EpubBackgroundOperation.adClean, {
        'epubPath': _epubPath,
        'outputPath': _outputPath,
        'patterns': _patterns,
      });
      _logController.append('广告清理完成');
      if (mounted) {
        context.read<ToastProvider>().showSuccess('广告清理完成，已保存到 $_outputPath');
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
            icon: Icons.cleaning_services_outlined,
            iconColor: const Color(0xFFEF4444),
            title: '广告清理',
            subtitle: '按正则规则批量清理 EPUB 中的广告内容',
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

                // 清理规则参数
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.tune, '清理规则'),
                const SizedBox(height: 8),
                buildCompactField(
                  context,
                  label: '正则规则',
                  value: _patterns,
                  hint: '格式：正则1|||替换1|||正则2|||替换2',
                  icon: Icons.cleaning_services_outlined,
                  maxLines: 2,
                  onChanged: (v) => setState(() => _patterns = v),
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
            label: '执行广告清理',
            icon: Icons.cleaning_services_outlined,
          ),
        ],
      ),
    );
  }
}
