import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../core/theme.dart';

/// 侧边栏导航项
class NavItem {
  final String label;
  final IconData icon;
  final String? route;
  final List<NavItem>? children;

  const NavItem({
    required this.label,
    required this.icon,
    this.route,
    this.children,
  });

  bool get isLeaf => route != null;
}

/// 侧边栏完整导航配置
final List<NavItem> _navGroups = [
  const NavItem(
      label: '仪表盘', icon: TDIcons.dashboard, route: '/dashboard'),
  NavItem(
    label: '文件转换',
    icon: TDIcons.swap,
    children: [
      const NavItem(
        label: 'TXT → EPUB',
        icon: TDIcons.book_open,
        route: '/txt2epub',
      ),
      const NavItem(
        label: '版本转换',
        icon: TDIcons.swap,
        route: '/epub-tool/convert-version',
      ),
      const NavItem(
        label: '简体转繁体',
        icon: TDIcons.translate,
        route: '/epub-tool/s2t',
      ),
      const NavItem(
        label: '繁体转简体',
        icon: TDIcons.translate,
        route: '/epub-tool/t2s',
      ),
    ],
  ),
  NavItem(
    label: '格式处理',
    icon: TDIcons.article,
    children: [
      const NavItem(
        label: '元数据编辑',
        icon: TDIcons.edit_1,
        route: '/metadata',
      ),
      const NavItem(
        label: 'EPUB → TXT',
        icon: TDIcons.article,
        route: '/epub-tool/epub-to-txt',
      ),
      const NavItem(
        label: '更换封面',
        icon: TDIcons.image,
        route: '/epub-tool/replace-cover',
      ),
      const NavItem(
        label: '合并 EPUB',
        icon: TDIcons.merge_cells,
        route: '/epub-tool/merge',
      ),
      const NavItem(
        label: '拆分 EPUB',
        icon: TDIcons.cut,
        route: '/epub-tool/split',
      ),
      const NavItem(
        label: '列出拆分目标',
        icon: TDIcons.list,
        route: '/epub-tool/list-split-targets',
      ),
      const NavItem(
        label: '字体子集化',
        icon: TDIcons.pen_quill,
        route: '/epub-tool/font-subset',
      ),
      const NavItem(
        label: '重新格式化',
        icon: TDIcons.layers,
        route: '/epub-tool/reformat',
      ),
    ],
  ),
  NavItem(
    label: '安全加密',
    icon: TDIcons.lock_on,
    children: [
      const NavItem(
        label: '名称混淆加密',
        icon: TDIcons.lock_on,
        route: '/epub-tool/encrypt',
      ),
      const NavItem(
        label: '名称混淆解密',
        icon: TDIcons.lock_off,
        route: '/epub-tool/decrypt',
      ),
      const NavItem(
        label: '字体加密',
        icon: TDIcons.key,
        route: '/epub-tool/encrypt-font',
      ),
    ],
  ),
  NavItem(
    label: '图片处理',
    icon: TDIcons.image,
    children: [
      const NavItem(
        label: '图片压缩',
        icon: TDIcons.image_edit,
        route: '/epub-tool/img-compress',
      ),
      const NavItem(
        label: '图片转 WebP',
        icon: TDIcons.image,
        route: '/epub-tool/img-to-webp',
      ),
      const NavItem(
        label: '图片水印',
        icon: TDIcons.pen_mark,
        route: '/epub-tool/image-watermark',
      ),
      const NavItem(
        label: 'WebP 转图片',
        icon: TDIcons.image_search,
        route: '/epub-tool/webp-to-img',
      ),
      const NavItem(
        label: '下载网络图片',
        icon: TDIcons.download,
        route: '/epub-tool/download-images',
      ),
    ],
  ),
  NavItem(
    label: '文本处理',
    icon: TDIcons.file_code,
    children: [
      const NavItem(
        label: '广告清理',
        icon: TDIcons.filter_2,
        route: '/epub-tool/ad-clean',
      ),
      const NavItem(
        label: '读书想法',
        icon: TDIcons.chat_heart,
        route: '/epub-tool/weread-thoughts',
      ),
      const NavItem(
        label: '文本对比',
        icon: TDIcons.file_copy,
        route: '/epub-tool/text-diff',
      ),
    ],
  ),
  NavItem(
    label: '注释 / 注音',
    icon: TDIcons.chat_bubble,
    children: [
      const NavItem(
        label: '拼音标注',
        icon: TDIcons.sound,
        route: '/epub-tool/phonetic',
      ),
      const NavItem(
        label: '批注提取',
        icon: TDIcons.chat_bubble,
        route: '/epub-tool/comment',
      ),
      const NavItem(
        label: '脚注转弹窗',
        icon: TDIcons.chat_bubble_add,
        route: '/epub-tool/footnote-to-comment',
      ),
      const NavItem(
        label: '弹窗转脚注',
        icon: TDIcons.file_code,
        route: '/epub-tool/span-to-footnote',
      ),
      const NavItem(
        label: '阅微转多看',
        icon: TDIcons.swap,
        route: '/epub-tool/yuewei',
      ),
      const NavItem(
        label: '得到转多看',
        icon: TDIcons.swap,
        route: '/epub-tool/zhangyue',
      ),
    ],
  ),
  NavItem(
    label: 'Kindle 推送',
    icon: TDIcons.send,
    children: [
      const NavItem(
        label: '邮箱推送',
        icon: TDIcons.mail,
        route: '/send-email',
      ),
      const NavItem(
          label: '网页推送', icon: TDIcons.internet, route: '/send-web'),
      const NavItem(
        label: 'WiFi 传书',
        icon: TDIcons.wifi,
        route: '/wifi-transfer',
      ),
    ],
  ),
  NavItem(
    label: '使用教程',
    icon: TDIcons.education,
    children: [
      const NavItem(
        label: '传书教程',
        icon: TDIcons.book_open,
        route: '/tutorial',
      ),
    ],
  ),
];

