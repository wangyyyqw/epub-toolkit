import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/theme.dart';
import 'shared/providers/toast_provider.dart';
import 'shared/widgets/app_scaffold.dart';
import 'shared/widgets/toast_overlay.dart';

/// 应用入口
void main() {
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
