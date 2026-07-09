import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'epub_tool_catalog.dart';

/// EPUB 工具箱入口页面
///
/// 按分类展示所有 EPUB 工具，采用阅微风格的卡片式布局。
class EpubToolsHubPage extends StatelessWidget {
  const EpubToolsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // 页面头部
          SliverToBoxAdapter(child: _buildHeader(context)),

          // 工具统计
          SliverToBoxAdapter(child: _buildStatsBar(context)),

          // 按分类渲染工具
          ..._buildCategorySections(context),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF5B8FF9).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_outlined, color: Color(0xFF5B8FF9), size: 12),
            SizedBox(width: 4),
            Text(
              '选择需要的工具',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF5B8FF9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context) {
    final totalTools = EpubToolCatalog.groups.fold<int>(
      0,
      (sum, g) => sum + g.tools.length,
    );
    final totalCategories = EpubToolCatalog.groups.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _StatBadge(
            icon: Icons.folder_outlined,
            label: '$totalCategories 个分类',
          ),
          const SizedBox(width: 10),
          _StatBadge(icon: Icons.extension_outlined, label: '$totalTools 个工具'),
        ],
      ),
    );
  }

  List<Widget> _buildCategorySections(BuildContext context) {
    final List<Widget> sections = [];

    for (final group in EpubToolCatalog.groups) {
      // 分类标题
      sections.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              children: [
                Icon(group.catIcon, size: 18, color: context.themeAccent),
                const SizedBox(width: 8),
                Text(
                  group.category,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeAccentLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${group.tools.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.themeAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 工具网格
      sections.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tool = group.tools[index];
              return _ToolCard(tool: tool);
            }, childCount: group.tools.length),
          ),
        ),
      );
    }

    return sections;
  }
}

// ==================== 统计标签 ====================

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        boxShadow: context.themeCardShadowLight,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.themeTextTertiary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.themeTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ==================== 工具卡片 ====================

class _ToolCard extends StatelessWidget {
  final EpubToolMeta tool;

  const _ToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.themeCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      elevation: 0,
      child: InkWell(
        onTap: () => context.go(tool.route),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            boxShadow: context.themeCardShadowLight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tool.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXS),
                ),
                child: Icon(tool.icon, color: tool.color, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Text(
                  tool.desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeTextTertiary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
