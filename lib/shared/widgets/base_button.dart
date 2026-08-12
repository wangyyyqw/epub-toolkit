import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../core/theme.dart';

/// 按钮样式枚举
enum BaseButtonVariant {
  /// 主色填充（墨色）
  primary,

  /// 描边
  secondary,

  /// 强调色填充（柔粉蓝）
  accent,

  /// 暗红填充（破坏性操作）
  danger,
}

/// 按钮尺寸枚举
enum BaseButtonSize {
  /// 紧凑：卡片内操作
  sm,

  /// 默认
  md,

  /// 大号：底部主操作
  lg,
}

/// 通用按钮组件（TDesign TDButton 封装）
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

    final tdSize = switch (size) {
      BaseButtonSize.sm => TDButtonSize.small,
      BaseButtonSize.md => TDButtonSize.medium,
      BaseButtonSize.lg => TDButtonSize.large,
    };

    final tdType = switch (variant) {
      BaseButtonVariant.secondary => TDButtonType.outline,
      _ => TDButtonType.fill,
    };

    final tdTheme = switch (variant) {
      BaseButtonVariant.danger => TDButtonTheme.danger,
      _ => TDButtonTheme.primary,
    };

    final fontSize = switch (size) {
      BaseButtonSize.sm => 12.0,
      BaseButtonSize.md => 14.0,
      BaseButtonSize.lg => 15.0,
    };

    // 加载态：自定义 child（转圈 + 文案）
    final Widget? child;
    if (loading) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(_fgColor(context)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: _fgColor(context),
            ),
          ),
        ],
      );
    } else {
      child = null;
    }

    final style = switch (variant) {
      BaseButtonVariant.accent => TDButtonStyle(
          backgroundColor: context.themeWarm,
          textColor: Colors.white,
          frameColor: Colors.transparent,
        ),
      _ => null,
    };

    return TDButton(
      text: label,
      size: tdSize,
      type: tdType,
      theme: tdTheme,
      disabled: disabled,
      isBlock: expanded,
      icon: loading ? null : icon,
      height: switch (size) {
        BaseButtonSize.sm => 32,
        BaseButtonSize.md => 40,
        BaseButtonSize.lg => 48,
      },
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
      style: style,
      onTap: disabled ? null : onPressed,
      child: child,
    );
  }

  Color _fgColor(BuildContext context) {
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
