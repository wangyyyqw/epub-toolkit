import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 卡片阴影层级
enum CardElevation {
  /// 无投影（内嵌卡片）
  flat,

  /// 默认投影
  normal,

  /// 强投影（浮层、弹窗）
  raised,
}

/// 通用卡片容器组件
///
/// [elevation] 控制卡片层次：
/// - flat: 仅描边，无投影（内嵌卡片）
/// - normal: 极轻投影 + 弱描边（默认）
/// - raised: 投影 + 无描边（浮层卡片）
class BaseCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double titleSpacing;
  final CardElevation elevation;

  const BaseCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.titleSpacing = 12,
    this.elevation = CardElevation.normal,
  });

  @override
  Widget build(BuildContext context) {
    final shadows = switch (elevation) {
      CardElevation.flat => const <BoxShadow>[],
      CardElevation.normal => context.themeCardShadow,
      CardElevation.raised => context.themeCardShadow,
    };

    final showBorder = elevation != CardElevation.raised;

    return Material(
      color: context.themeCard,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: shadows,
          border: showBorder
              ? Border.all(color: context.themeDividerLight, width: 1)
              : null,
        ),
        child: Padding(
          padding: padding,
          child: title == null
              ? child
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
