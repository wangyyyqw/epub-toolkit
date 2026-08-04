// 文本对比引擎（重构版）
//
// 重构自 notepad--（gitee.com/cxasm/notepad--）内置文本对比（cc-compare）的对比逻辑：
// - 行指纹哈希：每行归一化（空白模式 + 忽略大小写）后计算 64 位哈希
//   （双 32 位 djb2 变体，Web 精度安全），用哈希比较代替逐行全文比较
// - 锚点切分：贪心哈希匹配提取公共行作为锚点，把两文件切成块对，
//   将 O(n*m) 的 LCS 限制在局部块内（块间粗匹配）
// - 块内对齐（对应上游 BlockCompare::lessCmpMore）：少行对多行，
//   按字符二元组 Dice 系数计算相似度，达到阈值（50/70/90%）即配对；
//   阈值 0 为仅精确匹配，未配对行按位置相邻配对为 replace / 新增 / 删除
// - 字符级 LCS：Hirschberg 线性空间分治（非递归栈实现，内存 O(m)），
//   输出行内相等/不等片段（SectionNode），对应上游 LcsTemplate.h / LcsLine.cpp
// - 空白行分离：默认忽略空白行差异——空白行不参与锚点匹配，
//   左右空白行按顺序配对显示，单侧多余的空白行直接不输出（可关闭）
//
// 纯 Dart、无依赖，可在 Isolate 中运行。

/// 空白处理模式（行级哈希归一化，显示文本不变）
enum WhiteSpaceMode {
  /// 不忽略空白，按原文比较
  exact,

  /// 忽略行首尾空白
  trim,

  /// 只忽略行尾空白
  trimEnd,

  /// 忽略全部空白字符
  all,
}

/// 行级操作类型（统一行模型的展示类型）
enum DiffOp { equal, replace, delete, insert, unknown }

/// 行内字符差异片段
class CharSpan {
  final String text;
  final bool changed;

  const CharSpan(this.text, {required this.changed});
}

/// 每一小段的字符：相等与不等的字符段分开存放（对应上游 SectionNode）
class SectionNode {
  /// 是否相等
  bool equal;

  /// 尾巴状态：0 非尾巴；1 相等的尾巴；2 不相等的尾巴。
  /// 行尾（\r）归并到前一节后，用该字段保留行尾原本的相等状态
  int tailStatus;

  /// 尾巴长度（字符数）
  int tailLens;

  String text;

  SectionNode({required this.equal, required this.text, this.tailStatus = 0, this.tailLens = 0});
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

  bool get isChange =>
      op == DiffOp.delete || op == DiffOp.insert || op == DiffOp.replace;
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
  /// 统一行模型（左右两栏共用，行号即滚动锚点）
  final List<DiffRow> rows;

  /// 差异块列表（未过滤忽略项，导航时用 activeBlocks）
  final List<DiffBlock> blocks;

  /// 已对比的左侧行数（截断时小于输入行数）
  final int comparedLeft;

  /// 已对比的右侧行数
  final int comparedRight;

  const DiffResult({
    required this.rows,
    required this.blocks,
    this.comparedLeft = 0,
    this.comparedRight = 0,
  });

  /// 是否因行数上限截断了对比（未对比区域标记为 [DiffOp.unknown]）
  bool get truncated => rows.any((row) => row.op == DiffOp.unknown);

  /// 差异处数
  int get changeCount => blocks.length;
}

/// 对比选项
///
/// - [whitespaceMode]：行级哈希归一化的空白处理模式
/// - [ignoreCase]：忽略大小写（仅影响行级匹配，显示文本不变）
/// - [ignoreBlankLines]：忽略空白行差异：空白行不参与锚点匹配，
///   左右空白行按顺序配对显示，单侧多余的空白行直接不输出（不产生差异）
/// - [similarityThreshold]：块内行配对的相似度阈值：
///   0 为仅精确匹配；50/70/90 表示字符二元组 Dice 系数达到该百分比即配对
class DiffOptions {
  final WhiteSpaceMode whitespaceMode;
  final bool ignoreCase;
  final bool ignoreBlankLines;
  final int similarityThreshold;

