import 'package:epub_gadget/features/txt2epub/models/chapter.dart';

/// 数字字符集（含中文数字）
///
/// 匹配阿拉伯数字和中文数字，用于章节序号识别。
/// 预设正则中已内联此字符集，此处保留定义为参考常量。
// ignore: unused_element
const String _d = r'[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]';

/// 预设正则项
///
/// 每项包含名称、正则模式字符串、层级和是否切分标志。
class PresetPattern {
  /// 预设名称（用于下拉选择显示）
  final String name;

  /// 正则模式字符串
  final String pattern;

  /// 标题层级（1=h1, 2=h2...）
  final int level;

  /// 是否切分（true=按此模式切分章节，false=不切分，合并到上一章）
  final bool split;

  const PresetPattern(this.name, this.pattern, this.level, this.split);
}

/// 预设正则列表
///
/// 移植自 Python chapter_splitter.py 并扩展，覆盖常见的章节标题格式。
/// 每套预设包含 name（名称）、pattern（正则）、level（层级）、split（是否切分）。
final List<PresetPattern> presetPatterns = [
  // 1. 目录(第X章/节/卷/集/部/篇)
  PresetPattern(
    '目录(第X章/节/卷/集/部/篇)',
    r'''^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$''',
    1,
    true,
  ),
  // 2. 目录-古典(含回/场/话)
  PresetPattern(
    '目录-古典(含回/场/话)',
    r'''^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张)|回|场|话)).{0,30}$''',
    1,
    true,
  ),
  // 3. 数字+分隔符(1、标题)
  PresetPattern(
    '数字+分隔符(1、标题)',
    r'''^[ 　\t]{0,4}\d{1,5}[:：,.， 、_—\-].{1,30}$''',
    2,
    true,
  ),
  // 4. 中文数字+分隔符(一、标题)
  PresetPattern(
    '中文数字+分隔符(一、标题)',
    r'''^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\-].{1,30}$''',
    2,
    true,
  ),
  // 5. 正文+标题
  PresetPattern('正文+标题', r'''^[ 　\t]{0,4}正文[ 　]{1,4}.{0,20}$''', 1, true),
  // 6. Chapter/Section/Part/Episode
  PresetPattern(
    'Chapter/Section/Part/Episode',
    r'''^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$''',
    1,
    true,
  ),
  // 7. 特殊符号+序号(【第X章】)
  PresetPattern(
    '特殊符号+序号(【第X章】)',
    r'''^[ 　\t]{0,4}[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$''',
    2,
    true,
  ),
  // 8. 特殊符号+标题(☆标题)
  PresetPattern(
    '特殊符号+标题(☆标题)',
    r'''^[ 　\t]{0,4}(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$''',
    2,
    true,
  ),
  // 9. 章/卷+序号(卷五标题)
  PresetPattern(
    '章/卷+序号(卷五标题)',
    r'''^[ \t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$''',
    1,
    true,
  ),
  // 10. 书名+括号序号(标题(12))
  PresetPattern(
    '书名+括号序号(标题(12))',
    r'''^[\u4e00-\u9fa5]{1,20}[ 　\t]{0,4}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\t]{0,4}$''',
    2,
    true,
  ),
  // 11. 书名+序号(标题124)
  PresetPattern(
    '书名+序号(标题124)',
    r'''^[\u4e00-\u9fa5]{1,20}[ 　\t]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\t]{0,4}$''',
    2,
    true,
  ),
  // 12. 分页/分节阅读（不切分，合并到上一章）
  PresetPattern(
    '分页/分节阅读',
    r'''^[ 　\t]{0,4}(?:.{0,15}分[页节章段]阅读[-_ ]|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,6}\s{0,4}[页节]).{0,30}$''',
    2,
    false,
  ),
  // 13. 纯数字行（单独一行的数字作为章节标题）
  PresetPattern('纯数字行', r'''^[ 　\t]{0,4}\d{1,6}[ 　\t]{0,4}$''', 1, true),
  // 14. Markdown 标题（# 标题 / ## 标题）
  PresetPattern('Markdown标题(# 标题)', r'''^#{1,6}[ 　]+.{1,50}$''', 1, true),
  // 15. 卷+章组合（第一卷 第一章 标题）
  PresetPattern(
    '卷+章组合(第X卷 第X章)',
    r'''^[ 　\t]{0,4}第\s{0,2}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}\s{0,2}[卷部]\s*第\s{0,2}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}\s{0,2}[章节回].{0,30}$''',
    1,
    true,
  ),
  // 16. 英文标题（全大写或首字母大写，单独一行）
  PresetPattern(
    '英文标题(TITLE HERE)',
    r'''^[ 　\t]{0,4}(?:[A-Z][A-Z\s]{2,40}|[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,5})[ 　\t]{0,4}$''',
    2,
    true,
  ),
  // 17. 日期标题（2024-01-01 / 01/01 / 一月一日）
  PresetPattern(
    '日期标题',
    r'''^[ 　\t]{0,4}(?:\d{4}[-/年.]\d{1,2}[-/月.]\d{1,2}日?|\d{1,2}[-/]\d{1,2}|[〇零一二两三四五六七八九十]{1,4}月[〇零一二两三四五六七八九十]{1,4}日).{0,20}$''',
    2,
    true,
  ),
  // 18. 引号/书名号标题（《标题》/「标题」)
  PresetPattern(
    '引号标题(《标题》)',
    r'''^[ 　\t]{0,4}[《〈「『【\[「「].{1,30}[》〉」』】\]」」][ 　\t]{0,4}$''',
    2,
    true,
  ),
  // 19. 节标记（§1 标题 / § 1.1 标题）
  PresetPattern(
    '节标记(§1 标题)',
    r'''^[ 　\t]{0,4}§\s*\d{1,4}(?:\.\d{1,4})*\.?\s*.{0,30}$''',
    2,
    true,
  ),
  // 20. 上卷/下卷/上篇/下篇（无序号的结构标记）
  PresetPattern(
    '上下卷篇(上卷/下篇)',
    r'''^[ 　\t]{0,4}(?:上|下|前|后|续|终)(?:卷|部|篇|册|集|章)[ 　\t]{0,4}.{0,20}$''',
    1,
    true,
  ),
  // SplitChapter 风格：独立规则可自动组合出卷/部→章/回→节的多级目录。
  PresetPattern('卷标题（中文数字）', r'^\s*第[一二三四五六七八九十零〇百千两]+卷.*$', 1, true),
  PresetPattern('部标题（中文数字）', r'^\s*第[一二三四五六七八九十零〇百千两]+部.*$', 1, true),
  PresetPattern('章标题（中文数字）', r'^\s*第[一二三四五六七八九十零〇百千两]+章.*$', 2, true),
  PresetPattern('回标题（中文数字）', r'^\s*第[一二三四五六七八九十零〇百千两]+回.*$', 2, true),
  PresetPattern('节标题（中文数字）', r'^\s*第[一二三四五六七八九十零〇百千两]+节.*$', 3, true),
  PresetPattern('卷标题（数字）', r'^\s*第\d+卷.*$', 1, true),
  PresetPattern('部标题（数字）', r'^\s*第\d+部.*$', 1, true),
  PresetPattern('章标题（数字）', r'^\s*第\d+章.*$', 2, true),
  PresetPattern('回标题（数字）', r'^\s*第\d+回.*$', 2, true),
  PresetPattern('节标题（数字）', r'^\s*第\d+节.*$', 3, true),
  PresetPattern('序言/简介/后记/尾声', r'^\s*(?:序[1-9言曲]?|内容简介|简介|后记|尾声)\s*$', 2, true),
];

