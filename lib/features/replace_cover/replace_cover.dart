import 'epub_service.dart';

/// 替换 EPUB 封面图片操作
///
/// 将 EPUB 的封面图片替换为用户指定的新图片，
/// 并将修改后的 EPUB 输出到指定路径。
class ReplaceCoverOperation {
  ReplaceCoverOperation._();

  /// 替换 EPUB 封面图片
  ///
  /// 参数 [epubPath] 原始 EPUB 文件路径
  /// 参数 [coverPath] 新封面图片的文件路径
  /// 参数 [outputPath] 输出 EPUB 文件路径
  static Future<void> execute({
    required String epubPath,
    required String coverPath,
    required String outputPath,
  }) async {
    // 直接委托 EpubService 完成封面替换
    await EpubService.replaceCover(
      epubPath: epubPath,
      coverPath: coverPath,
      outputPath: outputPath,
    );
  }
}
