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

/// 20 套预设正则列表
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
];

/// 内部使用的原始章节数据（分割过程中的中间结果）
class _RawChapter {
  final String title;
  final String content;

  _RawChapter(this.title, this.content);
}

/// 章节分割器
///
/// 移植自 Python chapter_splitter.py，提供 12 套预设正则和自定义正则的章节分割功能。
/// 支持扁平切分和层级递归切分两种模式。
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
    // 空模式或空文本，整篇作为一个章节
    if (customPattern.isEmpty || text.trim().isEmpty) {
      return [Chapter(title: '正文', content: text, level: 1)];
    }

    final RegExp pattern;
    try {
      pattern = RegExp(customPattern);
    } catch (_) {
      // 正则编译失败，整篇作为一个章节
      return [Chapter(title: '正文', content: text, level: 1)];
    }

    // 逐行扫描切分
    final rawChapters = _splitTextInternal(text, pattern, true);

    // 转换为 Chapter 对象，根据 splitTitle 决定是否保留标题在正文中
    return rawChapters.map((rc) {
      var content = rc.content;
      if (!splitTitle && rc.title != '正文' && rc.title != '简介') {
        // 标题保留在正文首行。
        // 注：Dart 字符串插值 '$rc.title' 会被解析为 '$rc' + '.title'，
        // 导致 rc.toString() 被调用，输出 "Instance of '_RawChapter'.title"。
        // 必须用 ${rc.title} 显式访问字段。
        content = content.isEmpty ? rc.title : '${rc.title}\n$content';
      }
      return Chapter(title: rc.title, content: content.trim(), level: 1);
    }).toList();
  }

  /// 层级递归切分
  ///
  /// 使用多套正则模式递归切分文本，生成嵌套的章节结构。
  /// 第一套模式按 [levels[0]] 层级切分，每章内容再用第二套模式按 [levels[1]] 层级切分，依此类推。
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
    if (patterns.isEmpty || text.trim().isEmpty) {
      return [Chapter(title: '正文', content: text, level: 1)];
    }

    return _splitRecursive(text, patterns, levels, splits, 0);
  }

  /// 扫描模式
  ///
  /// 用全部 12 套预设正则扫描文本，返回每套预设的匹配统计信息。
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
          'example': '',
        });
        continue;
      }

      // 逐行匹配，收集匹配行
      final matchedLines = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (pattern.hasMatch(trimmed)) {
          matchedLines.add(trimmed);
        }
      }

      results.add({
        'name': preset.name,
        'count': matchedLines.length,
        'chapters': matchedLines.take(20).toList(),
        'example': matchedLines.isNotEmpty ? matchedLines.first : '',
      });
    }

    return results;
  }

  /// 递归切分内部实现
  ///
  /// [text] 当前层待分割的文本
  /// [patterns] 全部正则模式列表
  /// [levels] 全部层级列表
  /// [splits] 全部切分标志列表
  /// [depth] 当前递归深度（对应 patterns/levels/splits 的索引）
  /// 返回当前层的章节列表
  List<Chapter> _splitRecursive(
    String text,
    List<String> patterns,
    List<int> levels,
    List<bool> splits,
    int depth,
  ) {
    // 超出模式列表深度，返回为叶子章节
    if (depth >= patterns.length) {
      if (text.trim().isEmpty) return [];
      return [
        Chapter(
          title: '正文',
          content: text,
          level: depth > 0 ? levels[depth - 1] + 1 : 1,
        ),
      ];
    }

    final patternStr = patterns[depth];
    final level = levels[depth];
    final shouldSplit = splits[depth];

    // 空模式，直接递归下一层
    if (patternStr.isEmpty) {
      return _splitRecursive(text, patterns, levels, splits, depth + 1);
    }

    final RegExp pattern;
    try {
      pattern = RegExp(patternStr);
    } catch (_) {
      // 正则编译失败，直接递归下一层
      return _splitRecursive(text, patterns, levels, splits, depth + 1);
    }

    // 用当前模式分割文本
    final rawChapters = _splitTextInternal(text, pattern, shouldSplit);

    // 已是最深层，返回扁平章节
    if (depth + 1 >= patterns.length) {
      return rawChapters
          .map(
            (rc) => Chapter(title: rc.title, content: rc.content, level: level),
          )
          .toList();
    }

    // 递归分割每章的内容
    final result = <Chapter>[];
    for (final rc in rawChapters) {
      final children = _splitRecursive(
        rc.content,
        patterns,
        levels,
        splits,
        depth + 1,
      );
      result.add(
        Chapter(
          title: rc.title,
          // 有子章节时正文为空（正文已在子章节中），无子章节时保留正文
          content: children.isEmpty ? rc.content : '',
          level: level,
          children: children,
        ),
      );
    }
    return result;
  }

  /// 逐行扫描切分文本（内部方法）
  ///
  /// [text] 待分割的文本
  /// [pattern] 已编译的正则
  /// [shouldSplit] 是否按匹配行切分（false=匹配行归入正文，不切分）
  /// 返回原始章节列表
  List<_RawChapter> _splitTextInternal(
    String text,
    RegExp pattern,
    bool shouldSplit,
  ) {
    final lines = text.split('\n');
    final chapters = <_RawChapter>[];
    String? currentTitle;
    final currentContent = <String>[];

    for (final line in lines) {
      final trimmedLine = line.trim();
      final isMatch = pattern.hasMatch(trimmedLine);

      if (isMatch && shouldSplit) {
        // 匹配到标题且需要切分，保存前一章
        if (currentTitle != null) {
          chapters.add(
            _RawChapter(currentTitle, currentContent.join('\n').trim()),
          );
        } else if (currentContent.any((l) => l.trim().isNotEmpty)) {
          // 首个匹配之前有内容，作为「简介」章节
          chapters.add(_RawChapter('简介', currentContent.join('\n').trim()));
        }
        currentTitle = trimmedLine;
        currentContent.clear();
      } else {
        // 非匹配行或不需要切分的匹配行，归入当前章节正文
        currentContent.add(line);
      }
    }

    // 保存最后一章
    if (currentTitle != null) {
      chapters.add(_RawChapter(currentTitle, currentContent.join('\n').trim()));
    } else if (currentContent.any((l) => l.trim().isNotEmpty)) {
      // 没有匹配到任何标题，整篇作为一个章节
      chapters.add(_RawChapter('正文', currentContent.join('\n').trim()));
    }

    // 空文本兜底
    if (chapters.isEmpty && text.trim().isNotEmpty) {
      chapters.add(_RawChapter('正文', text));
    }

    return chapters;
  }
}
