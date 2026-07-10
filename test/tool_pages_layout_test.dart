import 'package:epub_gadget/core/theme.dart';
import 'package:epub_gadget/features/epub_tools/tools/ad_clean_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/comment_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/convert_version_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/decrypt_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/download_images_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/encrypt_font_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/encrypt_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/epub_to_txt_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/font_subset_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/footnote_to_comment_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/img_compress_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/img_to_webp_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/list_split_targets_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/merge_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/phonetic_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/reformat_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/replace_cover_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/s2t_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/span_to_footnote_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/split_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/t2s_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/webp_to_img_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/yuewei_page.dart';
import 'package:epub_gadget/features/epub_tools/tools/zhangyue_page.dart';
import 'package:epub_gadget/features/metadata/metadata_page.dart';
import 'package:epub_gadget/features/send_to_kindle/send_to_kindle_page.dart';
import 'package:epub_gadget/shared/providers/toast_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final pages = <(String, Widget)>[
    ('替换封面', const ReplaceCoverPage()),
    ('格式重构', const ReformatPage()),
    ('版本转换', const ConvertVersionPage()),
    ('EPUB 转 TXT', const EpubToTxtPage()),
    ('广告清理', const AdCleanPage()),
    ('简体转繁体', const S2tPage()),
    ('繁体转简体', const T2sPage()),
    ('拼音标注', const PhoneticPage()),
    ('批注处理', const CommentPage()),
    ('脚注转批注', const FootnoteToCommentPage()),
    ('Span 转脚注', const SpanToFootnotePage()),
    ('阅微转多看', const YueweiPage()),
    ('得到转多看', const ZhangyuePage()),
    ('图片压缩', const ImgCompressPage()),
    ('图片转 WebP', const ImgToWebpPage()),
    ('WebP 转图片', const WebpToImgPage()),
    ('下载网络图片', const DownloadImagesPage()),
    ('内容加密', const EncryptPage()),
    ('内容解密', const DecryptPage()),
    ('字体加密', const EncryptFontPage()),
    ('合并 EPUB', const MergePage()),
    ('拆分 EPUB', const SplitPage()),
    ('列出拆分目标', const ListSplitTargetsPage()),
    ('字体子集化', const FontSubsetPage()),
    ('元数据编辑', const MetadataPage()),
    ('Kindle 邮箱推送', const SendToKindlePage(tab: KindleTab.email)),
  ];

  testWidgets('所有功能页在窄窗口下均可构建且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final (name, page) in pages) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ToastProvider(),
          child: MaterialApp(theme: AppTheme.dark, home: page),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$name 页面发生布局异常');
    }
  });
}
