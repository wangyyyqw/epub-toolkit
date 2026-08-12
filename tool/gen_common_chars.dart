// 生成常用字字典：GB2312 一级字表（0xB0A1-0xD7F9，3755 字）。
// 运行：dart run tool/gen_common_chars.dart
// 输出：lib/features/phonetic/common_chars.dart
import 'dart:io';

import 'package:enough_convert/gbk.dart';

void main() {
  final buf = StringBuffer();
  for (var row = 0xB0; row <= 0xD7; row++) {
    for (var col = 0xA1; col <= 0xFE; col++) {
      if (row == 0xD7 && col > 0xF9) break;
      buf.write(gbk.decode([row, col]));
    }
  }
  final chars = buf.toString();
  if (chars.length != 3755) {
    stderr.writeln('异常：一级字数量 ${chars.length} != 3755');
    exit(1);
  }
  final content = '''
/// 常用字字典（GB2312 一级字表，3755 字）。
///
/// 由 tool/gen_common_chars.dart 自动生成，不要手工编辑。
/// 注音功能「仅生僻字」模式依据本表判断：不在本表的汉字视为生僻字并注音。
const String kCommonHanzi = '$chars';
''';
  final out = File('lib/features/phonetic/common_chars.dart');
  out.writeAsStringSync(content);
  stdout.writeln('已生成 ${out.path}，共 ${chars.length} 字');
}
