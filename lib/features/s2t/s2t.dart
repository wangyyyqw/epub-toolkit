import 'chinese_convert_base.dart';

/// 简体转繁体操作
///
/// 将 EPUB 中的简体中文内容转换为繁体中文。
/// 转换范围包括 HTML/XHTML 正文、NCX 目录、OPF 元数据。
class S2tOperation {
  S2tOperation._();

  /// 执行简转繁
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
      mode: 's2t',
    );
  }
}
