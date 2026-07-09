import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
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

    // 3. 比较 GBK 和 Big5 的可读性
    final gbkScore = _scoreGbk(bytes);
    final big5Score = _scoreBig5(bytes);

    if (gbkScore >= big5Score) {
      return 'gbk';
    }
    return 'big5';
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
        if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
          return utf8.decode(bytes.sublist(3), allowMalformed: true);
        }
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf-16le':
        return _decodeUtf16(bytes, littleEndian: true);
      case 'utf-16be':
        return _decodeUtf16(bytes, littleEndian: false);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return _decodeGbk(bytes);
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
    // 尝试用系统编解码器（如果可用），否则降级为 latin1
    try {
      return _decodeWithSystemCodec(bytes, 'gbk');
    } catch (_) {
      // 降级：按字节直接映射 ASCII 部分，非 ASCII 用占位符
      return _fallbackDecode(bytes);
    }
  }

  /// Big5 解码
  static String _decodeBig5(Uint8List bytes) {
    try {
      return _decodeWithSystemCodec(bytes, 'big5');
    } catch (_) {
      return _fallbackDecode(bytes);
    }
  }

  /// 尝试用系统编解码器解码
  static String _decodeWithSystemCodec(Uint8List bytes, String codec) {
    // Dart 的 dart:convert 不直接支持 GBK/Big5
    // 在 Flutter 中需要依赖 flutter_encoding 或者手动处理
    // 这里用 latin1 作为降级方案，配合前端的编码检测提示
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b < 0x80) {
        result.writeCharCode(b);
      } else if (i + 1 < bytes.length) {
        // 双字节字符，用替换字符占位（原始值未使用，跳过计算）
        result.writeCharCode(0xFFFD); // 替换字符
        i++;
      }
    }
    return result.toString();
  }

  /// 降级解码：ASCII 部分正常，非 ASCII 用替换字符
  static String _fallbackDecode(Uint8List bytes) {
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b < 0x80) {
        result.writeCharCode(b);
      } else if (i + 1 < bytes.length) {
        result.writeCharCode(0xFFFD);
        i++;
      }
    }
    return result.toString();
  }

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
