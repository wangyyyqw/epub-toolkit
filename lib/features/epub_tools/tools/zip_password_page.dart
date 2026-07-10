import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/base_input.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_background_operation.dart';
import '../epub_tool_widgets.dart';

enum _ZipPasswordMode { add, remove }

class ZipPasswordPage extends StatefulWidget {
  const ZipPasswordPage({super.key});

  @override
  State<ZipPasswordPage> createState() => _ZipPasswordPageState();
}

class _ZipPasswordPageState extends State<ZipPasswordPage> {
  _ZipPasswordMode _mode = _ZipPasswordMode.add;
  String _epubPath = '';
  String _outputPath = '';
  String _password = '';
  String _confirmation = '';
  bool _showPassword = false;
  bool _loading = false;
  final OutputLogController _logController = OutputLogController();

  bool get _isAdding => _mode == _ZipPasswordMode.add;
  String get _suffix => _isAdding ? 'password' : 'unlocked';

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    await _autoFillOutputPath();
    if (mounted) setState(() {});
  }

  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final base = p.basenameWithoutExtension(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: '${base}_$_suffix.epub',
    );
  }

  Future<void> _pickOutput() async {
    final base = _epubPath.isEmpty
        ? 'output'
        : p.basenameWithoutExtension(_epubPath);
    final path = await FileService.saveFile(
      defaultFileName: '${base}_$_suffix.epub',
      initialDirectory: _epubPath.isEmpty ? null : p.dirname(_epubPath),
    );
    if (path != null && mounted) setState(() => _outputPath = path);
  }

  Future<void> _changeMode(_ZipPasswordMode mode) async {
    if (_mode == mode || _loading) return;
    setState(() {
      _mode = mode;
      _confirmation = '';
      _outputPath = '';
    });
    await _autoFillOutputPath();
    if (mounted) setState(() {});
  }

  Future<void> _copyToPublicDownload() async {
    if (!Platform.isAndroid || _outputPath.isEmpty) return;
    final output = File(_outputPath);
    if (!await output.exists()) return;
    try {
      final publicPath = await FileService.copyFileToPublicDownload(
        sourcePath: _outputPath,
        filename: p.basename(_outputPath),
      );
      await output.delete();
      _outputPath = publicPath;
      _logController.append('PROGRESS: 已复制到公共 Download: $publicPath');
    } catch (error) {
      _logController.append('WARN: 复制到公共 Download 失败：$error');
    }
  }

  Future<void> _execute() async {
    final toast = context.read<ToastProvider>();
    if (_epubPath.isEmpty) {
      toast.showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_password.isEmpty) {
      toast.showWarning('请输入密码');
      return;
    }
    if (_isAdding && _password != _confirmation) {
      toast.showWarning('两次输入的密码不一致');
      return;
    }
    if (_outputPath.isEmpty) await _autoFillOutputPath();

    setState(() => _loading = true);
    _logController.clear();
    _logController.append(
      'PROGRESS: 开始${_isAdding ? '添加' : '解除'} EPUB ZIP 密码...',
    );
    try {
      final result = await runEpubBackgroundOperation<String>(
        _isAdding
            ? EpubBackgroundOperation.addZipPassword
            : EpubBackgroundOperation.removeZipPassword,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'password': _password,
        },
      );
      for (final line in result.split('\n')) {
        if (line.trim().isNotEmpty) _logController.append(line.trim());
      }
      await _copyToPublicDownload();
      if (mounted) toast.showSuccess(_isAdding ? '密码添加完成' : '密码解除完成');
    } catch (error) {
      _logController.append('ERROR: 操作失败：$error');
      if (mounted) toast.showError('操作失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _passwordField({required bool confirmation}) {
    return BaseInput(
      label: confirmation ? '确认密码' : '密码',
      hint: _isAdding ? '8–64 位可打印 ASCII 字符' : '输入原 ZIP 密码',
      value: confirmation ? _confirmation : _password,
      enabled: !_loading,
      obscureText: !_showPassword,
      prefixIcon: Icons.key_outlined,
      onChanged: (value) => setState(() {
        if (confirmation) {
          _confirmation = value;
        } else {
          _password = value;
        }
      }),
      suffix: confirmation
          ? null
          : IconButton(
              tooltip: _showPassword ? '隐藏密码' : '显示密码',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.password_outlined,
            iconColor: const Color(0xFF9F1239),
            title: 'EPUB ZIP 密码',
            subtitle: '解包 EPUB 内容，再使用密码重新打包',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                SegmentedButton<_ZipPasswordMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ZipPasswordMode.add,
                      label: Text('添加密码'),
                      icon: Icon(Icons.lock_outline),
                    ),
                    ButtonSegment(
                      value: _ZipPasswordMode.remove,
                      label: Text('解除密码'),
                      icon: Icon(Icons.lock_open_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      _changeMode(selection.first),
                ),
                const SizedBox(height: 20),
                buildSectionLabel(context, Icons.folder_open, 'EPUB 文件'),
                const SizedBox(height: 8),
                buildFilePickerRow(
                  context,
                  icon: Icons.book_outlined,
                  label: '输入文件',
                  value: _epubPath,
                  hint: '点击选择 EPUB 文件',
                  onTap: _loading ? () {} : _pickEpub,
                  isComplete: _epubPath.isNotEmpty,
                ),
                const SizedBox(height: 20),
                buildSectionLabel(context, Icons.key_outlined, '密码'),
                const SizedBox(height: 8),
                _passwordField(confirmation: false),
                if (_isAdding) ...[
                  const SizedBox(height: 12),
                  _passwordField(confirmation: true),
                ],
                const SizedBox(height: 16),
                buildInfoBar(
                  context,
                  _isAdding
                      ? '工具会先读取并解压 EPUB 内部文件，再保持原目录结构，使用 WinZip AES-256 密码重新打包成 .epub。支持密码 ZIP 的阅读器可输入密码后直接解压阅读。'
                      : '解除密码会重新打包为标准 EPUB，并恢复未压缩且位于首项的 mimetype。',
                ),
                const SizedBox(height: 20),
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
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.terminal, size: 18),
                  title: const Text('输出日志', style: TextStyle(fontSize: 13)),
                  children: [
                    SizedBox(
                      height: 150,
                      child: OutputLog(controller: _logController),
                    ),
                  ],
                ),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
            label: _isAdding ? '添加密码' : '解除密码',
            icon: _isAdding ? Icons.lock_outline : Icons.lock_open_outlined,
          ),
        ],
      ),
    );
  }
}
