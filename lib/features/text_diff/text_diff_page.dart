import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/big5.dart' as big5;
import 'package:enough_convert/gbk.dart' as gbk;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/background_task.dart';
import '../../core/encoding_detector.dart';
import '../../core/file_service.dart';
import '../../core/theme.dart';
import '../../shared/providers/toast_provider.dart';
import '../epub_tools/epub_tool_widgets.dart';
import 'diff_engine.dart';
import 'text_diff_controller.dart';

/// 文本对比页面
///
/// 双栏并排对比两个文本文件：差异高亮（行级 + 行内字符级）、同步滚动、
/// 差异导航、忽略选项、行编辑与左右互拷、正则查找替换、编码保存。
class TextDiffPage extends StatefulWidget {
  const TextDiffPage({super.key});

  @override
  State<TextDiffPage> createState() => _TextDiffPageState();
}

class _TextDiffPageState extends State<TextDiffPage> {
  // ==================== 常量 ====================

  static const String _monoFamily = 'monospace';
  static const double _lineHeight = 1.5;

  /// 窄屏（移动端）布局断点：小于该宽度时切换为紧凑布局
  static const double _narrowBreakpoint = 640;

  // 差异色（亮色）
  static const _delBg = Color(0xFFF7E3E1);
  static const _insBg = Color(0xFFE5F0E2);
  static const _repBg = Color(0xFFF8EDD8);
  static const _inlineDel = Color(0xFFE3BDB8);
  static const _inlineIns = Color(0xFFC2DABF);
  // 差异色（暗色）
  static const _delBgDark = Color(0xFF3B2624);
  static const _insBgDark = Color(0xFF233128);
  static const _repBgDark = Color(0xFF3A311F);
  static const _inlineDelDark = Color(0xFF6E4A45);
  static const _inlineInsDark = Color(0xFF46624B);

  // ==================== 状态 ====================

  final TextDiffController _controller = TextDiffController();
  final ScrollController _leftScroll = ScrollController();
  final ScrollController _rightScroll = ScrollController();
  bool _syncing = false;

  /// 屏幕宽度（build 时刷新，用于窄屏紧凑布局）
  double _screenWidth = 0;

  bool get _isNarrow => _screenWidth < _narrowBreakpoint;

  /// 文本字号（窄屏略小，单行显示更多字符）
  double get _fontSize => _isNarrow ? 11.5 : 12.5;

  /// 行上下内边距
  double get _rowVPadding => _isNarrow ? 2 : 3;

  /// 行号列宽
  double get _lineNoWidth => _isNarrow ? 32 : 40;

  /// 每行高度（左右取最大换行数，保证两栏同步滚动不错位）
  List<double> _rowHeights = const [];

  /// 行偏移前缀和（跳转用）
  List<double> _rowOffsets = const [];

  /// 上次计算行高的列宽（宽度变化时重算）
  double _lastColumnWidth = 0;

  /// 上次参与行高计算的结果（结果变化时重算）
  List<DiffRow>? _lastRowHeightResult;

  /// 文件读取中（后台 Isolate，避免大文件卡 UI）
  bool _fileLoading = false;

  String _leftPath = '';
  String _rightPath = '';
  String _leftEncoding = '';
  String _rightEncoding = '';

  // 查找替换
  bool _showFind = false;
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  bool _findRegex = false;
  String _findSide = '两侧';
  List<_FindMatch> _findMatches = [];
  int _currentMatch = -1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _leftScroll.addListener(_onLeftScroll);
    _rightScroll.addListener(_onRightScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _leftScroll.dispose();
    _rightScroll.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _rebuildFindMatches();
  }

  // ==================== 同步滚动 ====================

  void _onLeftScroll() => _syncScroll(_leftScroll, _rightScroll);

  void _onRightScroll() => _syncScroll(_rightScroll, _leftScroll);

  void _syncScroll(ScrollController source, ScrollController target) {
    if (_syncing || !source.hasClients || !target.hasClients) return;
    _syncing = true;
    target.jumpTo(
      source.offset.clamp(0.0, target.position.maxScrollExtent),
    );
    _syncing = false;
  }

  /// 两栏都滚动到指定行（差异导航 / 查找导航）
  void _scrollToRow(int rowIndex) {
    if (_rowOffsets.isEmpty || rowIndex >= _rowOffsets.length) return;
    final offset = _rowOffsets[rowIndex]
        .clamp(0.0, _leftScroll.position.maxScrollExtent);
    if (_leftScroll.hasClients) _leftScroll.jumpTo(offset);
    if (_rightScroll.hasClients) _rightScroll.jumpTo(offset);
  }

