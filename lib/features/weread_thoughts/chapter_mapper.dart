import 'dart:convert';
import 'dart:math';

/// 章节映射器输入:一条划线
class UnderlineInput {
  final String range;
  final String markText;

  UnderlineInput({required this.range, required this.markText});
}

/// 章节映射器输入:一条想法
class ReviewInput {
  final String content;
  final String abstract;
  final String author;
  final int likes;

  ReviewInput({
    required this.content,
    this.abstract = '',
    this.author = '',
    this.likes = 0,
  });
}

/// 章节映射器输入:一章的合并数据
class ChapterInput {
  final String uid;
  final String title;
  final List<UnderlineInput> underlines;
  final Map<String, List<ReviewInput>> reviewMap;

  ChapterInput({
    required this.uid,
    required this.title,
    required this.underlines,
    required this.reviewMap,
  });
}

/// 映射结果:一个远端章 → 一个本地文件
class MappedChapter {
  final String chapterUid;
  final String href;
  final List<UnderlineInput> underlines;
  final Map<String, List<ReviewInput>> reviewMap;
  final bool quoteOnly;

  MappedChapter({
    required this.chapterUid,
    required this.href,
    required this.underlines,
    required this.reviewMap,
    this.quoteOnly = false,
  });
}

/// 未匹配章节
class UnmatchedChapter {
  final String uid;
  final String title;
  final String reason;

  UnmatchedChapter({
    required this.uid,
    required this.title,
    required this.reason,
  });
}

/// 章节映射:用划线引文在本地 spine 文档里投票,把读书章节映射到 EPUB 内 href。
///
/// 移植自 pickthought.koplugin 的 chapter_map.lua。
/// 引文和文档正文走同一套 normalize(剥标签、解实体、去全部空白),
/// 这样换行/排版/实体化差异不影响命中;引文全不中时用章节标题兜底(避开目录页)。
class ChapterMapper {
  ChapterMapper._();

  /// 匹配算法版本:任何影响匹配结果的改动都必须 +1。
  static const algoVersion = 7;

