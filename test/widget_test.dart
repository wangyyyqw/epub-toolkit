import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:epub_gadget/main.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    // 包裹 MultiProvider 提供 ToastProvider，模拟真实运行环境
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ToastProvider()),
        ],
        child: const EpubGadgetApp(),
      ),
    );
    // 等待路由和第一帧渲染
    await tester.pump();
    expect(find.text('EPUB 工具箱'), findsWidgets);
  });
}
