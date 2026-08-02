import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      label: '仪表盘', icon: Icons.home_outlined, route: '/dashboard'),
  NavItem(
    label: '文件转换',
    icon: Icons.swap_horiz_outlined,
    children: [
      const NavItem(
        label: 'TXT → EPUB',
        icon: Icons.menu_book_outlined,
        route: '/txt2epub',
      ),
      const NavItem(
        label: '版本转换',
        icon: Icons.swap_vert_outlined,
        route: '/epub-tool/convert-version',
      ),
      const NavItem(
        label: '简体转繁体',
        icon: Icons.translate,
        route: '/epub-tool/s2t',
      ),
      const NavItem(
        label: '繁体转简体',
        icon: Icons.translate_outlined,
        route: '/epub-tool/t2s',
      ),
    ],
  ),
  NavItem(
    label: '格式处理',
    icon: Icons.format_shapes_outlined,
    children: [
      const NavItem(
        label: '元数据编辑',
        icon: Icons.edit_note_outlined,
        route: '/metadata',
      ),
      const NavItem(
        label: 'EPUB → TXT',
        icon: Icons.article_outlined,
        route: '/epub-tool/epub-to-txt',
      ),
      const NavItem(
        label: '更换封面',
        icon: Icons.image_outlined,
        route: '/epub-tool/replace-cover',
      ),
      const NavItem(
        label: '合并 EPUB',
        icon: Icons.call_merge_outlined,
        route: '/epub-tool/merge',
      ),
      const NavItem(
        label: '拆分 EPUB',
        icon: Icons.call_split_outlined,
        route: '/epub-tool/split',
      ),
      const NavItem(
        label: '列出拆分目标',
        icon: Icons.list_alt_outlined,
        route: '/epub-tool/list-split-targets',
      ),
      const NavItem(
        label: '字体子集化',
        icon: Icons.font_download_outlined,
        route: '/epub-tool/font-subset',
      ),
      const NavItem(
        label: '重新格式化',
        icon: Icons.auto_fix_high_outlined,
        route: '/epub-tool/reformat',
      ),
    ],
  ),
  NavItem(
    label: '安全加密',
    icon: Icons.lock_outline,
    children: [
      const NavItem(
        label: '名称混淆加密',
        icon: Icons.enhanced_encryption_outlined,
        route: '/epub-tool/encrypt',
      ),
      const NavItem(
        label: '名称混淆解密',
        icon: Icons.no_encryption_outlined,
        route: '/epub-tool/decrypt',
      ),
      const NavItem(
        label: '字体加密',
        icon: Icons.security_outlined,
        route: '/epub-tool/encrypt-font',
      ),
    ],
  ),
  NavItem(
    label: '图片处理',
    icon: Icons.photo_library_outlined,
    children: [
      const NavItem(
        label: '图片压缩',
        icon: Icons.compress_outlined,
        route: '/epub-tool/img-compress',
      ),
      const NavItem(
        label: '图片转 WebP',
        icon: Icons.image_outlined,
        route: '/epub-tool/img-to-webp',
      ),
      const NavItem(
        label: '图片水印',
        icon: Icons.fingerprint_outlined,
        route: '/epub-tool/image-watermark',
      ),
      const NavItem(
        label: 'WebP 转图片',
        icon: Icons.image_search_outlined,
        route: '/epub-tool/webp-to-img',
      ),
      const NavItem(
        label: '下载网络图片',
        icon: Icons.download_outlined,
        route: '/epub-tool/download-images',
      ),
    ],
  ),
  NavItem(
    label: '文本处理',
    icon: Icons.text_snippet_outlined,
    children: [
      const NavItem(
        label: '广告清理',
        icon: Icons.cleaning_services_outlined,
        route: '/epub-tool/ad-clean',
      ),
      const NavItem(
        label: '读书想法',
        icon: Icons.psychology_outlined,
        route: '/epub-tool/weread-thoughts',
      ),
    ],
  ),
  NavItem(
    label: '注释 / 注音',
    icon: Icons.comment_outlined,
    children: [
      const NavItem(
        label: '拼音标注',
        icon: Icons.record_voice_over_outlined,
        route: '/epub-tool/phonetic',
      ),
      const NavItem(
        label: '批注提取',
        icon: Icons.comment_bank_outlined,
        route: '/epub-tool/comment',
      ),
      const NavItem(
        label: '脚注转弹窗',
        icon: Icons.question_answer_outlined,
        route: '/epub-tool/footnote-to-comment',
      ),
      const NavItem(
        label: '弹窗转脚注',
        icon: Icons.format_quote_outlined,
        route: '/epub-tool/span-to-footnote',
      ),
      const NavItem(
        label: '阅微转多看',
        icon: Icons.sync_alt_outlined,
        route: '/epub-tool/yuewei',
      ),
      const NavItem(
        label: '得到转多看',
        icon: Icons.swap_horiz_outlined,
        route: '/epub-tool/zhangyue',
      ),
    ],
  ),
  NavItem(
    label: 'Kindle 推送',
    icon: Icons.send_outlined,
    children: [
      const NavItem(
        label: '邮箱推送',
        icon: Icons.mail_outline,
        route: '/send-email',
      ),
      const NavItem(
          label: '网页推送', icon: Icons.language, route: '/send-web'),
      const NavItem(
        label: 'WiFi 传书',
        icon: Icons.wifi_rounded,
        route: '/wifi-transfer',
      ),
    ],
  ),
  NavItem(
    label: '使用教程',
    icon: Icons.school_outlined,
    children: [
      const NavItem(
        label: '传书教程',
        icon: Icons.menu_book_outlined,
        route: '/tutorial',
      ),
    ],
  ),
];

