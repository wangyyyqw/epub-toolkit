import 'encrypt_decrypt_base.dart';

/// EPUB 解密操作
///
/// 对已名称混淆加密的 EPUB 进行解密：用 manifest item 的原始 id
/// 还原可读文件名，重写所有引用链接。
///
/// 若 id 含非法字符，用 MD5 hex 摘要兜底。
/// 检测到掌阅 DRM 时返回 'zhangyue_drm'，不支持解密。
class DecryptOperation {
  DecryptOperation._();

  /// 执行解密
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  ///
  /// 返回处理结果摘要字符串。
  /// 若未加密返回 'not_encrypted'。
  /// 若检测到掌阅 DRM 返回 'zhangyue_drm'。
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
  }) {
    return EncryptDecryptBase.process(
      epubPath: epubPath,
      outputPath: outputPath,
      mode: 'decrypt',
    );
  }
}
