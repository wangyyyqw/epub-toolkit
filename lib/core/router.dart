import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/txt2epub/txt2epub_page.dart';
// 工具箱入口已移除，工具直接通过侧边栏分类访问
// import '../features/epub_tools/epub_tools_hub_page.dart';
import '../features/epub_tools/tools/view_opf_page.dart';
import '../features/epub_tools/tools/replace_cover_page.dart';
import '../features/epub_tools/tools/reformat_page.dart';
import '../features/epub_tools/tools/convert_version_page.dart';
import '../features/epub_tools/tools/epub_to_txt_page.dart';
import '../features/epub_tools/tools/ad_clean_page.dart';
import '../features/epub_tools/tools/s2t_page.dart';
import '../features/epub_tools/tools/t2s_page.dart';
import '../features/epub_tools/tools/phonetic_page.dart';
import '../features/epub_tools/tools/comment_page.dart';
import '../features/epub_tools/tools/footnote_to_comment_page.dart';
import '../features/epub_tools/tools/span_to_footnote_page.dart';
import '../features/epub_tools/tools/yuewei_page.dart';
import '../features/epub_tools/tools/zhangyue_page.dart';
import '../features/epub_tools/tools/img_compress_page.dart';
import '../features/epub_tools/tools/img_to_webp_page.dart';
import '../features/epub_tools/tools/webp_to_img_page.dart';
import '../features/epub_tools/tools/download_images_page.dart';
import '../features/epub_tools/tools/encrypt_page.dart';
import '../features/epub_tools/tools/decrypt_page.dart';
import '../features/epub_tools/tools/encrypt_font_page.dart';
import '../features/epub_tools/tools/list_font_targets_page.dart';
import '../features/epub_tools/tools/merge_page.dart';
import '../features/epub_tools/tools/split_page.dart';
import '../features/epub_tools/tools/list_split_targets_page.dart';
import '../features/epub_tools/tools/font_subset_page.dart';
import '../features/metadata/metadata_page.dart';
import '../features/send_to_kindle/send_to_kindle_page.dart';
import '../features/send_to_kindle/web_send_page.dart';
import '../features/tutorial/tutorial_page.dart';
import '../shared/widgets/app_scaffold.dart';

/// 路由配置：侧边栏 + 内容区的 ShellRoute 结构
class AppRouter {
  AppRouter._();

  static final GoRouter config = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/txt2epub',
            name: 'txt2epub',
            builder: (context, state) => const Txt2EpubPage(),
          ),
          // EPUB 工具子页面（通过侧边栏分类直接访问）
          GoRoute(
            path: '/epub-tool/view-opf',
            builder: (context, state) => const ViewOpfPage(),
          ),
          GoRoute(
            path: '/epub-tool/replace-cover',
            builder: (context, state) => const ReplaceCoverPage(),
          ),
          GoRoute(
            path: '/epub-tool/reformat',
            builder: (context, state) => const ReformatPage(),
          ),
          GoRoute(
            path: '/epub-tool/convert-version',
            builder: (context, state) => const ConvertVersionPage(),
          ),
          GoRoute(
            path: '/epub-tool/epub-to-txt',
            builder: (context, state) => const EpubToTxtPage(),
          ),
          GoRoute(
            path: '/epub-tool/ad-clean',
            builder: (context, state) => const AdCleanPage(),
          ),
          GoRoute(
            path: '/epub-tool/s2t',
            builder: (context, state) => const S2tPage(),
          ),
          GoRoute(
            path: '/epub-tool/t2s',
            builder: (context, state) => const T2sPage(),
          ),
          GoRoute(
            path: '/epub-tool/phonetic',
            builder: (context, state) => const PhoneticPage(),
          ),
          GoRoute(
            path: '/epub-tool/comment',
            builder: (context, state) => const CommentPage(),
          ),
          GoRoute(
            path: '/epub-tool/footnote-to-comment',
            builder: (context, state) => const FootnoteToCommentPage(),
          ),
          GoRoute(
            path: '/epub-tool/span-to-footnote',
            builder: (context, state) => const SpanToFootnotePage(),
          ),
          GoRoute(
            path: '/epub-tool/yuewei',
            builder: (context, state) => const YueweiPage(),
          ),
          GoRoute(
            path: '/epub-tool/zhangyue',
            builder: (context, state) => const ZhangyuePage(),
          ),
          GoRoute(
            path: '/epub-tool/img-compress',
            builder: (context, state) => const ImgCompressPage(),
          ),
          GoRoute(
            path: '/epub-tool/img-to-webp',
            builder: (context, state) => const ImgToWebpPage(),
          ),
          GoRoute(
            path: '/epub-tool/webp-to-img',
            builder: (context, state) => const WebpToImgPage(),
          ),
          GoRoute(
            path: '/epub-tool/download-images',
            builder: (context, state) => const DownloadImagesPage(),
          ),
          GoRoute(
            path: '/epub-tool/encrypt',
            builder: (context, state) => const EncryptPage(),
          ),
          GoRoute(
            path: '/epub-tool/decrypt',
            builder: (context, state) => const DecryptPage(),
          ),
          GoRoute(
            path: '/epub-tool/encrypt-font',
            builder: (context, state) => const EncryptFontPage(),
          ),
          GoRoute(
            path: '/epub-tool/list-font-targets',
            builder: (context, state) => const ListFontTargetsPage(),
          ),
          GoRoute(
            path: '/epub-tool/merge',
            builder: (context, state) => const MergePage(),
          ),
          GoRoute(
            path: '/epub-tool/split',
            builder: (context, state) => const SplitPage(),
          ),
          GoRoute(
            path: '/epub-tool/list-split-targets',
            builder: (context, state) => const ListSplitTargetsPage(),
          ),
          GoRoute(
            path: '/epub-tool/font-subset',
            builder: (context, state) => const FontSubsetPage(),
          ),
          GoRoute(
            path: '/metadata',
            name: 'metadata',
            builder: (context, state) => const MetadataPage(),
          ),
          GoRoute(
            path: '/send-email',
            name: 'send_email',
            builder: (context, state) =>
                const SendToKindlePage(tab: KindleTab.email),
          ),
          GoRoute(
            path: '/send-web',
            name: 'send_web',
            builder: (context, state) => const WebSendPage(),
          ),
          GoRoute(
            path: '/tutorial',
            name: 'tutorial',
            builder: (context, state) => const TutorialPage(),
          ),
        ],
      ),
    ],
  );
}
