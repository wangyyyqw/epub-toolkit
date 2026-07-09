import 'chinese_convert_base.dart';

/// 繁体转简体操作
///
/// 将 EPUB 中的繁体中文内容转换为简体中文。
/// 转换范围包括 HTML/XHTML 正文、NCX 目录、OPF 元数据。
class T2sOperation {
  T2sOperation._();

  /// 执行繁转简
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) {
    return ChineseConvertBase.execute(
      epubPath: epubPath,
      outputPath: outputPath,
      mode: 't2s',
    );
  }
}
