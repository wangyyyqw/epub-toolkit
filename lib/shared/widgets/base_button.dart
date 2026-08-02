import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 按钮样式枚举
enum BaseButtonVariant {
  /// 主色填充（松青绿）
  primary,

  /// 描边
  secondary,

  /// 强调色填充（暖陶橙）
  accent,

  /// 红色填充（危险操作）
  danger,
}

/// 按钮尺寸枚举
enum BaseButtonSize {
  /// 紧凑：高 36px，卡片内操作
  sm,

  /// 默认：高 44px
  md,

  /// 大号：高 48px，底部主操作
  lg,
}

/// 通用按钮组件
class BaseButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BaseButtonVariant variant;
  final BaseButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  const BaseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BaseButtonVariant.primary,
    this.size = BaseButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = loading || onPressed == null;
    final foregroundColor = _foregroundColor(context);

    final double height = switch (size) {
      BaseButtonSize.sm => 36,
      BaseButtonSize.md => 44,
      BaseButtonSize.lg => 48,
    };

    final double fontSize = switch (size) {
      BaseButtonSize.sm => 12,
      BaseButtonSize.md => 14,
      BaseButtonSize.lg => 15,
    };

    final double iconSize = switch (size) {
      BaseButtonSize.sm => 15,
      BaseButtonSize.md => 18,
      BaseButtonSize.lg => 20,
    };

    final EdgeInsets padding = switch (size) {
      BaseButtonSize.sm =>
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      BaseButtonSize.md =>
        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      BaseButtonSize.lg =>
        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    };

    final Widget buttonChild = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(icon, size: iconSize),
          ),
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final OutlinedBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusS),
    );

    if (variant == BaseButtonVariant.secondary) {
      return SizedBox(
        height: height,
        child: OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            side: BorderSide(
              color: disabled
                  ? context.themeDividerLight
                  : context.themeDivider,
              width: 1.5,
            ),
            disabledForegroundColor: context.themeTextTertiary,
            padding: padding,
            shape: shape,
          ),
          child: buttonChild,
        ),
      );
    }

    final backgroundColor = switch (variant) {
      BaseButtonVariant.primary => context.themeAccent,
      BaseButtonVariant.accent => context.themeWarm,
      BaseButtonVariant.danger => context.themeError,
      BaseButtonVariant.secondary => Colors.transparent,
    };

    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.4),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.5),
          padding: padding,
          elevation: 0,
          shape: shape,
        ),
        child: buttonChild,
      ),
    );
  }

  Color _foregroundColor(BuildContext context) {
    switch (variant) {
      case BaseButtonVariant.primary:
        return Colors.white;
      case BaseButtonVariant.secondary:
        return context.themeTextSecondary;
      case BaseButtonVariant.accent:
        return Colors.white;
      case BaseButtonVariant.danger:
        return Colors.white;
    }
  }
}
