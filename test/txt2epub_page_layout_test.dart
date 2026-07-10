import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/features/txt2epub/txt2epub_page.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ToastProvider(),
        child: MaterialApp(theme: AppTheme.dark, home: const Txt2EpubPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('设置页按文件和图片分组，未启用时收起全屏首页详情', (tester) async {
    await pumpPage(tester, const Size(800, 900));

    expect(find.text('文件信息'), findsOneWidget);
    expect(find.text('图片设置'), findsOneWidget);
    expect(find.text('全屏首页'), findsOneWidget);
    expect(find.text('章节头图'), findsOneWidget);
    expect(find.text('H1'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '分页'), findsOneWidget);
    expect(find.byTooltip('管理规则'), findsOneWidget);
    expect(find.byTooltip('选择预设正则'), findsOneWidget);
    expect(find.text('首页图片'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('首页图片'), findsOneWidget);
    expect(find.text('阅微 1080×2400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口下书名与作者自动换行且无溢出', (tester) async {
    await pumpPage(tester, const Size(500, 900));

    expect(find.text('书名'), findsOneWidget);
    expect(find.text('作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
