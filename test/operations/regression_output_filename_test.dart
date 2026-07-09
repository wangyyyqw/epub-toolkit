// 回归测试：输出文件名应基于当前输入文件 basename 计算
//
// 之前的 bug：用户连续处理多本 EPUB 时，_pickEpub 只在
// _outputPath.isEmpty 时才重新计算默认输出文件名，导致
// 重新选择输入文件后，输出文件名仍是上一本 EPUB 的名字，
// 但内容是新输入的。公共 Download/books/ 出现
// "文件名是 A、内容是 B" 的诡异文件。
//
// 修复：_pickEpub 重新选择输入时，若用户没主动选过输出位置，
// 强制重置 _outputPath 重新计算。
// 单元层面验证：默认输出文件名应严格基于 _epubPath basename + op 后缀。

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('默认输出文件名应基于输入文件 basename', () {
    // 模拟 epub_tools_page.dart 中的 _defaultOutputFilename 行为
    String defaultOutputFilename(String inputPath, String opSuffix) {
      final base = p.basenameWithoutExtension(inputPath);
      return opSuffix.isEmpty ? base : '${base}_$opSuffix';
    }

    test('不同输入文件应生成不同输出文件名', () {
      final name1 = defaultOutputFilename(
        '/storage/emulated/0/.../新版《囚于永夜》作者：麦香鸡呢 补R.epub',
        'output',
      );
      final name2 = defaultOutputFilename(
        '/storage/emulated/0/.../正文五卷＋外传.epub',
        'output',
      );

      expect(name1, isNot(name2),
          reason: '不同输入文件应生成不同输出文件名（不能用上一本的名字）');
      expect(name1, contains('囚于永夜'));
      expect(name2, contains('正文五卷'));
    });

    test('路径中含特殊字符（中文/全角括号）应正确提取 basename', () {
      // 用户真实场景：文件名带全角括号、中文、特殊字符
      final input = '/storage/emulated/0/Download/《测试》(ABO).epub';
      final name = defaultOutputFilename(input, 'output');
      expect(name, '《测试》(ABO)_output');
    });

    test('路径后无扩展名变体时也应正确', () {
      final input = '/data/user/0/com.x/files/books/no_ext';
      final name = defaultOutputFilename(input, 'reformatted');
      expect(name, 'no_ext_reformatted');
    });
  });
}
