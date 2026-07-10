import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 通用卡片容器组件
class BaseCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double titleSpacing;

  const BaseCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
    this.titleSpacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.themeCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        side: BorderSide(color: context.themeDividerLight, width: 1),
      ),
      child: Padding(
        padding: padding,
        child: title == null
            ? child
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题行：图标 + 标题 + 可选操作区
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.themeTextPrimary,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  SizedBox(height: titleSpacing),
                  child,
                ],
              ),
      ),
    );
  }
}
