/// 章节正文中只作为标题显示、但不单独分页的标题行。
class ChapterInlineHeading {
  const ChapterInlineHeading({required this.lineIndex, required this.level});

  /// 在 [Chapter.content] 按换行拆分后的行号。
  final int lineIndex;

  /// XHTML 标题级别（1–6）。
  final int level;
}

/// 章节数据模型
///
/// 支持嵌套结构，用于层级章节分割。
/// [level] 表示标题层级（1=h1, 2=h2...），[children] 用于层级模式下的子章节。
class Chapter {
  /// 章节标题
  final String title;

  /// 章节正文（纯文本）
  final String content;

  /// 层级（1=h1, 2=h2...）
  final int level;

  /// 子章节（层级模式）
  final List<Chapter> children;

  /// 匹配到但未勾选“分割”的标题行。
  final List<ChapterInlineHeading> inlineHeadings;

  /// 该章节标题在源 TXT 中的行号（从 0 开始）。
  final int? sourceLineIndex;

  /// 识别该标题的规则索引；自动生成的正文页为 null。
  final int? matchedRuleIndex;

  /// 构造函数
  ///
  /// [title] 章节标题（必填）
  /// [content] 章节正文，默认为空
  /// [level] 标题层级，默认为 1
  /// [children] 子章节列表，默认为空
  const Chapter({
    required this.title,
    this.content = '',
    this.level = 1,
    this.children = const [],
    this.inlineHeadings = const [],
    this.sourceLineIndex,
    this.matchedRuleIndex,
  });

  /// 是否为叶子节点（无子章节）
  ///
  /// 叶子节点表示该章节没有更细的子章节分割，
  /// 其 [content] 字段包含实际正文内容。
  bool get isLeaf => children.isEmpty;

  /// 获取正文字数（字符数）
  ///
  /// 用于预览时显示每章字数统计。
  int get wordCount => content.length;

  @override
  String toString() =>
      'Chapter(title: $title, level: $level, children: ${children.length}, '
      'rule: $matchedRuleIndex, inlineHeadings: ${inlineHeadings.length}, '
      'content: ${content.length} chars)';
}
