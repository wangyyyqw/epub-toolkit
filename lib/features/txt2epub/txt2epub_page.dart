import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/core/file_service.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';
import 'package:epub_gadget/shared/widgets/base_button.dart';
import 'package:epub_gadget/shared/widgets/output_log.dart';

/// 单个标题级别的配置
class LevelConfig {
  int presetIndex;
  String customRegex;
  bool split;
  LevelConfig({
    required this.presetIndex,
    this.customRegex = '',
    this.split = true,
  });

  String get pattern =>
      customRegex.trim().isNotEmpty ? customRegex.trim() : _presetPattern();
  String _presetPattern() =>
      presetPatterns[presetIndex.clamp(0, presetPatterns.length - 1)].pattern;
  int get level => presetIndex.clamp(0, presetPatterns.length - 1) < 0
      ? 1
      : presetPatterns[presetIndex.clamp(0, presetPatterns.length - 1)].level;
}

/// TXT 转 EPUB 页面
///
/// 支持多级标题：用户可动态添加 1-3 级标题规则，
/// 每级可选预设正则或自定义正则，并控制是否按该级切分。
class Txt2EpubPage extends StatefulWidget {
  const Txt2EpubPage({super.key});

  @override
  State<Txt2EpubPage> createState() => _Txt2EpubPageState();
}