  const DiffOptions({
    this.whitespaceMode = WhiteSpaceMode.exact,
    this.ignoreCase = false,
    this.ignoreBlankLines = true,
    this.similarityThreshold = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is DiffOptions &&
      other.whitespaceMode == whitespaceMode &&
      other.ignoreCase == ignoreCase &&
      other.ignoreBlankLines == ignoreBlankLines &&
      other.similarityThreshold == similarityThreshold;

  @override
  int get hashCode => Object.hash(
      whitespaceMode, ignoreCase, ignoreBlankLines, similarityThreshold);
}

// ==================== Hirschberg 线性空间 LCS ====================

/// 最长公共子序列（LCS）计算：Hirschberg 线性空间分治
///
/// 移植自上游 src/LcsTemplate.h（字符级）与 src/LcsLine.cpp（行级）。
/// - [lcsLength]：滚动两行的 O(n) 空间 DP，只求长度
/// - [cmp]：分治求解（显式栈，非递归，避免调用栈溢出），返回 LCS 在 a 中的下标
class Lcs<T> {
  final List<T> _a;
  final List<T> _b;

  /// 每行最大 1 万个元素，超过则不再对比（否则 O(m*n) 可能溢出/超时）
  static const maxCmpLimit = 10000 * 10000;

  Lcs(this._a, this._b);

  /// 求两个序列的 LCS 长度（O(m*n) 时间、O(n) 空间）
  ///
  /// 与上游 LcsTemplate::getLcsLength 对应。序列过长时返回 0，视为完全不等。
  int lcsLength() {
    final m = _a.length;
    final n = _b.length;
    if (m <= 0 || n <= 0) return 0;
    final total = m * n;
    if (total > maxCmpLimit || total < 0) return 0;

    var prev = List<int>.filled(n + 1, 0);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 0; i < m; i++) {
      final tmp = prev;
      prev = cur;
      cur = tmp;
      for (var j = 0; j < n; j++) {
        if (_a[i] == _b[j]) {
          cur[j + 1] = prev[j] + 1;
        } else {
          cur[j + 1] = prev[j + 1] >= cur[j] ? prev[j + 1] : cur[j];
        }
      }
    }
    return cur[n];
  }

  /// 计算最长公共子序列，返回其元素在 a 中的下标（升序）。
  /// 任一侧为空时返回 null（调用方视为无公共子序列）。
  List<int>? cmp() {
    if (_a.isEmpty || _b.isEmpty) return null;
    return _hLcs1(_a.length, _b.length, 0, 0);
  }

  /// 分治核心：求 a[aStart, aStart+m) 与 b[bStart, bStart+n) 的 LCS 下标
  List<int> _hLcs1(int m, int n, int aStart, int bStart) {
    // 用户递归调用的栈
    final stack = <_LcsPara>[];
    // 保存结果的栈
    final resultStack = <List<int>>[];

    stack.add(_LcsPara(m, n, aStart, bStart));

    while (stack.isNotEmpty) {
      final para = stack.removeLast();

      if (para.n == 0) {
        resultStack.add(const []);
      } else if (para.m == 1) {
        // 在 b[bStart, bStart+n) 中查找单个元素
        var found = false;
        final target = _a[para.aStart];
        for (var j = para.bStart; j < para.bStart + para.n; j++) {
          if (_b[j] == target) {
            found = true;
            break;
          }
        }
        resultStack.add(found ? [para.aStart] : const []);
      } else {
        final i = para.m ~/ 2;

        final l1 = _findRow(i, para.n, para.aStart, para.bStart, reverse: false);
        final l2 = _findRow(
          para.m - i,
          para.n,
          para.aStart + para.m - 1,
          para.bStart + para.n - 1,
          reverse: true,
        );

        var maxSum = 0;
        var k = 0;
        for (var j = 0; j <= para.n; j++) {
          final sum = l1[j] + l2[para.n - j];
          if (sum > maxSum) {
            maxSum = sum;
            k = j;
          }
        }

        // 与上游一致：C2 先入栈（后执行）、C1 后入栈（先执行），
        // 结果按序合并
        stack.add(_LcsPara(
            para.m - i, para.n - k, para.aStart + i, para.bStart + k));
        stack.add(_LcsPara(i, k, para.aStart, para.bStart));
      }

      // 有结果就及时合并处理
      if (resultStack.length >= 2) {
        final r2 = resultStack.removeLast();
        final r1 = resultStack.removeLast();
        if (r1.isNotEmpty || r2.isNotEmpty) {
          if (r1.isNotEmpty && r2.isNotEmpty) {
            resultStack.add([...r1, ...r2]);
          } else if (r1.isNotEmpty) {
            resultStack.add(r1);
          } else {
            resultStack.add(r2);
          }
        }
      }
    }

    return resultStack.isEmpty ? const [] : resultStack.last;
  }

  /// 计算一行 LCS 长度数组（正序或反序，对应上游 findRow）
  List<int> _findRow(int m, int n, int aStart, int bStart,
      {required bool reverse}) {
    var prev = List<int>.filled(n + 1, 0);
    var cur = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      final tmp = prev;
      prev = cur;
      cur = tmp;
      // 正序从前往后；反序从尾部往前（aStart 指向子序列最后一个元素）
      final aIndex = reverse ? aStart - i + 1 : aStart + i - 1;
      for (var j = 1; j <= n; j++) {
        final bIndex = reverse ? bStart - j + 1 : bStart + j - 1;
        if (_a[aIndex] == _b[bIndex]) {
          cur[j] = prev[j - 1] + 1;
        } else {
          cur[j] = prev[j] >= cur[j - 1] ? prev[j] : cur[j - 1];
        }
      }
    }
    return cur;
  }
}

