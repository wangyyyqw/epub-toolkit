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
      'content: ${content.length} chars)';
}
