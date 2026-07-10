import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/theme.dart';

/// EPUB 工具公共 UI 组件库（阅微风格）

/// 路径中间截断
String truncatePath(String path, {int maxLen = 35}) {
  if (path.length <= maxLen) return path;
  final dir = p.dirname(path);
  final base = p.basename(path);
  if (base.length >= maxLen - 5) {
    return '.../${base.substring(0, maxLen - 8)}...';
  }
  final keep = maxLen - base.length - 5;
  if (keep <= 0) return '.../$base';
  return '${dir.substring(0, keep)}.../$base';
}

Color _mutedIconColor(Color color, bool isDark) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness * (isDark ? 0.72 : 0.62)).clamp(0.18, 0.62))
      .withSaturation((hsl.saturation * 0.82).clamp(0.0, 1.0))
      .toColor();
}

/// 区块标签（图标 + 文字）
Widget buildSectionLabel(BuildContext context, IconData icon, String text) {
  return Row(
    children: [
      Icon(icon, size: 16, color: context.themeAccent),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: context.themeTextPrimary,
        ),
      ),
    ],
  );
}

/// 信息提示条
Widget buildInfoBar(BuildContext context, String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.themeAccentLight.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.themeAccent.withValues(alpha: 0.12)),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 15, color: context.themeAccent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: context.themeAccent,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 可点击说明条
Widget buildHelpInfoBar(
  BuildContext context, {
  required String text,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeAccentLight.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.themeAccent.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: context.themeAccent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.themeAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 18, color: context.themeAccent),
        ],
      ),
    ),
  );
}

/// 工具说明弹窗段落
class ToolHelpSection {
  const ToolHelpSection({
    required this.title,
    required this.content,
    this.isCode = false,
  });

  final String title;
  final String content;
  final bool isCode;
}

/// 显示工具结构说明弹窗
Future<void> showToolHelpDialog(
  BuildContext context, {
  required String title,
  required List<ToolHelpSection> sections,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: context.themeCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: context.themeAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Text(
                    sections[i].title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _HelpContent(section: sections[i]),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
          ),
        ],
      );
    },
  );
}

class _HelpContent extends StatelessWidget {
  const _HelpContent({required this.section});

  final ToolHelpSection section;

  @override
  Widget build(BuildContext context) {
    if (!section.isCode) {
      return SelectableText(
        section.content,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: context.themeTextSecondary,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          section.content,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: context.themeTextPrimary,
          ),
        ),
      ),
    );
  }
}

/// 文件选择行（整行可点击）
Widget buildFilePickerRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
  required String hint,
  required VoidCallback onTap,
  required bool isComplete,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isComplete
              ? context.themeAccent.withValues(alpha: 0.32)
              : context.themeDividerLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isComplete ? context.themeAccent : context.themeTextTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeTextTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty
                      ? (value.length > 40 ? truncatePath(value) : value)
                      : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: value.isNotEmpty
                        ? context.themeTextPrimary
                        : context.themeTextTertiary,
                    fontWeight: value.isNotEmpty
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: context.themeTextTertiary.withValues(alpha: 0.5),
          ),
        ],
      ),
    ),
  );
}

/// 紧凑文本输入框（带标签）
Widget buildCompactField(
  BuildContext context, {
  required String label,
  required String value,
  required String hint,
  required IconData icon,
  required ValueChanged<String> onChanged,
  int maxLines = 1,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: context.themeTextTertiary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 13.5, color: context.themeTextTertiary),
          ),
        ],
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: maxLines > 1 ? null : 54,
        child: TextField(
          controller: TextEditingController(text: value),
          style: TextStyle(fontSize: 15, color: context.themeTextPrimary),
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 14.5,
              color: context.themeTextTertiary,
            ),
            filled: true,
            fillColor: context.themeCard,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDividerLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDividerLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDivider, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

/// 紧凑下拉选择器
Widget buildCompactSelect(
  BuildContext context, {
  required String label,
  required String value,
  required List<String> items,
  required ValueChanged<String?> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 13.5, color: context.themeTextTertiary),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 54,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$value'),
          initialValue: value,
          isExpanded: true,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.themeTextPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: context.themeCard,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDividerLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDividerLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              borderSide: BorderSide(color: context.themeDivider, width: 1.5),
            ),
          ),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: context.themeTextTertiary,
            size: 20,
          ),
          dropdownColor: context.themeCard,
        ),
      ),
    ],
  );
}

/// 工具页页头（参考设置页的大标题风格）
Widget buildToolHeader(
  BuildContext context, {
  required IconData icon,
  required Color iconColor,
  required String title,
  required String subtitle,
}) {
  final mutedIconColor = _mutedIconColor(iconColor, context.isDarkMode);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: mutedIconColor.withValues(
            alpha: context.isDarkMode ? 0.18 : 0.1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: mutedIconColor, size: 12),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: mutedIconColor,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 底部固定操作栏（悬浮胶囊风格 - 让纸色背景贯通）
Widget buildBottomActionBar(
  BuildContext context, {
  required bool loading,
  required VoidCallback onPressed,
  String label = '执行操作',
  IconData icon = Icons.play_arrow_rounded,
}) {
  return SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: loading
          ? Container(
              height: 50,
              decoration: BoxDecoration(
                color: context.themeCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                border: Border.all(color: context.themeDividerLight),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: context.themeAccent,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '正在处理，请稍候…',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.themeTextSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeAccent,
                  foregroundColor: const Color(0xFF202124),
                  elevation: 0,
                  shadowColor: context.themeAccent.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: const Color(0xFF202124)),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF202124),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

/// 日志按钮入口。日志组件会在弹窗中提供滚动、选择、复制和清空操作。
Widget buildLogPanel(BuildContext context, Widget logController) {
  return logController;
}

/// 设置项行（用于设置页面风格）
Widget buildSettingRow({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? value,
  Widget? trailing,
  VoidCallback? onTap,
  bool showDivider = true,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.themeTextSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.themeTextPrimary,
                  ),
                ),
              ),
              if (value != null)
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.themeTextTertiary,
                  ),
                ),
              ?trailing,
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.themeTextTertiary.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
      if (showDivider)
        Divider(indent: 50, height: 1, color: context.themeDividerLight),
    ],
  );
}

/// 分组卡片容器
Widget buildGroupCard({
  required BuildContext context,
  required List<Widget> children,
  EdgeInsets padding = const EdgeInsets.all(12),
}) {
  return Container(
    decoration: BoxDecoration(
      color: context.themeCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      border: Border.all(color: context.themeDividerLight),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      child: Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}
