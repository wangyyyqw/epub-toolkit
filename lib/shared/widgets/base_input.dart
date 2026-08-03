import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../core/theme.dart';

/// 带标签的输入框组件（TDesign TDInput 封装）
class BaseInput extends StatefulWidget {
  final String? label;
  final String? hint;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool readOnly;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? errorText;

  const BaseInput({
    super.key,
    this.label,
    this.hint,
    required this.value,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.readOnly = false,
    this.prefixIcon,
    this.suffix,
    this.errorText,
  });

  @override
  State<BaseInput> createState() => _BaseInputState();
}

class _BaseInputState extends State<BaseInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant BaseInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError =
        widget.errorText != null && widget.errorText!.isNotEmpty;
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 12.5,
              color: context.themeTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TDInput(
          controller: _controller,
          focusNode: _focusNode,
          hintText: widget.hint,
          readOnly: widget.readOnly || !enabled,
          obscureText: widget.obscureText,
          onChanged: widget.onChanged,
          needClear: false,
          showBottomDivider: false,
          textStyle: TextStyle(fontSize: 14, color: context.themeTextPrimary),
          backgroundColor: enabled
              ? context.themeCard
              : context.themeCardSoft,
          inputDecoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontSize: 13.5,
              color: context.themeTextTertiary,
            ),
            errorText: widget.errorText,
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    size: 18,
                    color: context.themeTextTertiary,
                  )
                : null,
            suffixIcon: widget.suffix != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: widget.suffix,
                  )
                : null,
            filled: true,
            fillColor: enabled
                ? context.themeCard
                : context.themeCardSoft,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(
                color: hasError
                    ? context.themeError
                    : context.themeDivider,
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(
                color: hasError
                    ? context.themeError
                    : context.themeDivider,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(
                color: hasError
                    ? context.themeError
                    : context.themeAccent,
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(
                color: context.themeDividerLight.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
