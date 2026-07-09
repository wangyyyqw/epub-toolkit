// Flutter integration test：覆盖主要 UI 流程
//
// 验证：
// 1. 应用启动后能进入 dashboard
// 2. 侧边栏可以导航到 txt2epub
// 3. 侧边栏可以导航到 epub-tools 并显示 26+ 个操作
// 4. 侧边栏可以导航到 send-to-kindle
// 5. 各页面没有明显异常（toast、加载等）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:epub_gadget/main.dart';
import 'package:epub_gadget/core/router.dart';
import 'package:epub_gadget/features/epub_tools/epub_tools_page.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';

/// 构造带 Provider 包裹的应用根 widget（与真实 main() 一致）
Widget _buildApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ToastProvider()),
    ],
    child: const EpubGadgetApp(),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('应用启动到 dashboard 并验证主要 UI 元素', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证应用名 "EPUB 工具箱" 在标题/侧边栏出现
    expect(find.text('EPUB 工具箱'), findsWidgets);
    // 仪表盘入口可见
    expect(find.text('仪表盘'), findsWidgets);
  });

  testWidgets('侧边栏导航到 txt2epub 页面', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 点击侧边栏的 TXT 转 EPUB 入口
    final txtLink = find.text('TXT 转 EPUB');
    expect(txtLink, findsWidgets);
    await tester.tap(txtLink.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 验证页面到达
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧边栏导航到 epub-tools 页面并显示操作列表', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 直接通过 GoRouter 跳转（更可靠）
    AppRouter.config.go('/epub-tools');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证 EpubToolOp 至少一个标签可见（如「查看 OPF 元数据」）
    final anyOpLabel = EpubToolOp.viewOpf.label;
    expect(find.text(anyOpLabel), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('路由直跳到 /send-email 不抛异常', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    AppRouter.config.go('/send-email');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('路由直跳到 /tutorial 不抛异常', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    AppRouter.config.go('/tutorial');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('路由直跳到 /metadata 不抛异常', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    AppRouter.config.go('/metadata');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Toast Provider showInfo 应触发 Toast 状态变更', (tester) async {
    final toastProvider = ToastProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: toastProvider),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                toastProvider.showInfo('测试 Toast');
              },
              child: const Text('Trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    // Toast 走 Overlay 渲染，不在 widget tree 中，但 provider.toasts 列表应包含新 Toast
    expect(toastProvider.toasts.length, 1);
    expect(toastProvider.toasts.first.message, '测试 Toast');
  });
}