  /// HTML 命名实体映射
  static const _entities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '',
    'ensp': '',
    'emsp': '',
    'thinsp': '',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'ldquo': '\u201C',
    'rdquo': '\u201D',
    'lsquo': '\u2018',
    'rsquo': '\u2019',
  };

  /// UTF-8 码点编码为字符串
  static String _utf8Char(int code) {
    if (code < 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
      return '';
    }
    return String.fromCharCode(code);
  }

  /// 全角→半角(字母/数字/标点)
  /// 出版版标题/正文常用全角,不转就和半角对不上。
  static String _foldFullwidth(String value) {
    final buffer = StringBuffer();
    for (final char in value.runes) {
      if (char >= 0xFF01 && char <= 0xFF5E) {
        buffer.writeCharCode(char - 0xFEE0);
      } else {
        buffer.writeCharCode(char);
      }
    }
    return buffer.toString();
  }

  /// 归一化:剥标签、解 HTML 实体、全角转半角、去不可见字符和空白
  ///
  /// 不可见字符只清真正的空白和不可见字符(单码点精确清除)。
  /// 不能用范围(如 U+2000-U+203F / U+3000-U+303F)——会误清弯引号、
  /// 中文句号、破折号等内容标点,导致引文/正文 normalize 后丢内容,匹配全挂。
  static String normalize(String value) {
    // 剥标签
    var text = value.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // 解数值实体 &#x...; 和 &#...;
    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => _utf8Char(int.parse(m.group(1)!, radix: 16)),
    );
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => _utf8Char(int.parse(m.group(1)!)),
    );

    // 解命名实体 &...;
    text = text.replaceAllMapped(
      RegExp(r'&(\w+);'),
      (m) => _entities[m.group(1)] ?? '',
    );

    // 全角→半角
    text = _foldFullwidth(text);

    // 去不可见字符(精确清除单码点)
    text = text.replaceAll('\u00A0', ''); // nbsp
    text = text.replaceAll('\u00AD', ''); // soft hyphen
    text = text.replaceAll('\u3000', ''); // 全角空格
    text = text.replaceAll('\u200B', ''); // 零宽空格
    text = text.replaceAll('\u200C', ''); // 零宽非连接符
    text = text.replaceAll('\u200D', ''); // 零宽连接符
    text = text.replaceAll('\uFEFF', ''); // BOM

    // 去所有空白
    text = text.replaceAll(RegExp(r'\s+'), '');

    return text;
  }

  /// 标题钥匙:剥掉「第X章/节/回…」编号前缀。
  ///
  /// 远端与本地书的章号体系经常不一致(实测:远端「第六章」= 本地「第二百八十四章」),
  /// 整标题匹配必死;章名本体才是稳定标识。
  /// 剥完不足 6 字符退回全标题。
  static String titleKey(String title) {
    final t = normalize(title);
    final stripped = t.replaceAll(
      RegExp(r'^第[\d零一二三四五六七八九十百千两]+[章节回卷部集篇]'),
      '',
    );
    if (stripped.length >= 6) return stripped;
    return t;
  }

  /// 参与投票的引文至少 12 字符(约 4 个汉字)
  static const _minQuoteChars = 12;

  /// 引文只取前缀窗口:远端对长引文会做中段省略,前缀最保真
  static const _maxQuoteBytes = 90;

  /// 取引文前缀(按 UTF-8 字节切,退到完整字符边界)
  static String _utf8Prefix(String text, int maxBytes) {
    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) return text;
    var cut = maxBytes;
    // 退到完整 UTF-8 字符边界:下一字节若是续字节(0x80-0xBF)说明切在字符中间
    while (cut > 0) {
      final nextByte = cut < bytes.length ? bytes[cut] : 0;
      if (nextByte < 0x80 || nextByte >= 0xC0) break;
      cut--;
    }
    return utf8.decode(bytes.sublist(0, cut), allowMalformed: true);
  }

  /// 从划线列表中提取引文
  ///
  /// 每条划线取 markText,normalize 后取前 90 字节前缀。
  /// 至少 12 字符,去重。保持原始顺序(热门划线按热度排)。
  static List<String> quotesOf(
    List<UnderlineInput> underlines, {
    int limit = 8,
  }) {
    final out = <String>[];
    final seen = <String>{};

    for (final row in underlines) {
      if (out.length >= limit) break;
      final quote = _utf8Prefix(normalize(row.markText), _maxQuoteBytes);
      if (quote.length >= _minQuoteChars && !seen.contains(quote)) {
        seen.add(quote);
        out.add(quote);
      }
    }
    return out;
  }

  /// 构建章节映射
  ///
  /// [spine] EPUB 的 spine href 列表(按阅读顺序)
  /// [readText] 读取 href 对应文件 HTML 内容的函数
  /// [chapters] 读书章节数据(含引文和想法)
  /// 返回 (mapped, unmatched)
  static (List<MappedChapter>, List<UnmatchedChapter>) build(
    List<String> spine,
    String Function(String href) readText,
    List<ChapterInput> chapters,
  ) {
    // 预计算每章引文与规范化标题;全部标题用于识别目录页
    final quotesList = <List<String>>[];
    final titles = <String?>[];
    final allTitles = <String>{};

    for (final ch in chapters) {
      quotesList.add(
        ch.underlines.isNotEmpty ? quotesOf(ch.underlines) : <String>[],
      );
      final title = titleKey(ch.title);
      if (title.length >= 6) {
        titles.add(title);
        allTitles.add(title);
      } else {
        titles.add(null);
      }
    }

    // 目录页检测阈值:一个文件若包含大半章节标题,它是目录/导航页
    final tocThreshold = max(2, (allTitles.length * 0.5).ceil());

    final scores = <int, List<({String href, int score})>>{};
    final titleHits = <int, List<String>>{};

    // 逐 spine 文件:normalize 正文 → 统计各章引文命中 → 统计标题命中
    for (final href in spine) {
      String text;
      try {
        final html = readText(href);
        text = normalize(html);
      } catch (_) {
        continue;
      }
      if (text.isEmpty) continue;

      final fileTitleCis = <int>[];
      final distinctTitles = <String>{};

      for (var ci = 0; ci < chapters.length; ci++) {
        // 引文投票
        final quotes = quotesList[ci];
        if (quotes.isNotEmpty) {
          var score = 0;
          for (final quote in quotes) {
            if (text.contains(quote)) score++;
          }
          if (score > 0) {
            scores.putIfAbsent(ci, () => []).add((href: href, score: score));
          }
        }

        // 标题命中
        final title = titles[ci];
        if (title != null && text.contains(title)) {
          fileTitleCis.add(ci);
          distinctTitles.add(title);
        }
      }

      // 目录页检测:超过阈值的标题命中整批作废
      if (distinctTitles.length < tocThreshold) {
        for (final ci in fileTitleCis) {
          titleHits.putIfAbsent(ci, () => []).add(href);
        }
      }
    }

    // 定案:一个远端章可以映射到多个本地文件(拆分章)
    const maxTargets = 4;
    final mapped = <MappedChapter>[];
    final unmatched = <UnmatchedChapter>[];

    for (var ci = 0; ci < chapters.length; ci++) {
      final ch = chapters[ci];

      if (ch.underlines.isEmpty) {
        unmatched.add(UnmatchedChapter(
          uid: ch.uid,
          title: ch.title,
          reason: 'no_data',
        ));
        continue;
      }

      // 统一定案规则:得分 >= min(2, 引文数) 的文件都是注入目标
      final strongMin = min(2, quotesList[ci].length);
      final chapterScores = scores[ci] ?? [];
      var targets = <String>[];
      var voteSingle = false;

      for (final entry in chapterScores) {
        if (entry.score >= strongMin && targets.length < maxTargets) {
          targets.add(entry.href);
        }
      }

      // 单引文命中多个文件是真歧义,放弃投票
      if (strongMin == 1 && targets.length > 1) {
        targets = [];
      }

      if (targets.isNotEmpty) {
        voteSingle = targets.length == 1;
      } else {
        // 标题兜底:放宽到 1~3 个命中
        final hits = titleHits[ci] ?? [];
        if (hits.isNotEmpty && hits.length <= 3) {
          targets = hits;
        }
      }

      if (targets.isNotEmpty) {
        // 只有「投票强证据 + 单目标」保留数字兜底;
        // 其余场景一律 quote_only,防止错位与跨文件重复。
        final quoteOnly = !voteSingle;
        for (final href in targets) {
          mapped.add(MappedChapter(
            chapterUid: ch.uid,
            href: href,
            underlines: ch.underlines,
            reviewMap: ch.reviewMap,
            quoteOnly: quoteOnly,
          ));
        }
      } else {
        unmatched.add(UnmatchedChapter(
          uid: ch.uid,
          title: ch.title,
          reason: 'no_hit',
        ));
      }
    }

    return (mapped, unmatched);
  }
}
