import 'epub_reformatter.dart';

/// EPUB 重新格式化操作
///
/// **完全对齐原 Wail (Python) 项目 reformat_epub.py 的功能集**：
/// 1. 将 EPUB 内部结构规范化到 Sigil 规范目录（OEBPS/Text、Styles、Images、Fonts、Audio、Video、Misc）
/// 2. 将没有列入 manifest 的有效文件自动列入 manifest
/// 3. 自动清除 manifest 中重复 ID / 无效 ID 的项
/// 4. 自动检查并提示 spine 引用无效 ID 的项
/// 5. 自动检查 manifest 中 xhtml 类型不被 spine 引用的情况
/// 6. 自动检测并纠正文件名大小写不一致导致的链接错误
/// 7. 自动检查找不到对应文件的链接
/// 8. 自动补齐 xhtml 缺少的 <?xml> 声明和 XHTML 1.1 DOCTYPE
/// 9. 自动重写 xhtml 中的 <a href>、<img src>、<video poster>、<input placeholder>
///    以及 CSS 中的 url()、@import，指向规范化后的新路径
/// 10. 修正 container.xml 的 media-type 为 application/oebps-package+xml
/// 11. mimetype 强制 STORED 且为 ZIP 第一个文件（沿用 EpubPacker.pack）
///
/// 调用方通过 [execute] 触发，返回日志字符串。
class ReformatOperation {
  ReformatOperation._();

  /// 规范化 EPUB 结构
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// 返回日志字符串（含操作过程、错误提示）
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) async {
    // 跳过已重构的文件（与 wail 版 run() 行为一致：避免重复处理）
    if (epubPath.toLowerCase().endsWith('_reformat.epub')) {
      return '警告: 该文件已经重排（_reformat 后缀），无需再次处理！';
    }

    final reformatter = EpubReformatter(
      epubPath: epubPath,
      outputPath: outputPath,
    );
    await reformatter.execute();
    // 末尾追加 OPF + 链接问题的总览
    if (reformatter.opfErrors.isEmpty && reformatter.linkErrors.isEmpty) {
      reformatter.logLines.add('重构成功，无 OPF 结构或链接问题');
    } else {
      reformatter.logLines.add('重构完成（含修复与提示，请查看上方日志）');
    }
    return reformatter.logLines.join('\n');
  }
}
