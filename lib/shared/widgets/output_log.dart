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

/// 输出日志入口。页面中仅显示按钮，点击后在弹窗中查看、滚动和复制日志。
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
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLogChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted || !_dialogOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
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

  void _clear() => widget.controller.clear();

  void _selectAll() {
    final length = widget.controller.text.length;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: length,
    );
    _focusNode.requestFocus();
  }

  int get _lineCount {
    final text = widget.controller.text;
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  }

  Future<void> _showLogDialog() async {
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        const compactButtonConstraints = BoxConstraints.tightFor(
          width: 36,
          height: 36,
        );
        return Dialog(
          backgroundColor: dialogContext.themeCard,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 28,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
            child: SizedBox(
              width: 820,
              height: 640,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compactHeader = constraints.maxWidth < 420;
                        return Row(
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 20,
                              color: dialogContext.themeAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: dialogContext.themeTextPrimary,
                                ),
                              ),
                            ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: widget.controller,
                              builder: (context, value, _) {
                                final hasContent = value.text.trim().isNotEmpty;
                                if (compactHeader) {
                                  return PopupMenuButton<String>(
                                    tooltip: '日志操作',
                                    enabled: hasContent,
                                    constraints: const BoxConstraints(
                                      minWidth: 132,
                                    ),
                                    icon: const Icon(
                                      Icons.more_horiz_rounded,
                                      size: 20,
                                    ),
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'select':
                                          _selectAll();
                                          break;
                                        case 'copy':
                                          _copyAll();
                                          break;
                                        case 'clear':
                                          _clear();
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'select',
                                        child: Text('全选'),
                                      ),
                                      PopupMenuItem(
                                        value: 'copy',
                                        child: Text('复制全部'),
                                      ),
                                      PopupMenuItem(
                                        value: 'clear',
                                        child: Text('清空日志'),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasContent)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Text(
                                          '$_lineCount 行',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                dialogContext.themeTextTertiary,
                                          ),
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: '全选',
                                      onPressed: hasContent ? _selectAll : null,
                                      constraints: compactButtonConstraints,
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.select_all_rounded,
                                        size: 19,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '复制全部',
                                      onPressed: hasContent ? _copyAll : null,
                                      constraints: compactButtonConstraints,
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '清空日志',
                                      onPressed: hasContent ? _clear : null,
                                      constraints: compactButtonConstraints,
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 19,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              constraints: compactButtonConstraints,
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Divider(height: 1, color: dialogContext.themeDividerLight),
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) {
                        if (value.text.trim().isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 32,
                                  color: dialogContext.themeTextTertiary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.emptyHint,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: dialogContext.themeTextTertiary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return Container(
                          color: dialogContext.themeBgPaper.withValues(
                            alpha: 0.72,
                          ),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: TextField(
                              controller: widget.controller,
                              focusNode: _focusNode,
                              scrollController: _scrollController,
                              readOnly: true,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              enableInteractiveSelection: true,
                              keyboardType: TextInputType.multiline,
                              scrollPhysics: const ClampingScrollPhysics(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(16),
                              ),
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.55,
                                color: dialogContext.themeTextSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasContent = value.text.trim().isNotEmpty;
        final hasError = value.text.contains('ERROR:');
        return SizedBox(
          height: 42,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showLogDialog,
            icon: Icon(
              hasError
                  ? Icons.error_outline_rounded
                  : Icons.receipt_long_outlined,
              size: 17,
              color: hasError ? context.themeError : context.themeAccent,
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hasContent ? '查看处理日志' : '查看日志'),
                if (hasContent) ...[
                  const SizedBox(width: 7),
                  Text(
                    '($_lineCount 行)',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ],
              ],
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeTextSecondary,
              side: BorderSide(
                color: hasError
                    ? context.themeError.withValues(alpha: 0.55)
                    : context.themeDividerLight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
            ),
          ),
        );
      },
    );
  }
}
