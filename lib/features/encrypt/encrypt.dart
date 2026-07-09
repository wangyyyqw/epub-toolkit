import 'encrypt_decrypt_base.dart';

/// EPUB 加密操作
///
/// 对 EPUB 进行名称混淆加密：将 manifest item 的文件名
/// 通过 MD5 哈希转换为含 `*` 和 `:` 的混淆字符串，
/// 使 Sigil 等编辑器无法打开修改。HTML/字体/图片内容本身不变，
/// 仅重写文件名和引用链接。
///
/// 加密检测：manifest href 中含 `*` 或 `:` 等非法字符即为已加密。
class EncryptOperation {
  EncryptOperation._();

  /// 执行加密
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串。
  /// 若已加密返回 'encrypted'。
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) {
    return EncryptDecryptBase.process(
      epubPath: epubPath,
      outputPath: outputPath,
      mode: 'encrypt',
    );
  }
}