/// 一行分章规则。规则按列表顺序执行，同一行只采用首个匹配规则。
class ChapterSplitRule {
  const ChapterSplitRule({
    required this.pattern,
    required this.level,
    required this.split,
  });

  final String pattern;
  final int level;
  final bool split;
}

/// 预览中识别到的标题。
class ChapterTitleMatch {
  const ChapterTitleMatch({
    required this.lineIndex,
    required this.title,
    required this.level,
    required this.split,
    required this.ruleIndex,
    required this.ignored,
  });

  final int lineIndex;
  final String title;
  final int level;
  final bool split;
  final int ruleIndex;
  final bool ignored;
}

/// 一次规则分析的完整结果。
class ChapterSplitAnalysis {
  const ChapterSplitAnalysis({
    required this.chapters,
    required this.matches,
    required this.matchCounts,
    required this.invalidRuleIndexes,
  });

  final List<Chapter> chapters;
  final List<ChapterTitleMatch> matches;
  final List<int> matchCounts;
  final List<int> invalidRuleIndexes;
}

/// 章节分割器
///
/// 提供常见标题预设、自定义正则以及顺序多规则分章功能。
class ChapterSplitter {
  /// 扁平切分
  ///
  /// 使用单个正则模式对文本进行切分，返回扁平的章节列表。
  /// 逐行扫描文本，匹配到标题行时开始新章节，非匹配行归入当前章节正文。
  ///
  /// [text] 待分割的文本
  /// [customPattern] 正则模式字符串（预设或自定义）
  /// [splitTitle] 是否将标题从正文中拆出（true=标题不包含在正文中，false=标题保留在正文首行）
  /// 返回切分后的章节列表
  List<Chapter> split(
    String text,
    String customPattern, {
    bool splitTitle = false,
  }) {
    return analyzeAndSplit(text, [
      ChapterSplitRule(pattern: customPattern, level: 1, split: true),
    ], keepSplitTitleInContent: !splitTitle).chapters;
  }

