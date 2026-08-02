import 'package:epub_gadget/core/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('工具 UI 使用系统无衬线字体（非思源宋体）', () {
    // 新设计：工具 UI 用系统无衬线，思源宋体仅用于 EPUB 内容预览
    // 测试环境将 fontFamily=null 解析为 'Roboto'，只要不是思源宋体即可
    expect(
      AppTheme.light.textTheme.bodyMedium?.fontFamily,
      isNot(appFontFamily),
    );
    expect(
      AppTheme.dark.textTheme.bodyMedium?.fontFamily,
      isNot(appFontFamily),
    );
    expect(
      AppTheme.light.appBarTheme.titleTextStyle?.fontFamily,
      isNot(appFontFamily),
    );
    expect(
      AppTheme.dark.appBarTheme.titleTextStyle?.fontFamily,
      isNot(appFontFamily),
    );
  });

  test('思源宋体三个字重均已打包为 Flutter 资源', () async {
    for (final asset in [
      'assets/fonts/SourceHanSerifCN-Regular.otf',
      'assets/fonts/SourceHanSerifCN-SemiBold.otf',
      'assets/fonts/SourceHanSerifCN-Bold.otf',
    ]) {
      final bytes = await rootBundle.load(asset);
      expect(bytes.lengthInBytes, greaterThan(1000000), reason: asset);
    }
  });
}
