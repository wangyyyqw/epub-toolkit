import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// 仪表盘页面：按 README 的功能域组织主要入口。
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const _primaryActions = [
    _ToolEntry(
      title: 'TXT 转 EPUB',
      subtitle: '从纯文本生成电子书',
      route: '/txt2epub',
      icon: Icons.menu_book_rounded,
      color: Color(0xFF2F6F73),
    ),
    _ToolEntry(
      title: 'EPUB 转 TXT',
      subtitle: '导出章节文本',
      route: '/epub-tool/epub-to-txt',
      icon: Icons.article_outlined,
      color: Color(0xFF466C9F),
    ),
    _ToolEntry(
      title: '重新格式化',
      subtitle: '规范内部结构',
      route: '/epub-tool/reformat',
      icon: Icons.auto_fix_high_outlined,
      color: Color(0xFF8A633F),
    ),
    _ToolEntry(
      title: 'Kindle 推送',
      subtitle: '邮箱或网页传书',
      route: '/send-email',
      icon: Icons.send_rounded,
      color: Color(0xFF5D7B42),
    ),
  ];

  static const _groups = [
    _ToolGroup(
      title: '文件转换',
      summary: 'TXT、EPUB 与简繁转换',
      icon: Icons.swap_horiz_rounded,
      color: Color(0xFF466C9F),
      tools: [
        _ToolEntry(
          title: 'TXT 转 EPUB',
          subtitle: '纯文本生成电子书',
          route: '/txt2epub',
          icon: Icons.menu_book_rounded,
          color: Color(0xFF466C9F),
        ),
        _ToolEntry(
          title: 'EPUB 转 TXT',
          subtitle: '章节导出为文本',
          route: '/epub-tool/epub-to-txt',
          icon: Icons.article_outlined,
          color: Color(0xFF466C9F),
        ),
        _ToolEntry(
          title: 'EPUB 2/3 互转',
          subtitle: '版本结构转换',
          route: '/epub-tool/convert-version',
          icon: Icons.swap_vert_outlined,
          color: Color(0xFF466C9F),
        ),
        _ToolEntry(
          title: '简体转繁体',
          subtitle: '中文内容转换',
          route: '/epub-tool/s2t',
          icon: Icons.translate,
          color: Color(0xFF466C9F),
        ),
        _ToolEntry(
          title: '繁体转简体',
          subtitle: '中文内容转换',
          route: '/epub-tool/t2s',
          icon: Icons.translate_outlined,
          color: Color(0xFF466C9F),
        ),
      ],
    ),
    _ToolGroup(
      title: '结构处理',
      summary: '元数据、封面、合并和拆分',
      icon: Icons.account_tree_outlined,
      color: Color(0xFF8A633F),
      tools: [
        _ToolEntry(
          title: '查看 OPF 元数据',
          subtitle: '读取包信息',
          route: '/epub-tool/view-opf',
          icon: Icons.code_outlined,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '编辑元数据',
          subtitle: '书名、作者、封面',
          route: '/metadata',
          icon: Icons.edit_note_rounded,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '替换封面图片',
          subtitle: '更新 EPUB 封面',
          route: '/epub-tool/replace-cover',
          icon: Icons.image_outlined,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '重新格式化',
          subtitle: '整理内部结构',
          route: '/epub-tool/reformat',
          icon: Icons.auto_fix_high_outlined,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '合并 EPUB',
          subtitle: '多本合并为一本',
          route: '/epub-tool/merge',
          icon: Icons.call_merge_outlined,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '拆分 EPUB',
          subtitle: '按章节拆分',
          route: '/epub-tool/split',
          icon: Icons.call_split,
          color: Color(0xFF8A633F),
        ),
        _ToolEntry(
          title: '列出拆分目标',
          subtitle: '查看章节索引',
          route: '/epub-tool/list-split-targets',
          icon: Icons.list_alt_outlined,
          color: Color(0xFF8A633F),
        ),
      ],
    ),
    _ToolGroup(
      title: '图片处理',
      summary: '压缩、WebP 转换和网络图片',
      icon: Icons.image_rounded,
      color: Color(0xFF4B805F),
      tools: [
        _ToolEntry(
          title: '图片压缩',
          subtitle: '降低文件体积',
          route: '/epub-tool/img-compress',
          icon: Icons.compress_outlined,
          color: Color(0xFF4B805F),
        ),
        _ToolEntry(
          title: '图片转 WebP',
          subtitle: '批量转换格式',
          route: '/epub-tool/img-to-webp',
          icon: Icons.image_outlined,
          color: Color(0xFF4B805F),
        ),
        _ToolEntry(
          title: 'WebP 转图片',
          subtitle: '转回 JPEG/PNG',
          route: '/epub-tool/webp-to-img',
          icon: Icons.image_search_outlined,
          color: Color(0xFF4B805F),
        ),
        _ToolEntry(
          title: '下载网络图片',
          subtitle: '补齐远程资源',
          route: '/epub-tool/download-images',
          icon: Icons.download_outlined,
          color: Color(0xFF4B805F),
        ),
      ],
    ),
    _ToolGroup(
      title: '字体与加密',
      summary: '字体瘦身、混淆和还原',
      icon: Icons.security_rounded,
      color: Color(0xFF7A5D9F),
      tools: [
        _ToolEntry(
          title: '字体子集化',
          subtitle: '减少字体体积',
          route: '/epub-tool/font-subset',
          icon: Icons.font_download_outlined,
          color: Color(0xFF7A5D9F),
        ),
        _ToolEntry(
          title: '字体加密',
          subtitle: '字形混淆保护',
          route: '/epub-tool/encrypt-font',
          icon: Icons.security_outlined,
          color: Color(0xFF7A5D9F),
        ),
        _ToolEntry(
          title: '列出字体目标',
          subtitle: '扫描字体引用',
          route: '/epub-tool/list-font-targets',
          icon: Icons.format_size_outlined,
          color: Color(0xFF7A5D9F),
        ),
        _ToolEntry(
          title: '名称混淆加密',
          subtitle: '保护内部文件名',
          route: '/epub-tool/encrypt',
          icon: Icons.enhanced_encryption_outlined,
          color: Color(0xFF7A5D9F),
        ),
        _ToolEntry(
          title: '名称混淆解密',
          subtitle: '恢复可编辑结构',
          route: '/epub-tool/decrypt',
          icon: Icons.no_encryption_outlined,
          color: Color(0xFF7A5D9F),
        ),
      ],
    ),
    _ToolGroup(
      title: '批注和脚注',
      summary: '弹窗、脚注和多看格式转换',
      icon: Icons.comment_bank_outlined,
      color: Color(0xFF9A6848),
      tools: [
        _ToolEntry(
          title: '弹窗批注提取',
          subtitle: '正文批注转注释',
          route: '/epub-tool/comment',
          icon: Icons.comment_bank_outlined,
          color: Color(0xFF9A6848),
        ),
        _ToolEntry(
          title: '脚注转弹窗',
          subtitle: '标准脚注转弹窗',
          route: '/epub-tool/footnote-to-comment',
          icon: Icons.question_answer_outlined,
          color: Color(0xFF9A6848),
        ),
        _ToolEntry(
          title: '弹窗转脚注',
          subtitle: '弹窗注释转 EPUB3',
          route: '/epub-tool/span-to-footnote',
          icon: Icons.format_quote_outlined,
          color: Color(0xFF9A6848),
        ),
        _ToolEntry(
          title: '阅微转多看',
          subtitle: '脚注格式转换',
          route: '/epub-tool/yuewei',
          icon: Icons.sync_alt_outlined,
          color: Color(0xFF9A6848),
        ),
        _ToolEntry(
          title: '得到/掌阅转多看',
          subtitle: '脚注格式转换',
          route: '/epub-tool/zhangyue',
          icon: Icons.swap_horiz_outlined,
          color: Color(0xFF9A6848),
        ),
      ],
    ),
    _ToolGroup(
      title: '阅读和推送',
      summary: 'Kindle 邮箱、网页推送和教程',
      icon: Icons.local_library_outlined,
      color: Color(0xFF5D7B42),
      tools: [
        _ToolEntry(
          title: 'Kindle 邮箱推送',
          subtitle: '发送到 Kindle',
          route: '/send-email',
          icon: Icons.send_rounded,
          color: Color(0xFF5D7B42),
        ),
        _ToolEntry(
          title: 'Send to Kindle',
          subtitle: '打开网页版推送',
          route: '/send-web',
          icon: Icons.open_in_browser_rounded,
          color: Color(0xFF5D7B42),
        ),
        _ToolEntry(
          title: 'Kindle 传书教程',
          subtitle: '流程和注意事项',
          route: '/tutorial',
          icon: Icons.school_rounded,
          color: Color(0xFF5D7B42),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _DashboardHeader(actions: _primaryActions),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _SectionTitle(
              title: '按工作内容选择工具',
              subtitle: '功能分组与 README 保持一致',
              actionLabel: '查看教程',
              onAction: () => context.go('/tutorial'),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final columns = width >= 1180
                  ? 3
                  : width >= 760
                  ? 2
                  : 1;
              final spacing = 12.0;
              final itemWidth = (width - spacing * (columns - 1)) / columns;

              return SliverList.builder(
                itemCount: (_groups.length / columns).ceil(),
                itemBuilder: (context, rowIndex) {
                  final start = rowIndex * columns;
                  final rowGroups = _groups.skip(start).take(columns).toList();
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: rowIndex == (_groups.length / columns).ceil() - 1
                          ? 0
                          : spacing,
                    ),
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: rowGroups
                          .map(
                            (group) => SizedBox(
                              width: itemWidth,
                              child: _GroupPanel(group: group),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          sliver: SliverToBoxAdapter(child: _BottomNotes()),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final List<_ToolEntry> actions;

  const _DashboardHeader({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
        boxShadow: context.themeCardShadowLight,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final intro = _IntroBlock(wide: wide);
          final quick = _QuickStartPanel(actions: actions);

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 16), quick],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: intro),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: quick),
            ],
          );
        },
      ),
    );
  }
}