  /// 多级规则切分
  ///
  /// 使用多套正则从上到下扫描文本，再按 [levels] 生成嵌套目录。
  /// 同一行只会由第一条匹配的规则处理。
  /// [splits] 数组控制每层模式是否实际切分（false=匹配行合并到上一章正文）。
  ///
  /// [text] 待分割的文本
  /// [patterns] 各层正则模式字符串列表
  /// [levels] 各层标题层级列表
  /// [splits] 各层是否切分标志列表
  /// 返回嵌套的章节列表
  List<Chapter> splitHierarchical(
    String text,
    List<String> patterns,
    List<int> levels,
    List<bool> splits,
  ) {
    final count = [
      patterns.length,
      levels.length,
      splits.length,
    ].reduce((a, b) => a < b ? a : b);
    final rules = [
      for (var i = 0; i < count; i++)
        ChapterSplitRule(
          pattern: patterns[i],
          level: levels[i],
          split: splits[i],
        ),
    ];
    return analyzeAndSplit(text, rules).chapters;
  }

  /// 按 SplitChapter 的行为顺序扫描规则并生成预览与章节树。
  ///
  /// - 规则从上到下执行，同一行由首个匹配规则处理，避免重复匹配。
  /// - `split=true` 的标题创建独立 XHTML 页面。
  /// - `split=false` 的标题保留在当前页面，并输出为对应 h1–h6。
  /// - [ignoredLineIndexes] 中的误识别标题按普通正文处理。
  /// - [suppressedLineIndexes] 中的行不再参与任何规则匹配，用于整类取消。
  ChapterSplitAnalysis analyzeAndSplit(
    String text,
    List<ChapterSplitRule> rules, {
    Set<int> ignoredLineIndexes = const {},
    Set<int> suppressedLineIndexes = const {},
    bool keepSplitTitleInContent = false,
  }) {
    if (text.trim().isEmpty) {
      return ChapterSplitAnalysis(
        chapters: [Chapter(title: '正文', content: text, level: 1)],
        matches: const [],
        matchCounts: List<int>.filled(rules.length, 0),
        invalidRuleIndexes: const [],
      );
    }

    final compiled = <RegExp?>[];
    final invalidRuleIndexes = <int>[];
    for (var i = 0; i < rules.length; i++) {
      final source = rules[i].pattern.trim();
      if (source.isEmpty) {
        compiled.add(null);
        continue;
      }
      try {
        compiled.add(RegExp(source));
      } catch (_) {
        compiled.add(null);
        invalidRuleIndexes.add(i);
      }
    }

    final lines = text.split('\n');
    final matches = <ChapterTitleMatch>[];
    final matchesByLine = <int, ChapterTitleMatch>{};
    final matchCounts = List<int>.filled(rules.length, 0);
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      if (suppressedLineIndexes.contains(lineIndex)) continue;
      final sourceLine = lines[lineIndex].replaceFirst(RegExp(r'\r$'), '');
      for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
        final pattern = compiled[ruleIndex];
        if (pattern == null || !pattern.hasMatch(sourceLine)) continue;
        final rule = rules[ruleIndex];
        final match = ChapterTitleMatch(
          lineIndex: lineIndex,
          title: sourceLine.trim(),
          level: rule.level.clamp(1, 6),
          split: rule.split,
          ruleIndex: ruleIndex,
          ignored: ignoredLineIndexes.contains(lineIndex),
        );
        matches.add(match);
        matchesByLine[lineIndex] = match;
        matchCounts[ruleIndex]++;
        break;
      }
    }

    final drafts = <_PageDraft>[];
    String? currentTitle;
    var currentLevel = 1;
    var synthetic = true;
    int? currentSourceLineIndex;
    int? currentRuleIndex;
    var currentLines = <String>[];
    var inlineHeadings = <ChapterInlineHeading>[];

    void flush() {
      final hasContent = currentLines.any((line) => line.trim().isNotEmpty);
      if (currentTitle == null && !hasContent) return;

      var firstContentLine = 0;
      while (firstContentLine < currentLines.length &&
          currentLines[firstContentLine].trim().isEmpty) {
        firstContentLine++;
      }
      var lastContentLine = currentLines.length;
      while (lastContentLine > firstContentLine &&
          currentLines[lastContentLine - 1].trim().isEmpty) {
        lastContentLine--;
      }
      final normalizedLines = currentLines.sublist(
        firstContentLine,
        lastContentLine,
      );
      final normalizedHeadings = [
        for (final heading in inlineHeadings)
          if (heading.lineIndex >= firstContentLine &&
              heading.lineIndex < lastContentLine)
            ChapterInlineHeading(
              lineIndex: heading.lineIndex - firstContentLine,
              level: heading.level,
            ),
      ];
      drafts.add(
        _PageDraft(
          title: currentTitle ?? (drafts.isEmpty ? '简介' : '正文'),
          content: normalizedLines.join('\n'),
          level: currentLevel,
          synthetic: synthetic,
          sourceLineIndex: currentSourceLineIndex,
          matchedRuleIndex: currentRuleIndex,
          inlineHeadings: List.unmodifiable(normalizedHeadings),
        ),
      );
    }

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex].replaceFirst(RegExp(r'\r$'), '');
      final match = matchesByLine[lineIndex];
      if (match != null && match.split && !match.ignored) {
        flush();
        currentTitle = match.title;
        currentLevel = match.level;
        synthetic = false;
        currentSourceLineIndex = match.lineIndex;
        currentRuleIndex = match.ruleIndex;
        currentLines = keepSplitTitleInContent ? [match.title] : <String>[];
        inlineHeadings = <ChapterInlineHeading>[];
        continue;
      }

      if (match != null && !match.split && !match.ignored) {
        inlineHeadings.add(
          ChapterInlineHeading(
            lineIndex: currentLines.length,
            level: match.level,
          ),
        );
      }
      currentLines.add(line);
    }
    flush();

    if (drafts.isEmpty) {
      drafts.add(
        _PageDraft(
          title: '正文',
          content: text.trim(),
          level: 1,
          synthetic: true,
          sourceLineIndex: null,
          matchedRuleIndex: null,
          inlineHeadings: const [],
        ),
      );
    }

    return ChapterSplitAnalysis(
      chapters: _buildChapterTree(drafts),
      matches: List.unmodifiable(matches),
      matchCounts: List.unmodifiable(matchCounts),
      invalidRuleIndexes: List.unmodifiable(invalidRuleIndexes),
    );
  }

  List<Chapter> _buildChapterTree(List<_PageDraft> drafts) {
    final roots = <_MutableChapter>[];
    final stack = <_MutableChapter>[];

    for (final draft in drafts) {
      final node = _MutableChapter(draft);
      if (draft.synthetic) {
        roots.add(node);
        stack.clear();
        continue;
      }

      while (stack.isNotEmpty && stack.last.draft.level >= draft.level) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }

    Chapter freeze(_MutableChapter node) {
      return Chapter(
        title: node.draft.title,
        content: node.draft.content,
        level: node.draft.level,
        sourceLineIndex: node.draft.sourceLineIndex,
        matchedRuleIndex: node.draft.matchedRuleIndex,
        inlineHeadings: node.draft.inlineHeadings,
        children: node.children.map(freeze).toList(growable: false),
      );
    }

    return roots.map(freeze).toList(growable: false);
  }

  /// 扫描模式
  ///
  /// 用全部预设正则扫描文本，返回每套预设的匹配统计信息。
  /// 用于帮助用户选择最合适的分割预设。
  ///
  /// [text] 待扫描的文本
  /// 返回列表，每项为 Map，包含：
  /// - name: 预设名称
  /// - count: 匹配行数
  /// - chapters: 前 20 条匹配行（用于预览）
  /// - example: 第一条匹配行（示例）
  List<Map<String, dynamic>> scan(String text) {
    final results = <Map<String, dynamic>>[];
    final lines = text.split('\n');

    for (final preset in presetPatterns) {
      final RegExp pattern;
      try {
        pattern = RegExp(preset.pattern);
      } catch (_) {
        // 正则编译失败，记录零匹配
        results.add({
          'name': preset.name,
          'count': 0,
          'chapters': <String>[],
          'lineIndexes': <int>[],
          'example': '',
        });
        continue;
      }

      // 逐行匹配，收集匹配行
      final matchedLines = <String>[];
      final matchedLineIndexes = <int>[];
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final line = lines[lineIndex];
        final sourceLine = line.replaceFirst(RegExp(r'\r$'), '');
        if (pattern.hasMatch(sourceLine)) {
          matchedLines.add(sourceLine.trim());
          matchedLineIndexes.add(lineIndex);
        }
      }

      results.add({
        'name': preset.name,
        'count': matchedLines.length,
        'chapters': matchedLines.take(20).toList(),
        'lineIndexes': matchedLineIndexes,
        'example': matchedLines.isNotEmpty ? matchedLines.first : '',
      });
    }

    return results;
  }
}

class _PageDraft {
  const _PageDraft({
    required this.title,
    required this.content,
    required this.level,
    required this.synthetic,
    required this.sourceLineIndex,
    required this.matchedRuleIndex,
    required this.inlineHeadings,
  });

  final String title;
  final String content;
  final int level;
  final bool synthetic;
  final int? sourceLineIndex;
  final int? matchedRuleIndex;
  final List<ChapterInlineHeading> inlineHeadings;
}

class _MutableChapter {
  _MutableChapter(this.draft);

  final _PageDraft draft;
  final List<_MutableChapter> children = [];
}