  /// 按列宽计算每行高度与偏移前缀和
  ///
  /// 行高 = max(左栏换行数, 右栏换行数) × 行高 + 内边距，
  /// 保证两栏同高、同步滚动与跳转精确。
  ///
  /// 换行数用字符宽度估算（等宽字体：拉丁 1 单位、CJK/全角 2 单位），
  /// 纯算术 O(n)，避免对超大文件逐行 TextPainter 测量的性能问题。
  void _computeRowHeights(List<DiffRow> rows, double columnWidth) {
    if (columnWidth <= 0) return;
    // 行内文本实际可用宽度 = 列宽 - 行号列 - 间距(6) - 内边距(4) - 边框(1~3)；
    // 测量宽度略窄，宁可多算一行也不截断
    final textWidth =
        (columnWidth - _lineNoWidth - 14).clamp(40.0, double.infinity);
    final charsPerLine = textWidth / (_fontSize * 0.6);
    final lineUnit = _fontSize * _lineHeight + _rowVPadding * 2;
    final heights = <double>[];
    for (final row in rows) {
      final leftLines = _estimateLineCount(row.leftText ?? '', charsPerLine);
      final rightLines =
          _estimateLineCount(row.rightText ?? '', charsPerLine);
      final lines = leftLines > rightLines ? leftLines : rightLines;
      heights.add(lines < 1 ? lineUnit : lines * lineUnit);
    }
    final offsets = List<double>.filled(heights.length + 1, 0);
    for (var i = 0; i < heights.length; i++) {
      offsets[i + 1] = offsets[i] + heights[i];
    }
    _rowHeights = heights;
    _rowOffsets = offsets;
    _lastRowHeightResult = rows;
  }

  /// 估算文本在给定每行字符容量下的换行行数（保守多算一行防截断）
  static int _estimateLineCount(String text, double charsPerLine) {
    if (text.isEmpty || charsPerLine <= 0) return 0;
    var units = 0.0;
    for (final r in text.runes) {
      units += (r > 0xFF) ? 2 : 1;
    }
    var lines = (units / charsPerLine).ceil();
    if (lines < 1) lines = 1;
    return lines + 1;
  }

