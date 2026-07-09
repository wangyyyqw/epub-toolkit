import 'package:flutter/material.dart';

import '../providers/toast_provider.dart';

/// Toast 全局叠加层
///
/// 通过 [Overlay] + [OverlayEntry] 在应用顶层显示 Toast。接收
/// [ToastProvider] 作为数据源，监听其变化增删 Toast 视图。Toast 从顶部滑入，
/// 由 Provider 在 3 秒后移除时触发滑出动画。不同类型使用不同颜色，支持点击关闭。
///
/// 典型用法：在 [MaterialApp.router] 的 builder 中包裹子组件：
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => ToastOverlay(
///     provider: toastProvider,
///     child: child!,
///   ),
///   ...
/// )
/// ```
class ToastOverlay extends StatefulWidget {
  /// Toast 数据源
  final ToastProvider provider;

  /// 被覆盖的子组件（应用内容）
  final Widget child;

  const ToastOverlay({
    super.key,
    required this.provider,
    required this.child,
  });

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<ToastOverlay>
    with TickerProviderStateMixin {
  /// 根 Overlay 的 key，用于获取 OverlayState 插入 / 移除 OverlayEntry
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  /// 初始 OverlayEntry，承载应用子组件；子组件变化时调用 markNeedsBuild 刷新
  late final OverlayEntry _initialEntry;

  /// 当前活跃的 Toast：id -> 运行时状态（OverlayEntry + 动画控制器）
  final Map<int, _ActiveToast> _active = {};

  /// 标记是否已 dispose，避免动画回调在销毁后操作 OverlayEntry
  bool _disposed = false;

  OverlayState? get _overlay => _overlayKey.currentState;

  @override
  void initState() {
    super.initState();
    _initialEntry = OverlayEntry(builder: (context) => widget.child);
    widget.provider.addListener(_onProviderChanged);
  }

  @override
  void didUpdateWidget(covariant ToastOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 子组件变化时刷新初始 Entry，使路由切换等内容能够更新
    if (widget.child != oldWidget.child) {
      _initialEntry.markNeedsBuild();
    }
    if (oldWidget.provider != widget.provider) {
      oldWidget.provider.removeListener(_onProviderChanged);
      widget.provider.addListener(_onProviderChanged);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.provider.removeListener(_onProviderChanged);
    // 清理所有动画控制器与 OverlayEntry
    for (final active in _active.values) {
      active.entry.remove();
      active.controller.dispose();
    }
    _active.clear();
    super.dispose();
  }

  /// Provider 变化回调：对比当前 Toast 列表，增删对应的 OverlayEntry
  void _onProviderChanged() {
    final overlay = _overlay;
    if (overlay == null) return;

    final currentIds = widget.provider.toasts.map((t) => t.id).toSet();

    // 1. 移除已不存在的 Toast（播放滑出后移除 Entry）
    final toRemove =
        _active.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      _dismissActive(id);
    }

    // 2. 新增的 Toast：插入 Entry 并播放滑入动画
    for (final toast in widget.provider.toasts) {
      if (_active.containsKey(toast.id)) continue;
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );
      final entry = OverlayEntry(
        builder: (context) => _ToastView(
          toast: toast,
          animation: controller,
          onTap: () => widget.provider.dismiss(toast.id),
        ),
      );
      _active[toast.id] = _ActiveToast(entry: entry, controller: controller);
      overlay.insert(entry);
      controller.forward(); // 滑入
    }
  }

  /// 播放滑出动画后移除 OverlayEntry 并释放动画控制器
  void _dismissActive(int id) {
    final active = _active.remove(id);
    if (active == null) return;
    active.controller.reverse().then((_) {
      if (_disposed) return;
      active.entry.remove();
      active.controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: _overlayKey,
      initialEntries: [_initialEntry],
    );
  }
}

/// 单个活跃 Toast 的运行时状态
class _ActiveToast {
  final OverlayEntry entry;
  final AnimationController controller;

  _ActiveToast({required this.entry, required this.controller});
}

/// 单个 Toast 视图：从顶部滑入 / 滑出
class _ToastView extends StatelessWidget {
  final ToastMessage toast;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _ToastView({
    required this.toast,
    required this.animation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // 从顶部滑入 / 滑出
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: FadeTransition(
                opacity: animation,
                child: _ToastCard(toast: toast, onTap: onTap),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast 卡片：根据类型显示对应配色与图标，支持点击关闭
class _ToastCard extends StatelessWidget {
  final ToastMessage toast;
  final VoidCallback onTap;

  const _ToastCard({required this.toast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = _toastStyle(toast.type, colorScheme);

    // 背景 = 在 surface 上叠加半透明语义色，适配亮 / 暗模式
    final Color bgColor = Color.alphaBlend(
      style.color.withValues(alpha: 0.14),
      colorScheme.surface,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: style.color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(style.icon, color: style.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  toast.message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              // 关闭按钮
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close,
                      size: 16, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toast 类型对应的配色与图标
_ToastStyle _toastStyle(ToastType type, ColorScheme colorScheme) {
  switch (type) {
    case ToastType.success:
      // 绿色
      return const _ToastStyle(
        icon: Icons.check_circle_outline,
        color: Color(0xFF16A34A),
      );
    case ToastType.warning:
      // 橙色
      return const _ToastStyle(
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFEA8A0A),
      );
    case ToastType.error:
      // 红色，使用 colorScheme 的错误色以适配主题
      return _ToastStyle(
        icon: Icons.error_outline,
        color: colorScheme.error,
      );
    case ToastType.info:
      // 蓝色
      return const _ToastStyle(
        icon: Icons.info_outline,
        color: Color(0xFF2563EB),
      );
  }
}

/// Toast 视觉样式：图标 + 语义色
class _ToastStyle {
  final IconData icon;
  final Color color;

  const _ToastStyle({required this.icon, required this.color});
}
