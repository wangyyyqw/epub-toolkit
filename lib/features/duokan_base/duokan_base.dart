import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

/// HTML 特殊字符转义
///
/// 将 &、<、>、" 转换为 HTML 实体，用于脚注内容的安全插入。
String escapeHtml(String? text) {
  if (text == null) return '';
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// 为 `<html>` 标签注入 xmlns:epub 命名空间
///
/// 若已有 xmlns:epub 声明则原样返回；否则在 xmlns 声明后或 `<html>` 标签末尾插入。
String addEpubNamespace(String htmlContent) {
  final epubNsPattern = RegExp(
    r"""xmlns:epub\s*=\s*["']http://www\.idpf\.org/2007/ops["']""",
  );
  if (epubNsPattern.hasMatch(htmlContent)) return htmlContent;

  final pattern = RegExp(
    r'(<html\b[^>]*)(>)',
    caseSensitive: false,
    dotAll: true,
  );
  return htmlContent.replaceFirstMapped(pattern, (match) {
    final tagStart = match.group(1)!;
    final tagEnd = match.group(2)!;
    if (epubNsPattern.hasMatch(tagStart)) return match.group(0)!;

    final xmlnsMatch = RegExp(
      r"""xmlns\s*=\s*["']http://www\.w3\.org/1999/xhtml["']""",
    ).firstMatch(tagStart);

    if (xmlnsMatch != null) {
      final endPos = xmlnsMatch.end;
      return '${tagStart.substring(0, endPos)}'
          ' xmlns:epub="http://www.idpf.org/2007/ops"'
          '${tagStart.substring(endPos)}$tagEnd';
    }
    return '$tagStart xmlns:epub="http://www.idpf.org/2007/ops"$tagEnd';
  });
}

/// 脚注信息
class FootnoteInfo {
  /// 脚注 ID（如 note1）
  final String id;

  /// 引用锚点 ID（如 note_ref1）
  final String refId;

  /// 脚注内容（已 HTML 转义）
  final String content;

  FootnoteInfo({required this.id, required this.refId, required this.content});
}

/// 构建集中的多看脚注区域 HTML
///
/// 将脚注列表按 id 去重、按数字排序后生成 <aside> 区块。
String buildFootnoteSection(List<FootnoteInfo> footnotes) {
  if (footnotes.isEmpty) return '';

  // 按 id 去重
  final seen = <String>{};
  final unique = <FootnoteInfo>[];
  for (final note in footnotes) {
    if (!seen.contains(note.id)) {
      seen.add(note.id);
      unique.add(note);
    }
  }

  // 按数字后缀排序
  unique.sort((a, b) {
    final numsA = RegExp(
      r'(\d+)',
    ).allMatches(a.id).map((m) => int.parse(m[1]!)).toList();
    final numsB = RegExp(
      r'(\d+)',
    ).allMatches(b.id).map((m) => int.parse(m[1]!)).toList();
    if (numsA.isEmpty) return numsB.isEmpty ? 0 : 1;
    if (numsB.isEmpty) return -1;
    for (var i = 0; i < numsA.length && i < numsB.length; i++) {
      final cmp = numsA[i].compareTo(numsB[i]);
      if (cmp != 0) return cmp;
    }
    return numsA.length.compareTo(numsB.length);
  });

  final parts = StringBuffer('\n\n');
  for (final note in unique) {
    parts.writeln('  <aside epub:type="footnote" id="${note.id}">');
    parts.writeln(
      '   <ol class="duokan-footnote-content" style="list-style:none">',
    );
    parts.writeln('   <li class="duokan-footnote-item" id="${note.id}">');
    parts.writeln('   <p><a href="#${note.refId}">${note.content}</a></p>');
    parts.writeln('   </li>');
    parts.writeln('   </ol>');
    parts.writeln('   </aside>');
  }
  return parts.toString();
}

/// 在 `</body>` 标签前插入脚注区域
///
/// 若无 `</body>` 标签则追加到末尾。
String injectFootnotesBeforeBodyClose(String text, String footnoteSection) {
  if (footnoteSection.isEmpty) return text;
  final idx = text.lastIndexOf('</body>');
  if (idx >= 0) {
    return '${text.substring(0, idx)}$footnoteSection</body>${text.substring(idx + 7)}';
  }
  return '$text$footnoteSection';
}

/// 多看脚注转换基类
///
/// 阅微→多看和掌阅→多看共用的 EPUB 处理基类。
/// 提供 note.png 注入、图片目录检测、OPF 处理、文件遍历等共享功能。
/// 子类需实现 [processHtml] 方法完成特定格式的脚注转换。
abstract class DuokanConverterBase {
  /// 输入 EPUB 文件路径
  final String epubPath;

  /// 输出 EPUB 文件路径
  final String outputPath;

  /// note.png 二进制数据（从 Flutter assets 加载，为 null 则跳过注入）
  final Uint8List? notePngBytes;

  /// 输入 EPUB 是否已包含 note.png
  bool _hasNotePng = false;

  /// 是否已注入 note.png 到输出 EPUB
  bool _notePngInjected = false;

  /// 检测到的图片目录名（如 Images、images、image）
  String _imagesDir = 'Images';

  /// 图片目录名（子类可读取）
  String get imagesDir => _imagesDir;

  DuokanConverterBase({
    required this.epubPath,
    required this.outputPath,
    this.notePngBytes,
  });

  /// 子类实现：处理 HTML/XHTML 文件中的脚注转换
  ///
  /// [filename] 文件名（用于日志）
  /// [content] HTML 文本内容
  /// 返回处理后的 HTML 文本
  String processHtml(String filename, String content);

  /// 执行转换
  ///
  /// 返回处理结果日志字符串（按行分隔）
  Future<String> process() async {
    final log = StringBuffer();
    log.writeln('开始多看脚注转换...');

    try {
      final inputBytes = await File(epubPath).readAsBytes();
      final inputArchive = ZipDecoder().decodeBytes(inputBytes);
      final outputArchive = Archive();

      _hasNotePng = _checkNotePngExists(inputArchive);
      _detectImagesDir(inputArchive);
      log.writeln('图片目录: $_imagesDir');

      final opfItems = <_OpfItem>[];
      final writtenFiles = <String>{};

      for (final file in inputArchive.files) {
        if (file.name.isEmpty) continue;
        if (writtenFiles.contains(file.name)) {
          log.writeln('  跳过重复文件: ${file.name}');
          continue;
        }

        final lowerName = file.name.toLowerCase();
        final rawBytes = _readFileBytes(file);

        if (file.name == 'mimetype') {
          // mimetype 不压缩
          final mf = ArchiveFile('mimetype', rawBytes.length, rawBytes);
          mf.compress = false;
          outputArchive.addFile(mf);
          writtenFiles.add(file.name);
        } else if (lowerName.endsWith('.opf')) {
          opfItems.add(_OpfItem(file.name, utf8.decode(rawBytes)));
          writtenFiles.add(file.name);
        } else if (lowerName.endsWith('.html') ||
            lowerName.endsWith('.xhtml') ||
            lowerName.endsWith('.htm')) {
          final content = utf8.decode(rawBytes);
          final newContent = processHtml(file.name, content);
          final bytes = Uint8List.fromList(utf8.encode(newContent));
          outputArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
          writtenFiles.add(file.name);
        } else {
          outputArchive.addFile(
            ArchiveFile(file.name, rawBytes.length, rawBytes),
          );
          writtenFiles.add(file.name);
        }
      }

      // 注入 note.png
      final noteBytes = notePngBytes;
      if (_notePngInjected && noteBytes != null) {
        final notePngPath = '$_imagesDir/note.png';
        if (!outputArchive.files.any((f) => f.name == notePngPath)) {
          outputArchive.addFile(
            ArchiveFile(notePngPath, noteBytes.length, noteBytes),
          );
          log.writeln('注入 note.png 到 $notePngPath');
        }
      }

      // 处理 OPF 文件
      for (final opfItem in opfItems) {
        final newContent = _processOpf(opfItem.filename, opfItem.content);
        final bytes = Uint8List.fromList(utf8.encode(newContent));
        outputArchive.addFile(
          ArchiveFile(opfItem.filename, bytes.length, bytes),
        );
      }

      // 保存
      await EpubPacker.pack(archive: outputArchive, outputPath: outputPath);

      log.writeln('转换完成: $outputPath');
      return log.toString();
    } catch (e) {
      log.writeln('错误: 处理EPUB失败: $e');
      return log.toString();
    }
  }

  /// 检查 EPUB 中是否已存在 note.png
  bool _checkNotePngExists(Archive archive) {
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith('note.png')) return true;
    }
    return false;
  }

  /// 标记需要注入 note.png（子类在发现脚注时调用）
  void injectNotePng() {
    if (!_notePngInjected && !_hasNotePng) {
      _notePngInjected = true;
    }
  }

  /// 检测 EPUB 中的图片目录名
  void _detectImagesDir(Archive archive) {
    for (final file in archive.files) {
      final lower = file.name.toLowerCase();
      if (lower.contains('/images/') || lower.startsWith('images/')) {
        final idx = lower.indexOf('images/');
        _imagesDir = file.name.substring(0, idx + 'images'.length);
        return;
      } else if (lower.contains('/image/') || lower.startsWith('image/')) {
        final idx = lower.indexOf('image/');
        _imagesDir = file.name.substring(0, idx + 'image'.length);
        return;
      }
    }
  }

  /// 处理 OPF 文件：去重 manifest 项，追加 note.png 声明
  String _processOpf(String filename, String content) {
    try {
      final document = xml.XmlDocument.parse(content);
      final manifests = document.findAllElements('manifest');
      if (manifests.isEmpty) return content;

      final manifest = manifests.first;

      // 去重 manifest 项
      final seenHrefs = <String>{};
      final items = manifest.findElements('item').toList();
      for (final item in items) {
        final href = item.getAttribute('href');
        if (href != null) {
          if (seenHrefs.contains(href)) {
            item.parent?.children.remove(item);
          } else {
            seenHrefs.add(href);
          }
        }
      }

      // 若已注入 note.png，追加 manifest 声明
      if (_notePngInjected) {
        final hasNotePng = manifest
            .findElements('item')
            .any(
              (item) => (item.getAttribute('href') ?? '').endsWith('note.png'),
            );

        if (!hasNotePng) {
          final notePngFull = '$_imagesDir/note.png';
          // 计算 OPF 相对路径
          final opfDir = p.dirname(filename);
          final relHref = opfDir == '.'
              ? notePngFull
              : p.posix.relative(notePngFull, from: opfDir);

          final newItem = xml.XmlElement(xml.XmlName('item'), [
            xml.XmlAttribute(xml.XmlName('id'), 'note-png'),
            xml.XmlAttribute(xml.XmlName('href'), relHref),
            xml.XmlAttribute(xml.XmlName('media-type'), 'image/png'),
          ], []);
          manifest.children.add(newItem);
        }
      }

      return document.toXmlString();
    } catch (e) {
      return content;
    }
  }

  /// 读取 ArchiveFile 的二进制内容
  Uint8List _readFileBytes(ArchiveFile file) {
    return Uint8List.fromList(file.content as List<int>);
  }
}

/// OPF 文件缓存项
class _OpfItem {
  final String filename;
  final String content;
  _OpfItem(this.filename, this.content);
}
