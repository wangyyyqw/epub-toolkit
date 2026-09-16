import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../epub_background_operation.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';

/// 拆分 EPUB 页面
///
/// 扫描 EPUB 的 TOC 章节目录并列出，用户通过勾选章节手动插入分割点，
/// 每个被勾选的章节作为下一分卷的起点。保留原 EPUB 版本
/// （EPUB2 输出带 NCX，EPUB3 输出带 nav）。
class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

/// 拆分目标条目（与后台返回的 data 字段对应）
class _SplitTargetUi {
  final String title;
  final int level;
  final String href;

  const _SplitTargetUi({
    required this.title,
    required this.level,
    required this.href,
  });
}

class _SplitPageState extends State<SplitPage> {
  String _epubPath = '';
  bool _loading = false;

  /// 拆分输出目录
  String _splitOutputDir = '';
  bool _userPickedOutputDir = false;
  int _selectionGeneration = 0;

  /// 章节目标列表
  List<_SplitTargetUi> _targets = [];
  bool _targetsLoading = false;

  /// 被勾选作为分割点的章节索引
  final Set<int> _selected = {};

  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 选择 EPUB 文件，随后自动扫描章节目录
  Future<void> _pickEpub() async {
    final generation = ++_selectionGeneration;
    final path = await FileService.pickEpub();
    if (!mounted || generation != _selectionGeneration || path == null) return;
    setState(() {
      _epubPath = path;
      _targets = [];
      _selected.clear();
    });
    if (!_userPickedOutputDir) {
      // 默认输出到安全目录下的独立子目录，避免隐藏路径和权限问题
      try {
        var base = p.basename(path);
        if (base.toLowerCase().endsWith('.epub')) {
          base = base.substring(0, base.length - 5);
        } else {
          base = p.basenameWithoutExtension(path);
        }
        // 清理非法字符
        base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        if (base.isEmpty) base = 'split';
        // 使用 FileService 的安全目录逻辑
        final safeFile = await FileService.getSafeOutputPath(
          '${base}_split/dummy.epub',
        );
        var outputDir = p.dirname(safeFile);
        // 桌面端若输入在真实 Documents 下，优先与输入同目录的子目录
        if (!kIsWeb &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
          final inputDir = p.dirname(path);
          // 若输入目录非隐藏且可写，优先使用输入同目录下的 _split 子目录
          if (!inputDir.contains('.trae-cn') && !inputDir.contains('/tmp')) {
            final candidate = p.join(inputDir, '${base}_split');
            outputDir = candidate;
          }
        }
        if (!mounted || generation != _selectionGeneration) return;
        if (!_userPickedOutputDir) _splitOutputDir = outputDir;
      } catch (_) {
        if (!mounted || generation != _selectionGeneration) return;
        if (!_userPickedOutputDir) _splitOutputDir = p.dirname(path);
      }
    }
    if (!mounted || generation != _selectionGeneration) return;
    await _loadTargets();
    if (mounted) setState(() {});
  }

  /// 扫描 EPUB 的 TOC 章节目录
  ///
  /// 记录发起扫描时的文件路径；扫描期间若用户改选了其他文件，
  /// 结果返回时路径不匹配则丢弃旧结果，避免用错误的章节列表拆分。
  Future<void> _loadTargets() async {
    if (_epubPath.isEmpty) return;
    final scanPath = _epubPath;
    setState(() => _targetsLoading = true);
    try {
      final result = await runEpubBackgroundOperation<Map>(
        EpubBackgroundOperation.listSplitTargets,
        {'epubPath': scanPath},
      );
      final data = (result['data'] as List?) ?? const [];
      if (!mounted || scanPath != _epubPath) return;
      setState(() {
        _targets = data
            .map(
              (e) => _SplitTargetUi(
                title: (e as Map)['title'] as String? ?? '',
                level: (e['level'] as num?)?.toInt() ?? 1,
                href: e['href'] as String? ?? '',
              ),
            )
            .toList();
        // 保留仍然有效的勾选
        _selected.removeWhere((i) => i < 0 || i >= _targets.length);
      });
      if (_targets.isEmpty) {
        context.read<ToastProvider>().showWarning('未解析到章节目录，无法设置分割点');
      }
    } catch (e) {
      if (!mounted || scanPath != _epubPath) return;
      context.read<ToastProvider>().showError('读取章节目录失败：$e');
    } finally {
      if (mounted && scanPath == _epubPath) {
        setState(() => _targetsLoading = false);
      }
    }
  }

  /// 选择拆分输出目录
  Future<void> _pickSplitOutputDir() async {
    final dir = await FileService.pickDirectory(title: '选择拆分输出目录');
    if (!mounted || dir == null) return;
    _userPickedOutputDir = true;
    setState(() => _splitOutputDir = dir);
  }

