import 'dart:ui' show ImageFilter;

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

/// 响应式行：宽屏(≥[breakpoint])横向排列子项，窄屏纵向堆叠
///
/// 用于把「文件选择 + 输出路径」「参数 + 参数」等表单在桌面端并排、
/// 移动端单列，避免桌面留白、移动端拥挤。
/// [flexes] 与 [children] 等长时按比例分配横向空间，缺省均分。
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;
  final List<int> flexes;
  final CrossAxisAlignment crossAxisAlignment;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.breakpoint = 720,
    this.spacing = 12,
    this.flexes = const [],
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= breakpoint;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(
                flex: i < flexes.length ? flexes[i] : 1,
                child: children[i],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 便捷函数：两个子项响应式并排（桌面双列、移动单列）
Widget buildResponsivePair({
  required Widget first,
  required Widget second,
  double breakpoint = 720,
  double spacing = 12,
  List<int> flexes = const [1, 1],
}) {
  return ResponsiveRow(
    breakpoint: breakpoint,
    spacing: spacing,
    flexes: flexes,
    children: [first, second],
  );
}

/// 工具页内容区边距
///
/// 桌面端(≥720)底部操作栏为悬浮按钮,内容区不需要大留白;
/// 移动端保留 80 底部空间给通栏按钮。
EdgeInsets toolPageContentPadding(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  return EdgeInsets.fromLTRB(16, 4, 16, wide ? 24 : 80);
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
///
/// 桌面端展示更长路径，移动端截断。
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
  final wide = MediaQuery.sizeOf(context).width >= 720;
  final displayValue = value.isNotEmpty
      ? (value.length > (wide ? 88 : 40) ? truncatePath(value, maxLen: wide ? 72 : 35) : value)
      : hint;
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
                  displayValue,
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
///
/// controller 由内部 StatefulWidget 管理并随组件销毁释放，
/// 避免每次 build 新建 TextEditingController 导致光标跳尾与内存泄漏。
Widget buildCompactField(
  BuildContext context, {
  required String label,
  required String value,
  required String hint,
  required IconData icon,
  required ValueChanged<String> onChanged,
  int maxLines = 1,
}) {
  return _CompactField(
    label: label,
    value: value,
    hint: hint,
    icon: icon,
    onChanged: onChanged,
    maxLines: maxLines,
  );
}

/// buildCompactField 的内部实现（StatefulWidget 管理 controller 生命周期）
class _CompactField extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final int maxLines;

  const _CompactField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onChanged,
    required this.maxLines,
  });

  @override
  State<_CompactField> createState() => _CompactFieldState();
}

class _CompactFieldState extends State<_CompactField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CompactField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步文本；编辑中(光标在内)不打断输入
    if (widget.value != oldWidget.value &&
        _controller.text != widget.value &&
        !_controller.selection.isValid) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 14, color: context.themeTextTertiary),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 13.5,
                color: context.themeTextTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.maxLines > 1 ? null : 54,
          child: TextField(
            controller: _controller,
            style: TextStyle(fontSize: 15, color: context.themeTextPrimary),
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              hintText: widget.hint,
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
            onChanged: widget.onChanged,
          ),
        ),
      ],
    );
  }
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
/// 桌面端字号/图标略大，移动端紧凑。
Widget buildToolHeader(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  return Padding(
    padding: EdgeInsets.fromLTRB(16, wide ? 8 : 6, 16, wide ? 12 : 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: wide ? 40 : 36,
          height: wide ? 40 : 36,
          decoration: BoxDecoration(
            color: context.themeAccentLight,
            borderRadius: BorderRadius.circular(AppTheme.radiusS),
          ),
          child: Icon(icon, color: context.themeAccent, size: wide ? 21 : 18),
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
                  fontSize: wide ? 19 : 17,
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
                  fontSize: wide ? 12.5 : 12,
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

/// 底部固定操作栏
///
/// 响应式：宽屏(≥720)为右下角悬浮胶囊按钮(不占通栏宽度，内容区不再
/// 需要底部大留白)；窄屏为通栏大按钮(触控友好)。
/// 加载态均为半透明磨砂玻璃。
Widget buildBottomActionBar(
  BuildContext context, {
  required bool loading,
  required VoidCallback onPressed,
  String label = '执行操作',
  IconData icon = Icons.play_arrow_rounded,
}) {
  return SafeArea(
    top: false,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final loadingWidget = ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: context.themeCard.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                border: Border.all(
                  color: context.themeDividerLight.withValues(alpha: 0.6),
                ),
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
            ),
          ),
        );
        final actionButton = SizedBox(
          height: 50,
          width: wide ? 260 : double.infinity,
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
        );

        if (!wide) {
          // 移动端：通栏操作栏
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: loading ? loadingWidget : actionButton,
          );
        }
        // 桌面端：右下角悬浮，内容区不再需要底部大留白
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 20),
          child: Align(
            alignment: Alignment.bottomRight,
            child: loading ? loadingWidget : actionButton,
          ),
        );
      },
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
    onClick: showArrow ? (cell) => onTap() : null,
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
