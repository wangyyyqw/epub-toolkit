import 'package:flutter/material.dart';

/// 通用页头组件（紧凑版：只显示简短描述标签）
class PageHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? description;

  const PageHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    if (description == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 12),
                const SizedBox(width: 4),
                Text(
                  description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: iconColor,
                    fontWeight: FontWeight.w500,
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
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('$featureName · 开发中',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