class _LcsPara {
  final int m;
  final int n;
  final int aStart;
  final int bStart;

  const _LcsPara(this.m, this.n, this.aStart, this.bStart);
}

// ==================== 对比引擎 ====================

/// 对比引擎
class DiffEngine {
  const DiffEngine();

  /// 相似度匹配的最大行对预算（超出后退化为位置配对）
  static const int _pairWorkLimit = 200000;

  /// 计算两个文本（按行拆分）的差异
  ///
  /// [maxCompareLines] 为对比行数上限：
  /// - null：全量对比（小文件）
  /// - 0：全部行标记为未对比（用于"先显示内容"的占位结果）
  /// - N：只对比前 N 行，其余行标记为 [DiffOp.unknown]
  DiffResult compute(
    List<String> leftLines,
    List<String> rightLines, {
    DiffOptions options = const DiffOptions(),
    int? maxCompareLines,
  }) {
    final compareLeft = maxCompareLines == null
        ? leftLines
        : leftLines.take(maxCompareLines).toList();
    final compareRight = maxCompareLines == null
        ? rightLines
        : rightLines.take(maxCompareLines).toList();

    final leftInfos = _buildLineInfos(compareLeft, options);
    final rightInfos = _buildLineInfos(compareRight, options);

    final rows = <DiffRow>[];

    // 锚点切分：贪心哈希匹配提取公共行，把两侧切成块对
    //（对应上游 CmpareMode::cmpByLine + cmpDateAndLcsLine 的行级 LCS 标记）
    final anchors = <(int, int)>[];
    var moreStart = 0;
    for (var i = 0; i < leftInfos.length; i++) {
      final leftInfo = leftInfos[i];
      if (options.ignoreBlankLines && leftInfo.isEmpty) continue;
      for (var j = moreStart; j < rightInfos.length; j++) {
        final rightInfo = rightInfos[j];
        if (options.ignoreBlankLines && rightInfo.isEmpty) continue;
        if (leftInfo.hash == rightInfo.hash) {
          anchors.add((i, j));
          moreStart = j + 1;
          break;
        }
      }
    }

    // 块级对比 + 组装：先输出锚点前的块，再输出锚点行
    var prevLeft = 0;
    var prevRight = 0;
    for (final (leftIndex, rightIndex) in anchors) {
      _processBlock(leftInfos, rightInfos, prevLeft, leftIndex, prevRight,
          rightIndex, options, rows);
      rows.add(DiffRow(
        leftIndex: leftIndex,
        rightIndex: rightIndex,
        op: DiffOp.equal,
        leftText: leftInfos[leftIndex].text,
        rightText: rightInfos[rightIndex].text,
      ));
      prevLeft = leftIndex + 1;
      prevRight = rightIndex + 1;
    }
    _processBlock(leftInfos, rightInfos, prevLeft, leftInfos.length,
        prevRight, rightInfos.length, options, rows);

    // 未对比的剩余行：生成 unknown 占位行（内容完整显示，无差异高亮）
    final leftRemain = leftLines.length - compareLeft.length;
    final rightRemain = rightLines.length - compareRight.length;
    final remain = leftRemain > rightRemain ? leftRemain : rightRemain;
    for (var i = 0; i < remain; i++) {
      final hasLeft = i < leftRemain;
      final hasRight = i < rightRemain;
      rows.add(DiffRow(
        leftIndex: hasLeft ? compareLeft.length + i : null,
        rightIndex: hasRight ? compareRight.length + i : null,
        op: DiffOp.unknown,
        leftText: hasLeft ? leftLines[compareLeft.length + i] : null,
        rightText: hasRight ? rightLines[compareRight.length + i] : null,
      ));
    }

    final blocks = <DiffBlock>[];
    var start = -1;
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].isChange) {
        if (start < 0) {
          start = r;
        } else if (_isParagraphGap(rows[r - 1], rows[r])) {
          // 行号跳变 > 1：中间被忽略的空白行（段落边界），按段落分两个不同点
          blocks.add(DiffBlock(start, r));
          start = r;
        }
      } else if (start >= 0) {
        blocks.add(DiffBlock(start, r));
        start = -1;
      }
    }
    if (start >= 0) blocks.add(DiffBlock(start, rows.length));

    return DiffResult(
      rows: rows,
      blocks: blocks,
      comparedLeft: compareLeft.length,
      comparedRight: compareRight.length,
    );
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

  // ==================== 行信息构建 ====================

  List<_LineInfo> _buildLineInfos(List<String> lines, DiffOptions options) {
    final infos = <_LineInfo>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final content =
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
      infos.add(_LineInfo(
        index: i,
        text: line,
        content: content,
        isEmpty: content.isEmpty,
        hash: _lineHash(_normalizeKey(line, options)),
        fullChars: _runesOf(line),
      ));
    }
    return infos;
  }

  static List<String> _runesOf(String s) =>
      [for (final r in s.runes) String.fromCharCode(r)];

  /// 行级归一化：空白模式 + 忽略大小写（只影响哈希，显示文本不变）
  static String _normalizeKey(String line, DiffOptions options) {
    var s = line;
    switch (options.whitespaceMode) {
      case WhiteSpaceMode.exact:
        break;
      case WhiteSpaceMode.trim:
        s = s.trim();
      case WhiteSpaceMode.trimEnd:
        s = s.replaceFirst(RegExp(r'\s+$'), '');
      case WhiteSpaceMode.all:
        s = s.replaceAll(RegExp(r'\s+'), '');
    }
    if (options.ignoreCase) s = s.toLowerCase();
    return s;
  }

  /// 行指纹哈希：双 32 位 djb2 变体拼成 64 位指纹串（Web 精度安全）。
  ///
  /// 对应上游 md4：只用于行级相等判断，不参与显示
  static String _lineHash(String key) {
    var h1 = 5381;
    var h2 = 1315423911;
    for (final c in key.codeUnits) {
      h1 = (h1 * 33 + c) & 0xFFFFFFFF;
      h2 = (h2 * 33 + c) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  // ==================== 块级对比 ====================

  /// 处理一个块对：[lStart, lEnd) 与 [rStart, rEnd) 之间的行
  ///
  /// 对应上游 BlockCompare::blockCmpLcs 的三种输出形态：
  /// - 空白行按顺序配对为相等行，多余空白行按新增/删除输出
  /// - 少行对多行：相似度阈值匹配（字符二元组 Dice 系数）
  /// - 未配对行按位置相邻配对为 replace / 新增 / 删除
  void _processBlock(
    List<_LineInfo> leftInfos,
    List<_LineInfo> rightInfos,
    int lStart,
    int lEnd,
    int rStart,
    int rEnd,
    DiffOptions options,
    List<DiffRow> rows,
  ) {
    final leftLines = leftInfos.sublist(lStart, lEnd);
    final rightLines = rightInfos.sublist(rStart, rEnd);

    // 空白行分离（忽略空白行时：左右空白行按顺序配对显示，
    // 单侧多余的空白行直接不输出——不再显示为大面积空白差异）
    var lContent = leftLines;
    var rContent = rightLines;
    if (options.ignoreBlankLines) {
      final lBlanks = [
        for (final l in leftLines)
          if (l.isEmpty) l
      ];
      final rBlanks = [
        for (final r in rightLines)
          if (r.isEmpty) r
      ];
      final pairCount = lBlanks.length < rBlanks.length
          ? lBlanks.length
          : rBlanks.length;
      for (var k = 0; k < pairCount; k++) {
        rows.add(DiffRow(
          leftIndex: lBlanks[k].index,
          rightIndex: rBlanks[k].index,
          op: DiffOp.equal,
          leftText: lBlanks[k].text,
          rightText: rBlanks[k].text,
        ));
      }
      lContent = [
        for (final l in leftLines)
          if (!l.isEmpty) l
      ];
      rContent = [
        for (final r in rightLines)
          if (!r.isEmpty) r
      ];
    }

    // 内容行对比
    if (lContent.isEmpty && rContent.isEmpty) return;
    if (lContent.isEmpty) {
      for (final r in rContent) {
        rows.add(DiffRow(
          leftIndex: null,
          rightIndex: r.index,
          op: DiffOp.insert,
          rightText: r.text,
        ));
      }
      return;
    }
    if (rContent.isEmpty) {
      for (final l in lContent) {
        rows.add(DiffRow(
          leftIndex: l.index,
          rightIndex: null,
          op: DiffOp.delete,
          leftText: l.text,
        ));
      }
      return;
    }
    if (lContent.length == 1 && rContent.length == 1) {
      // 1 对 1：直接行内字符级对比
      rows.add(_replaceRow(lContent.first, rContent.first));
      return;
    }

    // 相似度阈值匹配（仅阈值 > 0 时启用；对应上游 lessCmpMore 的策略）
    if (options.similarityThreshold > 0) {
      if (_pairWithSimilarity(lContent, rContent, options.similarityThreshold, rows)) {
        return;
      }
    }

    // 未配对：按位置相邻配对（对应上游"1:1 行内对比 + 对齐块"的退化形态）
    _pairPositional(lContent, rContent, rows);
  }

  /// 少行对多行：按字符二元组 Dice 系数匹配相似行（对应上游 lessCmpMore）
  ///
  /// 返回是否产生配对；配对行输出 replace（带行内片段），
  /// 配对间隙的行按新增/删除输出
  bool _pairWithSimilarity(
    List<_LineInfo> lContent,
    List<_LineInfo> rContent,
    int threshold,
    List<DiffRow> rows,
  ) {
    final lessIsLeft = lContent.length <= rContent.length;
    final less = lessIsLeft ? lContent : rContent;
    final more = lessIsLeft ? rContent : lContent;

    // 工作量预算：行对超过上限时放弃相似度匹配（退化为位置配对），
    // 防止超大差异块下的 O(n*m) 二元组计算卡死界面
    if (less.length * more.length > _pairWorkLimit) return false;

    final minRatio = threshold / 100.0;

    final pairs = <(int, int)>[];
    var moreStart = 0;
    for (var i = 0; i < less.length; i++) {
      var best = -1;
      var bestDice = 0.0;
      for (var j = moreStart; j < more.length; j++) {
        final a = less[i].content;
        final b = more[j].content;
        // 长度相差悬殊的行不参与相似度匹配
        final minLen = a.length < b.length ? a.length : b.length;
        final maxLen = a.length > b.length ? a.length : b.length;
        if (minLen * 2 < maxLen) continue;
        final dice = _diceSimilarity(a, b);
        if (dice >= minRatio && dice > bestDice) {
          best = j;
          bestDice = dice;
        }
      }
      if (best >= 0) {
        pairs.add((i, best));
        moreStart = best + 1;
      }
    }

    if (pairs.isEmpty) return false;

    var curLess = 0;
    var curMore = 0;
    for (final (li, mi) in pairs) {
      // 配对前的行：按新增/删除输出
      for (var k = curLess; k < li; k++) {
        rows.add(lessIsLeft
            ? _deleteRow(less[k])
            : _insertRow(less[k]));
      }
      for (var k = curMore; k < mi; k++) {
        rows.add(lessIsLeft
            ? _insertRow(more[k])
            : _deleteRow(more[k]));
      }
      // 配对行：行内字符级对比
      rows.add(_replaceRow(less[li], more[mi]));
      curLess = li + 1;
      curMore = mi + 1;
    }
    for (var k = curLess; k < less.length; k++) {
      rows.add(lessIsLeft ? _deleteRow(less[k]) : _insertRow(less[k]));
    }
    for (var k = curMore; k < more.length; k++) {
      rows.add(lessIsLeft ? _insertRow(more[k]) : _deleteRow(more[k]));
    }
    return true;
  }

  /// 按位置相邻配对：第 k 对配对为 replace，多余的按新增/删除输出
  void _pairPositional(
    List<_LineInfo> lContent,
    List<_LineInfo> rContent,
    List<DiffRow> rows,
  ) {
    final pairCount = lContent.length < rContent.length
        ? lContent.length
        : rContent.length;
    for (var k = 0; k < pairCount; k++) {
      rows.add(_replaceRow(lContent[k], rContent[k]));
    }
    for (var k = pairCount; k < lContent.length; k++) {
      rows.add(_deleteRow(lContent[k]));
    }
    for (var k = pairCount; k < rContent.length; k++) {
      rows.add(_insertRow(rContent[k]));
    }
  }

  // ==================== 行内字符级对比 ====================

  DiffRow _replaceRow(_LineInfo left, _LineInfo right) {
    return DiffRow(
      leftIndex: left.index,
      rightIndex: right.index,
      op: DiffOp.replace,
      leftText: left.text,
      rightText: right.text,
      leftSpans: _charDiffSpans(left.fullChars, right.fullChars, left.text),
      rightSpans: _charDiffSpans(right.fullChars, left.fullChars, right.text),
    );
  }

  DiffRow _deleteRow(_LineInfo l) => DiffRow(
        leftIndex: l.index,
        rightIndex: null,
        op: DiffOp.delete,
        leftText: l.text,
      );

  DiffRow _insertRow(_LineInfo r) => DiffRow(
        leftIndex: null,
        rightIndex: r.index,
        op: DiffOp.insert,
        rightText: r.text,
      );

  /// 单行字符级差分：Hirschberg LCS → 行内相等/不等片段（对应上游 cmpLine）
  static List<CharSpan> _charDiffSpans(
    List<String> lineChars,
    List<String> otherChars,
    String fullText,
  ) {
    final lcs = Lcs(lineChars, otherChars);
    final lcsLength = lcs.lcsLength();

    if (lcsLength <= 0) {
      return [CharSpan(fullText, changed: true)];
    }

    final lcsIndices = lcs.cmp();
    if (lcsIndices == null || lcsIndices.isEmpty) {
      return [CharSpan(fullText, changed: true)];
    }

    final lcsChars = [for (final idx in lcsIndices) lineChars[idx]];
    final sections = _splitSections(lineChars, lcsChars);
    return _spansFromSections(sections);
  }

  /// 将一行的字符按 LCS 序列切分为相等/不等片段（对应上游 lineCmpLcs）
  static List<SectionNode> _splitSections(
      List<String> lineChars, List<String> lcsChars) {
    final result = <SectionNode>[];
    var noEqualTimes = 0;
    var equalTimes = 0;
    var lcsIndex = 0;
    final linesLength = lineChars.length;
    final lcsLength = lcsChars.length;
    var fileSrcIndex = 0;

    // 第二层循环，处理一行的每一个字符
    while (fileSrcIndex < linesLength) {
      // 第三层循环：把相等与不等的字符各分成一段段
      while (fileSrcIndex < linesLength &&
          (lcsIndex >= lcsLength ||
              lineChars[fileSrcIndex] != lcsChars[lcsIndex])) {
        if (equalTimes > 0) {
          result.add(
              _sectionFrom(lineChars, fileSrcIndex - equalTimes, equalTimes, true));
          equalTimes = 0;
        }
        ++fileSrcIndex;
        ++noEqualTimes;
      }

      // 加入不相等的
      if (noEqualTimes > 0) {
        result.add(
            _sectionFrom(lineChars, fileSrcIndex - noEqualTimes, noEqualTimes, false));
        noEqualTimes = 0;
      }

      // 遇到一个相等的
      if (fileSrcIndex < linesLength && lcsIndex < lcsLength) {
        ++equalTimes;
        ++lcsIndex;
        ++fileSrcIndex;
      }
    }

    // 退出第二层循环时，处理尾部的情况
    if (equalTimes > 0) {
      result.add(
          _sectionFrom(lineChars, fileSrcIndex - equalTimes, equalTimes, true));
    } else if (noEqualTimes > 0) {
      result.add(
          _sectionFrom(lineChars, fileSrcIndex - noEqualTimes, noEqualTimes, false));
    }

    // 将最后的换行段归并到前一个节（保留其相等状态）
    _dealLineTail(result);

    return result;
  }

  static SectionNode _sectionFrom(
      List<String> chars, int start, int length, bool equal) {
    return SectionNode(
      equal: equal,
      text: chars.sublist(start, start + length).join(),
    );
  }

  /// 将最后的换行段归并到前一个节（对应上游 dealLineTail）
  ///
  /// 行尾（\r）若与前一节相等状态不同，用 tailStatus/tailLens 记录，
  /// 以便显示时单独标记换行符的相等状态
  static void _dealLineTail(List<SectionNode> result) {
    if (result.length >= 2 &&
        (result.last.text == '\r\n' ||
            result.last.text == '\n' ||
            result.last.text == '\r')) {
      final last = result.removeLast();
      final curLast = result.last;
      curLast.text = curLast.text + last.text;
      // 如果前后节相等状态不一样
      if (last.equal != curLast.equal) {
        curLast.tailStatus = last.equal ? 1 : 2;
        // 后面设置相等或不等时，要扣除尾巴上的长度
        curLast.tailLens = last.text.runes.length;
      }
    }
  }

  /// 行内片段 → 字符差异片段（行尾单独标记相等状态）
  static List<CharSpan> _spansFromSections(List<SectionNode> sections) {
    final spans = <CharSpan>[];
    for (final section in sections) {
      if (section.tailLens > 0 && section.tailStatus != 0) {
        final mainLen = section.text.runes.length - section.tailLens;
        final mainText = String.fromCharCodes(
            section.text.runes.take(mainLen).toList());
        final tailText = String.fromCharCodes(
            section.text.runes.skip(mainLen).toList());
        if (mainText.isNotEmpty) {
          spans.add(CharSpan(mainText, changed: !section.equal));
        }
        spans.add(CharSpan(tailText, changed: section.tailStatus != 1));
      } else {
        spans.add(CharSpan(section.text, changed: !section.equal));
      }
    }
    return spans;
  }

  // ==================== 相似度 ====================

  /// 字符二元组 Dice 系数：2 × 公共二元组数 / 双方二元组总数
  static double _diceSimilarity(String a, String b) {
    final bigramsA = _bigrams(a);
    final bigramsB = _bigrams(b);
    if (bigramsA.isEmpty || bigramsB.isEmpty) return 0;

    final counts = <String, int>{};
    for (final g in bigramsA) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
    var intersection = 0;
    for (final g in bigramsB) {
      final count = counts[g];
      if (count != null && count > 0) {
        intersection++;
        counts[g] = count - 1;
      }
    }
    return 2 * intersection / (bigramsA.length + bigramsB.length);
  }

  static List<String> _bigrams(String s) {
    final runes = s.runes.toList();
    if (runes.length < 2) return const [];
    return [
      for (var i = 0; i < runes.length - 1; i++)
        String.fromCharCodes([runes[i], runes[i + 1]]),
    ];
  }
}

/// 行信息（内部模型，对应上游 LineFileInfo）
class _LineInfo {
  /// 行号（原始文件行号）
  final int index;

  /// 行完整文本（CRLF 文件行尾的 \r 保留在文本内）
  final String text;

  /// 去掉行尾后的内容（相似度匹配用）
  final String content;

  /// 是否空白行（去掉行尾后为空）
  final bool isEmpty;

  /// 行内容哈希（指纹串），参与行级锚点匹配
  final String hash;

  /// 完整字符列表（含行尾，行内字符级对比用）
  final List<String> fullChars;

  _LineInfo({
    required this.index,
    required this.text,
    required this.content,
    required this.isEmpty,
    required this.hash,
    required this.fullChars,
  });
}
