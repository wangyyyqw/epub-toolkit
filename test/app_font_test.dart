import 'package:epub_gadget/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('工具 UI 主题使用系统字体（未打包自定义字体）', () {
    // 思源宋体资源已从打包中移除，主题字体族不得引用已删除的字体名
    // （测试环境默认字体族解析为 'Roboto'，只要不是已删除的 'SourceHanSerifApp' 即可）
    expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, isNot('SourceHanSerifApp'));
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, isNot('SourceHanSerifApp'));
    expect(AppTheme.light.appBarTheme.titleTextStyle?.fontFamily, isNot('SourceHanSerifApp'));
    expect(AppTheme.dark.appBarTheme.titleTextStyle?.fontFamily, isNot('SourceHanSerifApp'));
  });
}