class _Txt2EpubPageState extends State<Txt2EpubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _txtPath = '';
  String _outputPath = '';
  String _title = '';
  String _author = '';
  String _coverPath = '';

  /// 多级标题配置（至少 1 级，最多 3 级）
  final List<LevelConfig> _levels = [LevelConfig(presetIndex: 0)];

  bool _removeEmptyLines = true;
  bool _fixIndent = true;
  bool _splitTitle = false;
  bool _loading = false;
  bool _scanning = false;
  List<Chapter> _chapters = [];
  List<Map<String, dynamic>> _scanResults = [];
  final OutputLogController _logController = OutputLogController();

  late final List<String> _presetNames = presetPatterns
      .map((pat) => pat.name)
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logController.dispose();
    super.dispose();
  }

  // ==================== 文件选择 ====================

  Future<void> _pickTxt() async {
    final path = await FileService.pickTxt();
    if (path == null) return;
    _txtPath = path;
    if (_title.isEmpty) {
      _title = p.basenameWithoutExtension(path);
    }
    if (_outputPath.isEmpty) {
      final name = _title.trim().isNotEmpty
          ? '${_title.trim()}.epub'
          : '${p.basenameWithoutExtension(path)}.epub';
      _outputPath = await FileService.getDefaultOutputPathForInput(
        inputPath: path,
        filename: name,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickCover() async {
    final path = await FileService.pickImage();
    if (path == null) return;
    setState(() => _coverPath = path);
  }

  Future<void> _pickOutput() async {
    final defaultName = _title.trim().isNotEmpty
        ? '${_title.trim()}.epub'
        : 'output.epub';
    final path = await FileService.saveFile(
      defaultFileName: defaultName,
      initialDirectory: _txtPath.isNotEmpty ? p.dirname(_txtPath) : null,
    );
    if (path == null) return;
    setState(() => _outputPath = path);
  }

  // ==================== 工具方法 ====================

  bool _isValidRegex(String pattern) {
    if (pattern.isEmpty) return true;
    try {
      RegExp(pattern);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _truncatePath(String path, {int maxLen = 30}) {
    if (path.length <= maxLen) return path;
    final dir = p.dirname(path);
    final base = p.basename(path);
    if (base.length >= maxLen - 5) {
      return '.../${base.substring(0, maxLen - 8)}...';
    }
    final keep = maxLen - base.length - 5;
    if (keep <= 0) return '.../$base';
    return '${dir.substring(0, keep)}.../$base';
  }

  /// 收集所有级别的正则、层级、切分标志
  List<String> get _allPatterns => _levels.map((l) => l.pattern).toList();
  List<int> get _allLevels =>
      _levels.asMap().entries.map((e) => e.key + 1).toList();
  List<bool> get _allSplits => _levels.map((l) => l.split).toList();

  // ==================== 扫描与预览 ====================

  Future<void> _scanPatterns() async {
    if (_txtPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 TXT 文件');
      return;
    }
    setState(() => _scanning = true);
    try {
      final encoding = EncodingDetector.detect(_txtPath);
      final rawText = EncodingDetector.readFile(_txtPath, encoding);
      final cleaner = TextCleaner(
        removeEmptyLines: _removeEmptyLines,
        fixIndent: _fixIndent,
      );
      final cleanText = cleaner.clean(rawText);
      final splitter = ChapterSplitter();
      final results = splitter.scan(cleanText);
      results.sort((a, b) => (b['count'] as int) - (a['count'] as int));
      setState(() => _scanResults = results);

      final best = results.isNotEmpty && (results.first['count'] as int) > 0
          ? results.first
          : null;
      if (best != null) {
        final bestName = best['name'] as String;
        final bestCount = best['count'] as int;
        final index = _presetNames.indexOf(bestName);
        if (index >= 0) {
          setState(() => _levels.first.presetIndex = index);
        }
        if (mounted) {
          context.read<ToastProvider>().showSuccess(
            '推荐预设：「$bestName」(匹配 $bestCount 处)',
          );
        }
      } else if (mounted) {
        context.read<ToastProvider>().showWarning('未找到匹配的章节标题格式');
      }
    } catch (e) {
      if (mounted) context.read<ToastProvider>().showError('扫描失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _previewSplit() async {
    if (_txtPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 TXT 文件');
      return;
    }
    for (final l in _levels) {
      if (!_isValidRegex(l.pattern)) {
        context.read<ToastProvider>().showError('正则表达式无效');
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final encoding = EncodingDetector.detect(_txtPath);
      final rawText = EncodingDetector.readFile(_txtPath, encoding);
      final cleaner = TextCleaner(
        removeEmptyLines: _removeEmptyLines,
        fixIndent: _fixIndent,
      );
      final cleanText = cleaner.clean(rawText);
      final splitter = ChapterSplitter();

      List<Chapter> chapters;
      if (_levels.length == 1) {
        chapters = splitter.split(
          cleanText,
          _levels.first.pattern,
          splitTitle: _splitTitle,
        );
      } else {
        chapters = splitter.splitHierarchical(
          cleanText,
          _allPatterns,
          _allLevels,
          _allSplits,
        );
      }
      setState(() => _chapters = chapters);
      _tabController.animateTo(1);
      if (mounted) {
        context.read<ToastProvider>().showSuccess(
          '分割完成，共 ${_countLeafChapters(chapters)} 章',
        );
      }
    } catch (e) {
      if (mounted) context.read<ToastProvider>().showError('预览失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 统计叶子章节数
  int _countLeafChapters(List<Chapter> chapters) {
    var count = 0;
    for (final ch in chapters) {
      if (ch.children.isEmpty) {
        count++;
      } else {
        count += _countLeafChapters(ch.children);
      }
    }
    return count;
  }

  Future<void> _generate() async {
    if (_txtPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 TXT 文件');
      return;
    }
    if (_title.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请输入书名');
      return;
    }
    for (final l in _levels) {
      if (!_isValidRegex(l.pattern)) {
        context.read<ToastProvider>().showError('正则表达式无效');
        return;
      }
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 开始生成 EPUB...');

    try {
      _logController.append('正在检测文件编码...');
      final encoding = EncodingDetector.detect(_txtPath);
      _logController.append('检测到编码：$encoding');

      _logController.append('正在读取文件...');
      final rawText = EncodingDetector.readFile(_txtPath, encoding);
      _logController.append('文件读取完成，共 ${rawText.length} 字符');

      _logController.append('正在清洗文本...');
      final cleaner = TextCleaner(
        removeEmptyLines: _removeEmptyLines,
        fixIndent: _fixIndent,
      );
      final cleanText = cleaner.clean(rawText);
      _logController.append('文本清洗完成');

      _logController.append('正在分割章节...');
      final splitter = ChapterSplitter();
      List<Chapter> chapters;
      if (_levels.length == 1) {
        chapters = splitter.split(
          cleanText,
          _levels.first.pattern,
          splitTitle: _splitTitle,
        );
        _logController.append('章节分割完成（单级），共 ${chapters.length} 章');
      } else {
        chapters = splitter.splitHierarchical(
          cleanText,
          _allPatterns,
          _allLevels,
          _allSplits,
        );
        _logController.append(
          '章节分割完成（${_levels.length} 级），共 ${_countLeafChapters(chapters)} 个叶子章节',
        );
      }
      setState(() => _chapters = chapters);

      String outputPath = _outputPath;
      if (outputPath.isEmpty) {
        _logController.append('请选择输出路径...');
        final defaultName = '${_title.trim()}.epub';
        final selectedPath = await FileService.saveFile(
          defaultFileName: defaultName,
          initialDirectory: _txtPath.isNotEmpty ? p.dirname(_txtPath) : null,
        );
        if (selectedPath == null || selectedPath.isEmpty) {
          _logController.append('ERROR: 未选择输出路径，生成取消');
          if (mounted) {
            context.read<ToastProvider>().showWarning('未选择输出路径，生成已取消');
          }
          return;
        }
        outputPath = selectedPath;
        setState(() => _outputPath = outputPath);
      }

      _logController.append('正在生成 EPUB...');
      final (log, userVisiblePath) = await EpubGenerator.generate(
        outputPath: outputPath,
        title: _title.trim(),
        author: _author.trim().isEmpty ? '未知' : _author.trim(),
        chapters: chapters,
        coverPath: _coverPath.isNotEmpty ? _coverPath : null,
      );

      outputPath = userVisiblePath;
      _outputPath = userVisiblePath;
      for (final line in log.split('\n')) {
        if (line.trim().isNotEmpty) _logController.append(line.trim());
      }
      _logController.append('PROGRESS: EPUB 生成完成！');
      if (mounted) {
        context.read<ToastProvider>().showSuccess('EPUB 生成成功，已保存到 $outputPath');
      }
    } catch (e) {
      _logController.append('ERROR: 生成失败：$e');
      if (mounted) context.read<ToastProvider>().showError('生成失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==================== UI 组件 ====================

  Widget _buildFilePickerRow({
    required IconData icon,
    required String label,
    required String value,
    required String hint,
    required VoidCallback onTap,
    required bool isComplete,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isComplete ? cs.primary.withValues(alpha: 0.3) : cs.outline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isComplete ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isNotEmpty ? value : hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: value.isNotEmpty
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
    bool required = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              required ? '$label *' : label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 52,
          child: TextField(
            controller: TextEditingController(text: value),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14.5,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: context.themeCard,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: cs.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: cs.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: context.themeDivider, width: 1.5),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ==================== 多级标题配置组件 ====================

  /// 单个级别的配置卡片
  Widget _buildLevelConfigCard(int index) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = _levels[index];
    final levelNum = index + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 级别标题 + 切分开关 + 删除按钮
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.themeAccent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Text(
                  'L$levelNum',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: context.themeTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '第 $levelNum 级标题',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 切分开关
              Text(
                '切分',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 38,
                height: 24,
                child: Switch(
                  value: level.split,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => level.split = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              // 删除按钮（仅多级时可删）
              if (_levels.length > 1) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: cs.error),
                  onPressed: _loading
                      ? null
                      : () => setState(() => _levels.removeAt(index)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 预设正则下拉
          _buildDropdownField(
            label: '预设正则',
            value: _presetNames[level.presetIndex],
            items: _presetNames,
            onChanged: (v) {
              if (v == null) return;
              final idx = _presetNames.indexOf(v);
              if (idx >= 0) setState(() => level.presetIndex = idx);
            },
          ),
          const SizedBox(height: 8),
          // 自定义正则
          _buildTextField(
            label: '自定义正则（优先于预设）',
            value: level.customRegex,
            hint: '留空则使用预设正则',
            icon: Icons.code,
            onChanged: (v) => setState(() => level.customRegex = v),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 52,
          child: DropdownButtonFormField<String>(
            key: ValueKey('$label-$value'),
            initialValue: value,
            isExpanded: true,
            items: items
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: context.themeCard,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: cs.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: cs.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                borderSide: BorderSide(color: context.themeDivider, width: 1.5),
              ),
            ),
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: cs.onSurfaceVariant,
              size: 20,
            ),
            dropdownColor: context.themeCard,
          ),
        ),
      ],
    );
  }

  Widget _buildChip(
    String label,
    bool selected,
    ValueChanged<bool> onSelected,
  ) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: _loading ? null : onSelected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildSectionLabel(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String text,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildScanResults() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasResults = _scanResults.any((r) => (r['count'] as int) > 0);

    if (!hasResults) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '未找到匹配的章节标题，请尝试自定义正则',
          style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final r = _scanResults[index];
          final name = r['name'] as String;
          final count = r['count'] as int;
          final example = r['example'] as String;
          final isSelected = name == _presetNames[_levels.first.presetIndex];

          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
            minVerticalPadding: 0,
            leading: Icon(
              count > 0
                  ? Icons.check_circle_outline
                  : Icons.remove_circle_outline,
              size: 16,
              color: count > 0
                  ? (isSelected
                        ? cs.primary
                        : cs.primary.withValues(alpha: 0.4))
                  : cs.outline,
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? cs.primary : null,
              ),
            ),
            subtitle: count > 0
                ? Text(
                    '匹配 $count 处${example.isNotEmpty ? ' · $example' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  )
                : null,
            onTap: count > 0
                ? () {
                    final idx = _presetNames.indexOf(name);
                    if (idx >= 0) {
                      setState(() => _levels.first.presetIndex = idx);
                    }
                  }
                : null,
          );
        },
      ),
    );
  }

  // ==================== 设置标签页 ====================

  Widget _buildSettingsTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // ---- 文件信息区 ----
        _buildSectionLabel(theme, cs, Icons.folder_open, '文件信息'),
        const SizedBox(height: 8),
        _buildFilePickerRow(
          icon: Icons.description,
          label: 'TXT 文件',
          value: _txtPath.isNotEmpty ? p.basename(_txtPath) : '',
          hint: '点击选择 TXT 文件',
          onTap: _loading ? () {} : _pickTxt,
          isComplete: _txtPath.isNotEmpty,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: '书名',
                value: _title,
                hint: '输入书名',
                icon: Icons.book,
                onChanged: (v) => setState(() => _title = v),
                required: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: '作者',
                value: _author,
                hint: '输入作者（可选）',
                icon: Icons.person,
                onChanged: (v) => setState(() => _author = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildFilePickerRow(
                icon: Icons.image,
                label: '封面图片',
                value: _coverPath.isNotEmpty ? p.basename(_coverPath) : '',
                hint: '可选',
                onTap: _loading ? () {} : _pickCover,
                isComplete: _coverPath.isNotEmpty,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFilePickerRow(
                icon: Icons.folder_open,
                label: '输出路径',
                value: _outputPath.isNotEmpty ? _truncatePath(_outputPath) : '',
                hint: '点击选择',
                onTap: _loading ? () {} : _pickOutput,
                isComplete: _outputPath.isNotEmpty,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ---- 章节分割区（多级标题）----
        Row(
          children: [
            _buildSectionLabel(theme, cs, Icons.content_cut, '章节分割'),
            const Spacer(),
            // 添加级别按钮
            if (_levels.length < 3)
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加级别', style: TextStyle(fontSize: 12)),
                onPressed: _loading
                    ? null
                    : () => setState(
                        () => _levels.add(
                          LevelConfig(presetIndex: _levels.length),
                        ),
                      ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // 多级提示
        if (_levels.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '多级标题模式：上级匹配的章节内容会被下级正则再次切分，生成嵌套目录',
                    style: TextStyle(fontSize: 11, color: cs.primary),
                  ),
                ),
              ],
            ),
          ),

        // 各级配置卡片
        ..._levels.asMap().entries.map((e) => _buildLevelConfigCard(e.key)),

        // 智能扫描按钮
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: BaseButton(
                  label: '智能扫描推荐预设',
                  icon: Icons.auto_fix_high,
                  onPressed: _scanning ? null : _scanPatterns,
                  variant: BaseButtonVariant.secondary,
                  loading: _scanning,
                ),
              ),
            ),
          ],
        ),

        // 扫描结果
        if (_scanResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildScanResults(),
        ],

        const SizedBox(height: 10),

        // 清洗选项
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _buildChip(
              '去除空行',
              _removeEmptyLines,
              (v) => setState(() => _removeEmptyLines = v),
            ),
            _buildChip(
              '修正缩进',
              _fixIndent,
              (v) => setState(() => _fixIndent = v),
            ),
            _buildChip(
              '拆分标题',
              _splitTitle,
              (v) => setState(() => _splitTitle = v),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 预览标签页（支持嵌套树）====================

  Widget _buildPreviewTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book,
              size: 56,
              color: cs.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方"预览分割"查看章节列表',
              style: TextStyle(color: cs.outline, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final leafCount = _countLeafChapters(_chapters);
    final totalWords = _sumWords(_chapters);

    return Column(
      children: [
        // 统计栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.primaryContainer.withValues(alpha: 0.3),
          child: Row(
            children: [
              Text(
                '$leafCount 章',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$totalWords 字',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
              if (_levels.length > 1) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_levels.length}级',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text('点击展开预览', style: TextStyle(color: cs.outline, fontSize: 11)),
            ],
          ),
        ),
        // 章节列表（支持嵌套）
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _chapters.length,
            itemBuilder: (context, index) {
              return _buildChapterNode(_chapters[index], index, 0);
            },
          ),
        ),
        // 日志
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutputLog(controller: _logController),
        ),
      ],
    );
  }

  /// 递归统计字数
  int _sumWords(List<Chapter> chapters) {
    var total = 0;
    for (final ch in chapters) {
      total += ch.content.length;
      if (ch.children.isNotEmpty) total += _sumWords(ch.children);
    }
    return total;
  }

  /// 构建章节节点（支持嵌套树展示）
  Widget _buildChapterNode(Chapter chapter, int index, int depth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasChildren = chapter.children.isNotEmpty;

    // 叶子章节可展开预览内容
    if (!hasChildren) {
      final previewText = chapter.content.isEmpty
          ? '（无内容）'
          : (chapter.content.length > 500
                ? '${chapter.content.substring(0, 500)}...'
                : chapter.content);

      return Padding(
        padding: EdgeInsets.only(left: depth * 20.0),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          dense: true,
          title: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Text(
              '${chapter.wordCount} 字',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.topLeft,
                child: SelectableText(
                  previewText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 有子章节的节点：可折叠子树
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
        initiallyExpanded: depth < 1,
        title: Row(
          children: [
            Icon(Icons.folder, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${chapter.children.length}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        children: chapter.children
            .asMap()
            .entries
            .map((e) => _buildChapterNode(e.value, e.key, depth + 1))
            .toList(),
      ),
    );
  }

  // ==================== 主构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // 紧凑分类标签（替代页头）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_stories,
                        color: AppTheme.accent,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '将 TXT 转换为 EPUB 电子书',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 分段式 Tab
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: cs.onPrimary,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
                padding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(text: '设置'),
                  Tab(text: '预览'),
                ],
              ),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildSettingsTab(), _buildPreviewTab()],
            ),
          ),

          // 底部固定操作栏
          Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: BaseButton(
                      label: '预览分割',
                      icon: Icons.preview,
                      onPressed: _loading ? null : _previewSplit,
                      variant: BaseButtonVariant.secondary,
                      loading: _loading,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 50,
                    child: BaseButton(
                      label: '生成 EPUB',
                      icon: Icons.auto_stories,
                      onPressed: _loading ? null : _generate,
                      variant: BaseButtonVariant.primary,
                      loading: _loading,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