  /// 将多行文本逐行追加到日志
  void _logAppendLines(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _logController.append(line.trim());
    }
  }

  /// 执行拆分 EPUB 操作
  Future<void> _execute() async {
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }
    if (_selected.isEmpty) {
      context.read<ToastProvider>().showWarning('请在章节目录中勾选至少 1 个分割点');
      return;
    }
    if (_loading || _targetsLoading) return;
    final inputPath = _epubPath;
    final points = _selected.toList()..sort();
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「拆分 EPUB」操作...');
    _logController.append('输入文件：$_epubPath');
    // 输出目录为空时，按平台选择安全目录
    String outputDir = _splitOutputDir.isEmpty
        ? p.dirname(_epubPath)
        : _splitOutputDir;
    try {
      // 验证输出权限，失败时自动选择应用安全目录。
      try {
        await FileService.ensureWritableDirectory(outputDir);
      } catch (_) {
        // 无权限则回退到安全目录
        final safe = await FileService.getSafeOutputPath('split_probe.epub');
        outputDir = p.join(
          p.dirname(safe),
          '${p.basenameWithoutExtension(inputPath)}_split',
        );
        await FileService.ensureWritableDirectory(outputDir);
        _logController.append('WARN: 原输出目录无写权限，已回退到 $outputDir');
        if (mounted) setState(() => _splitOutputDir = outputDir);
      }
      _logController.append('输出目录：$outputDir');
      final result = await runEpubBackgroundOperation<Map<String, dynamic>>(
        EpubBackgroundOperation.split,
        {'epubPath': inputPath, 'outputDir': outputDir, 'splitPoints': points},
      );
      _logAppendLines(result['log'] as String);
      final files = (result['outputPaths'] as List)
          .cast<String>()
          .map(File.new)
          .toList();
      if (files.isEmpty) {
        throw StateError('未生成拆分文件，请检查章节目录和分割点');
      }
      _logController.append('已生成 ${files.length} 个文件:');
      for (final file in files) {
        _logController.append(
          '  - ${p.basename(file.path)} (${(file.lengthSync() / 1024).toStringAsFixed(1)} KB)',
        );
      }
      if (!kIsWeb && Platform.isAndroid) {
        for (final file in files) {
          try {
            final copied = await FileService.copyFileToPublicDownload(
              sourcePath: file.path,
              filename: p.basename(file.path),
            );
            _logController.append('已复制到公共目录: $copied');
          } catch (e) {
            _logController.append('复制到公共目录失败 ${p.basename(file.path)}: $e');
          }
        }
      }
      if (mounted) context.read<ToastProvider>().showSuccess('拆分完成');
    } catch (e, st) {
      _logController.append('ERROR: 操作失败：$e');
      _logController.append('STACK: $st');
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
            icon: Icons.call_split,
            title: '拆分 EPUB',
            subtitle: '列出章节目录，勾选章节作为分割点拆分为多个 EPUB',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                // 输入 + 输出（桌面双列并排，移动端单列）
                ResponsiveRow(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildSectionLabel(
                          context,
                          Icons.folder_open,
                          'EPUB 文件',
                        ),
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
                        buildSectionLabel(context, Icons.folder_open, '输出目录'),
                        const SizedBox(height: 8),
                        buildFilePickerRow(
                          context,
                          icon: Icons.folder_open,
                          label: '输出目录',
                          value: _splitOutputDir,
                          hint: '点击选择拆分输出目录',
                          onTap: _loading ? () {} : _pickSplitOutputDir,
                          isComplete: _splitOutputDir.isNotEmpty,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 章节目录
                buildSectionLabel(context, Icons.list_alt_outlined, '章节目录'),
                const SizedBox(height: 8),
                buildInfoBar(
                  context,
                  '勾选章节作为分割点：每个被勾选的章节将作为下一分卷的起点（默认从第一段开始）。',
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline),
                  ),
                  child: _buildTargetList(),
                ),
                if (_targets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已勾选 ${_selected.length} 个分割点，可拆分为 ${_selected.length + 1} 卷',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => setState(_selected.clear),
                        child: const Text('清空勾选'),
                      ),
                    ],
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
            label: '按分割点拆分',
            icon: Icons.call_split,
          ),
        ],
      ),
    );
  }

  /// 章节目标勾选列表
  Widget _buildTargetList() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_targetsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_targets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _epubPath.isEmpty ? '选择 EPUB 后自动扫描章节目录' : '未解析到章节目录',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _targets.length,
      itemBuilder: (context, index) {
        final target = _targets[index];
        final checked = _selected.contains(index);
        return CheckboxListTile(
          value: checked,
          dense: true,
          // 保持 40px+ 触控高度：不压缩垂直密度，用 contentPadding 控制紧凑
          visualDensity: VisualDensity.standard,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: theme.colorScheme.primary,
          contentPadding: EdgeInsets.only(
            left: 12 + (target.level - 1) * 16,
            top: 2,
            bottom: 2,
          ),
          title: Text(
            target.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
              color: checked ? theme.colorScheme.primary : cs.onSurface,
            ),
          ),
          subtitle: target.href.isNotEmpty
              ? Text(
                  '${index + 1} · ${target.href}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.outline),
                )
              : null,
          onChanged: _loading
              ? null
              : (v) {
                  setState(() {
                    if (v ?? false) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  });
                },
        );
      },
    );
  }
}
