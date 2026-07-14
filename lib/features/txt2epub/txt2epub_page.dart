import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/core/file_service.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/output_naming.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';
import 'package:epub_gadget/shared/widgets/base_button.dart';
import 'package:epub_gadget/shared/widgets/file_drop_target.dart';
import 'package:epub_gadget/shared/widgets/output_log.dart';

/// 单个标题级别的配置
class LevelConfig {
  final TextEditingController regexController;
  int level;
  bool split;
  String? presetName;

  LevelConfig({
    required String pattern,
    required this.level,
    this.split = true,
    this.presetName,
  }) : regexController = TextEditingController(text: pattern);

  factory LevelConfig.fromPreset(PresetPattern preset) {
    return LevelConfig(
      pattern: preset.pattern,
      level: preset.level,
      split: preset.split,
      presetName: preset.name,
    );
  }

  String get pattern => regexController.text.trim();

  void applyPreset(PresetPattern preset) {
    regexController.text = preset.pattern;
    level = preset.level;
    split = preset.split;
    presetName = preset.name;
  }

  void dispose() => regexController.dispose();
}

/// TXT 转 EPUB 页面
///
/// 支持多级标题：用户可动态添加最多 15 条标题规则，
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
  bool _outputPathManuallySelected = false;
  int _outputPathRevision = 0;
  String _title = '';
  String _author = '';
  String _coverPath = '';
  String _headerImagePath = '';
  String _fullScreenCoverImagePath = '';
  ChapterHeaderImageStyle _headerImageStyle = ChapterHeaderImageStyle.yuewei;
  bool _addFullScreenCover = false;
  FullScreenCoverStyle _fullScreenCoverStyle = FullScreenCoverStyle.yuewei;

  /// 多级标题配置（至少 1 条，最多 15 条）
  final List<LevelConfig> _levels = [
    LevelConfig.fromPreset(presetPatterns.first),
  ];

  bool _removeEmptyLines = true;
  bool _fixIndent = true;
  bool _loading = false;
  bool _scanning = false;
  List<Chapter> _chapters = [];
  ChapterSplitAnalysis? _chapterAnalysis;
  String _preparedText = '';
  final Set<int> _ignoredTitleLines = {};
  final Map<int, Set<int>> _disabledRuleLines = {};
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
    for (final level in _levels) {
      level.dispose();
    }
    super.dispose();
  }

  // ==================== 文件选择 ====================

  Future<void> _pickTxt() async {
    final path = await FileService.pickTxt();
    if (path == null) return;
    final inputChanged = path != _txtPath;
    final previousTitleWasAutomatic =
        _txtPath.isNotEmpty &&
        _title.trim() == p.basenameWithoutExtension(_txtPath).trim();
    setState(() {
      _txtPath = path;
      _scanResults = [];
      _invalidateAnalysis();
      if (_title.trim().isEmpty || previousTitleWasAutomatic) {
        _title = p.basenameWithoutExtension(path);
      }
      if (inputChanged) {
        _outputPath = '';
        _outputPathManuallySelected = false;
        _outputPathRevision++;
      }
    });
    await _refreshAutomaticOutputPath();
    await _scanPatterns();
  }

  Future<void> _pickCover() async {
    final path = await FileService.pickImage();
    if (path == null) return;
    setState(() => _coverPath = path);
  }

  Future<void> _pickHeaderImage() async {
    final path = await FileService.pickImage();
    if (path == null) return;
    final extension = p.extension(path).toLowerCase();
    if (extension != '.png' && extension != '.jpg' && extension != '.jpeg') {
      if (mounted) {
        context.read<ToastProvider>().showWarning('章节头图仅支持 PNG、JPG 或 JPEG 图片');
      }
      return;
    }
    setState(() => _headerImagePath = path);
  }

  Future<void> _pickFullScreenCoverImage() async {
    final path = await FileService.pickImage();
    if (path == null) return;
    final extension = p.extension(path).toLowerCase();
    if (extension != '.png' && extension != '.jpg' && extension != '.jpeg') {
      if (mounted) {
        context.read<ToastProvider>().showWarning('首页图片仅支持 PNG、JPG 或 JPEG 图片');
      }
      return;
    }
    setState(() => _fullScreenCoverImagePath = path);
  }

  Future<void> _pickOutput() async {
    final defaultName = Txt2EpubNaming.buildFilename(
      title: _title,
      author: _author,
      inputPath: _txtPath,
    );
    final path = await FileService.saveFile(
      defaultFileName: defaultName,
      initialDirectory: _txtPath.isNotEmpty ? p.dirname(_txtPath) : null,
    );
    if (path == null) return;
    setState(() {
      _outputPath = path;
      _outputPathManuallySelected = true;
      _outputPathRevision++;
    });
  }

  void _updateTitle(String value) {
    setState(() => _title = value);
    _refreshAutomaticOutputPath();
  }

  void _updateAuthor(String value) {
    setState(() => _author = value);
    _refreshAutomaticOutputPath();
  }

  Future<void> _refreshAutomaticOutputPath() async {
    if (_outputPathManuallySelected || _txtPath.isEmpty) return;
    final revision = ++_outputPathRevision;
    final filename = Txt2EpubNaming.buildFilename(
      title: _title,
      author: _author,
      inputPath: _txtPath,
    );
    final path = await FileService.getDefaultOutputPathForInput(
      inputPath: _txtPath,
      filename: filename,
    );
    if (!mounted ||
        revision != _outputPathRevision ||
        _outputPathManuallySelected) {
      return;
    }
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

  List<ChapterSplitRule> get _splitRules => [
    for (final level in _levels)
      ChapterSplitRule(
        pattern: level.pattern,
        level: level.level,
        split: level.split,
      ),
  ];

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
      final displayedResults = [...results]
        ..sort((a, b) => (b['count'] as int) - (a['count'] as int));

      // 依照预设顺序组合互补规则。已经由前面规则覆盖的标题不会再添加
      // 宽泛预设，避免同一章节被重复识别。
      final selectedPresets = <PresetPattern>[];
      final coveredLines = <int>{};
      final splitChapterPresetNames = {
        '卷标题（中文数字）',
        '部标题（中文数字）',
        '章标题（中文数字）',
        '回标题（中文数字）',
        '节标题（中文数字）',
        '卷标题（数字）',
        '部标题（数字）',
        '章标题（数字）',
        '回标题（数字）',
        '节标题（数字）',
        '序言/简介/后记/尾声',
      };
      final prioritizedIndexes = [
        for (var index = 0; index < presetPatterns.length; index++)
          if (splitChapterPresetNames.contains(presetPatterns[index].name))
            index,
        for (var index = 0; index < presetPatterns.length; index++)
          if (!splitChapterPresetNames.contains(presetPatterns[index].name))
            index,
      ];
      for (final index in prioritizedIndexes) {
        final lineIndexes = (results[index]['lineIndexes'] as List<int>?) ?? [];
        if (lineIndexes.isEmpty ||
            !lineIndexes.any(
              (lineIndex) => !coveredLines.contains(lineIndex),
            )) {
          continue;
        }
        selectedPresets.add(presetPatterns[index]);
        coveredLines.addAll(lineIndexes);
        if (selectedPresets.length >= 8) break;
      }

      setState(() {
        _scanResults = displayedResults;
        if (selectedPresets.isNotEmpty) {
          for (final level in _levels) {
            level.dispose();
          }
          _levels
            ..clear()
            ..addAll(selectedPresets.map(LevelConfig.fromPreset));
          _invalidateAnalysis();
        }
      });

      if (selectedPresets.isNotEmpty) {
        if (mounted) {
          context.read<ToastProvider>().showSuccess(
            '已自动添加 ${selectedPresets.length} 条规则，识别 ${coveredLines.length} 个标题',
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
      final cleanText = _readAndCleanText();
      final analysis = _analyzeText(cleanText);
      setState(() {
        _preparedText = cleanText;
        _chapterAnalysis = analysis;
        _chapters = analysis.chapters;
      });
      _tabController.animateTo(1);
      if (mounted) {
        context.read<ToastProvider>().showSuccess(
          '识别 ${analysis.matches.length} 个标题，生成 ${_countAllChapters(analysis.chapters)} 个页面',
        );
      }
    } catch (e) {
      if (mounted) context.read<ToastProvider>().showError('预览失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _readAndCleanText() {
    final encoding = EncodingDetector.detect(_txtPath);
    final rawText = EncodingDetector.readFile(_txtPath, encoding);
    return TextCleaner(
      removeEmptyLines: _removeEmptyLines,
      fixIndent: _fixIndent,
    ).clean(rawText);
  }

  ChapterSplitAnalysis _analyzeText(String text) {
    final suppressedLineIndexes = <int>{
      for (final lines in _disabledRuleLines.values) ...lines,
    };
    return ChapterSplitter().analyzeAndSplit(
      text,
      _splitRules,
      ignoredLineIndexes: _ignoredTitleLines,
      suppressedLineIndexes: suppressedLineIndexes,
      keepSplitTitleInContent: false,
    );
  }

  void _invalidateAnalysis({bool clearIgnored = true}) {
    _chapterAnalysis = null;
    _preparedText = '';
    _chapters = [];
    if (clearIgnored) {
      _ignoredTitleLines.clear();
      _disabledRuleLines.clear();
    }
  }

  void _toggleTitleMatch(ChapterTitleMatch match, bool enabled) {
    if (enabled) {
      _ignoredTitleLines.remove(match.lineIndex);
    } else {
      _ignoredTitleLines.add(match.lineIndex);
    }
    if (_preparedText.isEmpty) return;
    final analysis = _analyzeText(_preparedText);
    setState(() {
      _chapterAnalysis = analysis;
      _chapters = analysis.chapters;
    });
  }

  void _toggleRuleCategory(int ruleIndex, bool enabled) {
    if (_preparedText.isEmpty || _chapterAnalysis == null) return;
    if (enabled) {
      _disabledRuleLines.remove(ruleIndex);
    } else {
      final lineIndexes = {
        for (final match in _chapterAnalysis!.matches)
          if (match.ruleIndex == ruleIndex) match.lineIndex,
      };
      if (lineIndexes.isEmpty) return;
      _disabledRuleLines[ruleIndex] = lineIndexes;
    }
    final analysis = _analyzeText(_preparedText);
    setState(() {
      _chapterAnalysis = analysis;
      _chapters = analysis.chapters;
    });
  }

  String _ruleCategoryLabel(int ruleIndex) {
    if (ruleIndex < 0 || ruleIndex >= _levels.length) {
      return '规则 ${ruleIndex + 1}';
    }
    final presetName = _levels[ruleIndex].presetName;
    return presetName == null || presetName.isEmpty
        ? '自定义规则 ${ruleIndex + 1}'
        : presetName;
  }

  String _rulePattern(int ruleIndex) {
    if (ruleIndex < 0 || ruleIndex >= _levels.length) return '';
    return _levels[ruleIndex].pattern;
  }

  Widget _buildRuleMatchDetails(int? ruleIndex) {
    final cs = Theme.of(context).colorScheme;
    final isAutomatic = ruleIndex == null;
    final label = isAutomatic ? '自动正文（未匹配正则）' : _ruleCategoryLabel(ruleIndex);
    final pattern = isAutomatic ? '' : _rulePattern(ruleIndex);

    return Tooltip(
      message: pattern.isEmpty ? label : '$label\n$pattern',
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAutomatic ? label : '匹配规则：$label',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: isAutomatic ? cs.onSurfaceVariant : cs.primary,
              ),
            ),
            if (pattern.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                pattern,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 统计实际生成的 XHTML 页面数（父级标题页也会生成页面）。
  int _countAllChapters(List<Chapter> chapters) {
    var count = 0;
    for (final ch in chapters) {
      count++;
      count += _countAllChapters(ch.children);
    }
    return count;
  }

  Future<void> _generate() async {
    if (_txtPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 TXT 文件');
      return;
    }
    if (_addFullScreenCover && _fullScreenCoverImagePath.isEmpty) {
      context.read<ToastProvider>().showWarning('添加全屏首页前请先选择首页图片');
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
      final analysis = _analyzeText(cleanText);
      final chapters = analysis.chapters;
      _logController.append(
        '章节分析完成：${analysis.matches.length} 个标题，${_countAllChapters(chapters)} 个页面',
      );
      setState(() {
        _preparedText = cleanText;
        _chapterAnalysis = analysis;
        _chapters = chapters;
      });

      String outputPath = _outputPath;
      if (outputPath.isEmpty) {
        _logController.append('请选择输出路径...');
        final defaultName = Txt2EpubNaming.buildFilename(
          title: _title,
          author: _author,
          inputPath: _txtPath,
        );
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
        setState(() {
          _outputPath = outputPath;
          _outputPathManuallySelected = true;
          _outputPathRevision++;
        });
      }

      _logController.append('正在生成 EPUB...');
      final resolvedTitle = Txt2EpubNaming.resolveTitle(
        title: _title,
        inputPath: _txtPath,
      );
      final (log, userVisiblePath) = await EpubGenerator.generate(
        outputPath: outputPath,
        title: resolvedTitle,
        author: _author.trim().isEmpty ? '未知' : _author.trim(),
        chapters: chapters,
        coverPath: _coverPath.isNotEmpty ? _coverPath : null,
        headerImagePath: _headerImagePath.isNotEmpty ? _headerImagePath : null,
        headerImageStyle: _headerImageStyle,
        fullScreenCoverImagePath:
            _addFullScreenCover && _fullScreenCoverImagePath.isNotEmpty
            ? _fullScreenCoverImagePath
            : null,
        fullScreenCoverStyle: _addFullScreenCover
            ? _fullScreenCoverStyle
            : null,
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
    final defaultDropHandler = _shouldAcceptDroppedFiles(label)
        ? (List<String> paths) {
            FileService.primeDroppedPaths(paths);
            onTap();
          }
        : null;
    final row = InkWell(
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
    return FileDropTarget(onFilesDropped: defaultDropHandler, child: row);
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: child,
    );
  }

  Widget _buildResponsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: [first, const SizedBox(height: 10), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildImagePickerWithClear({
    required String label,
    required String path,
    required String hint,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildFilePickerRow(
            icon: Icons.add_photo_alternate_outlined,
            label: label,
            value: path.isEmpty ? '' : p.basename(path),
            hint: hint,
            onTap: _loading ? () {} : onPick,
            isComplete: path.isNotEmpty,
          ),
        ),
        if (path.isNotEmpty) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: '移除$label',
            onPressed: _loading ? null : onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: value ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: _loading ? null : onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
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
    final cs = Theme.of(context).colorScheme;
    final level = _levels[index];
    final levelNum = level.level;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题级别、分页状态和规则管理各自占用明确区域，避免互相遮挡。
          Row(
            children: [
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.themeAccentLight,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: context.themeAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'H$levelNum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.themeTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 104,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: level.level,
                    isDense: true,
                    borderRadius: BorderRadius.circular(8),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextPrimary,
                    ),
                    items: [
                      for (var value = 1; value <= 6; value++)
                        DropdownMenuItem(
                          value: value,
                          child: Text('$value 级标题'),
                        ),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) => setState(() {
                            level.level = value ?? level.level;
                            level.presetName = null;
                            _invalidateAnalysis();
                          }),
                  ),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: '开启后，匹配到的标题会新建 EPUB 页面',
                child: FilterChip(
                  selected: level.split,
                  showCheckmark: true,
                  checkmarkColor: context.themeWarm,
                  selectedColor: context.themeWarmLight,
                  backgroundColor: context.themeBgWarm,
                  side: BorderSide(
                    color: level.split
                        ? context.themeWarm.withValues(alpha: 0.55)
                        : context.themeDividerLight,
                  ),
                  label: const Text('分页'),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: level.split
                        ? context.themeWarm
                        : context.themeTextSecondary,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: _loading
                      ? null
                      : (value) => setState(() {
                          level.split = value;
                          _invalidateAnalysis();
                        }),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: '管理规则',
                enabled: !_loading,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('上移规则'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index < _levels.length - 1,
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('下移规则'),
                      ],
                    ),
                  ),
                  if (_levels.length > 1) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: cs.error,
                          ),
                          const SizedBox(width: 10),
                          Text('删除规则', style: TextStyle(color: cs.error)),
                        ],
                      ),
                    ),
                  ],
                ],
                onSelected: (action) => setState(() {
                  switch (action) {
                    case 'up':
                      final item = _levels.removeAt(index);
                      _levels.insert(index - 1, item);
                      break;
                    case 'down':
                      final item = _levels.removeAt(index);
                      _levels.insert(index + 1, item);
                      break;
                    case 'delete':
                      _levels.removeAt(index).dispose();
                      break;
                  }
                  _invalidateAnalysis();
                }),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            level.presetName == null ? '自定义匹配规则' : '预设 · ${level.presetName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.themeTextTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: level.regexController,
            enabled: !_loading,
            maxLines: 1,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '输入正则表达式，靠前规则优先匹配',
              errorText: _isValidRegex(level.pattern) ? null : '正则无效',
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              suffixIcon: PopupMenuButton<int>(
                tooltip: '选择预设正则',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.rule_rounded, size: 19),
                itemBuilder: (context) => [
                  for (
                    var presetIndex = 0;
                    presetIndex < presetPatterns.length;
                    presetIndex++
                  )
                    PopupMenuItem(
                      value: presetIndex,
                      child: Text(
                        'H${presetPatterns[presetIndex].level} · '
                        '${presetPatterns[presetIndex].name}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onSelected: (presetIndex) => setState(() {
                  level.applyPreset(presetPatterns[presetIndex]);
                  _invalidateAnalysis();
                }),
              ),
            ),
            onChanged: (_) => setState(() {
              level.presetName = null;
              _invalidateAnalysis();
            }),
          ),
        ],
      ),
    );
  }

  bool _shouldAcceptDroppedFiles(String label) {
    if (label.contains('输出') || label.contains('保存')) return false;
    return label.contains('文件') ||
        label.contains('图片') ||
        label.toUpperCase().contains('EPUB') ||
        label.toUpperCase().contains('TXT');
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
          final isSelected = _levels.any((level) => level.presetName == name);

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
                    if (idx >= 0 && !isSelected) {
                      setState(() {
                        if (_levels.length == 1 &&
                            _levels.first.pattern.isEmpty) {
                          _levels.first.applyPreset(presetPatterns[idx]);
                        } else if (_levels.length < 15) {
                          _levels.add(
                            LevelConfig.fromPreset(presetPatterns[idx]),
                          );
                        }
                        _invalidateAnalysis();
                      });
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      children: [
        // ---- 文件信息区 ----
        _buildSectionLabel(theme, cs, Icons.folder_open, '文件信息'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          child: Column(
            children: [
              _buildFilePickerRow(
                icon: Icons.description,
                label: 'TXT 文件',
                value: _txtPath.isNotEmpty ? p.basename(_txtPath) : '',
                hint: '点击选择 TXT 文件',
                onTap: _loading ? () {} : _pickTxt,
                isComplete: _txtPath.isNotEmpty,
              ),
              const SizedBox(height: 10),
              _buildResponsivePair(
                _buildTextField(
                  label: '书名',
                  value: _title,
                  hint: '输入书名（留空则使用原文件名）',
                  icon: Icons.book,
                  onChanged: _updateTitle,
                ),
                _buildTextField(
                  label: '作者',
                  value: _author,
                  hint: '输入作者（可选）',
                  icon: Icons.person,
                  onChanged: _updateAuthor,
                ),
              ),
              const SizedBox(height: 10),
              _buildFilePickerRow(
                icon: Icons.folder_open,
                label: '输出路径',
                value: _outputPath.isNotEmpty ? _truncatePath(_outputPath) : '',
                hint: '点击选择 EPUB 保存位置',
                onTap: _loading ? () {} : _pickOutput,
                isComplete: _outputPath.isNotEmpty,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ---- 图片设置 ----
        _buildSectionLabel(theme, cs, Icons.collections_outlined, '图片设置'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImagePickerWithClear(
                label: '封面图片',
                path: _coverPath,
                hint: '可选，用于普通封面页',
                onPick: _pickCover,
                onClear: () => setState(() => _coverPath = ''),
              ),
              const Divider(height: 24),
              _buildFeatureToggle(
                icon: Icons.crop_portrait,
                title: '全屏首页',
                subtitle: '使用独立图片作为阅读顺序第一页',
                value: _addFullScreenCover,
                onChanged: (value) =>
                    setState(() => _addFullScreenCover = value),
              ),
              if (_addFullScreenCover) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImagePickerWithClear(
                        label: '首页图片',
                        path: _fullScreenCoverImagePath,
                        hint:
                            _fullScreenCoverStyle == FullScreenCoverStyle.yuewei
                            ? '1080×2400 · PNG/JPG'
                            : '1536×2048 · PNG/JPG',
                        onPick: _pickFullScreenCoverImage,
                        onClear: () =>
                            setState(() => _fullScreenCoverImagePath = ''),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '模板',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          _buildChip(
                            '阅微 1080×2400',
                            _fullScreenCoverStyle ==
                                FullScreenCoverStyle.yuewei,
                            (_) => setState(
                              () => _fullScreenCoverStyle =
                                  FullScreenCoverStyle.yuewei,
                            ),
                          ),
                          _buildChip(
                            'Kindle 1536×2048',
                            _fullScreenCoverStyle ==
                                FullScreenCoverStyle.kindle,
                            (_) => setState(
                              () => _fullScreenCoverStyle =
                                  FullScreenCoverStyle.kindle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _headerImagePath.isNotEmpty
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.panorama_outlined,
                      size: 18,
                      color: _headerImagePath.isNotEmpty
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '章节头图',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '可选，在每个章节标题前显示',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImagePickerWithClear(
                      label: '头图图片',
                      path: _headerImagePath,
                      hint: '选择 PNG/JPG 图片',
                      onPick: _pickHeaderImage,
                      onClear: () => setState(() => _headerImagePath = ''),
                    ),
                    if (_headerImagePath.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '样式',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          _buildChip(
                            '阅微通栏',
                            _headerImageStyle == ChapterHeaderImageStyle.yuewei,
                            (_) => setState(
                              () => _headerImageStyle =
                                  ChapterHeaderImageStyle.yuewei,
                            ),
                          ),
                          _buildChip(
                            'Kindle 越界',
                            _headerImageStyle == ChapterHeaderImageStyle.kindle,
                            (_) => setState(
                              () => _headerImageStyle =
                                  ChapterHeaderImageStyle.kindle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ---- 章节分割区（多级标题）----
        Row(
          children: [
            _buildSectionLabel(theme, cs, Icons.content_cut, '章节分割'),
            const Spacer(),
            // 添加级别按钮
            if (_levels.length < 15)
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加规则', style: TextStyle(fontSize: 12)),
                onPressed: _loading
                    ? null
                    : () => setState(() {
                        _levels.add(
                          LevelConfig(
                            pattern: '',
                            level: (_levels.last.level + 1).clamp(1, 6),
                          ),
                        );
                        _invalidateAnalysis();
                      }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),

        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '规则从上到下执行，同一行只采用首个匹配；取消“分割”会保留标题样式但不新建页面',
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
              (v) => setState(() {
                _removeEmptyLines = v;
                _invalidateAnalysis();
              }),
            ),
            _buildChip(
              '修正缩进',
              _fixIndent,
              (v) => setState(() {
                _fixIndent = v;
                _invalidateAnalysis();
              }),
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

    final pageCount = _countAllChapters(_chapters);
    final totalWords = _sumWords(_chapters);
    final activeTitleCount =
        _chapterAnalysis?.matches.where((match) => !match.ignored).length ?? 0;
    final categoryCounts = <int, int>{};
    for (final match
        in _chapterAnalysis?.matches ?? const <ChapterTitleMatch>[]) {
      categoryCounts.update(
        match.ruleIndex,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    for (final entry in _disabledRuleLines.entries) {
      categoryCounts[entry.key] = entry.value.length;
    }
    final categoryIndexes = categoryCounts.keys.toList()..sort();

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
                '$pageCount 个页面',
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
              if (_chapterAnalysis != null) ...[
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
                    '$activeTitleCount 个标题',
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
        if (_chapterAnalysis != null && categoryIndexes.isNotEmpty)
          ExpansionTile(
            dense: true,
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('检查识别标题', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              '可整类关闭目录规则，也可逐条排除误识别',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final ruleIndex in categoryIndexes)
                        FilterChip(
                          selected: !_disabledRuleLines.containsKey(ruleIndex),
                          showCheckmark: true,
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${_ruleCategoryLabel(ruleIndex)} '
                            '(${categoryCounts[ruleIndex]})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onSelected: _loading
                              ? null
                              : (enabled) =>
                                    _toggleRuleCategory(ruleIndex, enabled),
                        ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              if (_chapterAnalysis!.matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '当前所有识别标题类型均已关闭',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _chapterAnalysis!.matches.length,
                    itemBuilder: (context, index) {
                      final match = _chapterAnalysis!.matches[index];
                      return CheckboxListTile(
                        dense: false,
                        isThreeLine: true,
                        visualDensity: VisualDensity.compact,
                        value: !match.ignored,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _loading
                            ? null
                            : (value) =>
                                  _toggleTitleMatch(match, value ?? true),
                        title: Text(
                          match.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: match.ignored
                                ? TextDecoration.lineThrough
                                : null,
                            color: match.title.length > 30 ? cs.error : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '第 ${match.lineIndex + 1} 行 · H${match.level} · '
                              '${match.split ? '分割页面' : '页内标题'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            _buildRuleMatchDetails(match.ruleIndex),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${chapter.wordCount} 字 · H${chapter.level}'
                  '${chapter.sourceLineIndex == null ? '' : ' · 第 ${chapter.sourceLineIndex! + 1} 行'}',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
                _buildRuleMatchDetails(chapter.matchedRuleIndex),
              ],
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
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${chapter.wordCount} 字 · H${chapter.level}'
                '${chapter.sourceLineIndex == null ? '' : ' · 第 ${chapter.sourceLineIndex! + 1} 行'}',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              _buildRuleMatchDetails(chapter.matchedRuleIndex),
            ],
          ),
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
                        '导入 TXT → 自动识别 → 检查分章 → 生成 EPUB',
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
                  Tab(text: '1  导入与规则'),
                  Tab(text: '2  检查与生成'),
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
