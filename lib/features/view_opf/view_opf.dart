import 'epub_service.dart';
import 'package:xml/xml.dart';

/// 查看 EPUB 的 OPF 元数据操作
///
/// 读取 EPUB 的 OPF（Open Packaging Format）文件内容，
/// 并格式化为带缩进的易读 XML 字符串返回，便于用户查看书籍元数据。
class ViewOpfOperation {
  ViewOpfOperation._();

  /// 读取 EPUB 的 OPF 文件内容并返回格式化的 XML 字符串
  ///
  /// 参数 [path] EPUB 文件路径
  /// 返回格式化后的 OPF XML 字符串；若格式化失败则返回原始内容
  static Future<String> execute(String path) async {
    // 通过 EpubService 读取 OPF 原始 XML 内容
    final opfContent = await EpubService.readOpfContent(path);

    try {
      // 使用 xml 包解析 XML 文档并格式化输出（带缩进）
      final document = XmlDocument.parse(opfContent);
      return document.toXmlString(pretty: true, indent: '  ');
    } catch (_) {
      // XML 解析或格式化失败时，返回原始内容，避免阻断查看流程
      return opfContent;
    }
  }
}
