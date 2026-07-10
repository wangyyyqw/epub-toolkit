import 'package:epub_gadget/core/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('亮色和暗色主题统一使用内置思源宋体', () {
    expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, appFontFamily);
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, appFontFamily);
    expect(
      AppTheme.light.appBarTheme.titleTextStyle?.fontFamily,
      appFontFamily,
    );
    expect(AppTheme.dark.appBarTheme.titleTextStyle?.fontFamily, appFontFamily);
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
