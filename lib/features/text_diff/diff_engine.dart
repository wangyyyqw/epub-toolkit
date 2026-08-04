// 文本对比引擎：行级 Myers 差分 + 修改行内字符级差分
//
// 纯 Dart、无依赖，可在 Isolate 中运行。
// 设计要点：
// - 左右两栏共享统一的"行模型"（rows），行号一一对应，
//   同步滚动按行号换算，天然保证两侧滚动进度一致
// - 相邻的 delete+insert 合并为 replace 行（两侧都有内容、分别着色）
// - replace 行再做一次字符级差分，输出行内差异片段

/// 行级操作类型
enum DiffOp { equal, replace, delete, insert }

/// 行内字符差异片段
class CharSpan {
  final String text;
  final bool changed;

  const CharSpan(this.text, {required this.changed});
}

/// 统一行模型：一行对应左右两栏各一条（可能为空）
class DiffRow {
  /// 左栏行号（null = 右侧独有行）
  final int? leftIndex;

  /// 右栏行号（null = 左侧独有行）
  final int? rightIndex;

  final DiffOp op;
  final String? leftText;
  final String? rightText;

  /// 字符级差异片段（仅 replace 行有值）
  final List<CharSpan>? leftSpans;
  final List<CharSpan>? rightSpans;

  const DiffRow({
    this.leftIndex,
    this.rightIndex,
    required this.op,
    this.leftText,
    this.rightText,
    this.leftSpans,
    this.rightSpans,
  });

  bool get isChange => op != DiffOp.equal;
}

/// 差异块（导航单元）：连续的非相等行
class DiffBlock {
  final int startRow;
  final int endRow;

  const DiffBlock(this.startRow, this.endRow);

  int get length => endRow - startRow;
}

/// 一次完整对比的结果
class DiffResult {
  final List<String> leftLines;
  final List<String> rightLines;

  /// 统一行模型（左右两栏共用，行号即滚动锚点）
  final List<DiffRow> rows;

  /// 差异块列表（未过滤忽略项，导航时用 activeBlocks）
  final List<DiffBlock> blocks;

  const DiffResult({
    required this.leftLines,
    required this.rightLines,
    required this.rows,
    required this.blocks,
  });

  /// 差异处数
  int get changeCount => blocks.length;
}

/// 对比选项
class DiffOptions {
  final bool ignoreWhitespace;
  final bool ignoreCase;

  const DiffOptions({this.ignoreWhitespace = false, this.ignoreCase = false});

  @override
  bool operator ==(Object other) =>
      other is DiffOptions &&
      other.ignoreWhitespace == ignoreWhitespace &&
      other.ignoreCase == ignoreCase;

  @override
  int get hashCode => Object.hash(ignoreWhitespace, ignoreCase);
}

/// 对比引擎
class DiffEngine {
  const DiffEngine();

