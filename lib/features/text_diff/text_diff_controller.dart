import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/background_task.dart';
import 'diff_engine.dart';

/// 文本对比控制器：管理两侧文本、对比选项、差异结果与差异操作
///
/// - 小文件（≤ [syncThreshold] 行）同步计算；大文件按块（[chunkSize] 行）
///   在后台 Isolate 中**逐块渐进计算**：每完成一块立即合并到行模型并通知界面，
///   差异边算边显示，无需等待全部完成
/// - 差异操作（复制左↔右、忽略）基于统一行模型，编辑/替换后自动重算
class TextDiffController extends ChangeNotifier {
  /// 行数超过该值时改走后台逐块计算
  static const syncThreshold = 3000;

  /// 渐进计算的分块行数
  static const chunkSize = 10000;

  String _leftText = '';
  String _rightText = '';
  List<String> _leftLines = const [];
  List<String> _rightLines = const [];
  DiffOptions _options = const DiffOptions();

  /// 每块的差异结果（null = 该块尚未计算，渲染占位行）
  List<List<DiffRow>?> _chunks = const [];

  /// 各块的占位行数（max(块左行数, 块右行数)）
  List<int> _chunkPlaceholders = const [];

  /// 已完成的块数
  int _comparedChunks = 0;

  bool _computing = false;

  /// 平铺缓存（块完成时失效重建）
  List<DiffRow>? _rowsCache;
  List<DiffBlock>? _blocksCache;

  /// 当前选中的差异块（索引指向 activeBlocks）
  int _selectedBlock = -1;

  /// 被忽略的差异行（键：leftIndex->rightIndex）
  final Set<String> _ignoredPairs = {};

  Timer? _debounce;

  /// 计算世代：文本变化时自增，异步结果过期则丢弃
  int _generation = 0;

  /// 是否已 dispose(页面切走后停止剩余块的渐进计算)
  bool _disposed = false;

  String get leftText => _leftText;
  String get rightText => _rightText;
  DiffOptions get options => _options;

  /// 是否正在后台计算（渐进进行中）
  bool get computing => _computing;
  int get selectedBlock => _selectedBlock;
  int get leftLineCount => _leftLines.length;
  int get rightLineCount => _rightLines.length;

  /// 按行拆分的缓存（避免大文件反复 split）
  List<String> get leftLines => _leftLines;
  List<String> get rightLines => _rightLines;

  /// 当前统一行模型（已对比部分为真实差异，未对比部分为占位行）
  List<DiffRow> get rows => _rowsCache ??= _flattenRows();

  /// 未被忽略的差异块（仅已对比区域）
  List<DiffBlock> get activeBlocks => _blocksCache ??= _scanBlocks();

  /// 已被忽略的差异行数
  int get ignoredCount => _ignoredPairs.length;

  /// 已对比行数（进度显示用，按左栏口径）
  int get comparedLines {
    var total = 0;
    for (var k = 0; k < _comparedChunks && k < _chunks.length; k++) {
      final start = k * chunkSize;
      total += start < _leftLines.length
          ? (chunkSize < _leftLines.length - start
              ? chunkSize
              : _leftLines.length - start)
          : 0;
    }
    return total;
  }

  /// 对比总行数（进度显示用，取两侧较大值）
  int get totalLines {
    final n = _leftLines.length;
    final m = _rightLines.length;
    return n > m ? n : m;
  }

  static String _pairKey(int? leftIndex, int? rightIndex) =>
      '$leftIndex->$rightIndex';

  bool isRowIgnored(DiffRow row) =>
      _ignoredPairs.contains(_pairKey(row.leftIndex, row.rightIndex));

  /// 设置文本（任一参数为 null 表示不变）
  void setTexts({String? left, String? right}) {
    var changed = false;
    if (left != null && left != _leftText) {
      _leftText = left;
      changed = true;
    }
    if (right != null && right != _rightText) {
      _rightText = right;
      changed = true;
    }
    if (changed) _recompute();
  }

  void setLeftText(String text) => setTexts(left: text);

  void setRightText(String text) => setTexts(right: text);

  void setOptions(DiffOptions options) {
    if (_options == options) return;
    _options = options;
    _recompute();
  }

  /// 修改指定行文本（编辑后整段重算）
  void updateLine(int lineIndex, String newText, {required bool isLeft}) {
    final text = isLeft ? _leftText : _rightText;
    final lines = splitLines(text);
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines[lineIndex] = newText;
    if (isLeft) {
      _leftText = lines.join('\n');
    } else {
      _rightText = lines.join('\n');
    }
    _recompute();
  }

