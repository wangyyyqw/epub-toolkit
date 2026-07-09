import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// 输出日志专用 Controller（封装 TextEditingController，自动通知监听）
class OutputLogController extends TextEditingController {
  OutputLogController({super.text});

  /// 追加一行文本（自动加换行）
  void append(String line) {
    if (text.isEmpty) {
      text = line;
    } else if (text.endsWith('\n')) {
      text = '$text$line';
    } else {
      text = '$text\n$line';
    }
  }

  /// 追加多行
  void appendLines(Iterable<String> lines) {
    final buf = StringBuffer(text);
    if (buf.isNotEmpty && !buf.toString().endsWith('\n')) {
      buf.writeln();
    }
    for (final line in lines) {
      buf.writeln(line);
    }
    text = buf.toString();
  }

  /// 替换全部内容
  void setAll(String content) {
    text = content;
  }
}

/// 输出日志面板（可独立滚动、折叠、清空、复制、自动滚动到底）
class OutputLog extends StatefulWidget {
  final TextEditingController controller;
  final String title;
  final double expandedHeight;
  final double collapsedHeight;
  final String emptyHint;

  const OutputLog({
    super.key,
    required this.controller,
    this.title = '处理日志',
    this.expandedHeight = 240,
    this.collapsedHeight = 40,
    this.emptyHint = '暂无日志',
  });

  @override
  State<OutputLog> createState() => _OutputLogState();
}

class _OutputLogState extends State<OutputLog> {
  bool _expanded = true;
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _copyAll() {
    final text = widget.controller.text;
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日志已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _clear() {
    widget.controller.clear();
    setState(() {});
  }

  int get _lineCount {
    final text = widget.controller.text;
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.controller.text.trim().isNotEmpty;
    final logBg = context.isDarkMode
        ? context.themeBgPaper.withValues(alpha: 0.72)
        : context.themeBgPaper.withValues(alpha: 0.64);
    final logTextColor = context.isDarkMode
        ? context.themeTextSecondary
        : context.themeTextPrimary;

    return Container(
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        boxShadow: _expanded ? context.themeCardShadowLight : const [],
        border: Border.all(
          color: context.themeDividerLight.withValues(
            alpha: context.isDarkMode ? 0.85 : 0.7,
          ),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(AppTheme.radiusM),
              bottom: Radius.circular(_expanded ? 0 : AppTheme.radiusM),
            ),
            child: Container(
              height: widget.collapsedHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: _expanded
                      ? BorderSide(color: context.themeDividerLight, width: 0.5)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: context.themeAccentLight,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: context.themeAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.themeTextPrimary,
                    ),
                  ),
                  if (hasContent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.themeChipBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_lineCount 行',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.themeTextTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_expanded) ...[
                    _IconAction(
                      icon: _autoScroll
                          ? Icons.vertical_align_bottom_rounded
                          : Icons.vertical_align_center_rounded,
                      tooltip: _autoScroll ? '已开启自动滚动' : '已关闭自动滚动',
                      active: _autoScroll,
                      onTap: () => setState(() => _autoScroll = !_autoScroll),
                    ),
                    _IconAction(
                      icon: Icons.copy_rounded,
                      tooltip: '复制全部',
                      onTap: hasContent ? _copyAll : null,
                    ),
                    _IconAction(
                      icon: Icons.cleaning_services_rounded,
                      tooltip: '清空',
                      onTap: hasContent ? _clear : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.5,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Container(
                    height: hasContent ? widget.expandedHeight : 108,
                    decoration: BoxDecoration(
                      color: logBg,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(AppTheme.radiusM),
                      ),
                    ),
                    child: hasContent
                        ? Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            radius: const Radius.circular(3),
                            child: TextField(
                              controller: widget.controller,
                              scrollController: _scrollController,
                              readOnly: true,
                              showCursor: false,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              enableInteractiveSelection: true,
                              keyboardType: TextInputType.multiline,
                              scrollPhysics: const ClampingScrollPhysics(),
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                              ),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontFamilyFallback: [
                                  'Menlo',
                                  'Consolas',
                                  'monospace',
                                ],
                                fontSize: 12.5,
                                height: 1.55,
                                color: logTextColor,
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 26,
                                    color: context.themeTextTertiary.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.emptyHint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.themeTextTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: disabled
                ? context.themeTextTertiary.withValues(alpha: 0.3)
                : (active ? context.themeAccent : context.themeTextSecondary),
          ),
        ),
      ),
    );
  }
}