const double _sidebarWidthDesktop = 260;
const double _sidebarWidthTablet = 240;

/// 移动端底部导航栏配置（4 项 + 更多）
const List<_BottomNavDef> _bottomNavDefs = [
  _BottomNavDef(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: '仪表盘',
    route: '/dashboard',
  ),
  _BottomNavDef(
    icon: Icons.swap_horiz_outlined,
    activeIcon: Icons.swap_horiz_rounded,
    label: '转换',
    route: '/txt2epub',
  ),
  _BottomNavDef(
    icon: Icons.format_shapes_outlined,
    activeIcon: Icons.format_shapes_rounded,
    label: '格式',
    route: '/metadata',
  ),
  _BottomNavDef(
    icon: Icons.lock_outline,
    activeIcon: Icons.lock_rounded,
    label: '安全',
    route: '/epub-tool/encrypt',
  ),
];

class _BottomNavDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  const _BottomNavDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

const String _brandName = 'EPUB 工具箱';

// ==================== 应用整体布局 ====================

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
        systemNavigationBarColor: context.themeBg,
        systemNavigationBarIconBrightness:
            context.isDarkMode ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: ChangeNotifierProvider(
        create: (_) => SidebarState(),
        child: Builder(
          builder: (context) {
            if (context.isDesktop) {
              return _DesktopLayout(child: child);
            } else if (context.isTablet) {
              return _TabletLayout(child: child);
            }
            return _MobileLayout(child: child);
          },
        ),
      ),
    );
  }
}

// ==================== 桌面端布局（≥1024px）====================

