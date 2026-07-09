// 测试 EPUB 格式化功能：用真实文件验证 reformat 操作
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';

void main() {
  test('用真实EPUB测试格式化功能', () async {
    final inputPath =
        '/Users/aaa/.trae-cn/attachments/6a4d974cf98b9d1c4f971a45/53ad1b9a-b6a8-4736-bc7f-2d4f709cb700_我的智商逐年递增.epub';
    final outputPath = '/tmp/test_reformat_output.epub';

    // 跳过如果输入文件不存在
    if (!File(inputPath).existsSync()) {
      print('SKIP: 输入文件不存在');
      return;
    }

    // 删除旧输出
    final oldFile = File(outputPath);
    if (oldFile.existsSync()) oldFile.deleteSync();

    print('=== 开始格式化测试 ===');

    final log = await ReformatOperation.execute(
      epubPath: inputPath,
      outputPath: outputPath,
    );

    print('=== 格式化日志 ===');
    print(log);
    print('=== /日志 ===');

    // 验证输出文件
    final outFile = File(outputPath);
    expect(outFile.existsSync(), isTrue, reason: '输出文件应存在');
    expect(outFile.lengthSync(), greaterThan(1000), reason: '输出文件不应为空');

    print('输出文件大小: ${outFile.lengthSync()} bytes');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
