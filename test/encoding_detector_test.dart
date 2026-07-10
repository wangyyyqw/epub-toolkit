import 'dart:typed_data';

import 'package:enough_convert/big5.dart' as big5;
import 'package:enough_convert/gbk.dart' as gbk;
import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EncodingDetector', () {
    test('完整解码 GBK 中文文本', () {
      const source = '中文小说：轻舟已过万重山';
      final bytes = Uint8List.fromList(gbk.gbk.encode(source));

      expect(EncodingDetector.detectFromBytes(bytes), 'gbk');
      expect(EncodingDetector.decodeBytes(bytes, 'gbk'), source);
    });

    test('完整解码 Big5 中文文本', () {
      const source = '中文小說：輕舟已過萬重山';
      final bytes = Uint8List.fromList(big5.big5.encode(source));

      final encoding = EncodingDetector.detectFromBytes(bytes);
      expect(encoding, 'big5');
      expect(EncodingDetector.decodeBytes(bytes, encoding), source);
      expect(EncodingDetector.decodeBytes(bytes, 'big5'), source);
    });

    test('GB18030 不会被错误地当作 GBK 解码', () {
      final fourByteSequence = Uint8List.fromList([0x81, 0x30, 0x81, 0x30]);

      expect(
        () => EncodingDetector.decodeBytes(fourByteSequence, 'gb18030'),
        throwsUnsupportedError,
      );
    });

    test('Big5 遇到不完整字节时使用替换字符而不崩溃', () {
      final malformed = Uint8List.fromList([0xA4]);

      expect(EncodingDetector.decodeBytes(malformed, 'big5'), '\uFFFD');
    });
  });
}
