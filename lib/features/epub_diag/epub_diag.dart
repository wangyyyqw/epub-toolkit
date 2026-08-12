import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

/// EPUB 诊断操作
///
/// 检查 EPUB 的结构完整性：
/// 1. 容器结构（META-INF/container.xml、OPF 路径）
/// 2. OPF 元数据完整性
/// 3. manifest 中每个文件是否真实存在于包内
/// 4. spine 引用的 id 是否都存在于 manifest
/// 5. 正文 HTML 内部的 href/src 引用是否有效（相对路径解析）
///
/// 输出文本诊断报告，行首标注 [OK] / [WARN] / [ERROR]。
class EpubDiagnoseOperation {
  EpubDiagnoseOperation._();

  /// 执行诊断，返回多行诊断报告
  static Future<String> execute(String epubPath) async {
    final lines = <String>[];
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    lines.add('EPUB 诊断：${p.basename(epubPath)}');
    lines.add('包内文件总数：${archive.files.length}');
    lines.add('');

    // ---- 1. 容器结构 ----
    lines.add('── 容器结构 ──');
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      lines.add('[ERROR] 缺少 META-INF/container.xml');
    } else {
      lines.add('[OK] 找到 META-INF/container.xml');
      final containerXml = utf8.decode(containerFile.content as List<int>);
      final opfPathMatch = RegExp(r'full-path="([^"]+)"').firstMatch(
        containerXml,
      );
      if (opfPathMatch == null) {
        lines.add('[ERROR] container.xml 中未找到 OPF 路径');
      } else {
        final opfPath = opfPathMatch.group(1)!;
        if (archive.findFile(opfPath) == null) {
          lines.add('[ERROR] container.xml 指向的 OPF 不存在：$opfPath');
        } else {
          lines.add('[OK] OPF：$opfPath');
        }
      }
    }
    lines.add('');

    // ---- 2-4. OPF / manifest / spine ----
    final opfPath = _findOpfPath(archive);
    if (opfPath == null) {
      lines.add('[ERROR] 无法确定 OPF 路径，诊断终止');
      return lines.join('\n');
    }

    final opfFile = archive.findFile(opfPath);
    final opfXml = utf8.decode(opfFile!.content as List<int>);
    final doc = xml.XmlDocument.parse(opfXml);
    final package = doc.findAllElements('package').firstOrNull;
    if (package == null) {
      lines.add('[ERROR] OPF 中缺少 package 根元素');
      return lines.join('\n');
    }

    // metadata
    lines.add('── 元数据 ──');
    final metadata = package.findElements('metadata').firstOrNull;
    final title = metadata?.findElements('title').firstOrNull?.innerText.trim();
    final creator = metadata
        ?.findElements('creator')
        .firstOrNull
        ?.innerText
        .trim();
    if (title == null || title.isEmpty) {
      lines.add('[WARN] 缺少书名（metadata/title）');
    } else {
      lines.add('[OK] 书名：$title');
    }
    if (creator == null || creator.isEmpty) {
      lines.add('[WARN] 缺少作者（metadata/creator）');
    } else {
      lines.add('[OK] 作者：$creator');
    }
    final version = package.getAttribute('version');
    lines.add('EPUB 版本：${version ?? '未知'}');
    lines.add('');

