/// 所有 Unicode 空白字符集合
///
/// 包含以下字符：
/// - \r \n \t \x20 \xa0（常规空白与不换行空格）
/// - \u2000-\u2007（各种宽度空格）
/// - \u2008-\u200a（标点空格等）
/// - \u200b \u200c \u200d（零宽字符）
/// - \u202f \u2060（窄不换行空格、字连接符）
/// - \u3000（全角空格）
/// - \ufeff（BOM / 零宽不换行空格）
const String blankChars =
    '\r\n\t\x20\xa0'
    '\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007'
    '\u2008\u2009\u200a'
    '\u200b\u200c\u200d'
    '\u202f\u2060'
    '\u3000'
    '\ufeff';

/// 空白字符集合（用于快速查找）
final Set<String> _blankCharSet = blankChars.split('').toSet();

/// 文本清洗器
///
/// 移植自 Python text_cleaner.py，提供文本规范化功能：
/// 1. 规范化换行符（\r\n → \n, \r → \n）
/// 2. 去除 BOM
/// 3. 去除多余空行（3+ 换行压缩为 \n\n，纯空白行删除）
/// 4. 修正缩进（每行去除首尾空白字符）
class TextCleaner {
  /// 是否去除多余空行
  final bool removeEmptyLines;

  /// 是否修正缩进
  final bool fixIndent;

  /// 构造函数
  ///
  /// [removeEmptyLines] 是否去除多余空行，默认 true
  /// [fixIndent] 是否修正缩进，默认 true
  TextCleaner({this.removeEmptyLines = true, this.fixIndent = true});

  /// 清洗文本
  ///
  /// 按以下步骤处理：
  /// 1. 规范化换行：\r\n → \n, \r → \n
  /// 2. 去除 BOM：去除开头的 \ufeff
  /// 3. 去多余空行（若 [removeEmptyLines] 为 true）：
  ///    - 3+ 连续换行压缩为 \n\n
  ///    - 纯空白行（仅含 [blankChars] 中字符的行）删除
  /// 4. 修正缩进（若 [fixIndent] 为 true）：每行去除首尾空白字符
  ///
  /// [text] 待清洗的原始文本
  /// 返回清洗后的文本
  String clean(String text) {
    // 1. 规范化换行：\r\n → \n, \r → \n
    var result = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. 去除 BOM：去除开头的 \ufeff
    result = result.replaceFirst(RegExp(r'^\ufeff+'), '');

    // 3. 去多余空行
    if (removeEmptyLines) {
      result = _removeExtraEmptyLines(result);
    }

    // 4. 修正缩进
    if (fixIndent) {
      result = _fixIndentation(result);
    }

    return result;
  }

  /// 去除多余空行
  ///
  /// 将 3+ 连续换行压缩为 \n\n，并删除纯空白行（仅含 [blankChars] 的行）。
  ///
  /// [text] 待处理的文本
  /// 返回处理后的文本
  String _removeExtraEmptyLines(String text) {
    // 3+ 换行压缩为 \n\n
    var result = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 纯空白行删除（只含空白字符的行）
    final lines = result.split('\n');
    final cleanedLines = <String>[];
    for (final line in lines) {
      if (!_isBlankLine(line)) {
        cleanedLines.add(line);
      }
    }
    return cleanedLines.join('\n');
  }

  /// 修正缩进
  ///
  /// 去除每行首尾的空白字符（使用 [blankChars] 定义）。
  ///
  /// [text] 待处理的文本
  /// 返回处理后的文本
  String _fixIndentation(String text) {
    final lines = text.split('\n');
    final fixedLines = lines.map((line) => _stripBlank(line)).toList();
    return fixedLines.join('\n');
  }

  /// 判断是否为纯空白行
  ///
  /// 空行或仅包含 [blankChars] 中字符的行返回 true。
  ///
  /// [line] 待检查的行
  /// 返回是否为纯空白行
  bool _isBlankLine(String line) {
    return line.split('').every((c) => _blankCharSet.contains(c));
  }

  /// 去除字符串首尾的空白字符
  ///
  /// 使用 [blankChars] 中定义的字符集进行裁剪。
  ///
  /// [s] 待裁剪的字符串
  /// 返回裁剪后的字符串
  String _stripBlank(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && _blankCharSet.contains(s[start])) {
      start++;
    }
    while (end > start && _blankCharSet.contains(s[end - 1])) {
      end--;
    }
    return s.substring(start, end);
  }
}