  /// 根据行号（左/右侧各自的行号）找统一行模型中的行
  int _rowForLine(List<DiffRow> rows,
      {required bool isLeft, required int line}) {
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      if ((isLeft ? row.leftIndex : row.rightIndex) == line) return r;
    }
    return 0;
  }

  // ==================== 差异导航 ====================

  void _goToBlock(int index) {
    final blocks = _controller.activeBlocks;
    if (blocks.isEmpty) return;
    final target = index % blocks.length;
    _controller.selectBlock(target);
    _scrollToRow(blocks[target].startRow);
  }

  void _nextBlock() => _goToBlock(_controller.selectedBlock + 1);

  void _prevBlock() {
    final count = _controller.activeBlocks.length;
    if (count == 0) return;
    final current = _controller.selectedBlock;
    _goToBlock((current <= 0 ? count : current) - 1);
  }

  // ==================== 文件读写 ====================

  Future<void> _pickSide(bool isLeft) async {
    final path = await FileService.pickTxt();
    if (path == null || !mounted) return;
    await _loadFile(path, isLeft: isLeft);
  }

  /// 后台读取文件（编码检测 + 解码在 Isolate 中执行，大文件不卡 UI）
  Future<void> _loadFile(String path, {required bool isLeft}) async {
    if (mounted) setState(() => _fileLoading = true);
    try {
      final (text, encoding) =
          await runBackgroundTask(_loadFileTask, path);
      _controller.setTexts(
        left: isLeft ? text : null,
        right: isLeft ? null : text,
      );
      if (mounted) {
        setState(() {
          if (isLeft) {
            _leftPath = path;
            _leftEncoding = encoding;
          } else {
            _rightPath = path;
            _rightEncoding = encoding;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        context.read<ToastProvider>().showError('读取文件失败：$e');
      }
    } finally {
      if (mounted) setState(() => _fileLoading = false);
    }
  }

  static (String, String) _loadFileTask(String path) {
    final encoding = EncodingDetector.detect(path);
    final text = EncodingDetector.readFile(path, encoding);
    return (text, encoding);
  }

  Future<void> _saveSide(bool isLeft) async {
    final text = isLeft ? _controller.leftText : _controller.rightText;
    final encoding = isLeft ? _leftEncoding : _rightEncoding;
    final current = isLeft ? _leftPath : _rightPath;
    final path = await FileService.saveFile(
      defaultFileName: current.isNotEmpty
          ? p.basename(current)
          : (isLeft ? '对比-A.txt' : '对比-B.txt'),
      initialDirectory: current.isNotEmpty ? p.dirname(current) : null,
    );
    if (path == null || !mounted) return;
    final toast = context.read<ToastProvider>();
    try {
      await File(path).writeAsBytes(_encodeText(text, encoding));
      toast.showSuccess('已保存：${p.basename(path)}');
    } catch (e) {
      toast.showError('保存失败：$e');
    }
  }

  List<int> _encodeText(String text, String encoding) {
    switch (encoding) {
      case 'gbk':
        return gbk.GbkEncoder().convert(text);
      case 'big5':
        return big5.Big5Encoder().convert(text);
      default:
        return utf8.encode(text);
    }
  }

  // ==================== 行编辑 ====================

  Future<void> _editRow(DiffRow row) async {
    final leftEditable = row.leftIndex != null;
    final rightEditable = row.rightIndex != null;
    if (!leftEditable && !rightEditable) return;

    final leftCtrl = TextEditingController(text: row.leftText ?? '');
    final rightCtrl = TextEditingController(text: row.rightText ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        title: Text(
          '编辑第 ${(row.leftIndex ?? row.rightIndex ?? 0) + 1} 行',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: _isNarrow ? (_screenWidth - 48) : 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leftEditable)
                TextField(
                  controller: leftCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: _monoFamily, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '左侧文本',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              if (leftEditable && rightEditable) const SizedBox(height: 10),
              if (rightEditable)
                TextField(
                  controller: rightCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: _monoFamily, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '右侧文本',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    leftCtrl.dispose();
    rightCtrl.dispose();
    if (saved != true || !mounted) return;
    if (leftEditable) {
      _controller.updateLine(row.leftIndex!, leftCtrl.text, isLeft: true);
    }
    if (rightEditable) {
      _controller.updateLine(row.rightIndex!, rightCtrl.text, isLeft: false);
    }
  }

  // ==================== 查找替换 ====================

  void _rebuildFindMatches() {
    final query = _findCtrl.text;
    if (query.isEmpty) {
      _findMatches = [];
      _currentMatch = -1;
      return;
    }
    RegExp? re;
    try {
      re = _findRegex
          ? RegExp(query, multiLine: true)
          : RegExp(RegExp.escape(query), multiLine: true);
    } catch (_) {
      _findMatches = [];
      _currentMatch = -1;
      return;
    }
    final matches = <_FindMatch>[];
    final leftLines = _controller.leftLines;
    if (_findSide != '右栏') {
      for (var i = 0; i < leftLines.length; i++) {
        for (final m in re.allMatches(leftLines[i])) {
          matches.add(
            _FindMatch(isLeft: true, lineIndex: i, start: m.start, end: m.end),
          );
        }
      }
    }
    final rightLines = _controller.rightLines;
    if (_findSide != '左栏') {
      for (var i = 0; i < rightLines.length; i++) {
        for (final m in re.allMatches(rightLines[i])) {
          matches.add(
            _FindMatch(isLeft: false, lineIndex: i, start: m.start, end: m.end),
          );
        }
      }
    }
    _findMatches = matches;
    _currentMatch = -1;
  }

  List<_FindMatch> _matchesFor(
          {required bool isLeft, required int? line}) =>
      [
        for (final m in _findMatches)
          if (m.isLeft == isLeft && m.lineIndex == line) m,
      ];

  void _goToFindMatch(int index) {
    if (_findMatches.isEmpty) return;
    final target = (index % _findMatches.length + _findMatches.length) %
        _findMatches.length;
    _currentMatch = target;
    final m = _findMatches[target];
    final rows = _controller.rows;
    if (rows.isNotEmpty) {
      _scrollToRow(
        _rowForLine(rows, isLeft: m.isLeft, line: m.lineIndex),
      );
    }
    setState(() {});
  }

  void _nextFindMatch() => _goToFindMatch(_currentMatch + 1);

  void _prevFindMatch() => _goToFindMatch(_currentMatch - 1);

  void _replaceCurrentMatch() {
    if (_findMatches.isEmpty || _currentMatch < 0) {
      context.read<ToastProvider>().showWarning('没有可替换的匹配项');
      return;
    }
    final m = _findMatches[_currentMatch];
    final lines =
        m.isLeft ? _controller.leftLines : _controller.rightLines;
    if (m.lineIndex < 0 || m.lineIndex >= lines.length) return;
    final line = lines[m.lineIndex];
    if (m.start < 0 || m.end > line.length || m.start > m.end) return;
    final newLine = line.replaceRange(m.start, m.end, _replaceCtrl.text);
    _controller.updateLine(m.lineIndex, newLine, isLeft: m.isLeft);
    _currentMatch = -1;
    context.read<ToastProvider>().showSuccess('已替换 1 处');
  }

  void _replaceAllMatches() {
    final query = _findCtrl.text;
    if (query.isEmpty) {
      context.read<ToastProvider>().showWarning('请输入查找内容');
      return;
    }
    RegExp re;
    try {
      re = _findRegex
          ? RegExp(query, multiLine: true)
          : RegExp(RegExp.escape(query), multiLine: true);
    } catch (_) {
      context.read<ToastProvider>().showError('正则表达式错误');
      return;
    }
    var count = 0;
    String? newLeft;
    String? newRight;
    if (_findSide != '右栏') {
      count += re.allMatches(_controller.leftText).length;
      newLeft = _controller.leftText.replaceAll(re, _replaceCtrl.text);
    }
    if (_findSide != '左栏') {
      count += re.allMatches(_controller.rightText).length;
      newRight = _controller.rightText.replaceAll(re, _replaceCtrl.text);
    }
    if (count == 0) {
      context.read<ToastProvider>().showWarning('没有匹配项');
      return;
    }
    _controller.setTexts(left: newLeft, right: newRight);
    context.read<ToastProvider>().showSuccess('已替换 $count 处');
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.compare_arrows_rounded,
            title: '文本对比',
            subtitle: '对比两个文本文件的差异，支持编辑、替换与正则查找',
          ),
          _buildToolbar(context),
          if (_controller.computing || _fileLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (_controller.computing)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '正在对比…已处理 ${_controller.comparedLines} / ${_controller.totalLines} 行，已完成部分实时高亮',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeTextTertiary,
                ),
              ),
            ),
          if (_showFind) _buildFindPanel(context),
          Expanded(child: _buildDiffArea(context)),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  // ==================== 工具栏 ====================

  Widget _buildToolbar(BuildContext context) {
    if (_isNarrow) return _buildCompactToolbar(context);
    final hasBlocks = _controller.activeBlocks.isNotEmpty;
    final ignored = _controller.ignoredCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () => _pickSide(true),
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            label: const Text('打开 A'),
          ),
          TextButton.icon(
            onPressed: () => _pickSide(false),
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            label: const Text('打开 B'),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: context.themeDividerLight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<WhiteSpaceMode>(
              value: _controller.options.whitespaceMode,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: const TextStyle(fontSize: 12),
              items: const [
                DropdownMenuItem(
                  value: WhiteSpaceMode.exact,
                  child: Text('不忽略空白'),
                ),
                DropdownMenuItem(
                  value: WhiteSpaceMode.trim,
                  child: Text('忽略行首尾空白'),
                ),
                DropdownMenuItem(
                  value: WhiteSpaceMode.trimEnd,
                  child: Text('忽略行尾空白'),
                ),
                DropdownMenuItem(
                  value: WhiteSpaceMode.all,
                  child: Text('忽略全部空白'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _controller.setOptions(DiffOptions(
                  whitespaceMode: v,
                  ignoreCase: _controller.options.ignoreCase,
                  ignoreBlankLines: _controller.options.ignoreBlankLines,
                  similarityThreshold:
                      _controller.options.similarityThreshold,
                ));
              },
            ),
          ),
          Tooltip(
            message: '忽略空白行差异：空白行按顺序配对显示，单侧多余的空白行不再标记为差异',
            waitDuration: const Duration(milliseconds: 400),
            child: FilterChip(
              label: const Text('忽略空白行'),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: _controller.options.ignoreBlankLines
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _controller.options.ignoreBlankLines
                    ? context.themeTextPrimary
                    : context.themeTextSecondary,
              ),
              selected: _controller.options.ignoreBlankLines,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => _controller.setOptions(DiffOptions(
                whitespaceMode: _controller.options.whitespaceMode,
                ignoreCase: _controller.options.ignoreCase,
                ignoreBlankLines: v,
                similarityThreshold: _controller.options.similarityThreshold,
              )),
            ),
          ),
          FilterChip(
            label: const Text('忽略大小写'),
            labelStyle: TextStyle(
              fontSize: 12,
              color: _controller.options.ignoreCase
                  ? context.themeTextPrimary
                  : context.themeTextSecondary,
            ),
            selected: _controller.options.ignoreCase,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => _controller.setOptions(DiffOptions(
              whitespaceMode: _controller.options.whitespaceMode,
              ignoreCase: v,
              ignoreBlankLines: _controller.options.ignoreBlankLines,
              similarityThreshold: _controller.options.similarityThreshold,
            )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: context.themeDividerLight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<int>(
              value: _controller.options.similarityThreshold,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: const TextStyle(fontSize: 12),
              items: const [
                DropdownMenuItem(value: 0, child: Text('仅精确匹配')),
                DropdownMenuItem(value: 50, child: Text('相似度 ≥ 50%')),
                DropdownMenuItem(value: 70, child: Text('相似度 ≥ 70%')),
                DropdownMenuItem(value: 90, child: Text('相似度 ≥ 90%')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _controller.setOptions(DiffOptions(
                  whitespaceMode: _controller.options.whitespaceMode,
                  ignoreCase: _controller.options.ignoreCase,
                  ignoreBlankLines: _controller.options.ignoreBlankLines,
                  similarityThreshold: v,
                ));
              },
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () => setState(() => _showFind = !_showFind),
            icon: const Icon(Icons.find_in_page_rounded, size: 17),
            label: Text(_showFind ? '收起查找' : '查找替换'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '上一处差异',
            visualDensity: VisualDensity.compact,
            onPressed: !hasBlocks ? null : _prevBlock,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          IconButton(
            tooltip: '下一处差异',
            visualDensity: VisualDensity.compact,
            onPressed: !hasBlocks ? null : _nextBlock,
            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          ),
          if (ignored)
            TextButton(
              onPressed: () => _controller.clearIgnored(),
              child: const Text('清除忽略'),
            ),
        ],
      ),
    );
  }

  /// 窄屏（移动端）紧凑工具栏：对比选项收进「选项」底部弹层，按钮更小
  Widget _buildCompactToolbar(BuildContext context) {
    final hasBlocks = _controller.activeBlocks.isNotEmpty;
    final ignored = _controller.ignoredCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () => _pickSide(true),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 12),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 15),
            label: const Text('打开A'),
          ),
          TextButton.icon(
            onPressed: () => _pickSide(false),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 12),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 15),
            label: const Text('打开B'),
          ),
          TextButton.icon(
            onPressed: _showOptionsSheet,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 12),
            ),
            icon: const Icon(Icons.tune_rounded, size: 15),
            label: const Text('选项'),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _showFind = !_showFind),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 12),
            ),
            icon: const Icon(Icons.find_in_page_rounded, size: 15),
            label: Text(_showFind ? '收起' : '查找'),
          ),
          IconButton(
            tooltip: '上一处差异',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            onPressed: !hasBlocks ? null : _prevBlock,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          IconButton(
            tooltip: '下一处差异',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            onPressed: !hasBlocks ? null : _nextBlock,
            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          ),
          if (ignored)
            TextButton(
              onPressed: () => _controller.clearIgnored(),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('清除忽略'),
            ),
        ],
      ),
    );
  }

  /// 窄屏对比选项弹层：切换立即生效
  Future<void> _showOptionsSheet() {
    final options = _controller.options;
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.themeCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '对比选项',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WhiteSpaceMode>(
                initialValue: options.whitespaceMode,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: '空白模式',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: TextStyle(fontSize: 13, color: context.themeTextPrimary),
                items: const [
                  DropdownMenuItem(
                    value: WhiteSpaceMode.exact,
                    child: Text('不忽略空白'),
                  ),
                  DropdownMenuItem(
                    value: WhiteSpaceMode.trim,
                    child: Text('忽略行首尾空白'),
                  ),
                  DropdownMenuItem(
                    value: WhiteSpaceMode.trimEnd,
                    child: Text('忽略行尾空白'),
                  ),
                  DropdownMenuItem(
                    value: WhiteSpaceMode.all,
                    child: Text('忽略全部空白'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _controller.setOptions(DiffOptions(
                    whitespaceMode: v,
                    ignoreCase: _controller.options.ignoreCase,
                    ignoreBlankLines: _controller.options.ignoreBlankLines,
                    similarityThreshold:
                        _controller.options.similarityThreshold,
                  ));
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('忽略空白行', style: TextStyle(fontSize: 13)),
                subtitle: const Text('单侧多余的空白行不显示为差异', style: TextStyle(fontSize: 11)),
                value: options.ignoreBlankLines,
                onChanged: (v) => _controller.setOptions(DiffOptions(
                  whitespaceMode: _controller.options.whitespaceMode,
                  ignoreCase: _controller.options.ignoreCase,
                  ignoreBlankLines: v,
                  similarityThreshold: _controller.options.similarityThreshold,
                )),
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('忽略大小写', style: TextStyle(fontSize: 13)),
                value: options.ignoreCase,
                onChanged: (v) => _controller.setOptions(DiffOptions(
                  whitespaceMode: _controller.options.whitespaceMode,
                  ignoreCase: v,
                  ignoreBlankLines: _controller.options.ignoreBlankLines,
                  similarityThreshold: _controller.options.similarityThreshold,
                )),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: options.similarityThreshold,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: '相似度匹配',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: TextStyle(fontSize: 13, color: context.themeTextPrimary),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('仅精确匹配')),
                  DropdownMenuItem(value: 50, child: Text('相似度 ≥ 50%')),
                  DropdownMenuItem(value: 70, child: Text('相似度 ≥ 70%')),
                  DropdownMenuItem(value: 90, child: Text('相似度 ≥ 90%')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _controller.setOptions(DiffOptions(
                    whitespaceMode: _controller.options.whitespaceMode,
                    ignoreCase: _controller.options.ignoreCase,
                    ignoreBlankLines: _controller.options.ignoreBlankLines,
                    similarityThreshold: v,
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 查找面板 ====================

  Widget _buildFindPanel(BuildContext context) {
    // 窄屏下查找/替换输入框占满可用宽度，减少换行
    final fieldWidth = _isNarrow
        ? (_screenWidth - 20 - 24).clamp(140.0, 220.0)
        : 220.0;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(_isNarrow ? 10 : 16, 0, _isNarrow ? 10 : 16, 8),
      padding: EdgeInsets.fromLTRB(_isNarrow ? 10 : 12, _isNarrow ? 8 : 10, _isNarrow ? 10 : 12, _isNarrow ? 8 : 10),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: fieldWidth,
            child: TextField(
              controller: _findCtrl,
              onChanged: (_) {
                _rebuildFindMatches();
                setState(() {});
              },
              decoration: const InputDecoration(
                labelText: '查找',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: _monoFamily, fontSize: 13),
            ),
          ),
          FilterChip(
            label: const Text('正则'),
            selected: _findRegex,
            visualDensity: VisualDensity.compact,
            onSelected: (v) {
              setState(() => _findRegex = v);
              _rebuildFindMatches();
            },
          ),
          DropdownButton<String>(
            value: _findSide,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 13),
            items: const [
              DropdownMenuItem(value: '两侧', child: Text('两侧')),
              DropdownMenuItem(value: '左栏', child: Text('左栏')),
              DropdownMenuItem(value: '右栏', child: Text('右栏')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _findSide = v);
              _rebuildFindMatches();
            },
          ),
          Text(
            '${_findMatches.length} 处匹配',
            style: TextStyle(fontSize: 12, color: context.themeTextTertiary),
          ),
          SizedBox(
            width: fieldWidth,
            child: TextField(
              controller: _replaceCtrl,
              decoration: const InputDecoration(
                labelText: '替换为（支持 \$1 捕获组）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: _monoFamily, fontSize: 13),
            ),
          ),
          TextButton.icon(
            onPressed: _findMatches.isEmpty ? null : _prevFindMatch,
            style: _isNarrow
                ? TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 12),
                  )
                : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 15),
            label: const Text('上一个'),
          ),
          TextButton.icon(
            onPressed: _findMatches.isEmpty ? null : _nextFindMatch,
            style: _isNarrow
                ? TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 12),
                  )
                : null,
            icon: const Icon(Icons.arrow_downward_rounded, size: 15),
            label: const Text('下一个'),
          ),
          TextButton.icon(
            onPressed: _findMatches.isEmpty ? null : _replaceCurrentMatch,
            style: _isNarrow
                ? TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 12),
                  )
                : null,
            icon: const Icon(Icons.swap_horiz_rounded, size: 15),
            label: const Text('替换'),
          ),
          FilledButton.tonalIcon(
            onPressed: _findMatches.isEmpty ? null : _replaceAllMatches,
            style: _isNarrow
                ? FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 12),
                  )
                : null,
            icon: const Icon(Icons.done_all_rounded, size: 15),
            label: const Text('全部替换'),
          ),
        ],
      ),
    );
  }

  // ==================== 对比区域 ====================

  Widget _buildDiffArea(BuildContext context) {
    final rows = _controller.rows;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '打开两个文本文件开始对比\n（支持 UTF-8 / GBK / Big5 编码）',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: context.themeTextTertiary,
          ),
        ),
      );
    }
    final selectedBlock = _controller.selectedBlock >= 0
        ? _controller.activeBlocks[_controller.selectedBlock]
        : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(_isNarrow ? 10 : 16, 0, _isNarrow ? 10 : 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = _isNarrow ? 6 : 10;
          final columnWidth = (constraints.maxWidth - gap) / 2;
          if (columnWidth != _lastColumnWidth ||
              !identical(_lastRowHeightResult, rows)) {
            _lastColumnWidth = columnWidth;
            _computeRowHeights(rows, columnWidth);
          }
          return Row(
            children: [
              Expanded(
                child: _buildColumn(
                  context,
                  rows: rows,
                  isLeft: true,
                  selectedBlock: selectedBlock,
                ),
              ),
              SizedBox(width: gap.toDouble()),
              Expanded(
                child: _buildColumn(
                  context,
                  rows: rows,
                  isLeft: false,
                  selectedBlock: selectedBlock,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context, {
    required List<DiffRow> rows,
    required bool isLeft,
    required DiffBlock? selectedBlock,
  }) {
    final path = isLeft ? _leftPath : _rightPath;
    final encoding = isLeft ? _leftEncoding : _rightEncoding;
    final lineCount = isLeft
        ? _controller.leftLineCount
        : _controller.rightLineCount;
    final scroll = isLeft ? _leftScroll : _rightScroll;
    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: context.themeDividerLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 列头
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.themeBgWarm,
              border: Border(
                bottom: BorderSide(color: context.themeDividerLight),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isLeft
                      ? Icons.arrow_back_rounded
                      : Icons.arrow_forward_rounded,
                  size: 14,
                  color: context.themeTextTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path.isEmpty
                        ? (isLeft ? '左侧（未打开）' : '右侧（未打开）')
                        : p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextPrimary,
                    ),
                  ),
                ),
                Text(
                  '$lineCount 行${encoding.isEmpty ? '' : ' · $encoding'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeTextTertiary,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: '保存${isLeft ? '左侧' : '右侧'}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _saveSide(isLeft),
                  icon: Icon(
                    Icons.save_outlined,
                    size: 16,
                    color: context.themeTextTertiary,
                  ),
                ),
              ],
            ),
          ),
          // 行列表
          Expanded(
            child: Scrollbar(
              controller: scroll,
              child: ListView.builder(
                controller: scroll,
                itemCount: rows.length,
                itemBuilder: (context, rowIndex) {
                  final row = rows[rowIndex];
                  final height = rowIndex < _rowHeights.length
                      ? _rowHeights[rowIndex]
                      : _fontSize * _lineHeight + _rowVPadding * 2;
                  final selected = selectedBlock != null &&
                      rowIndex >= selectedBlock.startRow &&
                      rowIndex < selectedBlock.endRow;
                  final isCurrentMatch = _findMatches.isNotEmpty &&
                      _currentMatch >= 0 &&
                      _findMatches[_currentMatch].lineIndex ==
                          (isLeft ? row.leftIndex : row.rightIndex) &&
                      _findMatches[_currentMatch].isLeft == isLeft;
                  return _buildRow(
                    context,
                    row: row,
                    isLeft: isLeft,
                    height: height,
                    selected: selected,
                    isCurrentMatch: isCurrentMatch,
                    onTap: () {
                      // 选中行所在差异块
                      if (row.isChange) {
                        final blocks = _controller.activeBlocks;
                        for (var b = 0; b < blocks.length; b++) {
                          final blk = blocks[b];
                          if (rowIndex >= blk.startRow && rowIndex < blk.endRow) {
                            _controller.selectBlock(b);
                            break;
                          }
                        }
                      } else {
                        _controller.selectBlock(-1);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required DiffRow row,
    required bool isLeft,
    required double height,
    required bool selected,
    required bool isCurrentMatch,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDarkMode;
    final lineIndex = isLeft ? row.leftIndex : row.rightIndex;
    final text = isLeft ? row.leftText : row.rightText;
    final spans = isLeft ? row.leftSpans : row.rightSpans;
    final ignored = _controller.isRowIgnored(row);

    Color? bg;
    switch (row.op) {
      case DiffOp.equal:
      case DiffOp.unknown:
        bg = null;
      case DiffOp.delete:
        bg = isLeft ? (isDark ? _delBgDark : _delBg) : null;
      case DiffOp.insert:
        bg = !isLeft ? (isDark ? _insBgDark : _insBg) : null;
      case DiffOp.replace:
        bg = isDark ? _repBgDark : _repBg;
    }
    if (ignored) {
      bg = isDark
          ? const Color(0xFF23262B)
          : const Color(0xFFF2F3F5);
    }
    if (row.op == DiffOp.unknown) {
      // 未对比区域：中性底色 + 分隔线，弱化显示
      bg = isDark ? const Color(0xFF1E2126) : const Color(0xFFF4F5F7);
    }

    final inlineColor = (row.op == DiffOp.replace)
        ? (isLeft
            ? (isDark ? _inlineDelDark : _inlineDel)
            : (isDark ? _inlineInsDark : _inlineIns))
        : null;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.only(
          left: 4,
          top: _rowVPadding,
          bottom: _rowVPadding,
        ),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            left: BorderSide(
              width: selected ? 3 : 1,
              color: selected
                  ? context.themeAccent
                  : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _lineNoWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  lineIndex == null ? '' : '${lineIndex + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: _isNarrow ? 10 : 10.5,
                    color: ignored
                        ? context.themeTextTertiary
                        : const Color(0xFF9AA0A6),
                  ),
                ),
              ),
            ),
            SizedBox(width: _isNarrow ? 4 : 6),
            Expanded(
              child: RichText(
                softWrap: true,
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: _monoFamily,
                    fontSize: _fontSize,
                    height: _lineHeight,
                    color: ignored
                        ? context.themeTextTertiary
                        : row.op == DiffOp.unknown
                            ? context.themeTextSecondary
                            : context.themeTextPrimary,
                  ),
                  children: _buildRowSpans(
                    context,
                    text ?? '',
                    row.op == DiffOp.unknown ? null : spans,
                    _matchesFor(isLeft: isLeft, line: lineIndex),
                    isCurrentMatch: isCurrentMatch,
                    inlineColor:
                        row.op == DiffOp.unknown ? null : inlineColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 组合行内差异片段与查找匹配高亮
  List<InlineSpan> _buildRowSpans(
    BuildContext context,
    String text,
    List<CharSpan>? diffSpans,
    List<_FindMatch> matches,
    {required bool isCurrentMatch,
    required Color? inlineColor}) {
    if (text.isEmpty) return const [];
    final segments = <({String text, bool changed})>[];
    if (diffSpans == null || diffSpans.isEmpty) {
      segments.add((text: text, changed: false));
    } else {
      for (final s in diffSpans) {
        segments.add((text: s.text, changed: s.changed));
      }
    }
    final out = <InlineSpan>[];
    var offset = 0;
    for (final seg in segments) {
      final segStart = offset;
      final segEnd = offset + seg.text.length;
      var pos = segStart;
      for (final m in matches) {
        if (m.end <= segStart || m.start >= segEnd) continue;
        final s = m.start < segStart ? segStart : m.start;
        final e = m.end > segEnd ? segEnd : m.end;
        if (s > pos) {
          out.add(_span(seg.text.substring(pos - segStart, s - segStart),
              seg.changed, false, inlineColor: inlineColor));
        }
        out.add(_span(seg.text.substring(s - segStart, e - segStart),
            seg.changed, true,
            inlineColor: inlineColor, isCurrentMatch: isCurrentMatch));
        pos = e;
      }
      if (pos < segEnd) {
        out.add(_span(seg.text.substring(pos - segStart), seg.changed, false,
            inlineColor: inlineColor));
      }
      offset = segEnd;
    }
    return out;
  }

  InlineSpan _span(
    String text,
    bool changed,
    bool matched, {
    Color? inlineColor,
    bool isCurrentMatch = false,
  }) {
    TextStyle? style;
    if (changed) {
      style = TextStyle(backgroundColor: inlineColor);
    }
    if (matched) {
      style = (style ?? const TextStyle()).copyWith(
        backgroundColor: const Color(0xFFB3D4F0),
        decoration: TextDecoration.underline,
        decorationColor: const Color(0xFF2E7AB8),
      );
      if (isCurrentMatch) {
        style = style.copyWith(
          backgroundColor: const Color(0xFFFFC857),
          fontWeight: FontWeight.w700,
        );
      }
    }
    return TextSpan(text: text, style: style);
  }

  // ==================== 底部操作栏 ====================

  Widget _buildBottomBar(BuildContext context) {
    final rows = _controller.rows;
    if (rows.isEmpty) {
      return const SizedBox(height: 12);
    }
    final selected = _controller.selectedBlock;
    final compact = _isNarrow;
    if (selected < 0) {
      return Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 4, compact ? 10 : 16, 8),
        child: Text(
          '点击差异行或使用上下箭头查看差异点',
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            color: context.themeTextTertiary,
          ),
        ),
      );
    }
    final btnStyle = compact
        ? TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(fontSize: 12),
          )
        : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 4, compact ? 10 : 16, 8),
        child: Wrap(
          spacing: compact ? 4 : 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () {
                final block = _controller.activeBlocks[selected];
                _editRow(_controller.rows[block.startRow]);
              },
              style: btnStyle,
              icon: Icon(Icons.edit_outlined, size: compact ? 15 : 16),
              label: const Text('编辑该差异'),
            ),
            TextButton.icon(
              onPressed: () =>
                  _controller.copyBlock(selected, toLeft: false),
              style: btnStyle,
              icon: Icon(Icons.arrow_back_rounded, size: compact ? 15 : 16),
              label: const Text('复制左 → 右'),
            ),
            TextButton.icon(
              onPressed: () => _controller.copyBlock(selected, toLeft: true),
              style: btnStyle,
              icon: Icon(Icons.arrow_forward_rounded, size: compact ? 15 : 16),
              label: const Text('复制右 → 左'),
            ),
            TextButton.icon(
              onPressed: () => _controller.ignoreSelectedBlock(),
              style: btnStyle,
              icon: Icon(Icons.visibility_off_outlined, size: compact ? 15 : 16),
              label: const Text('忽略该差异'),
            ),
            TextButton(
              onPressed: () => _controller.selectBlock(-1),
              style: btnStyle,
              child: const Text('取消选择'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 查找匹配（行内区间）
class _FindMatch {
  final bool isLeft;
  final int lineIndex;
  final int start;
  final int end;

  const _FindMatch({
    required this.isLeft,
    required this.lineIndex,
    required this.start,
    required this.end,
  });
}
