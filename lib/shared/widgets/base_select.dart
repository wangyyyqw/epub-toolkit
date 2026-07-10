import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 带标签的下拉选择器组件
class BaseSelect extends StatelessWidget {
  final String? label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final String? hint;
  final bool enabled;

  const BaseSelect({
    super.key,
    this.label,
    required this.value,
    required this.items,
    this.onChanged,
    this.hint,
    this.enabled = true,
  });

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 12.5,
              color: context.themeTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey<String?>(value),
          initialValue: value,
          hint: hint != null
              ? Text(
                  hint!,
                  style: TextStyle(
                    color: context.themeTextTertiary,
                    fontSize: 14,
                  ),
                )
              : null,
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.themeTextPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
          decoration: InputDecoration(
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
          ),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: context.themeTextTertiary,
            size: 20,
          ),
          dropdownColor: context.themeCard,
        ),
      ],
    );
  }
}
