import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/shared/widgets/output_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<OutputLogController> pumpLog(
    WidgetTester tester, {
    required Size size,
    String text = '',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = OutputLogController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OutputLog(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('日志入口打开可滚动、选择、复制和清空的弹窗', (tester) async {
    final controller = await pumpLog(
      tester,
      size: const Size(800, 700),
      text: '开始处理\n完成处理',
    );

    expect(find.text('查看处理日志'), findsOneWidget);
    expect(find.text('(2 行)'), findsOneWidget);

    await tester.tap(find.text('查看处理日志'));
    await tester.pumpAndSettle();

    expect(find.text('处理日志'), findsOneWidget);
    expect(find.byTooltip('全选'), findsOneWidget);
    expect(find.byTooltip('复制全部'), findsOneWidget);
    expect(find.byTooltip('清空日志'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('清空日志'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.text('暂无日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口日志弹窗不溢出', (tester) async {
    await pumpLog(
      tester,
      size: const Size(320, 500),
      text: List.generate(40, (index) => '第 ${index + 1} 行日志').join('\n'),
    );

    await tester.tap(find.text('查看处理日志'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('日志操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
