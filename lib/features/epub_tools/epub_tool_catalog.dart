import 'package:flutter/material.dart';

/// EPUB 工具元数据模型
class EpubToolMeta {
  final String id;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  final String route;

  const EpubToolMeta({
    required this.id,
    required this.label,
    required this.desc,
    required this.icon,
    required this.color,
    required this.route,
  });
}

/// EPUB 工具，按分类分组
class EpubToolCatalog {
  EpubToolCatalog._();

  static const List<
    ({String category, IconData catIcon, List<EpubToolMeta> tools})
  >
  groups = [
    (
      category: '基础工具',
      catIcon: Icons.build_outlined,
      tools: [
        EpubToolMeta(
          id: 'replaceCover',
          label: '替换封面图片',
          desc: '将 EPUB 的封面图片替换为新图片',
          icon: Icons.image_outlined,
          color: Color(0xFFEC4899),
          route: '/epub-tool/replace-cover',
        ),
        EpubToolMeta(
          id: 'reformat',
          label: '重新格式化',
          desc: '规范化 EPUB 内部结构，清理冗余文件',
          icon: Icons.auto_fix_high_outlined,
          color: Color(0xFF8B5CF6),
          route: '/epub-tool/reformat',
        ),
        EpubToolMeta(
          id: 'convertVersion',
          label: '版本转换',
          desc: 'EPUB 2.0 与 3.0 互转',
          icon: Icons.swap_vert_outlined,
          color: Color(0xFF10B981),
          route: '/epub-tool/convert-version',
        ),
        EpubToolMeta(
          id: 'epubToTxt',
          label: 'EPUB 转 TXT',
          desc: '将 EPUB 电子书转换为纯文本',
          icon: Icons.article_outlined,
          color: Color(0xFFF59E0B),
          route: '/epub-tool/epub-to-txt',
        ),
      ],
    ),
    (
      category: '内容处理',
      catIcon: Icons.text_fields,
      tools: [
        EpubToolMeta(
          id: 'adClean',
          label: '广告清理',
          desc: '按正则规则批量清理 EPUB 中的广告内容',
          icon: Icons.cleaning_services_outlined,
          color: Color(0xFFEF4444),
          route: '/epub-tool/ad-clean',
        ),
        EpubToolMeta(
          id: 's2t',
          label: '简体转繁体',
          desc: '将 EPUB 中的简体中文转换为繁体中文',
          icon: Icons.translate,
          color: Color(0xFF3B82F6),
          route: '/epub-tool/s2t',
        ),
        EpubToolMeta(
          id: 't2s',
          label: '繁体转简体',
          desc: '将 EPUB 中的繁体中文转换为简体中文',
          icon: Icons.translate_outlined,
          color: Color(0xFF6366F1),
          route: '/epub-tool/t2s',
        ),
        EpubToolMeta(
          id: 'phonetic',
          label: '拼音标注',
          desc: '为 EPUB 中的中文文本添加拼音标注',
          icon: Icons.record_voice_over_outlined,
          color: Color(0xFF14B8A6),
          route: '/epub-tool/phonetic',
        ),
        EpubToolMeta(
          id: 'comment',
          label: '批注提取',
          desc: '用正则从正文中提取批注转为悬浮脚注',
          icon: Icons.comment_bank_outlined,
          color: Color(0xFFF97316),
          route: '/epub-tool/comment',
        ),
        EpubToolMeta(
          id: 'footnoteToComment',
          label: '脚注转弹窗',
          desc: '将 EPUB 内部脚注链接转换为阅微弹窗注释',
          icon: Icons.question_answer_outlined,
          color: Color(0xFFA855F7),
          route: '/epub-tool/footnote-to-comment',
        ),
        EpubToolMeta(
          id: 'spanToFootnote',
          label: '弹窗转脚注',
          desc: '将阅微弹窗注释转换为 EPUB3 末尾脚注',
          icon: Icons.format_quote_outlined,
          color: Color(0xFF6D28D9),
          route: '/epub-tool/span-to-footnote',
        ),
        EpubToolMeta(
          id: 'yuewei',
          label: '阅微转多看',
          desc: '将阅微格式脚注转为多看标准格式',
          icon: Icons.sync_alt_outlined,
          color: Color(0xFF0D9488),
          route: '/epub-tool/yuewei',
        ),
        EpubToolMeta(
          id: 'zhangyue',
          label: '得到转多看',
          desc: '将得到格式脚注转为多看标准格式',
          icon: Icons.swap_horiz_outlined,
          color: Color(0xFF0891B2),
          route: '/epub-tool/zhangyue',
        ),
      ],
    ),
    (
      category: '图片处理',
      catIcon: Icons.image,
      tools: [
        EpubToolMeta(
          id: 'imgCompress',
          label: '图片压缩',
          desc: '压缩 EPUB 中的图片以减小体积',
          icon: Icons.compress_outlined,
          color: Color(0xFF059669),
          route: '/epub-tool/img-compress',
        ),
        EpubToolMeta(
          id: 'imgToWebp',
          label: '图片转 WebP',
          desc: '将 EPUB 中的图片转换为 WebP 格式',
          icon: Icons.image_outlined,
          color: Color(0xFF7C3AED),
          route: '/epub-tool/img-to-webp',
        ),
        EpubToolMeta(
          id: 'imageWatermark',
          label: '图片水印',
          desc: '向 EPUB 图片写入或读取文本水印',
          icon: Icons.fingerprint_outlined,
          color: Color(0xFF0F766E),
          route: '/epub-tool/image-watermark',
        ),
        EpubToolMeta(
          id: 'webpToImg',
          label: 'WebP 转图片',
          desc: '将 EPUB 中的 WebP 图片转回 JPEG/PNG',
          icon: Icons.image_search_outlined,
          color: Color(0xFFDB2777),
          route: '/epub-tool/webp-to-img',
        ),
        EpubToolMeta(
          id: 'downloadImages',
          label: '下载网络图片',
          desc: '下载 EPUB 中引用的网络图片到本地',
          icon: Icons.download_outlined,
          color: Color(0xFF2563EB),
          route: '/epub-tool/download-images',
        ),
      ],
    ),
    (
      category: '安全加密',
      catIcon: Icons.security,
      tools: [
        EpubToolMeta(
          id: 'encrypt',
          label: '名称混淆加密',
          desc: '混淆 EPUB 文件名使编辑器无法打开修改',
          icon: Icons.enhanced_encryption_outlined,
          color: Color(0xFFDC2626),
          route: '/epub-tool/encrypt',
        ),
        EpubToolMeta(
          id: 'decrypt',
          label: '名称混淆解密',
          desc: '还原被混淆的 EPUB 文件名',
          icon: Icons.no_encryption_outlined,
          color: Color(0xFFEA580C),
          route: '/epub-tool/decrypt',
        ),
        EpubToolMeta(
          id: 'encryptFont',
          label: '字体加密',
          desc: '字形混淆加密实现防复制保护',
          icon: Icons.security_outlined,
          color: Color(0xFFBE123C),
          route: '/epub-tool/encrypt-font',
        ),
      ],
    ),
    (
      category: '合并拆分',
      catIcon: Icons.call_split,
      tools: [
        EpubToolMeta(
          id: 'merge',
          label: '合并 EPUB',
          desc: '将多个 EPUB 合并为一个',
          icon: Icons.call_merge_outlined,
          color: Color(0xFF16A34A),
          route: '/epub-tool/merge',
        ),
        EpubToolMeta(
          id: 'split',
          label: '拆分 EPUB',
          desc: '按章节拆分点将 EPUB 拆分为多个',
          icon: Icons.call_split,
          color: Color(0xFFCA8A04),
          route: '/epub-tool/split',
        ),
        EpubToolMeta(
          id: 'listSplitTargets',
          label: '列出拆分目标',
          desc: '扫描 EPUB 目录结构供选择拆分点',
          icon: Icons.list_alt_outlined,
          color: Color(0xFF65A30D),
          route: '/epub-tool/list-split-targets',
        ),
      ],
    ),
    (
      category: '字体处理',
      catIcon: Icons.font_download,
      tools: [
        EpubToolMeta(
          id: 'fontSubset',
          label: '字体子集化',
          desc: '子集化 EPUB 中的字体文件以减小体积',
          icon: Icons.font_download_outlined,
          color: Color(0xFF7C3AED),
          route: '/epub-tool/font-subset',
        ),
      ],
    ),
  ];

  /// 按 id 查找工具元数据
  static EpubToolMeta? findById(String id) {
    for (final g in groups) {
      for (final t in g.tools) {
        if (t.id == id) return t;
      }
    }
    return null;
  }
}
