import 'epub_service.dart';

/// EPUB 广告清理操作
///
/// 根据用户提供的正则表达式规则，批量清理 EPUB 中所有 HTML 文件内的广告内容，
/// 并将清理后的 EPUB 保存到指定路径。
class AdCleanOperation {
  AdCleanOperation._();

  /// 按正则规则清理 EPUB 中的广告
  ///
  /// 参数 [epubPath] 原始 EPUB 文件路径
  /// 参数 [outputPath] 输出 EPUB 文件路径
  /// 参数 [patterns] 规则字符串，格式为 'pattern1|||replacement1|||pattern2|||replacement2'
  ///   奇数位（第 1、3、5... 段）为正则表达式，偶数位（第 2、4、6... 段）为替换文本
  static Future<void> execute({
    required String epubPath,
    required String outputPath,
    required String patterns,
  }) async {
    // 解析规则字符串为正则-替换对列表
    final rules = _parsePatterns(patterns);
    if (rules.isEmpty) {
      throw ArgumentError('patterns 格式无效，未解析到有效的清理规则');
    }

    // 读取 EPUB 中所有 HTML 文件（中文安全版本，避开 epubx 的 URI 解码 bug）
    final htmlFiles = await EpubService.readAllHtmlSafe(epubPath);

    // 获取 OPF 所在目录，用于将 HTML 文件名解析为 ZIP 内完整路径
    final opfDir = await _getOpfDirectory(epubPath);

    // 对每个 HTML 文件依次应用所有正则替换规则
    final modifications = <String, String>{};
    for (final entry in htmlFiles) {
      var content = entry.value;
      for (final rule in rules) {
        content = content.replaceAll(rule.pattern, rule.replacement);
      }
      // 将相对文件名解析为 ZIP 内完整路径，确保 modifyAndSave 能正确定位文件
      final fullPath = _resolvePath(opfDir, entry.key);
      modifications[fullPath] = content;
    }

    // 保存修改后的 EPUB
    await EpubService.modifyAndSave(
      epubPath: epubPath,
      modifications: modifications,
      outputPath: outputPath,
    );
  }

  /// 解析 patterns 字符串为正则-替换规则列表
  ///
  /// 参数 [patterns] 用 ||| 分隔的规则字符串
  /// 返回解析后的规则列表；正则编译失败时抛出 FormatException
  static List<_ReplaceRule> _parsePatterns(String patterns) {
    final parts = patterns.split('|||');
    final rules = <_ReplaceRule>[];

    // 每两个相邻段组成一条规则：第一段为正则，第二段为替换文本
    for (var i = 0; i + 1 < parts.length; i += 2) {
      final patternStr = parts[i];
      final replacement = parts[i + 1];
      if (patternStr.isEmpty) continue;
      try {
        rules.add(_ReplaceRule(RegExp(patternStr), replacement));
      } catch (e) {
        // 正则表达式语法错误时抛出异常，提示用户修正
        throw FormatException('正则表达式无效 "$patternStr": $e');
      }
    }
    return rules;
  }

  /// 获取 EPUB 中 OPF 文件所在的目录路径
  ///
  /// 通过读取 container.xml 确定 OPF 的 full-path，再提取其目录部分。
  ///
  /// 参数 [epubPath] EPUB 文件路径
  /// 返回 OPF 所在目录（以 / 结尾），若 OPF 在根目录则返回空字符串
  static Future<String> _getOpfDirectory(String epubPath) async {
    final containerXml = await EpubService.readFileInEpub(
      epubPath,
      'META-INF/container.xml',
    );
    final match = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (match == null) {
      throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
    }
    final opfPath = match.group(1)!;
    // 提取 OPF 文件所在目录（如 OEBPS/content.opf → OEBPS/）
    final lastSlash = opfPath.lastIndexOf('/');
    return lastSlash >= 0 ? opfPath.substring(0, lastSlash + 1) : '';
  }

  /// 将相对于 OPF 目录的文件名解析为 ZIP 内完整路径
  ///
  /// 参数 [opfDir] OPF 所在目录
  /// 参数 [href] manifest 中的相对 href
  /// 返回 ZIP 内的完整文件路径
  static String _resolvePath(String opfDir, String href) {
    // 若 href 已是绝对路径（含 OPF 目录前缀），则直接使用
    if (opfDir.isNotEmpty && href.startsWith(opfDir)) {
      href = href.substring(opfDir.length);
    }
    // 处理可能的 URL 编码（如 %20 → 空格）
    final decoded = Uri.decodeFull(href);
    final combined = opfDir + decoded;
    // 处理 ./ 和 ../ 等相对路径片段
    final segments = <String>[];
    for (final part in combined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments.join('/');
  }
}

/// 正则替换规则（内部使用）
class _ReplaceRule {
  _ReplaceRule(this.pattern, this.replacement);

  /// 要匹配的正则表达式
  final RegExp pattern;

  /// 匹配内容的替换文本
  final String replacement;
}
