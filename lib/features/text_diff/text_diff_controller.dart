import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/background_task.dart';
import 'diff_engine.dart';

/// 文本对比控制器：管理两侧文本、对比选项、差异结果与差异操作
///
/// - 小文件同步计算（毫秒级），大文件走 Isolate + 防抖
/// - 差异操作（复制左↔右、忽略）基于统一行模型，编辑/替换后自动重算
class TextDiffController extends ChangeNotifier {
  /// 行数超过该值时改走后台 Isolate
  static const _asyncThreshold = 3000;

  String _leftText = '';
  String _rightText = '';
  DiffOptions _options = const DiffOptions();
  DiffResult? _result;
  bool _loading = false;

  /// 当前选中的差异块（索引指向 activeBlocks）
  int _selectedBlock = -1;

  /// 被忽略的差异行（键：leftIndex->rightIndex）
  final Set<String> _ignoredPairs = {};

  Timer? _debounce;

  String get leftText => _leftText;
  String get rightText => _rightText;
  DiffOptions get options => _options;
  DiffResult? get result => _result;
  bool get loading => _loading;
  int get selectedBlock => _selectedBlock;

  /// 未被忽略的差异块
  List<DiffBlock> get activeBlocks {
    final result = _result;
    if (result == null) return const [];
    return [
      for (final b in result.blocks)
        if (!_isBlockIgnored(result, b)) b,
    ];
  }

  /// 有效差异处数
  int get changeCount => activeBlocks.length;

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
    final result = _result;
    final blocks = activeBlocks;
    if (result == null || blockIndex < 0 || blockIndex >= blocks.length) {
      return;
    }
    final block = blocks[blockIndex];
    final target = <String>[];
    for (var r = 0; r < result.rows.length; r++) {
      final row = result.rows[r];
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

  /// 忽略当前选中差异块（导航与统计不再计入；重新对比后自然失效）
  void ignoreSelectedBlock() {
    final result = _result;
    final blocks = activeBlocks;
    if (result == null || _selectedBlock < 0 ||
        _selectedBlock >= blocks.length) {
      return;
    }
    final block = blocks[_selectedBlock];
    for (var r = block.startRow; r < block.endRow; r++) {
      final row = result.rows[r];
      _ignoredPairs.add(_pairKey(row.leftIndex, row.rightIndex));
    }
    _selectedBlock = -1;
    notifyListeners();
  }

  /// 清除全部忽略标记
  void clearIgnored() {
    if (_ignoredPairs.isEmpty) return;
    _ignoredPairs.clear();
    notifyListeners();
  }

  /// 按行拆分文本（忽略末尾空行）
  static List<String> splitLines(String text) {
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  void _recompute() {
    _debounce?.cancel();
    final left = splitLines(_leftText);
    final right = splitLines(_rightText);
    _selectedBlock = -1;
    if (left.length + right.length > _asyncThreshold) {
      _loading = true;
      notifyListeners();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _computeAsync(left, right, _options);
      });
    } else {
      _computeSync(left, right);
    }
  }

  void _computeSync(List<String> left, List<String> right) {
    _result = const DiffEngine().compute(left, right, options: _options);
    _loading = false;
    notifyListeners();
  }

  Future<void> _computeAsync(
    List<String> left,
    List<String> right,
    DiffOptions options,
  ) async {
    final result = await runBackgroundTask(_isolateCompute, {
      'left': left,
      'right': right,
      'ignoreWhitespace': options.ignoreWhitespace,
      'ignoreCase': options.ignoreCase,
    });
    _result = result;
    _loading = false;
    notifyListeners();
  }

  static DiffResult _isolateCompute(Map<String, Object?> msg) {
    return const DiffEngine().compute(
      (msg['left'] as List).cast<String>(),
      (msg['right'] as List).cast<String>(),
      options: DiffOptions(
        ignoreWhitespace: msg['ignoreWhitespace'] as bool,
        ignoreCase: msg['ignoreCase'] as bool,
      ),
    );
  }

  bool _isBlockIgnored(DiffResult result, DiffBlock block) {
    for (var r = block.startRow; r < block.endRow; r++) {
      final row = result.rows[r];
      if (!_ignoredPairs.contains(_pairKey(row.leftIndex, row.rightIndex))) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
