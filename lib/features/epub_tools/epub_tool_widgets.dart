import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../core/file_service.dart';
import '../../core/theme.dart';
import '../../shared/widgets/file_drop_target.dart';

/// EPUB 工具公共 UI 组件库（TDesign 风格）

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
          fontWeight: FontWeight.w600,
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
  FilesDroppedCallback? onFilesDropped,
  bool dropEnabled = true,
}) {
  final defaultDropHandler = _shouldAcceptDroppedFiles(label)
      ? (List<String> paths) {
          FileService.primeDroppedPaths(paths);
          onTap();
        }
      : null;
  final row = InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isComplete
              ? context.themeWarm.withValues(alpha: 0.55)
              : context.themeDividerLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isComplete ? context.themeWarm : context.themeTextTertiary,
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
  return FileDropTarget(
    enabled: dropEnabled,
    onFilesDropped: onFilesDropped ?? defaultDropHandler,
    child: row,
  );
}

bool _shouldAcceptDroppedFiles(String label) {
  if (label.contains('输出') || label.contains('保存')) return false;
  return label.contains('文件') ||
      label.contains('图片') ||
      label.toUpperCase().contains('EPUB') ||
      label.toUpperCase().contains('TXT');
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
              borderSide: BorderSide(color: context.themeAccent, width: 1.5),
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
              borderSide: BorderSide(color: context.themeAccent, width: 1.5),
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
///
/// 采用统一的墨色中性风格，保证全篇不出现第二处彩色。
Widget buildToolHeader(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.themeAccentLight,
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
          ),
          child: Icon(icon, color: context.themeAccent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.themeTextTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
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
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusL),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

/// 设置项行（TDesign TDCell 风格：左图标 + 标签 + 右值 + 右箭头，全行可点）
Widget buildSettingRow({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? value,
  Color? valueColor,
  Widget? trailing,
  VoidCallback? onTap,
  bool showDivider = true,
}) {
  final showArrow = onTap != null;
  final style = TDCellStyle(
    context: context,
    leftIconColor: context.themeTextTertiary,
    titleStyle: TextStyle(
      fontSize: 14.5,
      color: context.themeTextPrimary,
    ),
    noteStyle: TextStyle(
      fontSize: 13.5,
      color: valueColor ?? context.themeTextTertiary,
    ),
    arrowColor: context.themeTextTertiary.withValues(alpha: 0.35),
    borderedColor: context.themeDividerLight,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  return TDCell(
    leftIcon: icon,
    title: title,
    note: value,
    rightIconWidget: trailing,
    arrow: showArrow,
    showBottomBorder: showDivider,
    onClick: showArrow ? (cell) => onTap!() : null,
    style: style,
  );
}

/// 开关设置行（TDesign TDSwitch：标题 + 副标题 + 右侧开关）
class SettingSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: context.themeTextPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TDSwitch(
            isOn: value,
            onChanged: onChanged == null
                ? null
                : (v) {
                    onChanged!(v);
                    return true;
                  },
            trackOnColor: context.themeWarm,
            trackOffColor: context.themeDividerLight,
          ),
        ],
      ),
    );
  }
}

/// 分组设置卡片（阅微设置页风格）
///
/// 圆角白卡；[title] 为卡片上方的分组小标题（浅灰小字）。
/// [children] 中直接放 [buildSettingRow] 即可形成分组列表，
/// 行间分割线自动由各行自绘。
Widget buildGroupCard({
  required BuildContext context,
  required List<Widget> children,
  String? title,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  double titleSpacing = 10,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (title != null) ...[
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: context.themeTextTertiary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        SizedBox(height: titleSpacing),
      ],
      Container(
        decoration: BoxDecoration(
          color: context.themeCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: context.themeDividerLight),
          boxShadow: context.themeCardShadowLight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          child: Padding(
            padding: padding,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    ],
  );
}
