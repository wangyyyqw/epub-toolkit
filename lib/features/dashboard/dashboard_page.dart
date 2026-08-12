import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';

/// 首页仅保留项目说明、致谢和相关资源推荐；具体功能从侧边栏进入。
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const _recommendations = [
    _Recommendation(
      title: '阅微',
      category: '软件推荐',
      description: '面向移动设备的本地电子书阅读器，专注 TXT 与 EPUB 的导入、目录识别和阅读排版。',
      platforms: 'Android · iPhone · iPad',
      url: 'https://www.zhendong.ltd/',
      icon: Icons.auto_stories_rounded,
    ),
    _Recommendation(
      title: '清墨',
      category: '软件推荐',
      description: '纯净的本地文本阅读器，支持 TXT、EPUB、ZIP、RAR 导入、章节识别、书签摘抄与进度同步。',
      platforms: 'Android · iPhone · iPad',
      url: 'https://lightink.zhendong.ltd/',
      icon: Icons.chrome_reader_mode_outlined,
    ),
    _Recommendation(
      title: '蠢卷栖萤',
      category: '博客推荐',
      description: '分享阅读、书籍与相关思考的个人博客，适合寻找下一本值得细读的书。',
      platforms: '网页',
      url: 'https://xn--3lru39bvpuzud.com/',
      icon: Icons.article_outlined,
    ),
    _Recommendation(
      title: 'TEpub Editor',
      category: '软件推荐',
      description: '面向 TXT 写作、EPUB 制作、校对、修复与文件级深度编辑的一体化电子书工作台。',
      platforms: 'Windows · macOS · Linux',
      url: 'https://github.com/YGHFv/TEpub-Editor',
      icon: Icons.edit_note_rounded,
    ),
  ];

  static const _platforms = [
    _PlatformSupport('macOS', '10.15 或更高版本', Icons.desktop_mac_rounded),
    _PlatformSupport(
      'Windows',
      'Windows 10 1809 或更高版本 / Windows 11',
      Icons.desktop_windows_rounded,
    ),
    _PlatformSupport(
      'Android',
      'Android 7.0 或更高版本',
      Icons.phone_android_rounded,
    ),
    _PlatformSupport(
      'iOS / iPadOS',
      'iOS 13 或更高版本',
      Icons.phone_iphone_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _WelcomeCard(),
              const SizedBox(height: 14),
              const _ThanksCard(),
              const SizedBox(height: 20),
              const _SectionHeading(
                title: '推荐',
                subtitle: '感谢这些优秀的阅读、制作与分享项目。',
              ),
              const SizedBox(height: 10),
              // 推荐卡片：桌面双列网格，移动端单列
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final cardWidth = wide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final item in _recommendations)
                        SizedBox(
                          width: cardWidth,
                          child: _RecommendationRow(item: item),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const _SectionHeading(
                title: '支持的平台与系统',
                subtitle: '各平台均以本地文件处理为主；Windows 网页推送需要 WebView2。',
              ),
              const SizedBox(height: 10),
              _PlatformGrid(items: _platforms),
            ]),
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
        boxShadow: context.themeCardShadowLight,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.themeAccentLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
            ),
            child: Icon(Icons.menu_book_rounded, color: context.themeAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EPUB 工具箱',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '本地 EPUB 处理工具。请从左侧目录选择需要的功能。',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: context.themeTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.themeTextPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12.5, color: context.themeTextTertiary),
        ),
      ],
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  final _Recommendation item;

  const _RecommendationRow({required this.item});

  Future<void> _openLink(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(item.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查网络或默认浏览器设置')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.themeCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusL),
      child: InkWell(
        onTap: () => _openLink(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(color: context.themeDividerLight),
            boxShadow: context.themeCardShadowLight,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.themeAccentLight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Icon(item.icon, size: 19, color: context.themeAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.themeTextPrimary,
                            ),
                          ),
                        ),
                        Text(
                          item.category,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.themeTextTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: context.themeTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.platforms,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.themeTextTertiary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformGrid extends StatelessWidget {
  final List<_PlatformSupport> items;

  const _PlatformGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 940
            ? 4
            : constraints.maxWidth >= 580
            ? 2
            : 1;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _PlatformCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final _PlatformSupport item;

  const _PlatformCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.themeDividerLight),
        boxShadow: context.themeCardShadowLight,
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 21, color: context.themeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.system,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: context.themeTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanksCard extends StatelessWidget {
  const _ThanksCard();

  static const _acknowledgements = [
    _Acknowledgement(
      '遥遥心航',
      'https://tieba.baidu.com/home/main?id=tb.1.7f262ae1.5_dXQ2Jp0F0MH9YJtgM2Ew',
    ),
    _Acknowledgement('lgernier', 'https://github.com/lgernier'),
    _Acknowledgement(
      'fontObfuscator',
      'https://github.com/solarhell/fontObfuscator',
    ),
    _Acknowledgement('epub_tool', 'https://github.com/cnwxi'),
    _Acknowledgement(
      'pickthought.koplugin',
      'https://github.com/Mr54233/pickthought.koplugin',
    ),
  ];

  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查网络或默认浏览器设置')));
    }
  }

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
              Icon(
                Icons.volunteer_activism_outlined,
                color: context.themeAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                '致谢',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.themeTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '感谢以下项目和作者提供的思路、实现参考或相关工具：',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: context.themeTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final item in _acknowledgements)
                ActionChip(
                  avatar: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: Text(item.name),
                  onPressed: () => _openLink(context, item.url),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.themeDividerLight),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: context.themeTextTertiary,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '注意',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: context.themeTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kindle 邮件发送功能可能尚未完成完整实机测试，因为目前没有 Kindle 设备。若无法发送、发送后 Kindle 未收到，或其它功能未生效、输出文件错误，请提供输入文件特征、操作步骤和输出结果，方便后续修复。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.55,
                        color: context.themeTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openLink(
                            context,
                            'mailto:wanmei8672873@outlook.com',
                          ),
                          icon: const Icon(Icons.email_outlined, size: 16),
                          label: const Text('wanmei8672873@outlook.com'),
                        ),
                        TextButton.icon(
                          onPressed: () => _openLink(
                            context,
                            'https://github.com/wangyyyqw/epub-toolkit/issues',
                          ),
                          icon: const Icon(Icons.bug_report_outlined, size: 16),
                          label: const Text('提交 Issue'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Recommendation {
  final String title;
  final String category;
  final String description;
  final String platforms;
  final String url;
  final IconData icon;

  const _Recommendation({
    required this.title,
    required this.category,
    required this.description,
    required this.platforms,
    required this.url,
    required this.icon,
  });
}

class _PlatformSupport {
  final String name;
  final String system;
  final IconData icon;

  const _PlatformSupport(this.name, this.system, this.icon);
}

class _Acknowledgement {
  final String name;
  final String url;

  const _Acknowledgement(this.name, this.url);
}