class _DesktopLayout extends StatelessWidget {
  final Widget child;
  const _DesktopLayout({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PaperBackground(child: SizedBox.shrink()),
          ),
          Row(
            children: [
              _Sidebar(
                currentPath: location,
                width: _sidebarWidthDesktop,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== 平板端布局（800–1023px）====================

class _TabletLayout extends StatelessWidget {
  final Widget child;
  const _TabletLayout({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PaperBackground(child: SizedBox.shrink()),
          ),
          Row(
            children: [
              _Sidebar(
                currentPath: location,
                width: _sidebarWidthTablet,
              ),
              Expanded(child: child),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== 移动端布局（<800px）====================

class _MobileLayout extends StatefulWidget {
  final Widget child;
  const _MobileLayout({required this.child});

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout> {
  bool _sidebarOpen = false;

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);
  void _closeSidebar() => setState(() => _sidebarOpen = false);

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = (screenWidth * 0.82).clamp(240.0, 320.0);
    final location = GoRouterState.of(context).uri.toString();
    final bottomNavIndex = _computeBottomNavIndex(location);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PaperBackground(child: SizedBox.shrink()),
          ),
          Column(
            children: [
              Container(height: topPadding, color: Colors.transparent),
              _MobileTopBar(
                onMenuTap: _toggleSidebar,
                title: _currentTitle(location),
              ),
              Expanded(child: widget.child),
            ],
          ),
          // 遮罩层
          if (_sidebarOpen)
            GestureDetector(
              onTap: _closeSidebar,
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          // 抽屉
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: _sidebarOpen ? 0 : -drawerWidth,
            top: 0,
            bottom: 0,
            width: drawerWidth,
            child: Material(
              elevation: 10,
              color: context.themeBg,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(AppTheme.radiusL),
                bottomRight: Radius.circular(AppTheme.radiusL),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(AppTheme.radiusL),
                  bottomRight: Radius.circular(AppTheme.radiusL),
                ),
                child: _Sidebar(
                  currentPath: location,
                  width: drawerWidth,
                  onNavigate: _closeSidebar,
                  topPadding: topPadding,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _MobileBottomNav(
        currentPath: location,
        selectedIndex: bottomNavIndex,
        onMoreTap: _toggleSidebar,
      ),
    );
  }

  String _currentTitle(String route) {
    for (final nav in _navGroups) {
      if (nav.route == route) return _brandName;
      if (nav.children != null) {
        for (final c in nav.children!) {
          if (c.route == route) return c.label;
        }
      }
    }
    return _brandName;
  }

  int _computeBottomNavIndex(String route) {
    for (var i = 0; i < _bottomNavDefs.length; i++) {
      if (_bottomNavDefs[i].route == route) return i;
    }
    // 分类首页匹配
    if (route == '/dashboard') return 0;
    return -1;
  }
}

// ==================== 移动端顶部栏 ====================

class _MobileTopBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final String title;

  const _MobileTopBar({required this.onMenuTap, required this.title});

  @override
  Widget build(BuildContext context) {
    final showLogo = title == _brandName;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.themeBg.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(
                color: context.themeDividerLight.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onMenuTap,
                icon: Icon(
                  Icons.menu,
                  size: 24,
                  color: context.themeAccent,
                ),
                tooltip: '显示菜单',
                splashRadius: 22,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: showLogo
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXS,
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  context.themeAccent,
                                  context.themeAccentDark,
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_stories_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _brandName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.themeTextPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.themeTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: 44),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 移动端底部导航栏 ====================

class _MobileBottomNav extends StatelessWidget {
  final String currentPath;
  final int selectedIndex;
  final VoidCallback onMoreTap;

  const _MobileBottomNav({
    required this.currentPath,
    required this.selectedIndex,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMoreActive = selectedIndex < 0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: context.themeBg.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: context.themeDividerLight.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  for (var i = 0; i < _bottomNavDefs.length; i++)
                    Expanded(
                      child: _buildItem(
                        context,
                        _bottomNavDefs[i],
                        selectedIndex == i,
                      ),
                    ),
                  Expanded(
                    child: _buildMoreItem(context, isMoreActive),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    _BottomNavDef item,
    bool isActive,
  ) {
    return InkWell(
      onTap: () => context.go(item.route),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isActive ? item.activeIcon : item.icon,
            size: 22,
            color: isActive
                ? context.themeAccent
                : context.themeTextTertiary,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? context.themeAccent
                  : context.themeTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreItem(BuildContext context, bool isActive) {
    return InkWell(
      onTap: onMoreTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.apps_rounded,
            size: 22,
            color: isActive
                ? context.themeAccent
                : context.themeTextTertiary,
          ),
          const SizedBox(height: 2),
          Text(
            '更多',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? context.themeAccent
                  : context.themeTextTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 侧边栏状态管理 ====================

/// 全局侧边栏状态管理：支持多分组同时展开
class SidebarState extends ChangeNotifier {
  final Set<String> _expandedGroups = {};

  Set<String> get expandedGroups => Set.unmodifiable(_expandedGroups);

  bool isExpanded(String groupLabel) =>
      _expandedGroups.contains(groupLabel);

  void toggle(String groupLabel) {
    if (_expandedGroups.contains(groupLabel)) {
      _expandedGroups.remove(groupLabel);
    } else {
      _expandedGroups.add(groupLabel);
    }
    notifyListeners();
  }

  void expand(String groupLabel) {
    if (_expandedGroups.add(groupLabel)) notifyListeners();
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
  final VoidCallback? onNavigate;
  final double? topPadding;

  const _Sidebar({
    required this.currentPath,
    required this.width,
    this.onNavigate,
    this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: context.themeBg,
      child: Column(
        children: [
          if (topPadding != null) SizedBox(height: topPadding! + 8),
          if (topPadding == null) const SizedBox(height: 16),
          _buildBrand(context),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: context.themeDivider),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: _navGroups.length,
              itemBuilder: (context, index) {
                final nav = _navGroups[index];
                if (nav.isLeaf) {
                  return _LeafNavTile(
                    icon: nav.icon,
                    label: nav.label,
                    route: nav.route!,
                    currentPath: currentPath,
                    onTap: () {
                      context.go(nav.route!);
                      onNavigate?.call();
                    },
                  );
                }
                return _ExpandableNavGroup(
                  parent: nav,
                  currentPath: currentPath,
                  onNavigate: onNavigate,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'v1.1.1',
              style: TextStyle(
                fontSize: 11,
                color: context.themeTextTertiary.withValues(alpha: 0.6),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.themeAccent,
                  context.themeAccentDark,
                ],
              ),
              boxShadow: AppTheme.glow(context.themeAccent, alpha: 0.20),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_stories_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _brandName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
    );
  }
}

// ==================== 叶子导航项 ====================

class _LeafNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String currentPath;
  final VoidCallback onTap;

  const _LeafNavTile({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentPath == route;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? context.themeAccentLight : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
            border: Border(
              left: BorderSide(
                color: isActive ? context.themeAccent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? context.themeAccent
                    : context.themeTextTertiary,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? context.themeAccent
                      : context.themeTextSecondary,
                ),
              ),
            ],
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
  final VoidCallback? onNavigate;

  const _ExpandableNavGroup({
    required this.parent,
    required this.currentPath,
    this.onNavigate,
  });

  @override
  State<_ExpandableNavGroup> createState() => _ExpandableNavGroupState();
}

class _ExpandableNavGroupState extends State<_ExpandableNavGroup>
    with SingleTickerProviderStateMixin {
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
    if (widget.currentPath != oldWidget.currentPath) {
      if (_hasActiveChild()) {
        _sidebarState(context).expand(widget.parent.label);
      } else {
        _sidebarState(context).collapse(widget.parent.label);
      }
    }
  }

  bool _hasActiveChild() {
    if (widget.parent.children == null) return false;
    return widget.parent.children!
        .any((c) => c.route == widget.currentPath);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(AppTheme.radiusS),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: hasActiveChild
                  ? context.themeAccentLight
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              border: Border(
                left: BorderSide(
                  color: hasActiveChild
                      ? context.themeAccent.withValues(alpha: 0.4)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.parent.icon,
                  size: 18,
                  color: hasActiveChild
                      ? context.themeAccent
                      : context.themeTextTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.parent.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: hasActiveChild
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: hasActiveChild
                          ? context.themeAccent
                          : context.themeTextSecondary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: hasActiveChild
                        ? context.themeAccent
                        : context.themeTextTertiary,
                  ),
                ),
              ],
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
                      const EdgeInsets.only(left: 8, top: 2, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.parent.children!.map((child) {
                      final isActive =
                          child.route == widget.currentPath;
                      return InkWell(
                        onTap: () {
                          context.go(child.route!);
                          widget.onNavigate?.call();
                        },
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusS),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? context.themeAccentLight
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusS,
                            ),
                            border: Border(
                              left: BorderSide(
                                color: isActive
                                    ? context.themeAccent
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                child.icon,
                                size: 16,
                                color: isActive
                                    ? context.themeAccent
                                    : context.themeTextTertiary
                                        .withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                child.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isActive
                                      ? context.themeAccent
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
