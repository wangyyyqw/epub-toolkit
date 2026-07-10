import 'package:path/path.dart' as p;

/// TXT 转 EPUB 的书名和输出文件名规则。
class Txt2EpubNaming {
  Txt2EpubNaming._();

  /// 元数据书名为空时使用原 TXT 文件名。
  static String resolveTitle({
    required String title,
    required String inputPath,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isNotEmpty) return normalizedTitle;

    final inputName = p.basenameWithoutExtension(inputPath).trim();
    return inputName.isEmpty ? '未命名' : inputName;
  }

  /// 生成 EPUB 文件名：
  /// - 有书名和作者：书名-作者.epub
  /// - 只有书名：书名.epub
  /// - 书名和作者都为空：原 TXT 文件名.epub
  /// - 只有作者：原 TXT 文件名-作者.epub
  static String buildFilename({
    required String title,
    required String author,
    required String inputPath,
  }) {
    final safeTitle = _sanitizeFilenamePart(
      resolveTitle(title: title, inputPath: inputPath),
    );
    final safeAuthor = _sanitizeFilenamePart(author);
    final basename = safeAuthor.isEmpty ? safeTitle : '$safeTitle-$safeAuthor';
    return '${basename.isEmpty ? '未命名' : basename}.epub';
  }

  /// 替换 Windows/macOS 文件名中不可使用的字符，同时保留中文标点。
  static String _sanitizeFilenamePart(String value) {
    var result = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    result = result.replaceFirst(RegExp(r'[. ]+$'), '');
    return result;
  }
}
