import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 带标签的输入框组件
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
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.themeDivider, width: 1),
    );
    final OutlineInputBorder focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.themeDivider, width: 1.5),
    );
    final OutlineInputBorder disabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: context.themeDividerLight.withValues(alpha: 0.5),
      ),
    );

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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          style: TextStyle(fontSize: 14, color: context.themeTextPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontSize: 13.5,
              color: context.themeTextTertiary,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    size: 18,
                    color: context.themeTextTertiary,
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            suffixIcon: widget.suffix != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: widget.suffix,
                  )
                : null,
            filled: true,
            fillColor: context.themeCard,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: focusedBorder,
            disabledBorder: disabledBorder,
          ),
        ),
      ],
    );
  }
}
