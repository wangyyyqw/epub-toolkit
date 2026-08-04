import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:epub_gadget/core/router.dart';
import 'package:epub_gadget/main.dart';
import 'package:epub_gadget/shared/widgets/app_scaffold.dart';
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

  testWidgets('侧边栏折叠/展开切换无布局异常', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(824, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ToastProvider()),
        ],
        child: const EpubGadgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 窄窗口（824 < 1150）启动后应处于折叠状态
    expect(tester.takeException(), isNull);

    // 手动展开
    final expandBtn = find.byTooltip('展开侧边栏');
    if (expandBtn.evaluate().isNotEmpty) {
      await tester.tap(expandBtn);
    } else {
      // 未折叠时直接点收起按钮
      await tester.tap(find.byTooltip('收起侧边栏').first);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 再收起
    await tester.tap(find.byTooltip('收起侧边栏').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态点分组展开后选择功能自动收起', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(824, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ToastProvider()),
        ],
        child: const EpubGadgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 折叠态点击分组图标（「Kindle 推送」，分组头为 send 图标）→ 展开侧边栏并展开分组
    expect(find.byTooltip('Kindle 推送'), findsOneWidget);
    await tester.tap(find.byTooltip('Kindle 推送'));
    await tester.pumpAndSettle();

    // 侧边栏已展开，显示分组子项
    expect(find.text('WiFi 传书'), findsOneWidget);

    // 点击子项导航 → 应自动收起
    await tester.tap(find.text('WiFi 传书'));
    // 固定 pump：目标页初始化进度圈在测试环境不停止，不能用 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // 导航后已收起：侧边栏回到图标栏，子项文字消失
    expect(find.text('WiFi 传书'), findsNothing);
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
  });

  testWidgets('移动端抽屉：隐藏侧栏，顶部按钮展开，选择/遮罩后自动收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // UniqueKey 强制全新挂载 + 重置路由：丢弃前序测试遗留的路由页面
    // （如 WiFi 页常驻的加载动画），避免 pumpAndSettle 无法收敛
    await tester.pumpWidget(
      KeyedSubtree(
        key: UniqueKey(),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ToastProvider()),
          ],
          child: const EpubGadgetApp(),
        ),
      ),
    );
    AppRouter.config.go('/dashboard');
    await tester.pumpAndSettle();

    // 侧边栏完全隐藏：仅顶部菜单按钮，无任何导航项可点
    expect(find.byTooltip('打开侧边栏'), findsOneWidget);
    expect(find.byTooltip('展开侧边栏'), findsNothing);
    expect(find.text('仪表盘').hitTestable(), findsNothing);

    // 点击顶部菜单按钮 → 抽屉展开，导航项可见
    await tester.tap(find.byTooltip('打开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.text('仪表盘').hitTestable(), findsOneWidget);

    // 点击导航项 → 选择功能后自动收起
    await tester.tap(find.text('仪表盘'));
    await tester.pumpAndSettle();
    expect(find.text('仪表盘').hitTestable(), findsNothing);

    // 再次展开，点遮罩区域收起
    await tester.tap(find.byTooltip('打开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.text('仪表盘').hitTestable(), findsOneWidget);
    await tester.tapAt(const Offset(370, 400));
    await tester.pumpAndSettle();
    expect(find.text('仪表盘').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
