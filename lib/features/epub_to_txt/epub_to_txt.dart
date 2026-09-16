import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;

/// EPUB 转 TXT 操作
///
/// 将 EPUB 电子书转换为纯文本格式：遍历所有章节，去除 HTML 标签，
/// 提取正文文字，按章节顺序拼接，章节之间以空行分隔。
class EpubToTxtOperation {
  EpubToTxtOperation._();

  /// 将 EPUB 转为纯文本
  ///
  /// 参数 [epubPath] EPUB 文件路径
  /// 参数 [keepImages] 是否保留图片到输出目录（暂不实现，预留参数）
  /// 返回转换后的纯文本字符串
  static Future<String> execute({
    required String epubPath,
    String? outputPath,
    bool keepImages = false,
  }) async {
    // 直接用 archive+OPF 解析，避免 epubx 库对中文路径的 URI 解码 bug
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 定位 OPF
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('EPUB 结构异常：找不到 META-INF/container.xml');
    }
    final containerXml = utf8.decode(containerFile.content as List<int>);
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
    ).firstMatch(containerXml);
    if (opfPathMatch == null) {
      throw Exception('EPUB 结构异常：container.xml 中未找到 OPF 路径');
    }
    final opfPath = opfPathMatch.group(1)!;
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件');
    }
    final opfContent = utf8.decode(opfFile.content as List<int>);

    // 解析 manifest：id → href，mediaType
    final manifestItems = <String, _HtmlManifestItem>{};
    try {
      final doc = xml.XmlDocument.parse(opfContent);
      for (final item in doc.findAllElements('item', namespace: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (id.isEmpty || href.isEmpty) continue;
        manifestItems[id] = _HtmlManifestItem(href: href, mediaType: mediaType);
      }
    } catch (_) {
      // 解析失败继续
    }

    // 解析 spine 顺序
    final spineOrder = <String>[];
    try {
      final doc = xml.XmlDocument.parse(opfContent);
      for (final itemref in doc.findAllElements('itemref', namespace: '*')) {
        final idref = itemref.getAttribute('idref') ?? '';
        if (idref.isNotEmpty) spineOrder.add(idref);
      }
    } catch (_) {}

    final buffer = StringBuffer();
    var foundAnyChapter = false;

    // 按 spine 顺序输出
    for (final id in spineOrder) {
      final item = manifestItems[id];
      if (item == null) continue;
      final lowerHref = item.href.toLowerCase();
      if (!lowerHref.endsWith('.xhtml') &&
          !lowerHref.endsWith('.html') &&
          !lowerHref.endsWith('.htm')) {
        continue;
      }
      // 解析 href 中的 URL 片段、查询参数、相对路径
      // 并尝试 URL 解码（EPUB 规范要求 manifest href 是 URI 编码的）
      ArchiveFile? file;
      try {
        // 尝试 URL 解码后的路径
        final decoded = _resolvePath(opfDir, Uri.decodeFull(item.href));
        file = archive.findFile(decoded);
        if (file == null) {
          // 退化：尝试原始路径
          final raw = _resolvePath(opfDir, item.href);
          file = archive.findFile(raw);
        }
      } catch (_) {
        // 解码错误时用原始路径
        final raw = _resolvePath(opfDir, item.href);
        file = archive.findFile(raw);
      }
      if (file == null) continue;
      foundAnyChapter = true;
      final html = utf8.decode(file.content as List<int>);
      final text = _htmlToText(html);
      if (text.isNotEmpty) {
        buffer.writeln(text);
        buffer.writeln();
      }
    }

    // 若 spine 为空则降级为所有 HTML 文件
    if (buffer.isEmpty || !foundAnyChapter) {
      for (final f in archive.files) {
        if (f.name.isEmpty) continue;
        final lower = f.name.toLowerCase();
        if (lower.endsWith('.html') ||
            lower.endsWith('.xhtml') ||
            lower.endsWith('.htm')) {
          final html = utf8.decode(f.content as List<int>);
          final text = _htmlToText(html);
          if (text.isNotEmpty) {
            buffer.writeln(text);
            buffer.writeln();
          }
        }
      }
    }

    final text = buffer.toString().trim();
    if (outputPath != null && outputPath.trim().isNotEmpty) {
      final normalized = _normalizeTxtOutputPath(outputPath);
      await File(normalized).writeAsString(text);
    }
    return text;
  }

  /// 规范化 TXT 输出路径，确保扩展名为单一 .txt。
  ///
  /// 修复历史 bug：部分平台保存对话框或旧逻辑把输出写成了
  /// `xxx.txt.epub` 或重复 `_output`。这里统一处理：
  /// 循环剥离所有尾缀 `.epub`/`.txt`（大小写不敏感），再单一追加 `.txt`。
  static String _normalizeTxtOutputPath(String path) {
    var result = path.trim();
    // 循环剥离尾缀，避免 .txt.epub / .epub.txt / 重复 .txt 等
    while (true) {
      final lower = result.toLowerCase();
      if (lower.endsWith('.epub')) {
        result = result.substring(0, result.length - '.epub'.length);
        continue;
      }
      if (lower.endsWith('.txt')) {
        // 暂剥离，循环外统一加回单一 .txt
        result = result.substring(0, result.length - '.txt'.length);
        continue;
      }
      break;
    }
    // 去除可能残留的点或空格
    result = result.replaceAll(RegExp(r'[.\s]+$'), '');
    return '$result.txt';
  }

  /// 将 HTML 内容转换为纯文本
  ///
  /// 去除所有 HTML 标签，将块级元素转换为换行，解码常见 HTML 实体。
  ///
  /// 参数 [html] HTML 字符串
  /// 返回提取的纯文本
  static String _htmlToText(String html) {
    var text = html;

    // 将块级标签的闭合标签转换为换行符，保留段落结构
    text = text.replaceAll(
      RegExp(
        r'</(?:p|div|h[1-6]|li|tr|blockquote|section|article|header|footer)>',
        caseSensitive: false,
      ),
      '\n',
    );
    // 将 <br> 标签转换为换行
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // 移除 <script> 和 <style> 标签及其内容（避免脚本/样式混入文本）
    text = text.replaceAll(
      RegExp(
        r'<(?:script|style)[^>]*>[\s\S]*?</(?:script|style)>',
        caseSensitive: false,
      ),
      '',
    );

    // 移除所有剩余 HTML 标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // Decode once, including decimal/hex references used by real XHTML books.
    text = text.replaceAllMapped(
      RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|nbsp|lt|gt|quot|apos|amp);'),
      (match) {
        final entity = match.group(1)!;
        const named = {
          'nbsp': ' ',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'amp': '&',
        };
        if (!entity.startsWith('#')) return named[entity]!;
        final hex = entity.length > 1 && entity[1].toLowerCase() == 'x';
        final code = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (code == null ||
            code <= 0 ||
            code > 0x10ffff ||
            (code >= 0xd800 && code <= 0xdfff)) {
          return match.group(0)!;
        }
        return code == 160 ? ' ' : String.fromCharCode(code);
      },
    );

    // 合并连续空格为单个空格（保留换行）
    text = text.replaceAll(RegExp(r'[^\S\n]+'), ' ');
    // 合并 3 个及以上连续换行为 2 个
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }
}

/// Manifest item 简化版
class _HtmlManifestItem {
  final String href;
  final String mediaType;
  _HtmlManifestItem({required this.href, required this.mediaType});
}

/// 将相对于 OPF 目录的 href 解析为 ZIP 内完整路径
///
/// 处理 URL 片段（#anchor）、查询参数、相对路径（./ 和 ../）。
///
/// 参数 [opfDir] OPF 所在目录（以 / 结尾）
/// 参数 [href] 相对路径
/// 返回 ZIP 内的完整文件路径
String _resolvePath(String opfDir, String href) {
  // 去除 URL 片段和查询参数（如 chapter.xhtml#section1）
  final pathPart = href.split(RegExp(r'[?#]')).first;
  final combined = opfDir + pathPart;
  // 逐段处理，解析 ./ 和 ../ 相对路径片段
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
