import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/core/file_service.dart';
import 'package:epub_gadget/features/epub_tools/epub_tool_widgets.dart';
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
  ChapterHeaderImageStyle _headerImageStyle = ChapterHeaderImageStyle.banner;
  bool _addFullScreenCover = false;
  FullScreenCoverStyle _fullScreenCoverStyle = FullScreenCoverStyle.yuewei;

  /// 正文样式
  BodyFontFamily _bodyFont = BodyFontFamily.serif;
  BodyFontSize _bodyFontSize = BodyFontSize.standard;
  LineSpacing _lineSpacing = LineSpacing.standard;
  ParagraphIndent _paragraphIndent = ParagraphIndent.twoChars;

  /// 去除空行（并入排版样式）
  bool _removeEmptyLines = true;

  /// 标题样式
  TitleAlign _titleAlign = TitleAlign.center;
  TitleDecoration _titleDecoration = TitleDecoration.none;
  TitleLayout _titleLayout = TitleLayout.single;
  TitleImageSpacing _titleImageSpacing = TitleImageSpacing.standard;

  /// 装饰颜色（分隔线/竖线/色块，留空用默认色）
  String _titleAccentColor = '';

  /// 双行红章颜色（序号 / 名称）
  String _chapterNumberColor = '#413245';
  String _chapterNameColor = '#C2181E';

  /// 多级标题配置（至少 1 条，最多 15 条）
  final List<LevelConfig> _levels = [
    LevelConfig.fromPreset(presetPatterns.first),
  ];

  bool _loading = false;
  bool _scanning = false;
  List<Chapter> _chapters = [];
  ChapterSplitAnalysis? _chapterAnalysis;
  String _preparedText = '';
  final Set<int> _ignoredTitleLines = {};
  final Map<int, Set<int>> _disabledRuleLines = {};
  List<Map<String, dynamic>> _scanResults = [];
  final OutputLogController _logController = OutputLogController();

  /// 设置页滚动控制器（预览区域滚轮事件转发给页面滚动）
  final ScrollController _settingsScrollController = ScrollController();

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
    _settingsScrollController.dispose();
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
    if (!mounted) return;
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
    if (path == null || !mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;
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
    if (path == null || !mounted) return;
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
        fixIndent: _paragraphIndent == ParagraphIndent.twoChars,
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
          // 仅当用户尚未自定义规则时才替换；否则保留现有配置并追加新预设。
          // 直接 clear 会静默丢弃用户手工配好的正则/分页开关/级别。
          final hasCustomRules = _levels.any(
            (l) =>
                l.presetName == null &&
                l.pattern.isNotEmpty &&
                l.pattern != r'^第.{1,20}章.{0,30}$',
          );
          if (!hasCustomRules) {
            for (final level in _levels) {
              level.dispose();
            }
            _levels
              ..clear()
              ..addAll(selectedPresets.map(LevelConfig.fromPreset));
          } else {
            // 追加不重复的预设规则(按正则去重)
            final existingPatterns =
                _levels.map((l) => l.pattern).toSet();
            for (final preset in selectedPresets) {
              if (!existingPatterns.contains(preset.pattern) &&
                  _levels.length < 15) {
                _levels.add(LevelConfig.fromPreset(preset));
                existingPatterns.add(preset.pattern);
              }
            }
          }
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
      fixIndent: _paragraphIndent == ParagraphIndent.twoChars,
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
        fixIndent: _paragraphIndent == ParagraphIndent.twoChars,
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
          if (mounted) {
            _logController.append('ERROR: 未选择输出路径，生成取消');
            context.read<ToastProvider>().showWarning('未选择输出路径，生成已取消');
          }
          return;
        }
        if (!mounted) return;
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
        bodyFont: _bodyFont,
        bodyFontSize: _bodyFontSize,
        lineSpacing: _lineSpacing,
        paragraphIndent: _paragraphIndent,
        titleAlign: _titleAlign,
        titleDecoration: _titleDecoration,
        titleLayout: _titleLayout,
        titleImageSpacing: _titleImageSpacing,
        titleAccentColor: _titleAccentColor,
        chapterNumberColor: _chapterNumberColor,
        chapterNameColor: _chapterNameColor,
      );
      if (!mounted) return;

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
      if (mounted) {
        _logController.append('ERROR: 生成失败：$e');
        context.read<ToastProvider>().showError('生成失败：$e');
      }
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
          color: context.themeCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isComplete
                ? context.themeWarm.withValues(alpha: 0.55)
                : context.themeDividerLight,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isComplete
                  ? context.themeWarm
                  : context.themeTextTertiary,
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
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value
                ? context.themeWarmLight
                : context.themeAccentLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: value
                ? context.themeAccent
                : context.themeTextTertiary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeTextTertiary,
                ),
              ),
            ],
          ),
        ),
        TDSwitch(
          isOn: value,
          onChanged: _loading
              ? null
              : (v) {
                  onChanged(v);
                  return true;
                },
          trackOnColor: context.themeWarm,
          trackOffColor: context.themeDividerLight,
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

  /// 样式选项行：左侧小标签 + 右侧 chips（独立一行）
  Widget _buildStyleRow(String label, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
        ],
      ),
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
        Icon(icon, size: 16, color: context.themeAccent),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: context.themeTextPrimary,
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
      controller: _settingsScrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        6,
        16,
        MediaQuery.sizeOf(context).width >= 720 ? 24 : 100,
      ),
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
                onTap: (_loading || _scanning) ? () {} : _pickTxt,
                isComplete: _txtPath.isNotEmpty,
              ),
              const SizedBox(height: 10),
              _buildResponsivePair(
                _LabeledTextField(
                  label: '书名',
                  value: _title,
                  hint: '输入书名（留空则使用原文件名）',
                  icon: Icons.book,
                  onChanged: _updateTitle,
                ),
                _LabeledTextField(
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
                            ? '推荐 1080×2400 · 任意尺寸均可 · PNG/JPG'
                            : '推荐 1536×2048 · 任意尺寸均可 · PNG/JPG',
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
                            '模板（仅推荐，不强制）',
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
                      hint: '选择 PNG/JPG 图片，模板在「排版样式」中预览',
                      onPick: _pickHeaderImage,
                      onClear: () => setState(() => _headerImagePath = ''),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ---- 正文与标题样式 ----
        _buildSectionLabel(theme, cs, Icons.text_format, '排版样式'),
        const SizedBox(height: 8),
        _buildSettingsCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // PC/平板：左侧预览、右侧样式选项；窄屏纵向排列
              final wide = constraints.maxWidth >= 560;

              final preview = _TypographyPreview(
                font: _bodyFont,
                fontSize: _bodyFontSize,
                lineSpacing: _lineSpacing,
                indent: _paragraphIndent,
                titleAlign: _titleAlign,
                titleDecoration: _titleDecoration,
                titleLayout: _titleLayout,
                titleImageSpacing: _titleImageSpacing,
                titleAccentColor: _titleAccentColor,
                chapterNumberColor: _chapterNumberColor,
                chapterNameColor: _chapterNameColor,
                headerImagePath: _headerImagePath,
                headerImageStyle: _headerImageStyle,
                wheelScrollController: _settingsScrollController,
              );

              final options = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头图模板选择（真实图片缩略）
                  if (_headerImagePath.isNotEmpty) ...[
                    Text(
                      '头图模板',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.themeTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        const cardWidth = 104.0;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: 8,
                          children: [
                            for (final entry in _headerStyleTemplates.entries)
                              SizedBox(
                                width: cardWidth,
                                child: _HeaderStylePreviewCard(
                                  label: entry.value,
                                  style: entry.key,
                                  imagePath: _headerImagePath,
                                  selected: _headerImageStyle == entry.key,
                                  onTap: () => setState(
                                    () => _headerImageStyle = entry.key,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    '正文',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStyleRow('字体', [
                    _buildChip(
                      '宋体（衬线）',
                      _bodyFont == BodyFontFamily.serif,
                      (_) => setState(() => _bodyFont = BodyFontFamily.serif),
                    ),
                    _buildChip(
                      '黑体（无衬线）',
                      _bodyFont == BodyFontFamily.sans,
                      (_) => setState(() => _bodyFont = BodyFontFamily.sans),
                    ),
                    _buildChip(
                      '楷体',
                      _bodyFont == BodyFontFamily.kaiti,
                      (_) => setState(() => _bodyFont = BodyFontFamily.kaiti),
                    ),
                  ]),
                  _buildStyleRow('字号', [
                    _buildChip(
                      '小',
                      _bodyFontSize == BodyFontSize.small,
                      (_) => setState(() => _bodyFontSize = BodyFontSize.small),
                    ),
                    _buildChip(
                      '标准',
                      _bodyFontSize == BodyFontSize.standard,
                      (_) => setState(
                        () => _bodyFontSize = BodyFontSize.standard,
                      ),
                    ),
                    _buildChip(
                      '大',
                      _bodyFontSize == BodyFontSize.large,
                      (_) => setState(() => _bodyFontSize = BodyFontSize.large),
                    ),
                  ]),
                  _buildStyleRow('行距', [
                    _buildChip(
                      '紧凑',
                      _lineSpacing == LineSpacing.compact,
                      (_) => setState(() => _lineSpacing = LineSpacing.compact),
                    ),
                    _buildChip(
                      '标准',
                      _lineSpacing == LineSpacing.standard,
                      (_) => setState(() => _lineSpacing = LineSpacing.standard),
                    ),
                    _buildChip(
                      '宽松',
                      _lineSpacing == LineSpacing.loose,
                      (_) => setState(() => _lineSpacing = LineSpacing.loose),
                    ),
                  ]),
                  _buildStyleRow('缩进', [
                    _buildChip(
                      '段首缩进',
                      _paragraphIndent == ParagraphIndent.twoChars,
                      (_) => setState(
                        () => _paragraphIndent = ParagraphIndent.twoChars,
                      ),
                    ),
                    _buildChip(
                      '无缩进',
                      _paragraphIndent == ParagraphIndent.none,
                      (_) => setState(
                        () => _paragraphIndent = ParagraphIndent.none,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '去除空行',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: context.themeTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '合并连续空行，段落之间不留空行',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.themeTextTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TDSwitch(
                        isOn: _removeEmptyLines,
                        onChanged: (v) {
                          setState(() => _removeEmptyLines = v);
                          _invalidateAnalysis();
                          return true;
                        },
                        trackOnColor: context.themeWarm,
                        trackOffColor: context.themeDividerLight,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    '标题',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStyleRow('对齐', [
                    _buildChip(
                      '居中',
                      _titleAlign == TitleAlign.center,
                      (_) => setState(() => _titleAlign = TitleAlign.center),
                    ),
                    _buildChip(
                      '左对齐',
                      _titleAlign == TitleAlign.left,
                      (_) => setState(() => _titleAlign = TitleAlign.left),
                    ),
                    _buildChip(
                      '右对齐',
                      _titleAlign == TitleAlign.right,
                      (_) => setState(() => _titleAlign = TitleAlign.right),
                    ),
                  ]),
                  _buildStyleRow('装饰', [
                    _buildChip(
                      '无',
                      _titleDecoration == TitleDecoration.none,
                      (_) => setState(
                        () => _titleDecoration = TitleDecoration.none,
                      ),
                    ),
                    _buildChip(
                      '分隔线',
                      _titleDecoration == TitleDecoration.divider,
                      (_) => setState(
                        () => _titleDecoration = TitleDecoration.divider,
                      ),
                    ),
                    _buildChip(
                      '左竖线',
                      _titleDecoration == TitleDecoration.leftBar,
                      (_) => setState(
                        () => _titleDecoration = TitleDecoration.leftBar,
                      ),
                    ),
                    _buildChip(
                      '标签色块',
                      _titleDecoration == TitleDecoration.boxed,
                      (_) => setState(
                        () => _titleDecoration = TitleDecoration.boxed,
                      ),
                    ),
                    _buildChip(
                      '橙右竖线',
                      _titleDecoration == TitleDecoration.orangeRight,
                      (_) => setState(
                        () => _titleDecoration = TitleDecoration.orangeRight,
                      ),
                    ),
                    _buildChip(
                      '上下边框',
                      _titleDecoration == TitleDecoration.topBottomLine,
                      (_) => setState(
                        () => _titleDecoration =
                            TitleDecoration.topBottomLine,
                      ),
                    ),
                  ]),
                  if (_titleDecoration != TitleDecoration.none)
                    _buildStyleRow('装饰颜色', [
                      for (final (label, color) in [
                        ('默认', ''),
                        ('红', '#C2181E'),
                        ('橙', '#FE9803'),
                        ('青', '#478686'),
                        ('暗金', '#91531D'),
                        ('墨', '#1A1A1A'),
                      ])
                        _buildChip(
                          label,
                          _titleAccentColor == color,
                          (_) => setState(() => _titleAccentColor = color),
                        ),
                    ]),
                  _buildStyleRow('布局', [
                    _buildChip(
                      '单行',
                      _titleLayout == TitleLayout.single,
                      (_) => setState(() => _titleLayout = TitleLayout.single),
                    ),
                    _buildChip(
                      '双行红章',
                      _titleLayout == TitleLayout.split,
                      (_) => setState(() => _titleLayout = TitleLayout.split),
                    ),
                  ]),
                  if (_titleLayout == TitleLayout.split) ...[
                    _buildStyleRow('序号颜色', [
                      for (final (label, color) in [
                        ('暗灰', '#413245'),
                        ('红', '#C2181E'),
                        ('青', '#478686'),
                        ('墨', '#1A1A1A'),
                        ('蓝', '#1F4A92'),
                      ])
                        _buildChip(
                          label,
                          _chapterNumberColor == color,
                          (_) => setState(() => _chapterNumberColor = color),
                        ),
                    ]),
                    _buildStyleRow('名称颜色', [
                      for (final (label, color) in [
                        ('红', '#C2181E'),
                        ('橙', '#FE9803'),
                        ('青', '#478686'),
                        ('暗金', '#91531D'),
                        ('墨', '#1A1A1A'),
                        ('蓝', '#1F4A92'),
                      ])
                        _buildChip(
                          label,
                          _chapterNameColor == color,
                          (_) => setState(() => _chapterNameColor = color),
                        ),
                    ]),
                  ],
                  if (_headerImagePath.isNotEmpty)
                    _buildStyleRow('头图间距', [
                      _buildChip(
                        '紧凑',
                        _titleImageSpacing == TitleImageSpacing.compact,
                        (_) => setState(
                          () => _titleImageSpacing = TitleImageSpacing.compact,
                        ),
                      ),
                      _buildChip(
                        '标准',
                        _titleImageSpacing == TitleImageSpacing.standard,
                        (_) => setState(
                          () => _titleImageSpacing = TitleImageSpacing.standard,
                        ),
                      ),
                      _buildChip(
                        '宽松',
                        _titleImageSpacing == TitleImageSpacing.loose,
                        (_) => setState(
                          () => _titleImageSpacing = TitleImageSpacing.loose,
                        ),
                      ),
                    ]),
                ],
              );

              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(height: 14),
                    options,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧预览（按比例分配，手机阅读比例）
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '预览',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.themeTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        preview,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 右侧样式选项
                  Expanded(flex: 3, child: options),
                ],
              );
            },
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
    return Scaffold(
      body: Column(
        children: [
          // 页头（与其他操作页一致：标题 + 说明）
          buildToolHeader(
            context,
            icon: Icons.auto_stories,
            title: 'TXT 转 EPUB',
            subtitle: '导入 TXT → 自动识别章节 → 检查分章 → 生成 EPUB',
          ),

          // 分段式 Tab
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: context.themeBgWarm,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: context.themeAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: context.themeTextTertiary,
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

          // 底部悬浮操作栏（与其他操作页一致的胶囊风格；桌面端右对齐限宽）
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    wide ? 24 : 16,
                    wide ? 16 : 12,
                  ),
                  child: Align(
                    alignment: wide
                        ? Alignment.bottomRight
                        : Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: wide
                          ? const BoxConstraints(maxWidth: 520)
                          : const BoxConstraints(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.themeCard,
                          borderRadius: BorderRadius.circular(AppTheme.radiusL),
                          border: Border.all(
                            color: context.themeDividerLight,
                          ),
                          boxShadow: context.themeCardShadowLight,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: BaseButton(
                                label: '预览分割',
                                icon: Icons.preview,
                                onPressed: _loading ? null : _previewSplit,
                                variant: BaseButtonVariant.secondary,
                                loading: _loading,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: BaseButton(
                                label: '生成 EPUB',
                                icon: Icons.auto_stories,
                                onPressed: _loading ? null : _generate,
                                variant: BaseButtonVariant.primary,
                                loading: _loading,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 头图模板预览 ====================

/// 头图模板名称映射
const Map<ChapterHeaderImageStyle, String> _headerStyleTemplates = {
  ChapterHeaderImageStyle.weread: '微信读书',
  ChapterHeaderImageStyle.kindle: 'Kindle 头图',
  ChapterHeaderImageStyle.center: '居中圆角',
  ChapterHeaderImageStyle.banner: '通用头图',
  ChapterHeaderImageStyle.small: '小图配标题',
};

/// 头图模板预览卡片：使用真实导入图片按模板样式渲染，选中高亮
class _HeaderStylePreviewCard extends StatelessWidget {
  final ChapterHeaderImageStyle style;
  final String label;
  final String imagePath;
  final bool selected;
  final VoidCallback onTap;

  const _HeaderStylePreviewCard({
    required this.style,
    required this.label,
    required this.imagePath,
    required this.selected,
    required this.onTap,
  });

  Widget _image(BuildContext context) {
    final fallback = Container(
      color: context.themeAccentSoft,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 18,
        color: context.themeTextTertiary,
      ),
    );
    return Image.file(
      File(imagePath),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  /// 按模板样式渲染真实图片（模拟效果）
  Widget _renderPreview(BuildContext context) {
    switch (style) {
      case ChapterHeaderImageStyle.weread:
        // 微信读书：三重出血，图片贴边显示
        return SizedBox(width: double.infinity, child: _image(context));
      case ChapterHeaderImageStyle.kindle:
        // 越界：图片比预览区宽，左右溢出（裁剪展示）
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 140,
              child: _image(context),
            ),
          ),
        );
      case ChapterHeaderImageStyle.center:
        // 居中圆角：四周留白 + 圆角
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: double.infinity, child: _image(context)),
          ),
        );
      case ChapterHeaderImageStyle.banner:
        // 顶部通栏：占满宽度置于顶部
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: double.infinity, child: _image(context)),
        );
      case ChapterHeaderImageStyle.small:
        // 小图配标题：小尺寸图 + 下方标题线
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 22,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _image(context),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 40,
              height: 2,
              decoration: BoxDecoration(
                color: context.themeDivider,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: selected
                  ? context.themeWarmLight.withValues(alpha: 0.5)
                  : context.themeCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? context.themeWarm
                    : context.themeDividerLight,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: _renderPreview(context),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? context.themeTextPrimary
                  : context.themeTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 排版样式实时预览 ====================

/// 章节页排版预览：用真实生成的 CSS 在 WebView（浏览器内核）中渲染，
/// 与 TEpub-Editor 的样式库预览方式一致；不支持 WebView 的平台
/// （Linux、测试环境）自动降级为 Flutter 模拟渲染。
class _TypographyPreview extends StatefulWidget {
  final BodyFontFamily font;
  final BodyFontSize fontSize;
  final LineSpacing lineSpacing;
  final ParagraphIndent indent;
  final TitleAlign titleAlign;
  final TitleDecoration titleDecoration;
  final TitleLayout titleLayout;
  final TitleImageSpacing titleImageSpacing;
  final String titleAccentColor;
  final String chapterNumberColor;
  final String chapterNameColor;

  /// 头图路径与模板（有头图时在标题上方按模板渲染真实图片）
  final String? headerImagePath;
  final ChapterHeaderImageStyle? headerImageStyle;

  /// 页面滚动控制器：预览区域滚轮事件转发给页面整体滚动
  final ScrollController? wheelScrollController;

  const _TypographyPreview({
    required this.font,
    required this.fontSize,
    required this.lineSpacing,
    required this.indent,
    required this.titleAlign,
    required this.titleDecoration,
    this.titleLayout = TitleLayout.single,
    this.titleImageSpacing = TitleImageSpacing.standard,
    this.titleAccentColor = '',
    this.chapterNumberColor = '#413245',
    this.chapterNameColor = '#C2181E',
    this.headerImagePath,
    this.headerImageStyle,
    this.wheelScrollController,
  });

  @override
  State<_TypographyPreview> createState() => _TypographyPreviewState();
}

class _TypographyPreviewState extends State<_TypographyPreview> {
  WebViewController? _controller;
  bool _webViewFailed = false;
  String? _lastHtml;

  /// 预览高度：按内容自适应（头图较大时不被裁切）
  double _previewHeight = 260;

  /// WebView 是否可用：桌面/移动真机可用，Linux 与测试环境降级
  bool get _webViewAvailable {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.android ||
      TargetPlatform.iOS => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    if (_webViewAvailable) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => _syncHeight()),
        );
      // 延迟到首帧渲染后加载，避免 controller 未就绪导致初始黑屏
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  @override
  void didUpdateWidget(covariant _TypographyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null && !_webViewFailed) {
      _loadPreview();
    }
  }

  /// 内容加载完成后测量文档高度，自适应预览容器
  ///
  /// 头图（base64）解码与布局需要时间，多次测量取最大值，
  /// 避免初次测量内容未完全布局导致正文被裁切。
  Future<void> _syncHeight() async {
    double maxHeight = _previewHeight;
    for (final delayMs in [0, 200, 500]) {
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (!mounted || _controller == null) return;
      try {
        final result = await _controller!.runJavaScriptReturningResult(
          'document.documentElement.scrollHeight',
        );
        final height = double.tryParse(result.toString());
        if (height != null && height > maxHeight) {
          maxHeight = height;
        }
      } catch (_) {
        // 测量失败时保持当前高度
      }
    }
    if (mounted) {
      final clamped = maxHeight.clamp(120.0, 520.0);
      if (clamped != _previewHeight) {
        setState(() => _previewHeight = clamped);
      }
    }
  }

  Future<void> _loadPreview() async {
    final html = await _buildHtml();
    if (html == _lastHtml || _controller == null) return;
    _lastHtml = html;
    if (mounted) setState(() => _previewHeight = 260);
    try {
      await _controller!.loadHtmlString(html);
    } catch (_) {
      if (mounted) setState(() => _webViewFailed = true);
    }
  }

  /// 拼接完整预览 HTML：真实生成的 CSS + 章节页结构
  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Future<String> _buildHtml() async {
    final w = widget;
    // 背景与文字颜色跟随日夜间模式(在首个 await 前取值,避免跨 async 使用 context)
    final bg = _hex(context.themeCard);
    final textColor = _hex(context.themeTextSecondary);
    final titleColor = _hex(context.themeTextPrimary);
    final css = EpubGenerator.generateCss(
      headerImageStyle: w.headerImagePath?.isNotEmpty == true
          ? w.headerImageStyle
          : null,
      bodyFont: w.font,
      bodyFontSize: w.fontSize,
      lineSpacing: w.lineSpacing,
      paragraphIndent: w.indent,
      titleAlign: w.titleAlign,
      titleDecoration: w.titleDecoration,
      titleLayout: w.titleLayout,
      titleImageSpacing: w.titleImageSpacing,
      titleAccentColor: w.titleAccentColor,
      chapterNumberColor: w.chapterNumberColor,
      chapterNameColor: w.chapterNameColor,
    );

    // 头图：转 base64 data URI 内嵌（WebView 无法直接读本地文件）
    String? headerImg;
    if (w.headerImagePath != null && w.headerImagePath!.isNotEmpty) {
      try {
        final bytes = await File(w.headerImagePath!).readAsBytes();
        final ext = w.headerImagePath!.toLowerCase().endsWith('.png')
            ? 'png'
            : 'jpeg';
        headerImg =
            'data:image/$ext;base64,${base64Encode(bytes)}';
      } catch (_) {
        headerImg = null;
      }
    }

    final headerHtml = headerImg == null
        ? ''
        : '<div class="logo"><img class="responsive-image" alt="logo" src="$headerImg"/></div>';

    // 标题：双行红章时拆分"第一章 初入江湖"
    final titleHtml = w.titleLayout == TitleLayout.split
        ? '<h1>'
            '<span class="chapter-number">第一章</span>'
            '<span class="chapter-name">初入江湖</span>'
            '</h1>'
        : '<h1>第一章  初入江湖</h1>';

    return '<!doctype html>\n'
        '<html>\n'
        '<head>\n'
        '<meta charset="utf-8"/>\n'
        '<style>'
        'html, body { margin: 0; padding: 0; overflow-x: hidden;'
        'background: $bg; color: $textColor; scrollbar-width: none; }'
        '::-webkit-scrollbar { display: none; }'
        'h1, h2, h3, h4, h5, h6 { color: $titleColor; }'
        '$css'
        '</style>\n'
        '</head>\n'
        '<body>\n'
        '$headerHtml'
        '$titleHtml\n'
        '<p>春江潮水连海平，海上明月共潮生。滟滟随波千万里，何处春江无月明。</p>\n'
        '<p>江流宛转绕芳甸，月照花林皆似霰。空里流霜不觉飞，汀上白沙看不见。</p>\n'
        '<p>江天一色无纤尘，皎皎空中孤月轮。江畔何人初见月，江月何年初照人。</p>\n'
        '<p>人生代代无穷已，江月年年望相似。不知江月待何人，但见长江送流水。</p>\n'
        '<p>白云一片去悠悠，青枫浦上不胜愁。谁家今夜扁舟子，何处相思明月楼。</p>\n'
        '</body>\n'
        '</html>';
  }

  @override
  Widget build(BuildContext context) {
    final useWebView = _controller != null && !_webViewFailed;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: useWebView
          ? AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: _previewHeight,
              // 预览区自适应高度无需自身滚动；滚轮事件转发给页面整体滚动
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final c = widget.wheelScrollController;
                    if (c != null && c.hasClients) {
                      final target = (c.offset + event.scrollDelta.dy).clamp(
                        c.position.minScrollExtent,
                        c.position.maxScrollExtent,
                      );
                      c.jumpTo(target);
                    }
                  }
                },
                child: WebViewWidget(controller: _controller!),
              ),
            )
          : _buildFallback(context),
    );
  }

  /// Flutter 模拟渲染（降级方案，视觉效果接近真实 CSS）
  Widget _buildFallback(BuildContext context) {
    final w = widget;
    final bodyFontSize = 13.0 *
        switch (w.fontSize) {
          BodyFontSize.small => 0.9,
          BodyFontSize.large => 1.1,
          BodyFontSize.standard => 1.0,
        };
    final lineHeight = switch (w.lineSpacing) {
      LineSpacing.compact => 1.5,
      LineSpacing.loose => 2.1,
      LineSpacing.standard => 1.8,
    };
    final fontFamily = w.font == BodyFontFamily.serif
        ? 'Songti SC'
        : w.font == BodyFontFamily.kaiti
        ? 'KaiTi'
        : 'PingFang SC';
    final indentText = w.indent == ParagraphIndent.twoChars ? '　　' : '';

    // 标题装饰样式（模拟，支持自定义颜色）
    final titleDecoration = _fallbackTitleDecoration(
      context,
      w.titleDecoration,
      w.titleAccentColor,
    );
    final titleAlign = switch (w.titleDecoration) {
      TitleDecoration.leftBar => TextAlign.left,
      TitleDecoration.orangeRight ||
      TitleDecoration.topBottomLine => TextAlign.right,
      _ => switch (w.titleAlign) {
          TitleAlign.center => TextAlign.center,
          TitleAlign.right => TextAlign.right,
          _ => TextAlign.left,
        },
    };

    // 标题内容：双行红章拆分为序号+名称（颜色可自定义）
    final numberColor =
        _colorFromHex(w.chapterNumberColor) ?? const Color(0xFF413245);
    final nameColor =
        _colorFromHex(w.chapterNameColor) ?? const Color(0xFFC2181E);
    final titleWidget = w.titleLayout == TitleLayout.split
        ? Column(
            crossAxisAlignment: titleAlign == TextAlign.right
                ? CrossAxisAlignment.end
                : titleAlign == TextAlign.center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                '第一章',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: fontFamily,
                  color: numberColor,
                ),
              ),
              Text(
                '初入江湖',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  fontFamily: fontFamily,
                  color: nameColor,
                ),
              ),
            ],
          )
        : Text(
            '第一章  初入江湖',
            textAlign: titleAlign,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: fontFamily,
              color: w.titleDecoration == TitleDecoration.boxed
                  ? Colors.white
                  : context.themeTextPrimary,
            ),
          );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?_buildFallbackHeader(context),
          Container(
            width: double.infinity,
            padding: titleDecoration.padding,
            decoration: titleDecoration.boxDecoration,
            child: titleWidget,
          ),
          const SizedBox(height: 10),
          for (final paragraph in const [
            '春江潮水连海平，海上明月共潮生。滟滟随波千万里，何处春江无月明。',
            '江流宛转绕芳甸，月照花林皆似霰。空里流霜不觉飞，汀上白沙看不见。',
            '江天一色无纤尘，皎皎空中孤月轮。江畔何人初见月，江月何年初照人。',
            '人生代代无穷已，江月年年望相似。不知江月待何人，但见长江送流水。',
            '白云一片去悠悠，青枫浦上不胜愁。谁家今夜扁舟子，何处相思明月楼。',
          ]) ...[
            Text(
              '$indentText$paragraph',
              style: TextStyle(
                fontSize: bodyFontSize,
                height: lineHeight,
                fontFamily: fontFamily,
                color: context.themeTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  /// 降级方案的头图渲染（按模板模拟）
  Widget? _buildFallbackHeader(BuildContext context) {
    final path = widget.headerImagePath;
    final style = widget.headerImageStyle;
    if (path == null || path.isEmpty || style == null) return null;

    final fallback = Container(
      height: 40,
      color: context.themeAccentSoft,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 18,
        color: context.themeTextTertiary,
      ),
    );
    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );

    switch (style) {
      case ChapterHeaderImageStyle.weread:
        return SizedBox(width: double.infinity, height: 56, child: image);
      case ChapterHeaderImageStyle.kindle:
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 320, height: 56, child: image),
          ),
        );
      case ChapterHeaderImageStyle.center:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: double.infinity, height: 56, child: image),
          ),
        );
      case ChapterHeaderImageStyle.banner:
        return SizedBox(width: double.infinity, height: 56, child: image);
      case ChapterHeaderImageStyle.small:
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Column(
            children: [
              SizedBox(
                width: 56,
                height: 36,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: image,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                width: 64,
                height: 2,
                decoration: BoxDecoration(
                  color: context.themeDivider,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        );
    }
  }

  /// 标题装饰的降级渲染样式（padding + boxDecoration）
  ({EdgeInsetsGeometry padding, BoxDecoration? boxDecoration})
  _fallbackTitleDecoration(
    BuildContext context,
    TitleDecoration decoration,
    String accentColor,
  ) {
    final accent = _colorFromHex(accentColor);
    switch (decoration) {
      case TitleDecoration.divider:
        return (
          padding: const EdgeInsets.only(bottom: 6),
          boxDecoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: accent ?? context.themeDivider,
                width: 1,
              ),
            ),
          ),
        );
      case TitleDecoration.leftBar:
        return (
          padding: const EdgeInsets.only(left: 8),
          boxDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accent ?? const Color(0xFFAB2524),
                width: 4,
              ),
            ),
          ),
        );
      case TitleDecoration.boxed:
        return (
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          boxDecoration: BoxDecoration(
            color: accent ?? const Color(0xFF2F2F2F),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      case TitleDecoration.orangeRight:
        return (
          padding: const EdgeInsets.only(right: 8),
          boxDecoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: accent ?? const Color(0xFFFE9803),
                width: 5,
              ),
            ),
          ),
        );
      case TitleDecoration.topBottomLine:
        return (
          padding: const EdgeInsets.symmetric(vertical: 6),
          boxDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: accent ?? context.themeDivider, width: 1),
              bottom: BorderSide(
                color: accent ?? context.themeDivider,
                width: 1,
              ),
            ),
          ),
        );
      case TitleDecoration.none:
        return (padding: EdgeInsets.zero, boxDecoration: null);
    }
  }

  /// 解析十六进制颜色字符串（#RRGGBB 或 RRGGBB），失败返回 null
  Color? _colorFromHex(String hex) {
    final raw = hex.trim().replaceFirst('#', '');
    if (raw.length != 6) return null;
    final value = int.tryParse('FF$raw', radix: 16);
    return value == null ? null : Color(value);
  }
}

/// 带标签的输入框。
///
/// 独立 State 持有 [TextEditingController] 与 [FocusNode]，避免父组件每次
/// rebuild 都重建 Controller 导致光标跳位、IME 组合状态丢失（中文输入被打断），
/// 并在 [dispose] 中释放。
class _LabeledTextField extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _LabeledTextField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  State<_LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<_LabeledTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _LabeledTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步，但用户正在输入/聚焦时不覆盖
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: (52 * MediaQuery.textScalerOf(context).scale(1.0))
              .clamp(52.0, 88.0),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
            decoration: InputDecoration(
              hintText: widget.hint,
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
            onChanged: widget.onChanged,
          ),
        ),
      ],
    );
  }
}
