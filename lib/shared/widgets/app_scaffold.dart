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
  const NavItem(label: '仪表盘', icon: Icons.home_outlined, route: '/dashboard'),
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
      const NavItem(label: '网页推送', icon: Icons.language, route: '/send-web'),
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

const double _sidebarWidth = 260;

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
        systemNavigationBarIconBrightness: context.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: ChangeNotifierProvider(
        create: (_) => SidebarState(),
        child: Builder(
          builder: (context) {
            final isWide = MediaQuery.of(context).size.width > 800;
            return isWide
                ? _DesktopLayout(child: child)
                : _MobileLayout(child: child);
          },
        ),
      ),
    );
  }
}

// ==================== 桌面端布局 ====================

class _DesktopLayout extends StatelessWidget {
  final Widget child;
  const _DesktopLayout({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return Scaffold(
      backgroundColor: Colors.transparent, // 让 PaperBackground 透出
      // 沉浸式：内容延伸到状态栏/导航栏
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PaperBackground(child: SizedBox.shrink()),
          ),
          // 内容层
          Row(
            children: [
              _Sidebar(currentPath: location),
              Expanded(
                child: child, // 直接显示，背景透明
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== 移动端布局 ====================

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
    final location = GoRouterState.of(context).uri.toString();

    return Scaffold(
      backgroundColor: Colors.transparent, // 让 PaperBackground 透出
      // 沉浸式：内容延伸到状态栏/导航栏
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PaperBackground(child: SizedBox.shrink()),
          ),
          // 内容层
          Column(
            children: [
              // 状态栏背景（透明，让系统时间等可见）
              Container(height: topPadding, color: Colors.transparent),
              _MobileTopBar(
                onMenuTap: _toggleSidebar,
                title: _currentTitle(location),
              ),
              Expanded(child: widget.child),
              // 底部安全区由内容自身处理（buildBottomActionBar 已用 SafeArea）
            ],
          ),

          // 遮罩层
          if (_sidebarOpen)
            GestureDetector(
              onTap: _closeSidebar,
              child: Container(color: Colors.black38),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: _sidebarOpen ? 0 : -_sidebarWidth,
            top: 0,
            bottom: 0,
            width: _sidebarWidth,
            child: Material(
              elevation: 10,
              color: context.themeCard,
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
                  onNavigate: _closeSidebar,
                  topPadding: topPadding,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _currentTitle(String route) {
    for (final nav in _navGroups) {
      if (nav.route == route) return _brandName;
      if (nav.children != null) {
        for (final child in nav.children!) {
          if (child.route == route) {
            return child.label;
          }
        }
      }
    }
    return _brandName;
  }

  /// 顶部栏品牌名（不重复内容区标题）
  static const _brandName = 'EPUB 工具箱';
}

// ==================== 移动端顶部栏 ====================

class _MobileTopBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final String title;

  const _MobileTopBar({required this.onMenuTap, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: context.themeBg.withValues(alpha: 0.96)),
      child: Row(
        children: [
          // 菜单按钮 - 透明背景, 突出图标
          IconButton(
            onPressed: onMenuTap,
            icon: Icon(Icons.menu, size: 24, color: context.themeTextPrimary),
            tooltip: '显示菜单',
            splashRadius: 22,
          ),
          const SizedBox(width: 2),
          // 当前页面标题
          Expanded(
            child: title == 'EPUB 工具箱'
                ? const SizedBox.shrink()
                : Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.themeTextSecondary.withValues(alpha: 0.9),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
    );
  }
}

// ==================== 侧边栏 ====================

/// 全局侧边栏状态管理：当前展开的分组
class SidebarState extends ChangeNotifier {
  /// 当前展开的分组名（只有一个为 null 时表示全部折叠；只允许一个展开）
  String? _expandedGroup;

  String? get expandedGroup => _expandedGroup;

  /// 切换分组（点击同一分组会折叠，点其它分组会切换）
  void toggle(String groupLabel) {
    if (_expandedGroup == groupLabel) {
      _expandedGroup = null;
    } else {
      _expandedGroup = groupLabel;
    }
    notifyListeners();
  }

  /// 设置为指定分组（不切换）
  void setExpanded(String? groupLabel) {
    if (_expandedGroup != groupLabel) {
      _expandedGroup = groupLabel;
      notifyListeners();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final String currentPath;
  final VoidCallback? onNavigate;
  final double? topPadding;

  const _Sidebar({required this.currentPath, this.onNavigate, this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _sidebarWidth,
      color: context.themeCard,
      child: Column(
        children: [
          // 顶部品牌区
          if (topPadding != null) SizedBox(height: topPadding! + 8),
          if (topPadding == null) const SizedBox(height: 14),
          _buildBrand(context),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: context.themeDivider),
          ),
          const SizedBox(height: 4),

          // 导航列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

          // 底部版本
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'v1.0.5',
              style: TextStyle(
                fontSize: 11,
                color: context.themeTextTertiary.withValues(alpha: 0.5),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.themeAccent,
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              boxShadow: AppTheme.glow(context.themeAccent, alpha: 0.16),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_stories_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'EPUB 工具箱',
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
            border: Border.all(
              color: isActive
                  ? context.themeAccent.withValues(alpha: 0.22)
                  : Colors.transparent,
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
              if (isActive) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: context.themeAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
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
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // 当前路径在分组中 → 展开
    // 否则跟随全局 SidebarState
    final sidebar = _sidebarState(context);
    if (_hasActiveChild()) {
      _expanded = true;
      sidebar.setExpanded(widget.parent.label);
    } else {
      _expanded = sidebar.expandedGroup == widget.parent.label;
    }
  }

  @override
  void didUpdateWidget(covariant _ExpandableNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPath != oldWidget.currentPath && _hasActiveChild()) {
      // 路由切换到本分组的子项 → 自动展开本分组
      _sidebarState(context).setExpanded(widget.parent.label);
    }
  }

  bool _hasActiveChild() {
    if (widget.parent.children == null) return false;
    return widget.parent.children!.any((c) => c.route == widget.currentPath);
  }

  /// 获取全局侧边栏状态
  SidebarState _sidebarState(BuildContext context) {
    return Provider.of<SidebarState>(context, listen: false);
  }

  void _toggle() {
    final sidebar = _sidebarState(context);
    if (_expanded) {
      // 当前已展开 → 折叠
      sidebar.setExpanded(null);
    } else {
      // 当前折叠 → 展开本分组（自动折叠其它）
      sidebar.setExpanded(widget.parent.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听全局 SidebarState 变化
    final sidebar = context.watch<SidebarState>();
    _expanded = sidebar.expandedGroup == widget.parent.label;
    final hasActiveChild = _hasActiveChild();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(AppTheme.radiusS),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: hasActiveChild
                  ? context.themeAccentLight
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              border: Border.all(
                color: hasActiveChild
                    ? context.themeAccent.withValues(alpha: 0.22)
                    : Colors.transparent,
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
                  turns: _expanded ? 0.25 : 0,
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
          child: _expanded && widget.parent.children != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.parent.children!.map((child) {
                      final isActive = child.route == widget.currentPath;
                      return InkWell(
                        onTap: () {
                          context.go(child.route!);
                          widget.onNavigate?.call();
                        },
                        borderRadius: BorderRadius.circular(AppTheme.radiusS),
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
                          ),
                          child: Row(
                            children: [
                              Icon(
                                child.icon,
                                size: 16,
                                color: isActive
                                    ? context.themeAccent
                                    : context.themeTextTertiary.withValues(
                                        alpha: 0.7,
                                      ),
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
                              if (isActive) ...[
                                const Spacer(),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: context.themeAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
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