  /// 计算两个文本（按行拆分）的差异
  DiffResult compute(
    List<String> leftLines,
    List<String> rightLines, {
    DiffOptions options = const DiffOptions(),
  }) {
    final leftKeys = [
      for (final l in leftLines) _comparisonKey(l, options),
    ];
    final rightKeys = [
      for (final l in rightLines) _comparisonKey(l, options),
    ];

    final edits = _myers(leftKeys, rightKeys);
    final rows = _buildRows(edits, leftLines, rightLines);

    final blocks = <DiffBlock>[];
    var start = -1;
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].isChange) {
        if (start < 0) start = r;
      } else if (start >= 0) {
        blocks.add(DiffBlock(start, r));
        start = -1;
      }
    }
    if (start >= 0) blocks.add(DiffBlock(start, rows.length));

    return DiffResult(
      leftLines: leftLines,
      rightLines: rightLines,
      rows: rows,
      blocks: blocks,
    );
  }

  /// 把行拆分为单个字符（按 rune，兼容中文/emoji）
  static List<String> _charsOf(String s) =>
      [for (final r in s.runes) String.fromCharCode(r)];

  /// 对两个字符串做字符级差分，返回 (左侧片段, 右侧片段)
  ///
  /// 左侧片段标记删除的字符，右侧片段标记新增的字符，其余为未变。
  static (List<CharSpan>, List<CharSpan>) charDiff(String a, String b) {
    if (a.isEmpty && b.isEmpty) return (const [], const []);
    final aChars = _charsOf(a);
    final bChars = _charsOf(b);
    final edits = _myers(aChars, bChars);
    final left = <CharSpan>[];
    final right = <CharSpan>[];

    void append(List<CharSpan> out, String ch, bool changed) {
      if (out.isNotEmpty && out.last.changed == changed) {
        out[out.length - 1] = CharSpan(out.last.text + ch, changed: changed);
      } else {
        out.add(CharSpan(ch, changed: changed));
      }
    }

    for (final e in edits) {
      if (e.type == _EditType.equal) {
        append(left, aChars[e.a], false);
        append(right, bChars[e.b], false);
      } else if (e.type == _EditType.delete) {
        append(left, aChars[e.a], true);
      } else {
        append(right, bChars[e.b], true);
      }
    }
    return (left, right);
  }

  String _comparisonKey(String line, DiffOptions options) {
    var s = line;
    if (options.ignoreCase) s = s.toLowerCase();
    if (options.ignoreWhitespace) {
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return s;
  }

  /// 把 Myers 编辑脚本转为统一行模型
  static List<DiffRow> _buildRows(
    List<_Edit> edits,
    List<String> leftLines,
    List<String> rightLines,
  ) {
    final rows = <DiffRow>[];
    var i = 0;
    while (i < edits.length) {
      final e = edits[i];
      if (e.type == _EditType.equal) {
        rows.add(DiffRow(
          leftIndex: e.a,
          rightIndex: e.b,
          op: DiffOp.equal,
          leftText: leftLines[e.a],
          rightText: rightLines[e.b],
        ));
        i++;
        continue;
      }

      // 收集连续 delete / insert，按顺序配对为 replace
      final deletes = <_Edit>[];
      final inserts = <_Edit>[];
      while (i < edits.length && edits[i].type != _EditType.equal) {
        if (edits[i].type == _EditType.delete) {
          deletes.add(edits[i]);
        } else {
          inserts.add(edits[i]);
        }
        i++;
      }

      final pairCount =
          deletes.length < inserts.length ? deletes.length : inserts.length;
      for (var j = 0; j < pairCount; j++) {
        final d = deletes[j];
        final ins = inserts[j];
        final (leftSpans, rightSpans) =
            charDiff(leftLines[d.a], rightLines[ins.b]);
        rows.add(DiffRow(
          leftIndex: d.a,
          rightIndex: ins.b,
          op: DiffOp.replace,
          leftText: leftLines[d.a],
          rightText: rightLines[ins.b],
          leftSpans: leftSpans,
          rightSpans: rightSpans,
        ));
      }
      for (final d in deletes.sublist(pairCount)) {
        rows.add(DiffRow(
          leftIndex: d.a,
          rightIndex: null,
          op: DiffOp.delete,
          leftText: leftLines[d.a],
        ));
      }
      for (final ins in inserts.sublist(pairCount)) {
        rows.add(DiffRow(
          leftIndex: null,
          rightIndex: ins.b,
          op: DiffOp.insert,
          rightText: rightLines[ins.b],
        ));
      }
    }
    return rows;
  }
}

enum _EditType { equal, delete, insert }

class _Edit {
  final _EditType type;

  /// a 中的索引（insert 为 -1）
  final int a;

  /// b 中的索引（delete 为 -1）
  final int b;

  const _Edit(this.type, this.a, this.b);
}

/// Myers O(ND) 差分，返回编辑脚本（正序）
///
/// [a]、[b] 为参与比较的元素列表（行文本或单字符列表）。
List<_Edit> _myers(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final max = n + m;
  if (max == 0) return const [];
  if (n == 0) {
    return [for (var j = 0; j < m; j++) _Edit(_EditType.insert, -1, j)];
  }
  if (m == 0) {
    return [for (var i = 0; i < n; i++) _Edit(_EditType.delete, i, -1)];
  }

  final offset = max;
  final v = List<int>.filled(2 * max + 1, 0);
  final trace = <List<int>>[];
  var done = false;
  for (var d = 0; d <= max; d++) {
    trace.add(List<int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      final down =
          k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset]);
      var x = down ? v[k + 1 + offset] : v[k - 1 + offset] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        done = true;
        break;
      }
    }
    if (done) break;
  }

  // 回溯生成编辑脚本
  final edits = <_Edit>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    final t = trace[d];
    final k = x - y;
    final down =
        k == -d || (k != d && t[k - 1 + offset] < t[k + 1 + offset]);
    final prevK = down ? k + 1 : k - 1;
    final prevX = t[prevK + offset];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      edits.add(_Edit(_EditType.equal, x - 1, y - 1));
      x--;
      y--;
    }
    if (d > 0) {
      if (x == prevX) {
        edits.add(_Edit(_EditType.insert, -1, y - 1));
        y--;
      } else {
        edits.add(_Edit(_EditType.delete, x - 1, -1));
        x--;
      }
    }
  }
  return edits.reversed.toList();
}