const double _sidebarWidthDesktop = 240;
const double _sidebarWidthMobile = 208;
const double _sidebarWidthCollapsed = 64;

/// 窗口宽度低于该值时代理侧边栏默认收起
const double _autoCollapseBreakpoint = 1150;

/// 窗口宽度低于该值时切换为移动端抽屉模式：
/// 侧边栏完全隐藏，仅保留顶部左侧菜单按钮，点击展开、选择功能后自动收起
const double _mobileDrawerBreakpoint = 700;

const String _brandName = 'EPUB 工具箱';

// ==================== 应用整体布局 ====================

/// 应用外壳：所有平台统一使用侧边栏布局。
///
/// 桌面端侧边栏稍宽；窄窗口（<1150px）自动收起为图标栏，
/// 品牌区按钮可手动展开/收起（手动选择后不再自动干预）。
/// 当前路径所在分组自动展开（由 [SidebarState] 管理）。
class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final overlay = context.isDarkMode
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            context.isDarkMode ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        // Android 12+ 三键导航：关闭系统强制对比度遮罩，实现真正透明沉浸
        systemNavigationBarContrastEnforced: false,
      ),
      child: ChangeNotifierProvider(
        create: (_) => SidebarState(),
        child: Builder(
          builder: (context) {
            final location = GoRouterState.of(context).uri.toString();
            final width = context.isDesktop
                ? _sidebarWidthDesktop
                : _sidebarWidthMobile;
            return Scaffold(
              backgroundColor: context.themeBg,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile =
                      constraints.maxWidth < _mobileDrawerBreakpoint;
                  // 窗口宽度变化时应用默认收起策略（用户手动选择后跳过）；移动端抽屉模式不干预
                  if (!isMobile) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      context.read<SidebarState>().applyWindowWidth(
                            constraints.maxWidth < _autoCollapseBreakpoint,
                          );
                    });
                  }
                  if (isMobile) {
                    return _buildMobileLayout(
                      context,
                      location: location,
                      child: child,
                    );
                  }
                  return Row(
                    children: [
                      _Sidebar(currentPath: location, width: width),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: _SafeContent(child: child),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 移动端布局：侧边栏完全隐藏，顶部栏左侧菜单按钮展开抽屉式侧边栏，
/// 遮罩点击或选择功能后自动收起。
Widget _buildMobileLayout(
  BuildContext context, {
  required String location,
  required Widget child,
}) {
  final sidebar = context.watch<SidebarState>();
  return Stack(
    children: [
      Column(
        children: [
          _MobileTopBar(onMenuTap: sidebar.toggleMobile),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: _SafeContent(mobile: true, child: child),
              ),
            ),
          ),
        ],
      ),
      // 遮罩：模糊灰色蒙层，点击收起抽屉
      if (sidebar.mobileOpen)
        Positioned.fill(
          child: GestureDetector(
            onTap: sidebar.closeMobile,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
              ),
            ),
          ),
        ),
      // 抽屉式侧边栏
      AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        left: sidebar.mobileOpen ? 0 : -_sidebarWidthDesktop - 16,
        top: 0,
        bottom: 0,
        width: _sidebarWidthDesktop,
        child: _Sidebar(
          currentPath: location,
          width: _sidebarWidthDesktop,
          drawerMode: true,
        ),
      ),
    ],
  );
}