    // manifest
    lines.add('── manifest（${_manifestItems(package).length} 项）──');
    var missingFiles = 0;
    final manifest = <String, ({String href, String mediaType})>{};
    for (final item in package.findElements('manifest').firstOrNull
            ?.findElements('item') ??
        const <xml.XmlElement>[]) {
      final id = item.getAttribute('id') ?? '';
      final href = item.getAttribute('href') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id.isEmpty) {
        lines.add('[WARN] manifest 中存在缺少 id 的 item（href=$href）');
        continue;
      }
      manifest[id] = (href: href, mediaType: mediaType);
      if (href.isEmpty) {
        lines.add('[WARN] item「$id」缺少 href');
        continue;
      }
      final target = _normalizeArchivePath(
        p.posix.join(p.posix.dirname(opfPath), href),
      );
      if (!archive.files.any((f) => _normalizeArchivePath(f.name) == target)) {
        missingFiles++;
        lines.add('[ERROR] manifest 引用的文件不存在：$href（$id）');
      }
    }
    if (missingFiles == 0) {
      lines.add('[OK] manifest 引用的文件均存在');
    }
    lines.add('');

    // spine
    lines.add('── spine（${_spineRefs(package).length} 项）──');
    final spineRefs = _spineRefs(package);
    if (spineRefs.isEmpty) {
      lines.add('[WARN] spine 为空');
    }
    var spineMissing = 0;
    for (final ref in spineRefs) {
      if (!manifest.containsKey(ref)) {
        spineMissing++;
        lines.add('[ERROR] spine 引用的 id 不在 manifest 中：$ref');
      }
    }
    if (spineMissing == 0 && spineRefs.isNotEmpty) {
      lines.add('[OK] spine 引用完整');
    }
    lines.add('');

    // ---- 5. 内部引用检查 ----
    lines.add('── 内部引用检查 ──');
    var checkedFiles = 0;
    var brokenRefs = 0;
    for (final entry in manifest.entries) {
      final href = entry.value.href;
      if (!(entry.value.mediaType.contains('html') ||
          entry.value.mediaType.contains('xml'))) {
        continue;
      }
      final target = _normalizeArchivePath(
        p.posix.join(p.posix.dirname(opfPath), href),
      );
      final contentFile = archive.files
          .where((f) => _normalizeArchivePath(f.name) == target)
          .firstOrNull;
      if (contentFile == null) continue;
      checkedFiles++;
      final text = utf8.decode(contentFile.content as List<int>);
      final fileDir = p.posix.dirname(target);
      // 提取 href 与 src 引用
      final refs = <String>[
        ...RegExp(r'href="([^"#?]+)').allMatches(text).map((m) => m.group(1)!),
        ...RegExp(r'src="([^"#?]+)').allMatches(text).map((m) => m.group(1)!),
      ];
      for (final ref in refs) {
        if (ref.startsWith('http://') ||
            ref.startsWith('https://') ||
            ref.startsWith('mailto:') ||
            ref.startsWith('data:')) {
          continue;
        }
        final refTarget = _normalizeArchivePath(p.posix.join(fileDir, ref));
        if (refTarget == _normalizeArchivePath(opfPath)) continue;
        if (!archive.files
            .any((f) => _normalizeArchivePath(f.name) == refTarget)) {
          brokenRefs++;
          lines.add('[ERROR] ${p.basename(href)} 引用不存在的文件：$ref');
        }
      }
    }
    lines.add('已检查 $checkedFiles 个正文文件');
    if (brokenRefs == 0) {
      lines.add('[OK] 未发现失效的内部引用');
    } else {
      lines.add('[WARN] 发现 $brokenRefs 处失效引用');
    }

    // 汇总
    final errorCount = lines.where((l) => l.startsWith('[ERROR]')).length;
    final warnCount = lines.where((l) => l.startsWith('[WARN]')).length;
    lines.add('');
    lines.add(
      '诊断完成：$errorCount 个错误，$warnCount 个警告',
    );

    return lines.join('\n');
  }

  static String? _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) return null;
    final xml = utf8.decode(containerFile.content as List<int>);
    final match = RegExp(r'full-path="([^"]+)"').firstMatch(xml);
    if (match == null) return null;
    final path = match.group(1)!;
    return archive.findFile(path) != null ? path : null;
  }

  static List<xml.XmlElement> _manifestItems(xml.XmlElement package) {
    return package.findElements('manifest').firstOrNull
            ?.findElements('item')
            .toList() ??
        const [];
  }

  static List<String> _spineRefs(xml.XmlElement package) {
    return package.findElements('spine').firstOrNull
            ?.findElements('itemref')
            .map((e) => e.getAttribute('idref') ?? '')
            .where((id) => id.isNotEmpty)
            .toList() ??
        const [];
  }

  /// 统一归档路径格式（去 ./、规范化分隔符）
  static String _normalizeArchivePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    final parts = <String>[];
    for (final part in normalized.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }
}
