import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_convert/big5.dart' as big5;
import 'package:enough_convert/gbk.dart' as gbk;

/// 文本编码检测器
///
/// 用于检测 TXT 文件的编码格式。支持 UTF-8（含 BOM）、GBK、Big5。
/// 检测策略：BOM 头检测 → UTF-8 严格解码尝试 → GBK/Big5 可读性比较。
class EncodingDetector {
  EncodingDetector._();

  /// 检测文件编码
  ///
  /// [path] 文件路径
  /// 返回编码名称，如 'utf-8'、'gbk'、'big5'
  static String detect(String path) {
    final bytes = File(path).readAsBytesSync();
    return detectFromBytes(bytes);
  }

  /// 从字节数组检测编码
  static String detectFromBytes(Uint8List bytes) {
    // 1. 检查 BOM 头
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16be';
    }

    // 2. 尝试 UTF-8 严格解码
    if (_isValidUtf8(bytes)) {
      return 'utf-8';
    }

    // 3. 比较 GBK 和 Big5 的字节合法性与解码后可读性
    final gbkScore = _scoreGbk(bytes);
    final big5Score = _scoreBig5(bytes);

    if (gbkScore != big5Score) {
      return gbkScore > big5Score ? 'gbk' : 'big5';
    }

    // 标准 Big5 的字节范围是 GBK 的子集，合法 Big5 文本通常会在上面的
    // 字节评分中打平。此时需要比较两种解码结果，而不能固定偏向 GBK。
    final gbkReadability = _scoreChineseReadability(_decodeGbk(bytes));
    final big5Readability = _scoreChineseReadability(_decodeBig5(bytes));
    return big5Readability > gbkReadability ? 'big5' : 'gbk';
  }

  /// 用指定编码读取文件
  static String readFile(String path, String encoding) {
    final bytes = File(path).readAsBytesSync();
    return decodeBytes(bytes, encoding);
  }

  /// 用指定编码解码字节数组
  static String decodeBytes(Uint8List bytes, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf-8':
        // 跳过 BOM
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          return utf8.decode(bytes.sublist(3), allowMalformed: true);
        }
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf-16le':
        return _decodeUtf16(bytes, littleEndian: true);
      case 'utf-16be':
        return _decodeUtf16(bytes, littleEndian: false);
      case 'gbk':
      case 'gb2312':
        return _decodeGbk(bytes);
      case 'gb18030':
        throw UnsupportedError(
          'GB18030 decoding is not supported; use UTF-8, GBK, or Big5.',
        );
      case 'big5':
        return _decodeBig5(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 检查字节数组是否为合法 UTF-8
  static bool _isValidUtf8(Uint8List bytes) {
    try {
      utf8.decode(bytes); // 严格模式，不允许 malformed
      return true;
    } catch (_) {
      return false;
    }
  }

  /// GBK 解码（简化实现：处理常见 GBK 双字节范围）
  ///
  /// GBK 编码：第一字节 0x81-0xFE，第二字节 0x40-0xFE（不含 0x7F）
  static String _decodeGbk(Uint8List bytes) {
    return gbk.gbk.decode(bytes, allowInvalid: true);
  }

  /// Big5 解码
  static String _decodeBig5(Uint8List bytes) {
    return const big5.Big5Codec(allowInvalid: true).decode(bytes);
  }

  /// 对解码结果进行中文可读性评分。
  ///
  /// GBK 的字节范围包含标准 Big5，单靠字节合法性无法区分二者。正确解码
  /// 通常会包含较多高频汉字，而错误解码得到的随机汉字命中率明显更低。
  static int _scoreChineseReadability(String text) {
    var score = 0;
    for (final rune in text.runes) {
      if (rune == 0xFFFD) {
        score -= 20;
        continue;
      }
      if (_commonChineseRunes.contains(rune)) {
        score += 3;
      } else if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF)) {
        score += 1;
      } else if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        score -= 5;
      }
    }
    return score;
  }

  static final Set<int> _commonChineseRunes =
      '''
的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会
可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部
度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应
开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正
心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情
者最立代想已通并提直题程展五果料象员位入常文总次品式活设及管特件长求老
头基资边流路级少图山统接知较将组见计别她手角期根论运农指区强放决西被干
做必战先回则任取据处理世车空快收类即建保造百规热领海口东导器压志金增争
济油思术极交受联认共权证改清己美再转更单风切打白教速花带安场身例真务具
万每目至达走积示议声报完离华名确才科张信马节话米整元况今集温传土许步群
广石记需段研界拉林律叫究观越织装影算低音众书布复容儿须际商非验连断深难
近矿千周委素技备半办青省列习响约支般史感劳便团往历市克何除消构府称太准
精值号率族维划选标写存候毛亲效斯院查江型眼王按格养易置派层片始却专状育
厂京识适属圆包火住调满县局照参红细引听该铁价严龙飞
這國們來時說產種麼為會發動過對學經著裡還開關樣總長頭邊級圖將見計別運農
區強決戰則處車類華確張馬話萬達積聲報鬥離書復兒際驗斷難礦週委備辦習團歷
市構府準號劃選寫親效院查江眼養置層專廠識屬圓滿縣照參紅細聽該鐵價嚴龍飛
'''
          .runes
          .toSet();

  /// UTF-16 解码
  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final result = StringBuffer();
    var i = 0;
    // 跳过 BOM
    if (bytes.length >= 2) {
      if (littleEndian && bytes[0] == 0xFF && bytes[1] == 0xFE) i = 2;
      if (!littleEndian && bytes[0] == 0xFE && bytes[1] == 0xFF) i = 2;
    }
    while (i + 1 < bytes.length) {
      int codeUnit;
      if (littleEndian) {
        codeUnit = bytes[i] | (bytes[i + 1] << 8);
      } else {
        codeUnit = (bytes[i] << 8) | bytes[i + 1];
      }
      result.writeCharCode(codeUnit);
      i += 2;
    }
    return result.toString();
  }

  /// 评估字节数组作为 GBK 编码的可读性分数
  ///
  /// 统计符合 GBK 双字节模式的比例，越高越可能是 GBK
  static int _scoreGbk(Uint8List bytes) {
    var score = 0;
    var doubleByteCount = 0;
    var validCount = 0;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
        doubleByteCount++;
        final b2 = bytes[i + 1];
        // GBK 第二字节范围：0x40-0xFE（不含 0x7F）
        if (b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
          validCount++;
        }
        i++;
      }
    }
    if (doubleByteCount > 0) {
      score = (validCount * 100) ~/ doubleByteCount;
    }
    return score;
  }

  /// 评估字节数组作为 Big5 编码的可读性分数
  ///
  /// Big5 第一字节 0xA1-0xF9，第二字节 0x40-0x7E 和 0xA1-0xFE
  static int _scoreBig5(Uint8List bytes) {
    var score = 0;
    var doubleByteCount = 0;
    var validCount = 0;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b >= 0xA1 && b <= 0xF9 && i + 1 < bytes.length) {
        doubleByteCount++;
        final b2 = bytes[i + 1];
        // Big5 第二字节范围：0x40-0x7E 或 0xA1-0xFE
        if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0xA1 && b2 <= 0xFE)) {
          validCount++;
        }
        i++;
      }
    }
    if (doubleByteCount > 0) {
      score = (validCount * 100) ~/ doubleByteCount;
    }
    return score;
  }
}
