
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../../encrypt_decrypt_base/encrypt_decrypt_base.dart';
import '../epub_tool_widgets.dart';

/// 名称混淆解密页面
///
/// 用 manifest id 还原被混淆的文件名，使 EPUB 恢复可编辑状态。
class DecryptPage extends StatefulWidget {
  const DecryptPage({super.key});

  @override
  State<DecryptPage> createState() => _DecryptPageState();
}

class _DecryptPageState extends State<DecryptPage> {
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

  /// 执行名称混淆解密操作
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
    _logController.append('PROGRESS: 开始执行「名称混淆解密」操作...');
    _logController.append('输入文件：$_epubPath');
    try {
      final result = await runEpubBackgroundOperation<String>(
        EpubBackgroundOperation.decrypt,
        {'epubPath': _epubPath, 'outputPath': _outputPath},
      );
      if (result == EncryptDecryptBase.zhangyueDrm) {
        _logController.append('检测到掌阅 DRM，不支持解密');
        if (mounted) {
          context.read<ToastProvider>().showError('检测到掌阅 DRM，不支持解密');
        }
      } else if (result == EncryptDecryptBase.notEncrypted) {
        _logController.append('该 EPUB 未被加密，无需解密');
        if (mounted) {
          context.read<ToastProvider>().showWarning('该 EPUB 未被加密，无需解密');
        }
      } else {
        _logAppendLines(result);
        await _copyToPublicDownload();
        if (mounted) context.read<ToastProvider>().showSuccess('解密完成');
      }
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
            icon: Icons.no_encryption_outlined,
            title: '名称混淆解密',
            subtitle: '还原被混淆的 EPUB 文件名',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
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
                  ),
                  ],
                ),
                const SizedBox(height: 16),
                buildSectionLabel(context, Icons.info_outline, '说明'),
                const SizedBox(height: 8),
                buildInfoBar(context, '用 manifest id 还原被混淆的文件名'),
                const SizedBox(height: 16),
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
