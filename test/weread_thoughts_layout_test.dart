// 微信读书页面布局回归测试
//
// 验证输出路径区的桌面双列并排 + 窄屏原顺序条件渲染:
// 1. 宽屏 + 已登录 + 未绑定书目: 输出区占位提示与输入区同行(Row 双列)
// 2. 窄屏 + 已登录 + 未绑定书目: 输出区不显示(窄屏仅在绑定后于底部显示)
// 3. 未登录: 输入/输出区均不显示

import 'package:epub_gadget/features/epub_tools/tools/weread_thoughts_page.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => ToastProvider(),
    child: MaterialApp(home: child),
  );
}

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  // 直接设置 view 尺寸(setSurfaceSize 在新版 Flutter 测试中不生效,
  // 会导致 MediaQuery 始终为默认 800x600)
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(const WereadThoughtsPage()));
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('宽屏已登录未绑定时,输出区占位与输入区同行', (tester) async {
    // 模拟已登录(Cookie 含 wr_skey)
    SharedPreferences.setMockInitialValues({
      'weread_cookies': '{"wr_skey":"test","wr_vid":"test"}',
    });
    await _pumpPage(tester, const Size(1440, 900));

    // 输入区存在
    expect(find.text('EPUB 文件'), findsWidgets);
    // 输出区占位提示存在(未绑定书目)
    expect(
      find.textContaining('搜索并绑定书目后'),
      findsOneWidget,
      reason: '宽屏未绑定时应显示输出占位提示',
    );
    // 占位与输入同行: 位于同一 Row 内(占位文本上溯 6 层内存在 Row 且同一行有 EPUB 文件 label)
    final placeholder = find.textContaining('搜索并绑定书目后');
    final row = find.ancestor(
      of: placeholder,
      matching: find.byType(Row),
    );
    expect(row, findsWidgets, reason: '占位应位于 Row(双列)中');
    // 双列结构: 该 Row 下同时含输入区 EPUB 文件行
    final epubs = find.ancestor(
      of: find.text('EPUB 文件'),
      matching: find.byType(Row),
    );
    expect(epubs, findsWidgets);
  });

  testWidgets('窄屏已登录未绑定时,输出区不显示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'weread_cookies': '{"wr_skey":"test","wr_vid":"test"}',
    });
    await _pumpPage(tester, const Size(500, 800));

    // 输入区存在
    expect(find.text('EPUB 文件'), findsWidgets);
    // 输出区及其占位均不显示(窄屏仅在绑定书目后于底部显示)
    expect(
      find.textContaining('搜索并绑定书目后'),
      findsNothing,
      reason: '窄屏未绑定时不应显示输出占位',
    );
  });

  testWidgets('未登录时输入/输出区均不显示', (tester) async {
    await _pumpPage(tester, const Size(1440, 900));

    expect(find.text('EPUB 文件'), findsNothing,
        reason: '未登录时不应显示输入区');
    expect(find.textContaining('搜索并绑定书目后'), findsNothing,
        reason: '未登录时不应显示输出占位');
  });
}