class _IntroBlock extends StatelessWidget {
  final bool wide;

  const _IntroBlock({required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.themeBgWarm,
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
                border: Border.all(color: context.themeDividerLight),
              ),
              child: Icon(
                Icons.auto_stories_rounded,
                color: context.themeTextPrimary,
                size: 25,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EPUB 工具箱',
                    style: TextStyle(
                      fontSize: wide ? 28 : 24,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: context.themeTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '一站式处理转换、结构修复、图片优化、字体处理、批注脚注和 Kindle 推送。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: context.themeTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatPill(label: '功能域', value: '6'),
            _StatPill(label: '工具入口', value: '29'),
            _StatPill(label: '运行方式', value: '本地'),
            _StatPill(label: '主要平台', value: 'macOS / Android'),
          ],
        ),
      ],
    );
  }
}

class _QuickStartPanel extends StatelessWidget {
  final List<_ToolEntry> actions;

  const _QuickStartPanel({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '常用入口',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.themeTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...actions.map((action) => _QuickActionTile(action: action)),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final _ToolEntry action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        child: InkWell(
          onTap: () => context.go(action.route),
          borderRadius: BorderRadius.circular(AppTheme.radiusS),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              border: Border.all(color: context.themeDividerLight),
            ),
            child: Row(
              children: [
                Icon(action.icon, color: action.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: context.themeTextPrimary,
                        ),
                      ),
                      Text(
                        action.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.themeTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.themeTextTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.themeTextPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: context.themeTextSecondary,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.school_outlined, size: 18),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _GroupPanel extends StatelessWidget {
  final _ToolGroup group;

  const _GroupPanel({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
        boxShadow: context.themeCardShadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Icon(group.icon, color: group.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.themeTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _CountBadge(count: group.tools.length),
            ],
          ),
          const SizedBox(height: 12),
          ...group.tools.map((tool) => _ToolRow(tool: tool)),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final _ToolEntry tool;

  const _ToolRow({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(tool.route),
        borderRadius: BorderRadius.circular(AppTheme.radiusXS),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            children: [
              Icon(tool.icon, color: tool.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.themeTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      tool.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.themeTextTertiary.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNotes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final notes = [
          _NoteBlock(
            icon: Icons.info_outline_rounded,
            title: '处理前保留原文件',
            text: '清理、加密、合并和拆分会生成新文件；处理前建议保存原始 EPUB。',
            color: context.themeInfo,
          ),
          _NoteBlock(
            icon: Icons.image_outlined,
            title: '图片工具依赖平台能力',
            text: 'macOS 打包版内置 cwebp，Windows 可随程序放置 bin/cwebp.exe。',
            color: context.themeSuccess,
          ),
          _NoteBlock(
            icon: Icons.warning_amber_rounded,
            title: 'Kindle 推送仍需实测',
            text: '邮箱推送受账号、白名单和设备状态影响，异常时可改用网页版推送。',
            color: context.themeWarning,
          ),
        ];

        if (narrow) {
          return Column(
            children: notes
                .map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: note,
                  ),
                )
                .toList(),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < notes.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: notes[i]),
            ],
          ],
        );
      },
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color color;

  const _NoteBlock({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.themeTextPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: context.themeTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.themeTextTertiary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.themeTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Text(
        '$count 项',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: context.themeTextSecondary,
        ),
      ),
    );
  }
}

class _ToolGroup {
  final String title;
  final String summary;
  final IconData icon;
  final Color color;
  final List<_ToolEntry> tools;

  const _ToolGroup({
    required this.title,
    required this.summary,
    required this.icon,
    required this.color,
    required this.tools,
  });
}

class _ToolEntry {
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color color;

  const _ToolEntry({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.color,
  });
}
