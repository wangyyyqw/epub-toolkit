import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 通用页头组件
///
/// 显示图标 + 标题 + 描述的紧凑行，用于工具页面顶部。
/// 桌面端三元素水平排列；手机端描述隐藏（顶栏已显示标题）。
class PageHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? description;
  final bool showDescription;

  const PageHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.description,
    this.showDescription = true,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: isMobile ? 18 : 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w700,
                    color: context.themeTextPrimary,
                  ),
                ),
                if (showDescription &&
                    description != null &&
                    !isMobile) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeTextTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用占位页面（功能待实现时使用）
class PlaceholderPage extends StatelessWidget {
  final String featureName;
  final String description;

  const PlaceholderPage({
    super.key,
    required this.featureName,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction,
            size: 64,
            color: context.themeTextTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '$featureName · 开发中',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.themeTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: context.themeTextTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
