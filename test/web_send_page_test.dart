import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/features/send_to_kindle/web_send_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  testWidgets('无内嵌 WebView 时显示浏览器回退页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const WebSendPage(
          forceExternalBrowser: true,
          openExternalBrowserOnStart: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('使用浏览器完成网页推送'), findsOneWidget);
    expect(find.text('在默认浏览器中打开'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 内置浏览器初始化失败时显示错误详情与重试按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const WebSendPage(
          openExternalBrowserOnStart: false,
          simulateWindowsInitFailed: 'WebView2 Runtime 安装失败（退出码 5）',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('内置浏览器不可用'), findsOneWidget);
    expect(find.textContaining('错误详情'), findsOneWidget);
    expect(find.textContaining('退出码 5'), findsOneWidget);
    expect(find.text('重试内置浏览器'), findsOneWidget);
    expect(find.text('在默认浏览器中打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
