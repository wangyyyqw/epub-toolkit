import 'dart:convert' show utf8;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 简繁中文转换器
///
/// 基于 OpenCC 字典数据实现的纯 Dart 简繁转换。
/// 字典文件打包在 assets/opencc/ 目录下，运行时加载。
///
/// 转换流程（对齐 OpenCC 官方 DictGroup Union 逻辑）：
/// 单次扫描，词组与单字字典 Union 最长匹配（词组优先），避免两阶段重叠破坏恒等词（如 皇后）。
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

  /// 已初始化的简转繁词组字典（须先调用 initS2T()）
  static Map<String, String> get s2tPhrases => _s2tPhrases!;

  /// 已初始化的简转繁字符字典（须先调用 initS2T()）
  static Map<String, String> get s2tCharacters => _s2tCharacters!;

  /// 已初始化的繁转简词组字典（须先调用 initT2S()）
  static Map<String, String> get t2sPhrases => _t2sPhrases!;

  /// 已初始化的繁转简字符字典（须先调用 initT2S()）
  static Map<String, String> get t2sCharacters => _t2sCharacters!;

  /// 简转繁词组最大 key 长度（须先调用 initS2T()）
  static int get s2tPhraseMaxLen => _s2tPhraseMaxLen;

  /// 简转繁字符最大 key 长度（须先调用 initS2T()）
  static int get s2tCharMaxLen => _s2tCharMaxLen;

  /// 繁转简词组最大 key 长度（须先调用 initT2S()）
  static int get t2sPhraseMaxLen => _t2sPhraseMaxLen;

  /// 繁转简字符最大 key 长度（须先调用 initT2S()）
  static int get t2sCharMaxLen => _t2sCharMaxLen;

  /// 用外部字典执行简体转繁体（供后台 Isolate 使用）
  ///
  /// 后台 Isolate 中 rootBundle 不可用（ServicesBinding 未初始化），
  /// 字典必须在 UI Isolate 加载后作为参数传入。
  static String s2tWithDict(
    String text, {
    required Map<String, String> phrases,
    required Map<String, String> characters,
    required int phraseMaxLen,
    required int charMaxLen,
  }) {
    return _convert(text, phrases, characters, phraseMaxLen, charMaxLen);
  }

  /// 用外部字典执行繁体转简体（供后台 Isolate 使用）
  static String t2sWithDict(
    String text, {
    required Map<String, String> phrases,
    required Map<String, String> characters,
    required int phraseMaxLen,
    required int charMaxLen,
  }) {
    return _convert(text, phrases, characters, phraseMaxLen, charMaxLen);
  }

  static Future<String> _loadAsset(String asset) async {
    // 优先尝试 .gz（压缩后体积 ~40%），失败回退到原始 txt
    final gzPath = '$asset.gz';
    try {
      final data = await rootBundle.load(gzPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final decoded = GZipDecoder().decodeBytes(bytes, verify: false);
      return utf8.decode(decoded);
    } catch (_) {
      return rootBundle.loadString(asset);
    }
  }

  /// 初始化简转繁字典
  static Future<void> initS2T() async {
    if (_s2tPhrases != null && _s2tCharacters != null) return;

    final phrasesData = await _loadAsset('assets/opencc/STPhrases.txt');
    final charsData = await _loadAsset('assets/opencc/STCharacters.txt');

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

    final phrasesData = await _loadAsset('assets/opencc/TSPhrases.txt');
    final charsData = await _loadAsset('assets/opencc/TSCharacters.txt');

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
  /// 跳过空行与 # 开头注释（官方字典带头部注释）
  static void _loadDict(
    String data,
    Map<String, String> dict,
    void Function(int len) onKeyLen,
  ) {
    for (final line in data.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#')) continue;

      final tabIdx = trimmed.indexOf('\t');
      if (tabIdx < 0) continue;

      final key = trimmed.substring(0, tabIdx);
      var value = trimmed.substring(tabIdx + 1).trim();

      if (key.isEmpty || value.isEmpty) continue;

      // 多映射取第一个（空格分隔，如 “发\t發 髮” 取 發）
      final spaceIdx = value.indexOf(' ');
      if (spaceIdx > 0) {
        value = value.substring(0, spaceIdx);
      } else {
        // 同时兼容制表符后可能残留空格，或逗号分隔（如 yiduiduo）
        final commaIdx = value.indexOf('，');
        if (commaIdx > 0) value = value.substring(0, commaIdx);
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
    return _convert(
      text,
      _s2tPhrases!,
      _s2tCharacters!,
      _s2tPhraseMaxLen,
      _s2tCharMaxLen,
    );
  }

  /// 繁体转简体
  ///
  /// [text] 待转换的繁体中文文本
  /// 返回转换后的简体中文文本
  static Future<String> t2s(String text) async {
    await initT2S();
    return _convert(
      text,
      _t2sPhrases!,
      _t2sCharacters!,
      _t2sPhraseMaxLen,
      _t2sCharMaxLen,
    );
  }

  /// 简体转繁体（同步版，需先调用 initS2T）
  ///
  /// [text] 待转换的简体中文文本
  /// 返回转换后的繁体中文文本
  static String s2tSync(String text) {
    if (_s2tPhrases == null || _s2tCharacters == null) {
      throw StateError('请先调用 initS2T() 初始化字典');
    }
    return _convert(
      text,
      _s2tPhrases!,
      _s2tCharacters!,
      _s2tPhraseMaxLen,
      _s2tCharMaxLen,
    );
  }

  /// 繁体转简体（同步版，需先调用 initT2S）
  ///
  /// [text] 待转换的繁体中文文本
  /// 返回转换后的简体中文文本
  static String t2sSync(String text) {
    if (_t2sPhrases == null || _t2sCharacters == null) {
      throw StateError('请先调用 initT2S() 初始化字典');
    }
    return _convert(
      text,
      _t2sPhrases!,
      _t2sCharacters!,
      _t2sPhraseMaxLen,
      _t2sCharMaxLen,
    );
  }

  /// 执行转换（Union 最长匹配，对齐 OpenCC DictGroup）
  ///
  /// 单次从左到右扫描，同时查询词组与单字字典，取最长匹配，
  /// 同长度词组优先，避免两阶段导致的恒等词被二次破坏（如 皇后 -> 皇後）。
  /// 标点等非中文字符无匹配，原样保留。
  static String _convert(
    String text,
    Map<String, String> phrases,
    Map<String, String> characters,
    int phraseMaxLen,
    int charMaxLen,
  ) {
    final maxLen = phraseMaxLen > charMaxLen ? phraseMaxLen : charMaxLen;
    final result = StringBuffer();
    var i = 0;

    while (i < text.length) {
      var matched = false;
      final remaining = text.length - i;
      final tryLen = remaining < maxLen ? remaining : maxLen;

      for (var len = tryLen; len >= 1; len--) {
        // 词组优先
        if (len <= phraseMaxLen) {
          final key = text.substring(i, i + len);
          final value = phrases[key];
          if (value != null) {
            result.write(value);
            i += len;
            matched = true;
            break;
          }
        }
        if (len <= charMaxLen) {
          final key = text.substring(i, i + len);
          final value = characters[key];
          if (value != null) {
            result.write(value);
            i += len;
            matched = true;
            break;
          }
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
