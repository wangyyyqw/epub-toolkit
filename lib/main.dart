import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/theme.dart';
import 'shared/providers/toast_provider.dart';
import 'shared/widgets/app_scaffold.dart';
import 'shared/widgets/toast_overlay.dart';

/// 应用入口
void main() {
  // Android 沉浸式：应用内容延伸到状态栏与系统导航栏之后（Android 12+ 导航栏透明）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 首帧前即应用透明系统栏样式，避免等待 AnnotatedRegion 期间露出系统栏底色
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  initTDesignTheme();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ToastProvider()),
        ChangeNotifierProvider(create: (_) => SidebarState()),
      ],
      child: const EpubGadgetApp(),
    ),
  );
}

/// 根应用组件，统一注入主题与 Toast 叠加层
class EpubGadgetApp extends StatelessWidget {
  const EpubGadgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final toastProvider = context.watch<ToastProvider>();
    return MaterialApp.router(
      title: 'EPUB 工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.config,
      builder: (context, child) =>
          ToastOverlay(provider: toastProvider, child: child!),
    );
  }
}
