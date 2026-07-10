import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 按钮样式枚举
enum BaseButtonVariant {
  /// 主色填充
  primary,

  /// 描边
  secondary,

  /// 红色填充（危险操作）
  danger,
}

/// 通用按钮组件
class BaseButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BaseButtonVariant variant;
  final IconData? icon;
  final bool loading;

  const BaseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BaseButtonVariant.primary,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = loading || onPressed == null;
    final foregroundColor = _foregroundColor(context);

    final Widget buttonChild = Row(
      mainAxisSize: MainAxisSize.min,
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
            child: Icon(icon, size: 18),
          ),
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );

    final OutlinedBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    const EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 9,
    );

    switch (variant) {
      case BaseButtonVariant.primary:
        return SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: disabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeAccent,
              foregroundColor: const Color(0xFF202124),
              disabledBackgroundColor: context.themeAccent.withValues(
                alpha: 0.82,
              ),
              disabledForegroundColor: const Color(
                0xFF202124,
              ).withValues(alpha: 0.72),
              padding: padding,
              elevation: 0,
              shape: shape,
            ),
            child: buttonChild,
          ),
        );
      case BaseButtonVariant.secondary:
        return SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: disabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeTextSecondary,
              side: BorderSide(color: context.themeDivider, width: 1),
              disabledForegroundColor: context.themeTextTertiary,
              padding: padding,
              shape: shape,
            ),
            child: buttonChild,
          ),
        );
      case BaseButtonVariant.danger:
        return SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: disabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeError,
              foregroundColor: Colors.white,
              disabledBackgroundColor: context.themeError.withValues(
                alpha: 0.4,
              ),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
              padding: padding,
              elevation: 0,
              shape: shape,
            ),
            child: buttonChild,
          ),
        );
    }
  }

  Color _foregroundColor(BuildContext context) {
    switch (variant) {
      case BaseButtonVariant.primary:
        return const Color(0xFF202124);
      case BaseButtonVariant.secondary:
        return context.themeTextSecondary;
      case BaseButtonVariant.danger:
        return Colors.white;
    }
  }
}