  /// 选中差异块（-1 取消）
  void selectBlock(int index) {
    if (_selectedBlock == index) return;
    _selectedBlock = index;
    notifyListeners();
  }

  /// 复制差异块：用一侧的内容覆盖另一侧
  ///
  /// [toLeft] 为 true 表示「复制右侧 → 左侧」，false 为「复制左侧 → 右侧」。
  /// 基于统一行模型重建目标侧文本：块内取源侧行，块外保持目标侧原样。
  void copyBlock(int blockIndex, {required bool toLeft}) {
    final rows = this.rows;
    final blocks = activeBlocks;
    if (rows.isEmpty || blockIndex < 0 || blockIndex >= blocks.length) {
      return;
    }
    final block = blocks[blockIndex];
    final target = <String>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final inBlock = r >= block.startRow && r < block.endRow;
      final String? text;
      if (inBlock) {
        // 块内：取源侧内容
        text = toLeft ? row.rightText : row.leftText;
      } else {
        // 块外：保持目标侧原内容
        text = toLeft ? row.leftText : row.rightText;
      }
      if (text != null) target.add(text);
    }
    if (toLeft) {
      _leftText = target.join('\n');
    } else {
      _rightText = target.join('\n');
    }
    _recompute();
  }

  /// 忽略当前选中差异块（导航不再计入；重新对比后自然失效）
  void ignoreSelectedBlock() {
    final rows = this.rows;
    final blocks = activeBlocks;
    if (rows.isEmpty || _selectedBlock < 0 ||
        _selectedBlock >= blocks.length) {
      return;
    }
    final block = blocks[_selectedBlock];
    for (var r = block.startRow; r < block.endRow; r++) {
      final row = rows[r];
      _ignoredPairs.add(_pairKey(row.leftIndex, row.rightIndex));
    }
    _selectedBlock = -1;
    _blocksCache = null;
    notifyListeners();
  }

  /// 清除全部忽略标记
  void clearIgnored() {
    if (_ignoredPairs.isEmpty) return;
    _ignoredPairs.clear();
    _blocksCache = null;
    notifyListeners();
  }

  /// 按行拆分文本（忽略末尾空行）
  static List<String> splitLines(String text) {
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  // ==================== 计算 ====================

  void _recompute() {
    _debounce?.cancel();
    _generation++;
    _leftLines = splitLines(_leftText);
    _rightLines = splitLines(_rightText);
    _selectedBlock = -1;
    _ignoredPairs.clear();

    final total = _leftLines.length + _rightLines.length;
    if (total <= syncThreshold) {
      // 小文件：同步全量对比
      final result = const DiffEngine().compute(
        _leftLines,
        _rightLines,
        options: _options,
      );
      _chunks = [result.rows];
      _chunkPlaceholders = [_placeholderCount(_leftLines.length,
          _rightLines.length)];
      _comparedChunks = 1;
      _computing = false;
      _rowsCache = null;
      _blocksCache = null;
      notifyListeners();
      return;
    }

    // 大文件：先显示占位内容，再逐块渐进计算
    final chunkCount =
        (totalLines + chunkSize - 1) ~/ chunkSize;
    _chunks = List<List<DiffRow>?>.filled(chunkCount, null);
    _chunkPlaceholders = [
      for (var k = 0; k < chunkCount; k++)
        _placeholderCount(
          _chunkCountAt(_leftLines.length, k),
          _chunkCountAt(_rightLines.length, k),
        ),
    ];
    _comparedChunks = 0;
    _computing = true;
    _rowsCache = null;
    _blocksCache = null;
    notifyListeners();

    final gen = _generation;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _computeChunks(gen);
    });
  }

  int _chunkCountAt(int total, int k) {
    final start = k * chunkSize;
    if (start >= total) return 0;
    final remain = total - start;
    return remain < chunkSize ? remain : chunkSize;
  }

  int _placeholderCount(int left, int right) =>
      left > right ? left : right;

  /// 逐块渐进计算：每完成一块立即合并并通知界面
  Future<void> _computeChunks(int gen) async {
    final chunkCount = _chunks.length;
    for (var k = 0; k < chunkCount; k++) {
      if (_disposed) return; // 页面已销毁，停止剩余计算
      final start = k * chunkSize;
      final leftChunk = start < _leftLines.length
          ? _leftLines.sublist(
              start,
              (start + chunkSize) < _leftLines.length
                  ? start + chunkSize
                  : _leftLines.length,
            )
          : const <String>[];
      final rightChunk = start < _rightLines.length
          ? _rightLines.sublist(
              start,
              (start + chunkSize) < _rightLines.length
                  ? start + chunkSize
                  : _rightLines.length,
            )
          : const <String>[];
      if (leftChunk.isEmpty && rightChunk.isEmpty) {
        _chunks[k] = const [];
        continue;
      }

      final chunkRows = await runBackgroundTask(_computeChunk, {
        'left': leftChunk,
        'right': rightChunk,
        'whitespaceMode': _options.whitespaceMode.name,
        'ignoreCase': _options.ignoreCase,
        'ignoreBlankLines': _options.ignoreBlankLines,
        'similarityThreshold': _options.similarityThreshold,
        'startLeft': start,
        'startRight': start,
      });
      if (gen != _generation) return; // 文本已变化，丢弃过期结果

      _chunks[k] = chunkRows;
      _comparedChunks = k + 1;
      _computing = k < chunkCount - 1;
      _rowsCache = null;
      _blocksCache = null;
      // 块集合已变化（合并/重排），旧选中索引可能越界，放弃选中
      _selectedBlock = -1;
      notifyListeners();
    }
  }

  static List<DiffRow> _computeChunk(Map<String, Object?> msg) {
    final startLeft = msg['startLeft'] as int;
    final startRight = msg['startRight'] as int;
    final result = const DiffEngine().compute(
      (msg['left'] as List).cast<String>(),
      (msg['right'] as List).cast<String>(),
      options: DiffOptions(
        whitespaceMode: WhiteSpaceMode.values
            .byName(msg['whitespaceMode'] as String),
        ignoreCase: msg['ignoreCase'] as bool,
        ignoreBlankLines: msg['ignoreBlankLines'] as bool,
        similarityThreshold: msg['similarityThreshold'] as int,
      ),
    );
    return [
      for (final row in result.rows)
        DiffRow(
          leftIndex: row.leftIndex == null
              ? null
              : row.leftIndex! + startLeft,
          rightIndex: row.rightIndex == null
              ? null
              : row.rightIndex! + startRight,
          op: row.op,
          leftText: row.leftText,
          rightText: row.rightText,
          leftSpans: row.leftSpans,
          rightSpans: row.rightSpans,
        ),
    ];
  }

  /// 平铺：已完成块用真实结果，未完成块用占位行（内容完整显示）
  List<DiffRow> _flattenRows() {
    final rows = <DiffRow>[];
    for (var k = 0; k < _chunks.length; k++) {
      final chunkRows = _chunks[k];
      if (chunkRows != null) {
        rows.addAll(chunkRows);
        continue;
      }
      final start = k * chunkSize;
      final count = _chunkPlaceholders[k];
      for (var i = 0; i < count; i++) {
        final leftIndex = start + i;
        final rightIndex = start + i;
        rows.add(DiffRow(
          leftIndex: leftIndex < _leftLines.length ? leftIndex : null,
          rightIndex: rightIndex < _rightLines.length ? rightIndex : null,
          op: DiffOp.unknown,
          leftText: leftIndex < _leftLines.length
              ? _leftLines[leftIndex]
              : null,
          rightText: rightIndex < _rightLines.length
              ? _rightLines[rightIndex]
              : null,
        ));
      }
    }
    return rows;
  }

  List<DiffBlock> _scanBlocks() {
    final rows = this.rows;
    final blocks = <DiffBlock>[];
    var start = -1;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      if (row.isChange &&
          !_ignoredPairs.contains(_pairKey(row.leftIndex, row.rightIndex))) {
        if (start < 0) {
          start = r;
        } else if (_isParagraphGap(rows[r - 1], row)) {
          // 相邻差异行之间的行号出现跳变：中间被忽略的空白行（段落边界），
          // 按段落划分为两个不同点
          blocks.add(DiffBlock(start, r));
          start = r;
        }
      } else if (start >= 0) {
        blocks.add(DiffBlock(start, r));
        start = -1;
      }
    }
    if (start >= 0) blocks.add(DiffBlock(start, rows.length));
    return blocks;
  }

  /// 相邻差异行之间是否存在段落边界（某侧行号跳变 > 1）
  static bool _isParagraphGap(DiffRow prev, DiffRow cur) {
    final pl = prev.leftIndex;
    final cl = cur.leftIndex;
    final pr = prev.rightIndex;
    final cr = cur.rightIndex;
    if (pl != null && cl != null && cl - pl > 1) return true;
    if (pr != null && cr != null && cr - pr > 1) return true;
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
