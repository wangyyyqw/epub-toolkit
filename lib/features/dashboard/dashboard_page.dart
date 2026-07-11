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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _WelcomeCard(),
              const SizedBox(height: 24),
              const _SectionHeading(
                title: '推荐',
                subtitle: '感谢这些优秀的阅读、制作与分享项目。',
              ),
              const SizedBox(height: 12),
              _RecommendationGrid(items: _recommendations),
              const SizedBox(height: 24),
              const _SectionHeading(
                title: '支持的平台与系统',
                subtitle: '各平台均以本地文件处理为主；Windows 网页推送需要 WebView2。',
              ),
              const SizedBox(height: 12),
              _PlatformGrid(items: _platforms),
              const SizedBox(height: 24),
              _ThanksCard(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
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
            width: 48,
            height: 48,
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
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '本地 EPUB 处理工具。请从左侧目录选择需要的功能。',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
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
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.themeTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: context.themeTextSecondary),
        ),
      ],
    );
  }
}

class _RecommendationGrid extends StatelessWidget {
  final List<_Recommendation> items;

  const _RecommendationGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 940 ? 2 : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _RecommendationCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final _Recommendation item;

  const _RecommendationCard({required this.item});

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
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: InkWell(
        onTap: () => _openLink(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            border: Border.all(color: context.themeDividerLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 21, color: context.themeAccent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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
              const SizedBox(height: 12),
              Text(
                item.description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.themeTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.devices_other_outlined,
                    size: 15,
                    color: context.themeTextTertiary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      item.platforms,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: context.themeAccent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '访问',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.themeAccent,
                    ),
                  ),
                ],
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
        const spacing = 12.0;
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
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.themeCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 22, color: context.themeAccent),
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
                    fontWeight: FontWeight.w800,
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
    _Acknowledgement('未响应', 'https://github.com/cnwxi'),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.themeBgWarm,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                color: context.themeAccent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                '致谢',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.themeTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '感谢以下项目和作者提供的思路、实现参考或相关工具：',
            style: TextStyle(
              fontSize: 13,
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
          const SizedBox(height: 16),
          Divider(height: 1, color: context.themeDividerLight),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: context.themeInfo,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '注意',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.themeTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Kindle 邮件发送功能可能尚未完成完整实机测试，因为目前没有 Kindle 设备。若无法发送、发送后 Kindle 未收到，或其它功能未生效、输出文件错误，请提供输入文件特征、操作步骤和输出结果，方便后续修复。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: context.themeTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
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
