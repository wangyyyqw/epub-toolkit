import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// 仪表盘页面：高频入口 + 工具概览
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const _quickActions = [
    _FeatureItem(
      icon: Icons.menu_book_rounded,
      bgColor: Color(0xFFE6F3F4),
      iconColor: AppTheme.accent,
      title: 'TXT 转 EPUB',
      desc: '从纯文本生成电子书',
      route: '/txt2epub',
    ),
    _FeatureItem(
      icon: Icons.article_outlined,
      bgColor: Color(0xFFEAF0FA),
      iconColor: Color(0xFF3D6AA8),
      title: 'EPUB 转 TXT',
      desc: '导出章节结构文本',
      route: '/epub-tool/epub-to-txt',
    ),
    _FeatureItem(
      icon: Icons.edit_note_rounded,
      bgColor: Color(0xFFFFF2E8),
      iconColor: AppTheme.warm,
      title: '元数据编辑',
      desc: '修改书名、作者、封面',
      route: '/metadata',
    ),
    _FeatureItem(
      icon: Icons.compress_outlined,
      bgColor: Color(0xFFEAF7EF),
      iconColor: AppTheme.success,
      title: '图片压缩',
      desc: '减小 EPUB 文件体积',
      route: '/epub-tool/img-compress',
    ),
    _FeatureItem(
      icon: Icons.call_merge_outlined,
      bgColor: Color(0xFFF1EDFA),
      iconColor: Color(0xFF7657B8),
      title: '合并 EPUB',
      desc: '多本合并为一本',
      route: '/epub-tool/merge',
    ),
    _FeatureItem(
      icon: Icons.cleaning_services_outlined,
      bgColor: Color(0xFFFFEEEE),
      iconColor: AppTheme.error,
      title: '广告清理',
      desc: '正则批量清理文本',
      route: '/epub-tool/ad-clean',
    ),
  ];

  static const _secondaryActions = [
    _FeatureItem(
      icon: Icons.send_rounded,
      bgColor: Color(0xFFEAF7EF),
      iconColor: AppTheme.success,
      title: 'Kindle 推送',
      desc: '通过邮箱或网页推送',
      route: '/send-email',
    ),
    _FeatureItem(
      icon: Icons.school_rounded,
      bgColor: Color(0xFFF1EDFA),
      iconColor: Color(0xFF7657B8),
      title: '使用教程',
      desc: '推送流程和注意事项',
      route: '/tutorial',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          sliver: SliverToBoxAdapter(child: _Header()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 132,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FeatureCard(feature: _quickActions[index]),
              childCount: _quickActions.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 680;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TipsPanel(),
                      const SizedBox(height: 12),
                      _MorePanel(actions: _secondaryActions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _TipsPanel()),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _MorePanel(actions: _secondaryActions),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.themeAccent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EPUB 工具箱',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: context.themeTextPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '创建、转换、清理和优化 EPUB 文件',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.themeTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/txt2epub'),
                icon: Icon(Icons.bolt_rounded, size: 18),
                label: Text('开始转换'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                child: _Metric(label: '工具', value: '26'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _Metric(label: '批处理', value: '支持'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _Metric(label: '运行', value: '本地'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.themeTextTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              color: context.themeTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _FeatureItem feature;

  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.themeCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      child: InkWell(
        onTap: () => context.go(feature.route),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
                      color: feature.bgColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusS),
                    ),
                    child: Icon(
                      feature.icon,
                      color: feature.iconColor,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: context.themeTextTertiary.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                feature.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.themeTextPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                feature.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: context.themeTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '处理建议',
      icon: Icons.tips_and_updates_outlined,
      child: Column(
        children: [
          _TipRow(
            color: context.themeAccent,
            text: '执行清理、加密、合并前，先保留一份原始 EPUB。',
          ),
          _TipRow(
            color: context.themeSuccess,
            text: 'TXT 转 EPUB 可先预览章节识别结果，再生成文件。',
          ),
          _TipRow(color: context.themeWarm, text: '图片压缩适合发布前统一处理，可明显降低文件体积。'),
        ],
      ),
    );
  }
}

class _MorePanel extends StatelessWidget {
  final List<_FeatureItem> actions;

  const _MorePanel({required this.actions});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '其他入口',
      icon: Icons.apps_outlined,
      child: Column(
        children: actions
            .map(
              (action) => Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: action.bgColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusS),
                    ),
                    child: Icon(action.icon, color: action.iconColor, size: 18),
                  ),
                  title: Text(
                    action.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.themeTextPrimary,
                    ),
                  ),
                  subtitle: Text(
                    action.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeTextTertiary,
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => context.go(action.route),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Panel({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(icon, size: 18, color: context.themeAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.themeTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final Color color;
  final String text;

  const _TipRow({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: context.themeTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final Color bgColor;
  final Color iconColor;
  final String title;
  final String desc;
  final String route;

  const _FeatureItem({
    required this.icon,
    required this.bgColor,
    required this.iconColor,
    required this.title,
    required this.desc,
    required this.route,
  });
}