/// 内容区安全边距。
///
/// 统一处理顶部/底部系统栏内边距并移除 MediaQuery 中的对应 inset，
/// 避免页面内层 SafeArea 重复留白：
/// - 移动端顶部由 [_MobileTopBar] 的 SafeArea 处理，本层不再加顶部内边距
/// - 底部统一加上系统导航栏内边距（edge-to-edge 下内容不被遮挡）
class _SafeContent extends StatelessWidget {
  final Widget child;

  /// 移动端布局：顶部内边距由顶部栏处理，本层置零
  final bool mobile;

  const _SafeContent({required this.child, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPadding = mobile ? 0.0 : media.padding.top;
    final bottomPadding = media.padding.bottom + 8;
    return MediaQuery.removePadding(
      context: context,
      removeTop: mobile,
      removeBottom: true,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: child,
      ),
    );
  }
}

/// 移动端顶部栏：透明背景与状态栏/页面底色融为一体，
/// 左侧菜单按钮 + 品牌名，高度紧凑以让更多空间给内容
class _MobileTopBar extends StatelessWidget {
  final VoidCallback onMenuTap;

  const _MobileTopBar({required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              onPressed: onMenuTap,
              tooltip: '打开侧边栏',
              icon: Icon(
                Icons.menu_rounded,
                size: 22,
                color: context.themeTextPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _brandName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.themeTextPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 侧边栏状态管理 ====================

/// 全局侧边栏状态管理：支持多分组同时展开 + 折叠/展开切换 + 移动端抽屉
class SidebarState extends ChangeNotifier {
  final Set<String> _expandedGroups = {};

  bool _collapsed = false;
  bool _userCollapsed = false;

  /// 由折叠态点击分组展开侧边栏后，选择功能会自动收起
  bool _autoCollapseAfterNav = false;

  /// 移动端抽屉模式：侧边栏是否展开
  bool _mobileOpen = false;

  Set<String> get expandedGroups => Set.unmodifiable(_expandedGroups);

  /// 侧边栏是否处于折叠（图标栏）状态
  bool get collapsed => _collapsed;

  /// 用户是否手动选择过折叠状态（自动策略不再干预）
  bool get userCollapsed => _userCollapsed;

  /// 移动端抽屉是否展开
  bool get mobileOpen => _mobileOpen;

  bool isExpanded(String groupLabel) => _expandedGroups.contains(groupLabel);

  /// 移动端：切换抽屉展开/收起
  void toggleMobile() {
    _mobileOpen = !_mobileOpen;
    notifyListeners();
  }

  /// 移动端：收起抽屉
  void closeMobile() {
    if (!_mobileOpen) return;
    _mobileOpen = false;
    notifyListeners();
  }

  /// 手动切换折叠/展开
  void toggleCollapsed() {
    _userCollapsed = true;
    _collapsed = !_collapsed;
    if (!_collapsed) _autoCollapseAfterNav = false;
    notifyListeners();
  }

  /// 窗口宽度变化时应用默认收起策略；用户手动选择后不再自动干预
  void applyWindowWidth(bool narrow) {
    if (_userCollapsed) return;
    if (_collapsed != narrow) {
      _collapsed = narrow;
      notifyListeners();
    }
  }

  /// 折叠态点击分组：展开侧边栏并展开该分组（收起其他分组）
  ///
  /// 随后通过侧边栏选择功能时，[navFromSidebar] 会自动收起。
  void expandAndOpen(String groupLabel) {
    _userCollapsed = true;
    _collapsed = false;
    _autoCollapseAfterNav = true;
    _expandedGroups
      ..clear()
      ..add(groupLabel);
    notifyListeners();
  }

  /// 通过侧边栏导航后调用：若此前由折叠态展开，则自动收起；移动端抽屉同步收起
  void navFromSidebar() {
    var changed = false;
    if (_autoCollapseAfterNav) {
      _autoCollapseAfterNav = false;
      if (!_collapsed) {
        _collapsed = true;
        changed = true;
      }
    }
    if (_mobileOpen) {
      _mobileOpen = false;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void toggle(String groupLabel) {
    if (_expandedGroups.contains(groupLabel)) {
      _expandedGroups.remove(groupLabel);
    } else {
      // 手风琴模式：展开当前分组，同时收起其他分组
      _expandedGroups
        ..clear()
        ..add(groupLabel);
    }
    notifyListeners();
  }

  void expand(String groupLabel) {
    if (_expandedGroups.length == 1 &&
        _expandedGroups.contains(groupLabel)) {
      return;
    }
    // 手风琴模式：只保留当前分组展开
    _expandedGroups
      ..clear()
      ..add(groupLabel);
    notifyListeners();
  }

  void collapse(String groupLabel) {
    if (_expandedGroups.remove(groupLabel)) notifyListeners();
  }

  // —— 向后兼容旧 API ——

  String? get expandedGroup =>
      _expandedGroups.isEmpty ? null : _expandedGroups.last;

  void setExpanded(String? groupLabel) {
    _expandedGroups.clear();
    if (groupLabel != null) _expandedGroups.add(groupLabel);
    notifyListeners();
  }
}

// ==================== 侧边栏 ====================

class _Sidebar extends StatelessWidget {
  final String currentPath;
  final double width;

  /// 移动端抽屉模式：始终展开显示，底部按钮改为「关闭抽屉」
  final bool drawerMode;

  const _Sidebar({
    required this.currentPath,
    required this.width,
    this.drawerMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final sidebar = context.watch<SidebarState>();
    final collapsed = drawerMode ? false : sidebar.collapsed;

    return Container(
      width: collapsed ? _sidebarWidthCollapsed : width,
      decoration: BoxDecoration(
        color: context.themeCard,
        border: Border(
          right: BorderSide(color: context.themeDividerLight, width: 1),
        ),
        boxShadow: drawerMode
            ? const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 16,
                  offset: Offset(4, 0),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            _buildBrand(context, collapsed),
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 12 : 14,
              ),
              child: Divider(height: 1, color: context.themeDivider),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : 8,
                  vertical: 4,
                ),
                itemCount: _navGroups.length,
                  itemBuilder: (context, index) {
                    final nav = _navGroups[index];
                    if (nav.isLeaf) {
                      return _LeafNavTile(
                        icon: nav.icon,
                        label: nav.label,
                        route: nav.route!,
                        currentPath: currentPath,
                        collapsed: collapsed,
                        onTap: () {
                          context.go(nav.route!);
                          context.read<SidebarState>().navFromSidebar();
                        },
                      );
                    }
                    return _ExpandableNavGroup(
                      parent: nav,
                      currentPath: currentPath,
                      collapsed: collapsed,
                    );
                  },
                ),
            ),
            if (!collapsed && !drawerMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'v1.2.6',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeTextTertiary.withValues(alpha: 0.6),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            // 底部按钮：抽屉模式不留按钮（靠点击遮罩收起），底部留白更干净；
            // 其余为折叠/展开切换
            if (drawerMode)
              const SizedBox(height: 12)
            else if (collapsed)
              IconButton(
                onPressed: () => context.read<SidebarState>().toggleCollapsed(),
                tooltip: '展开侧边栏',
                icon: Icon(
                  Icons.menu_rounded,
                  size: 20,
                  color: context.themeTextTertiary,
                ),
              )
            else
              IconButton(
                onPressed: () => context.read<SidebarState>().toggleCollapsed(),
                tooltip: '收起侧边栏',
                icon: Icon(
                  Icons.menu_open_rounded,
                  size: 19,
                  color: context.themeTextTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context, bool collapsed) {
    final logo = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: context.themeAccentLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
      ),
      child: Icon(
        Icons.auto_stories_rounded,
        color: context.themeAccent,
        size: 18,
      ),
    );

    if (collapsed) {
      return Center(child: logo);
    }

    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
        child: Row(
          children: [
            logo,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _brandName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    '本地电子书处理',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.themeTextTertiary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 叶子导航项 ====================

class _LeafNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String currentPath;
  final bool collapsed;
  final VoidCallback onTap;

  const _LeafNavTile({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentPath,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentPath == route;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
            hoverColor: context.themeAccentLight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? context.themeWarmLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: isActive
                      ? context.themeAccent
                      : context.themeTextTertiary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        hoverColor: context.themeAccentLight,
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? context.themeWarmLight : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: isActive
                      ? context.themeAccent
                      : context.themeTextTertiary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? context.themeTextPrimary
                          : context.themeTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 可展开分组 ====================

class _ExpandableNavGroup extends StatefulWidget {
  final NavItem parent;
  final String currentPath;
  final bool collapsed;

  const _ExpandableNavGroup({
    required this.parent,
    required this.currentPath,
    required this.collapsed,
  });

  @override
  State<_ExpandableNavGroup> createState() => _ExpandableNavGroupState();
}

class _ExpandableNavGroupState extends State<_ExpandableNavGroup> {
  @override
  void initState() {
    super.initState();
    // 当前路径在分组中 → 自动展开
    if (_hasActiveChild()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sidebarState(context).expand(widget.parent.label);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ExpandableNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 延迟到帧结束后再通知，避免 build 阶段 markNeedsBuild 异常
    if (widget.currentPath != oldWidget.currentPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_hasActiveChild()) {
          _sidebarState(context).expand(widget.parent.label);
        } else {
          _sidebarState(context).collapse(widget.parent.label);
        }
      });
    }
  }

  bool _hasActiveChild() {
    if (widget.parent.children == null) return false;
    return widget.parent.children!.any((c) => c.route == widget.currentPath);
  }

  SidebarState _sidebarState(BuildContext context) {
    return Provider.of<SidebarState>(context, listen: false);
  }

  void _toggle() {
    _sidebarState(context).toggle(widget.parent.label);
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = context.watch<SidebarState>();
    final isExpanded = sidebar.isExpanded(widget.parent.label);
    final hasActiveChild = _hasActiveChild();
    final collapsed = widget.collapsed;

    // 折叠态：仅分组图标，点击展开侧边栏并展开该分组
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Tooltip(
          message: widget.parent.label,
          child: InkWell(
            onTap: () => sidebar.expandAndOpen(widget.parent.label),
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: hasActiveChild
                    ? context.themeWarmLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
              child: Center(
                child: Icon(
                  widget.parent.icon,
                  size: 18,
                  color: hasActiveChild
                      ? context.themeAccent
                      : context.themeTextTertiary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(AppTheme.radiusS),
          hoverColor: context.themeAccentLight,
          child: Container(
            decoration: BoxDecoration(
              color: hasActiveChild
                  ? context.themeWarmLight
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.parent.icon,
                    size: 17,
                    color: hasActiveChild
                        ? context.themeAccent
                        : context.themeTextTertiary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.parent.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: hasActiveChild
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: hasActiveChild
                            ? context.themeTextPrimary
                            : context.themeTextSecondary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 15,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 子菜单
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: isExpanded && widget.parent.children != null
              ? Padding(
                  padding:
                      const EdgeInsets.only(left: 6, top: 2, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.parent.children!.map((child) {
                      final isActive = child.route == widget.currentPath;
                      return InkWell(
                        onTap: () {
                          context.go(child.route!);
                          sidebar.navFromSidebar();
                        },
                        borderRadius: BorderRadius.circular(AppTheme.radiusS),
                        hoverColor: context.themeAccentLight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? context.themeWarmLight
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusS),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                child.icon,
                                size: 15,
                                color: isActive
                                    ? context.themeAccent
                                    : context.themeTextTertiary
                                        .withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                child.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isActive
                                      ? context.themeTextPrimary
                                      : context.themeTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
