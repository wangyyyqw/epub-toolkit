import 'package:flutter/services.dart' show rootBundle;

/// 简繁中文转换器
///
/// 基于 OpenCC 字典数据实现的纯 Dart 简繁转换。
/// 字典文件打包在 assets/opencc/ 目录下，运行时加载。
///
/// 转换流程：
/// 1. 按标点符号分割字符串
/// 2. 对每个分段，先进行词组级最长匹配替换
/// 3. 再对未匹配部分进行字符级替换
class ChineseConverter {
  /// 简转繁：词组字典
  static Map<String, String>? _s2tPhrases;

  /// 简转繁：字符字典
  static Map<String, String>? _s2tCharacters;

  /// 繁转简：词组字典
  static Map<String, String>? _t2sPhrases;

  /// 繁转简：字符字典
  static Map<String, String>? _t2sCharacters;

  /// 字典文件中最大的 key 长度（字符数）
  static int _s2tPhraseMaxLen = 1;
  static int _s2tCharMaxLen = 1;
  static int _t2sPhraseMaxLen = 1;
  static int _t2sCharMaxLen = 1;

  /// 初始化简转繁字典
  static Future<void> initS2T() async {
    if (_s2tPhrases != null && _s2tCharacters != null) return;

    final phrasesData = await rootBundle.loadString('assets/opencc/STPhrases.txt');
    final charsData = await rootBundle.loadString('assets/opencc/STCharacters.txt');

    _s2tPhrases = {};
    _s2tCharacters = {};
    _s2tPhraseMaxLen = 1;
    _s2tCharMaxLen = 1;

    _loadDict(phrasesData, _s2tPhrases!, (len) {
      if (len > _s2tPhraseMaxLen) _s2tPhraseMaxLen = len;
    });
    _loadDict(charsData, _s2tCharacters!, (len) {
      if (len > _s2tCharMaxLen) _s2tCharMaxLen = len;
    });
  }

  /// 初始化繁转简字典
  static Future<void> initT2S() async {
    if (_t2sPhrases != null && _t2sCharacters != null) return;

    final phrasesData = await rootBundle.loadString('assets/opencc/TSPhrases.txt');
    final charsData = await rootBundle.loadString('assets/opencc/TSCharacters.txt');

    _t2sPhrases = {};
    _t2sCharacters = {};
    _t2sPhraseMaxLen = 1;
    _t2sCharMaxLen = 1;

    _loadDict(phrasesData, _t2sPhrases!, (len) {
      if (len > _t2sPhraseMaxLen) _t2sPhraseMaxLen = len;
    });
    _loadDict(charsData, _t2sCharacters!, (len) {
      if (len > _t2sCharMaxLen) _t2sCharMaxLen = len;
    });
  }

  /// 解析字典文件内容到 Map
  ///
  /// 字典文件格式：每行 `key\tvalue`
  /// value 可能包含空格分隔的多个映射，取第一个
  static void _loadDict(
    String data,
    Map<String, String> dict,
    void Function(int len) onKeyLen,
  ) {
    for (final line in data.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final tabIdx = trimmed.indexOf('\t');
      if (tabIdx < 0) continue;

      final key = trimmed.substring(0, tabIdx);
      var value = trimmed.substring(tabIdx + 1);

      // 多映射取第一个
      final spaceIdx = value.indexOf(' ');
      if (spaceIdx > 0) {
        value = value.substring(0, spaceIdx);
      }

      dict[key] = value;
      onKeyLen(key.length);
    }
  }

  /// 简体转繁体
  ///
  /// [text] 待转换的简体中文文本
  /// 返回转换后的繁体中文文本
  static Future<String> s2t(String text) async {
    await initS2T();
    return _convert(text, _s2tPhrases!, _s2tCharacters!,
        _s2tPhraseMaxLen, _s2tCharMaxLen);
  }

  /// 繁体转简体
  ///
  /// [text] 待转换的繁体中文文本
  /// 返回转换后的简体中文文本
  static Future<String> t2s(String text) async {
    await initT2S();
    return _convert(text, _t2sPhrases!, _t2sCharacters!,
        _t2sPhraseMaxLen, _t2sCharMaxLen);
  }

  /// 简体转繁体（同步版，需先调用 initS2T）
  ///
  /// [text] 待转换的简体中文文本
  /// 返回转换后的繁体中文文本
  static String s2tSync(String text) {
    if (_s2tPhrases == null || _s2tCharacters == null) {
      throw StateError('请先调用 initS2T() 初始化字典');
    }
    return _convert(text, _s2tPhrases!, _s2tCharacters!,
        _s2tPhraseMaxLen, _s2tCharMaxLen);
  }

  /// 繁体转简体（同步版，需先调用 initT2S）
  ///
  /// [text] 待转换的繁体中文文本
  /// 返回转换后的简体中文文本
  static String t2sSync(String text) {
    if (_t2sPhrases == null || _t2sCharacters == null) {
      throw StateError('请先调用 initT2S() 初始化字典');
    }
    return _convert(text, _t2sPhrases!, _t2sCharacters!,
        _t2sPhraseMaxLen, _t2sCharMaxLen);
  }

  /// 执行转换
  ///
  /// 先进行词组级最长匹配替换，再进行字符级替换。
  /// 标点等非中文字符在字典中无匹配，会原样保留。
  static String _convert(
    String text,
    Map<String, String> phrases,
    Map<String, String> characters,
    int phraseMaxLen,
    int charMaxLen,
  ) {
    // 先进行词组匹配，再进行字符匹配
    var result = _matchDict(text, phrases, phraseMaxLen);
    result = _matchDict(result, characters, charMaxLen);
    return result;
  }

  /// 在文本段中进行最长匹配替换
  ///
  /// 从左到右扫描文本，在字典中查找最长匹配的 key 并替换。
  static String _matchDict(
    String text,
    Map<String, String> dict,
    int maxLen,
  ) {
    final result = StringBuffer();
    var i = 0;

    while (i < text.length) {
      var matched = false;

      // 从最长开始尝试匹配
      final remaining = text.length - i;
      final tryLen = remaining < maxLen ? remaining : maxLen;

      for (var len = tryLen; len >= 1; len--) {
        final key = text.substring(i, i + len);
        final value = dict[key];
        if (value != null) {
          result.write(value);
          i += len;
          matched = true;
          break;
        }
      }

      if (!matched) {
        result.write(text[i]);
        i++;
      }
    }

    return result.toString();
  }
}
