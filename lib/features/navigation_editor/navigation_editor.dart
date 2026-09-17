import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/epub_image_helper.dart';
import '../../core/epub_packer.dart';
import 'navigation_model.dart';

class NavigationEditorOperation {
  NavigationEditorOperation._();

  static Future<List<NavigationValidationIssue>> validate(
    String epubPath,
    Map<NavigationSection, List<NavigationEntry>> sections,
  ) async {
    final archive = ZipDecoder().decodeBytes(
      await File(epubPath).readAsBytes(),
      verify: true,
    );
    return validateArchive(archive, sections);
  }

  static Future<EpubNavigationDocument> load(String epubPath) async {
    final archive = ZipDecoder().decodeBytes(
      await File(epubPath).readAsBytes(),
      verify: true,
    );
    final context = _NavigationContext.read(archive);
    final sections = {
      for (final section in NavigationSection.values)
        section: <NavigationEntry>[],
    };

    if (context.navPath != null) {
      final navFile = archive.findFile(context.navPath!);
      if (navFile != null) {
        final document = XmlDocument.parse(_readText(navFile));
        for (final section in NavigationSection.values) {
          final nav = _findNav(document, section);
          final list = nav?.childElements
              .where((element) => element.name.local == 'ol')
              .firstOrNull;
          if (list != null) {
            _readNavList(list, 1, context.navPath!, sections[section]!);
          }
        }
      }
    }

    if (context.ncxPath != null) {
      final ncxFile = archive.findFile(context.ncxPath!);
      if (ncxFile != null) {
        final document = XmlDocument.parse(_readText(ncxFile));
        if (sections[NavigationSection.toc]!.isEmpty) {
          final navMap = document.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'navMap')
              .firstOrNull;
          if (navMap != null) {
            _readNcx(
              navMap,
              1,
              context.ncxPath!,
              sections[NavigationSection.toc]!,
            );
          }
        }
        if (sections[NavigationSection.pageList]!.isEmpty) {
          _readNcxPageList(
            document,
            context.ncxPath!,
            sections[NavigationSection.pageList]!,
          );
        }
      }
    }

    if (sections[NavigationSection.landmarks]!.isEmpty) {
      final opfFile = archive.findFile(context.opfPath);
      if (opfFile != null) {
        _readOpfGuide(
          XmlDocument.parse(_readText(opfFile)),
          context.opfPath,
          sections[NavigationSection.landmarks]!,
        );
      }
    }

    if (sections[NavigationSection.toc]!.isEmpty) {
      for (final path in context.spinePaths) {
        sections[NavigationSection.toc]!.add(
          NavigationEntry(
            title: p.basenameWithoutExtension(path),
            href: path,
            level: 1,
          ),
        );
      }
    }

    final issues = validateArchive(archive, sections);
    return EpubNavigationDocument(
      sourcePath: epubPath,
      opfPath: context.opfPath,
      epubVersion: context.version,
      navPath: context.navPath,
      ncxPath: context.ncxPath,
      sections: sections,
      issues: issues,
    );
  }

  static Future<EpubNavigationDocument> regenerateFromHeadings(
    String epubPath,
  ) async {
    final current = await load(epubPath);
    final archive = ZipDecoder().decodeBytes(
      await File(epubPath).readAsBytes(),
      verify: true,
    );
    final context = _NavigationContext.read(archive);
    final toc = <NavigationEntry>[];

    for (final path in context.spinePaths) {
      final file = archive.findFile(path);
      if (file == null) continue;
      XmlDocument document;
      try {
        document = XmlDocument.parse(_readText(file));
      } catch (_) {
        continue;
      }
      final headings = document.descendants
          .whereType<XmlElement>()
          .where(
            (element) => RegExp(
              r'^h[1-6]$',
              caseSensitive: false,
            ).hasMatch(element.name.local),
          )
          .toList();
      final usedIds = document.descendants
          .whereType<XmlElement>()
          .expand(
            (element) => element.attributes
                .where((attribute) => attribute.name.local == 'id')
                .map((attribute) => attribute.value),
          )
          .toSet();
      var headingIndex = 0;
      int? baseHeadingLevel;
      var previousLevel = 1;
      for (final heading in headings) {
        final title = heading.innerText.trim();
        if (title.isEmpty) {
          headingIndex++;
          continue;
        }
        final rawLevel = int.parse(heading.name.local.substring(1));
        baseHeadingLevel ??= rawLevel;
        final relativeLevel = rawLevel - baseHeadingLevel + 1;
        final level = relativeLevel.clamp(1, previousLevel + 1);
        previousLevel = level;
        final existingId = heading.getAttribute('id')?.trim();
        final fragment = existingId != null && existingId.isNotEmpty
            ? existingId
            : _unusedGeneratedHeadingId(usedIds, headingIndex + 1);
        usedIds.add(fragment);
        toc.add(
          NavigationEntry(
            title: title,
            href: '$path#$fragment',
            level: level,
            sourceHeadingIndex: existingId == null || existingId.isEmpty
                ? headingIndex
                : null,
          ),
        );
        headingIndex++;
      }
    }

    final sections = {
      for (final section in NavigationSection.values)
        section: section == NavigationSection.toc
            ? toc
            : [...current.entries(section)],
    };
    return current.copyWith(
      sections: sections,
      issues: validateArchive(archive, sections),
    );
  }

  static Future<Map<String, Object?>> save({
    required String epubPath,
    required String outputPath,
    required EpubNavigationDocument navigation,
  }) async {
    final input = File(epubPath).absolute;
    final output = File(outputPath).absolute;
    if (input.path == output.path) {
      throw ArgumentError('输出路径不能覆盖输入 EPUB');
    }
    final archive = ZipDecoder().decodeBytes(
      await input.readAsBytes(),
      verify: true,
    );
    final context = _NavigationContext.read(archive);
    final issues = validateArchive(archive, navigation.sections);
    final errors = issues.where(
      (issue) => issue.severity == NavigationValidationSeverity.error,
    );
    if (errors.isNotEmpty) {
      throw FormatException(
        errors.map((issue) => issue.message).take(5).join('；'),
      );
    }

    var working = archive;
    working = _applyGeneratedAnchors(
      working,
      navigation.entries(NavigationSection.toc),
    );

    final isEpub3 = context.version.startsWith('3');
    var navPath = context.navPath;
    if (navPath != null || isEpub3) {
      navPath ??= _unusedPath(
        working,
        p.posix.join(context.opfDir, 'nav.xhtml'),
      );
      working = _writeNav(working, navPath, navigation.sections);
    }

    var ncxPath = context.ncxPath;
    if (ncxPath != null || !isEpub3) {
      ncxPath ??= _unusedPath(working, p.posix.join(context.opfDir, 'toc.ncx'));
      working = _writeNcx(
        working,
        ncxPath,
        navigation.entries(NavigationSection.toc),
        navigation.entries(NavigationSection.pageList),
      );
    }

    working = _updateOpf(
      working,
      context,
      navPath: navPath,
      ncxPath: ncxPath,
      landmarks: navigation.entries(NavigationSection.landmarks),
    );
    await output.parent.create(recursive: true);
    await EpubPacker.pack(archive: working, outputPath: output.path);

    final after = await load(output.path);
    return {
      'outputPath': output.path,
      'navigation': after.toJson(),
      'warnings': after.issues
          .where(
            (issue) => issue.severity == NavigationValidationSeverity.warning,
          )
          .map((issue) => issue.toJson())
          .toList(),
    };
  }

  static List<NavigationValidationIssue> validateStructure(
    Map<NavigationSection, List<NavigationEntry>> sections,
  ) {
    final issues = <NavigationValidationIssue>[];
    for (final section in NavigationSection.values) {
      final entries = sections[section] ?? const [];
      final seen = <String>{};
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (entry.title.trim().isEmpty) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.error,
              section: section,
              entryIndex: index,
              code: 'empty-title',
              message: '${section.label}第 ${index + 1} 项标题为空',
            ),
          );
        }
        if (entry.href.trim().isEmpty && section != NavigationSection.toc) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.error,
              section: section,
              entryIndex: index,
              code: 'empty-href',
              message: '${section.label}第 ${index + 1} 项链接为空',
            ),
          );
        }
        if (entry.level < 1 ||
            (index == 0 && entry.level != 1) ||
            (index > 0 && entry.level > entries[index - 1].level + 1)) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.error,
              section: section,
              entryIndex: index,
              code: 'invalid-level',
              message: '${section.label}第 ${index + 1} 项层级跳跃无效',
            ),
          );
        }
        final duplicateKey = '${entry.title.trim()}\u0000${entry.href.trim()}';
        if (!seen.add(duplicateKey)) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.warning,
              section: section,
              entryIndex: index,
              code: 'duplicate-entry',
              message: '${section.label}存在重复条目：${entry.title}',
            ),
          );
        }
      }
    }
    return issues;
  }

  static List<NavigationValidationIssue> validateArchive(
    Archive archive,
    Map<NavigationSection, List<NavigationEntry>> sections,
  ) {
    final issues = validateStructure(sections);
    final ids = <String, Set<String>?>{};
    final empty = <String, bool>{};
    for (final section in NavigationSection.values) {
      final entries = sections[section] ?? const [];
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (entry.href.trim().isEmpty) continue;
        final split = _splitHref(entry.href);
        final file = archive.findFile(split.path);
        if (file == null) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.error,
              section: section,
              entryIndex: index,
              code: 'missing-target',
              message: '${entry.title} 指向不存在的文件：${split.path}',
            ),
          );
          continue;
        }
        if (!_isXmlContent(split.path)) continue;
        if (!ids.containsKey(split.path)) {
          try {
            final document = XmlDocument.parse(_readText(file));
            ids[split.path] = document.descendants
                .whereType<XmlElement>()
                .expand(
                  (element) => element.attributes
                      .where((attribute) => attribute.name.local == 'id')
                      .map((attribute) => attribute.value),
                )
                .toSet();
            final body = document.descendants
                .whereType<XmlElement>()
                .where((element) => element.name.local == 'body')
                .firstOrNull;
            empty[split.path] = (body?.innerText.trim() ?? '').isEmpty;
          } catch (_) {
            ids[split.path] = null;
          }
        }
        if (split.fragment.isNotEmpty &&
            entry.sourceHeadingIndex == null &&
            ids[split.path] != null &&
            !ids[split.path]!.contains(split.fragment)) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.error,
              section: section,
              entryIndex: index,
              code: 'invalid-anchor',
              message: '${entry.title} 的锚点不存在：${entry.href}',
            ),
          );
        }
        if (section == NavigationSection.toc && empty[split.path] == true) {
          issues.add(
            NavigationValidationIssue(
              severity: NavigationValidationSeverity.warning,
              section: section,
              entryIndex: index,
              code: 'empty-chapter',
              message: '${entry.title} 指向空章节：${split.path}',
            ),
          );
        }
      }
    }
    return issues;
  }

  static Archive _applyGeneratedAnchors(
    Archive archive,
    List<NavigationEntry> entries,
  ) {
    final byPath = <String, List<NavigationEntry>>{};
    for (final entry in entries) {
      if (entry.sourceHeadingIndex == null) continue;
      final split = _splitHref(entry.href);
      byPath.putIfAbsent(split.path, () => []).add(entry);
    }

    var result = archive;
    for (final pathEntry in byPath.entries) {
      final file = result.findFile(pathEntry.key);
      if (file == null) continue;
      final document = XmlDocument.parse(_readText(file));
      final headings = document.descendants
          .whereType<XmlElement>()
          .where(
            (element) => RegExp(
              r'^h[1-6]$',
              caseSensitive: false,
            ).hasMatch(element.name.local),
          )
          .toList();
      for (final entry in pathEntry.value) {
        final headingIndex = entry.sourceHeadingIndex!;
        if (headingIndex < 0 || headingIndex >= headings.length) {
          throw StateError('无法定位待补锚点的标题：${entry.title}');
        }
        final fragment = _splitHref(entry.href).fragment;
        if (fragment.isEmpty) continue;
        final heading = headings[headingIndex];
        final existing = heading.getAttribute('id')?.trim();
        if (existing == null || existing.isEmpty) {
          heading.setAttribute('id', fragment);
        } else if (existing != fragment) {
          throw StateError('标题锚点已变化：${entry.title}');
        }
      }
      final bytes = utf8.encode(
        document.toXmlString(pretty: true, indent: '  '),
      );
      result = EpubImageHelper.addOrReplaceFileSafe(
        result,
        ArchiveFile(pathEntry.key, bytes.length, bytes),
      );
    }
    return result;
  }

  static String _unusedGeneratedHeadingId(Set<String> usedIds, int index) {
    final base = 'epub-toolkit-heading-$index';
    if (!usedIds.contains(base)) return base;
    var suffix = 2;
    while (usedIds.contains('$base-$suffix')) {
      suffix++;
    }
    return '$base-$suffix';
  }

  static Archive _writeNav(
    Archive archive,
    String navPath,
    Map<NavigationSection, List<NavigationEntry>> sections,
  ) {
    final existing = archive.findFile(navPath);
    final document = existing == null
        ? XmlDocument.parse(_newNavDocument())
        : XmlDocument.parse(_readText(existing));
    final body = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'body')
        .firstOrNull;
    if (body == null) throw StateError('NAV 文档缺少 body：$navPath');

    for (final section in NavigationSection.values) {
      final entries = sections[section] ?? const [];
      var nav = _findNav(document, section);
      if (entries.isEmpty && section != NavigationSection.toc) {
        nav?.remove();
        continue;
      }
      nav ??= XmlElement.tag(
        'nav',
        attributes: [
          XmlAttribute(XmlName('epub:type'), section.epubType),
          XmlAttribute(XmlName('id'), section.epubType.replaceAll('-', '_')),
        ],
      );
      if (nav.parent == null) body.children.add(nav);
      final existingLists = nav.childElements
          .where((element) => element.name.local == 'ol')
          .toList();
      for (final list in existingLists) {
        list.remove();
      }
      final heading = nav.childElements
          .where((element) => RegExp(r'^h[1-6]$').hasMatch(element.name.local))
          .firstOrNull;
      if (heading == null) {
        nav.children.insert(
          0,
          XmlElement.tag('h1', children: [XmlText(section.label)]),
        );
      }
      nav.children.add(_buildNavList(entries, navPath));
    }

    final bytes = utf8.encode(document.toXmlString(pretty: true, indent: '  '));
    return EpubImageHelper.addOrReplaceFileSafe(
      archive,
      ArchiveFile(navPath, bytes.length, bytes),
    );
  }

  static Archive _writeNcx(
    Archive archive,
    String ncxPath,
    List<NavigationEntry> tocEntries,
    List<NavigationEntry> pageListEntries,
  ) {
    final existing = archive.findFile(ncxPath);
    final document = existing == null
        ? XmlDocument.parse(_newNcxDocument())
        : XmlDocument.parse(_readText(existing));
    var navMap = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'navMap')
        .firstOrNull;
    if (navMap == null) {
      navMap = XmlElement.tag('navMap');
      document.rootElement.children.add(navMap);
    }
    navMap.children.clear();
    final roots = _toTree(tocEntries);
    var playOrder = 1;
    for (final node in roots) {
      navMap.children.add(_buildNcxPoint(node, ncxPath, () => playOrder++));
    }
    _writeNcxPageList(document, ncxPath, pageListEntries, () => playOrder++);
    final depth = tocEntries.isEmpty
        ? 1
        : tocEntries
              .map((entry) => entry.level)
              .reduce((a, b) => a > b ? a : b);
    final depthMeta = document.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'meta' &&
              element.getAttribute('name') == 'dtb:depth',
        )
        .firstOrNull;
    depthMeta?.setAttribute('content', '$depth');
    final bytes = utf8.encode(document.toXmlString(pretty: true, indent: '  '));
    return EpubImageHelper.addOrReplaceFileSafe(
      archive,
      ArchiveFile(ncxPath, bytes.length, bytes),
    );
  }

  static Archive _updateOpf(
    Archive archive,
    _NavigationContext context, {
    required String? navPath,
    required String? ncxPath,
    required List<NavigationEntry> landmarks,
  }) {
    final file = archive.findFile(context.opfPath);
    if (file == null) throw StateError('找不到 OPF：${context.opfPath}');
    final document = XmlDocument.parse(_readText(file));
    final manifest = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'manifest')
        .firstOrNull;
    final spine = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'spine')
        .firstOrNull;
    if (manifest == null || spine == null) {
      throw StateError('OPF 缺少 manifest 或 spine');
    }

    if (navPath != null) {
      var navItem = _manifestItemForPath(document, context.opfPath, navPath);
      if (navItem == null) {
        navItem = XmlElement.tag(
          'item',
          attributes: [
            XmlAttribute(XmlName('id'), _unusedId(document, 'nav')),
            XmlAttribute(
              XmlName('href'),
              p.posix.relative(navPath, from: context.opfDir),
            ),
            XmlAttribute(XmlName('media-type'), 'application/xhtml+xml'),
            XmlAttribute(XmlName('properties'), 'nav'),
          ],
        );
        manifest.children.add(navItem);
      } else {
        final tokens =
            (navItem.getAttribute('properties') ?? '')
                .split(RegExp(r'\s+'))
                .where((token) => token.isNotEmpty)
                .toSet()
              ..add('nav');
        navItem.setAttribute('properties', tokens.join(' '));
        navItem.setAttribute('media-type', 'application/xhtml+xml');
      }
    }

    if (ncxPath != null) {
      var ncxItem = _manifestItemForPath(document, context.opfPath, ncxPath);
      if (ncxItem == null) {
        ncxItem = XmlElement.tag(
          'item',
          attributes: [
            XmlAttribute(XmlName('id'), _unusedId(document, 'ncx')),
            XmlAttribute(
              XmlName('href'),
              p.posix.relative(ncxPath, from: context.opfDir),
            ),
            XmlAttribute(XmlName('media-type'), 'application/x-dtbncx+xml'),
          ],
        );
        manifest.children.add(ncxItem);
      } else {
        ncxItem.setAttribute('media-type', 'application/x-dtbncx+xml');
      }
      spine.setAttribute('toc', ncxItem.getAttribute('id')!);
    }

    _writeOpfGuide(
      document,
      context.opfPath,
      landmarks,
      create: !context.version.startsWith('3'),
    );

    final bytes = utf8.encode(document.toXmlString(pretty: true, indent: '  '));
    return EpubImageHelper.addOrReplaceFileSafe(
      archive,
      ArchiveFile(context.opfPath, bytes.length, bytes),
    );
  }

  static XmlElement? _manifestItemForPath(
    XmlDocument document,
    String opfPath,
    String targetPath,
  ) {
    return document.descendants.whereType<XmlElement>().where((element) {
      if (element.name.local != 'item') return false;
      final href = element.getAttribute('href');
      return href != null && _resolveHref(opfPath, href).path == targetPath;
    }).firstOrNull;
  }

  static String _unusedId(XmlDocument document, String base) {
    final ids = document.descendants
        .whereType<XmlElement>()
        .map((element) => element.getAttribute('id'))
        .whereType<String>()
        .toSet();
    if (!ids.contains(base)) return base;
    var index = 2;
    while (ids.contains('$base$index')) {
      index++;
    }
    return '$base$index';
  }

  static String _unusedPath(Archive archive, String preferred) {
    if (archive.findFile(preferred) == null) return preferred;
    final extension = p.posix.extension(preferred);
    final stem = preferred.substring(0, preferred.length - extension.length);
    var index = 2;
    while (archive.findFile('$stem$index$extension') != null) {
      index++;
    }
    return '$stem$index$extension';
  }

  static XmlElement _buildNavList(
    List<NavigationEntry> entries,
    String navPath,
  ) {
    final ol = XmlElement.tag('ol');
    for (final node in _toTree(entries)) {
      ol.children.add(_buildNavItem(node, navPath));
    }
    return ol;
  }

  static XmlElement _buildNavItem(_NavigationNode node, String navPath) {
    final target = node.entry.href.trim();
    final semanticAttributes = node.entry.semanticType.trim().isEmpty
        ? const <XmlAttribute>[]
        : [XmlAttribute(XmlName('epub:type'), node.entry.semanticType.trim())];
    final label = target.isEmpty
        ? XmlElement.tag(
            'span',
            attributes: semanticAttributes,
            children: [XmlText(node.entry.title)],
          )
        : XmlElement.tag(
            'a',
            attributes: [
              XmlAttribute(XmlName('href'), _relativeHref(navPath, target)),
              ...semanticAttributes,
            ],
            children: [XmlText(node.entry.title)],
          );
    final li = XmlElement.tag('li', children: [label]);
    if (node.children.isNotEmpty) {
      final ol = XmlElement.tag('ol');
      for (final child in node.children) {
        ol.children.add(_buildNavItem(child, navPath));
      }
      li.children.add(ol);
    }
    return li;
  }

  static XmlElement _buildNcxPoint(
    _NavigationNode node,
    String ncxPath,
    int Function() nextOrder,
  ) {
    final order = nextOrder();
    final point = XmlElement.tag(
      'navPoint',
      attributes: [
        XmlAttribute(XmlName('id'), 'navPoint-$order'),
        XmlAttribute(XmlName('playOrder'), '$order'),
      ],
      children: [
        XmlElement.tag(
          'navLabel',
          children: [
            XmlElement.tag('text', children: [XmlText(node.entry.title)]),
          ],
        ),
        XmlElement.tag(
          'content',
          attributes: [
            XmlAttribute(
              XmlName('src'),
              _relativeHref(ncxPath, node.entry.href),
            ),
          ],
        ),
      ],
    );
    for (final child in node.children) {
      point.children.add(_buildNcxPoint(child, ncxPath, nextOrder));
    }
    return point;
  }

  static void _writeNcxPageList(
    XmlDocument document,
    String ncxPath,
    List<NavigationEntry> entries,
    int Function() nextOrder,
  ) {
    var pageList = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'pageList')
        .firstOrNull;
    if (entries.isEmpty) {
      pageList?.remove();
      return;
    }
    pageList ??= XmlElement.tag('pageList');
    if (pageList.parent == null) document.rootElement.children.add(pageList);
    for (final target
        in pageList.childElements
            .where((element) => element.name.local == 'pageTarget')
            .toList()) {
      target.remove();
    }
    final heading = pageList.childElements
        .where((element) => element.name.local == 'navLabel')
        .firstOrNull;
    if (heading == null) {
      pageList.children.insert(
        0,
        XmlElement.tag(
          'navLabel',
          children: [
            XmlElement.tag('text', children: [XmlText('页码')]),
          ],
        ),
      );
    }
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final order = nextOrder();
      pageList.children.add(
        XmlElement.tag(
          'pageTarget',
          attributes: [
            XmlAttribute(XmlName('id'), 'pageTarget-$order'),
            XmlAttribute(XmlName('playOrder'), '$order'),
            XmlAttribute(
              XmlName('type'),
              entry.semanticType.trim().isEmpty
                  ? 'normal'
                  : entry.semanticType.trim(),
            ),
            XmlAttribute(XmlName('value'), '${index + 1}'),
          ],
          children: [
            XmlElement.tag(
              'navLabel',
              children: [
                XmlElement.tag('text', children: [XmlText(entry.title)]),
              ],
            ),
            XmlElement.tag(
              'content',
              attributes: [
                XmlAttribute(
                  XmlName('src'),
                  _relativeHref(ncxPath, entry.href),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  static void _writeOpfGuide(
    XmlDocument document,
    String opfPath,
    List<NavigationEntry> landmarks, {
    required bool create,
  }) {
    var guide = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'guide')
        .firstOrNull;
    if (guide == null && (!create || landmarks.isEmpty)) return;
    guide ??= XmlElement.tag('guide');
    if (guide.parent == null) document.rootElement.children.add(guide);
    for (final reference
        in guide.childElements
            .where((element) => element.name.local == 'reference')
            .toList()) {
      reference.remove();
    }
    for (final entry in landmarks) {
      guide.children.add(
        XmlElement.tag(
          'reference',
          attributes: [
            XmlAttribute(
              XmlName('type'),
              entry.semanticType.trim().isEmpty
                  ? 'text'
                  : entry.semanticType.trim(),
            ),
            XmlAttribute(XmlName('title'), entry.title),
            XmlAttribute(XmlName('href'), _relativeHref(opfPath, entry.href)),
          ],
        ),
      );
    }
    if (landmarks.isEmpty && guide.childElements.isEmpty) guide.remove();
  }

  static List<_NavigationNode> _toTree(List<NavigationEntry> entries) {
    final roots = <_NavigationNode>[];
    final stack = <_NavigationNode>[];
    for (final entry in entries) {
      final level = entry.level.clamp(1, stack.length + 1);
      while (stack.length >= level) {
        stack.removeLast();
      }
      final node = _NavigationNode(entry);
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }
    return roots;
  }

  static XmlElement? _findNav(XmlDocument document, NavigationSection section) {
    return document.descendants.whereType<XmlElement>().where((element) {
      if (element.name.local != 'nav') return false;
      final type = element.attributes
          .where((attribute) => attribute.name.local == 'type')
          .map((attribute) => attribute.value)
          .firstOrNull;
      return type?.split(RegExp(r'\s+')).contains(section.epubType) ?? false;
    }).firstOrNull;
  }

  static void _readNavList(
    XmlElement ol,
    int level,
    String navPath,
    List<NavigationEntry> output,
  ) {
    for (final li in ol.childElements.where(
      (element) => element.name.local == 'li',
    )) {
      final link = li.childElements
          .where(
            (element) =>
                element.name.local == 'a' || element.name.local == 'span',
          )
          .firstOrNull;
      if (link != null) {
        final href = link.name.local == 'a'
            ? link.getAttribute('href') ?? ''
            : '';
        output.add(
          NavigationEntry(
            title: link.innerText.trim(),
            href: href.isEmpty ? '' : _resolveHref(navPath, href).full,
            level: level,
            semanticType:
                link.attributes
                    .where((attribute) => attribute.name.local == 'type')
                    .map((attribute) => attribute.value)
                    .firstOrNull ??
                '',
          ),
        );
      }
      final child = li.childElements
          .where((element) => element.name.local == 'ol')
          .firstOrNull;
      if (child != null) _readNavList(child, level + 1, navPath, output);
    }
  }

  static void _readNcx(
    XmlElement parent,
    int level,
    String ncxPath,
    List<NavigationEntry> output,
  ) {
    for (final point in parent.childElements.where(
      (element) => element.name.local == 'navPoint',
    )) {
      final label = point.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'text')
          .firstOrNull
          ?.innerText
          .trim();
      final src = point.childElements
          .where((element) => element.name.local == 'content')
          .firstOrNull
          ?.getAttribute('src');
      output.add(
        NavigationEntry(
          title: label ?? '',
          href: src == null || src.isEmpty
              ? ''
              : _resolveHref(ncxPath, src).full,
          level: level,
        ),
      );
      _readNcx(point, level + 1, ncxPath, output);
    }
  }

  static void _readNcxPageList(
    XmlDocument document,
    String ncxPath,
    List<NavigationEntry> output,
  ) {
    final pageList = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'pageList')
        .firstOrNull;
    if (pageList == null) return;
    for (final target in pageList.childElements.where(
      (element) => element.name.local == 'pageTarget',
    )) {
      final label = target.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'text')
          .firstOrNull
          ?.innerText
          .trim();
      final src = target.childElements
          .where((element) => element.name.local == 'content')
          .firstOrNull
          ?.getAttribute('src');
      output.add(
        NavigationEntry(
          title: label ?? '',
          href: src == null || src.isEmpty
              ? ''
              : _resolveHref(ncxPath, src).full,
          level: 1,
          semanticType: target.getAttribute('type')?.trim() ?? '',
        ),
      );
    }
  }

  static void _readOpfGuide(
    XmlDocument document,
    String opfPath,
    List<NavigationEntry> output,
  ) {
    final guide = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'guide')
        .firstOrNull;
    if (guide == null) return;
    for (final reference in guide.childElements.where(
      (element) => element.name.local == 'reference',
    )) {
      final href = reference.getAttribute('href')?.trim() ?? '';
      output.add(
        NavigationEntry(
          title: reference.getAttribute('title')?.trim() ?? '',
          href: href.isEmpty ? '' : _resolveHref(opfPath, href).full,
          level: 1,
          semanticType: reference.getAttribute('type')?.trim() ?? '',
        ),
      );
    }
  }

  static _ResolvedHref _resolveHref(String sourcePath, String href) {
    final split = _splitHref(href);
    final decoded = _decode(split.path).replaceAll('\\', '/');
    final path = decoded.startsWith('/')
        ? decoded.substring(1)
        : p.posix.normalize(p.posix.join(p.posix.dirname(sourcePath), decoded));
    return _ResolvedHref(path, split.query, split.fragment);
  }

  static _ResolvedHref _splitHref(String href) {
    final hash = href.indexOf('#');
    final withoutFragment = hash < 0 ? href : href.substring(0, hash);
    final queryIndex = withoutFragment.indexOf('?');
    final path = queryIndex < 0
        ? withoutFragment
        : withoutFragment.substring(0, queryIndex);
    final query = queryIndex < 0
        ? ''
        : withoutFragment.substring(queryIndex + 1);
    final fragment = hash < 0 ? '' : _decode(href.substring(hash + 1));
    return _ResolvedHref(path, query, fragment);
  }

  static String _relativeHref(String sourcePath, String targetHref) {
    if (targetHref.trim().isEmpty) return '';
    final split = _splitHref(targetHref);
    final relative = p.posix.relative(
      split.path,
      from: p.posix.dirname(sourcePath),
    );
    return _ResolvedHref(relative, split.query, split.fragment).full;
  }

  static String _decode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  static bool _isXmlContent(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.svg');
  }

  static String _readText(ArchiveFile file) =>
      utf8.decode(file.content as List<int>, allowMalformed: true);

  static String _newNavDocument() => '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><meta charset="utf-8"/><title>导航</title></head>
  <body></body>
</html>''';

  static String _newNcxDocument() => '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="epub-toolkit"/><meta name="dtb:depth" content="1"/></head>
  <docTitle><text>目录</text></docTitle>
  <navMap></navMap>
</ncx>''';
}

class _NavigationContext {
  final String opfPath;
  final String opfDir;
  final String version;
  final String? navPath;
  final String? ncxPath;
  final List<String> spinePaths;

  const _NavigationContext({
    required this.opfPath,
    required this.opfDir,
    required this.version,
    required this.navPath,
    required this.ncxPath,
    required this.spinePaths,
  });

  factory _NavigationContext.read(Archive archive) {
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) throw StateError('找不到 OPF');
    final file = archive.findFile(opfPath);
    if (file == null) throw StateError('找不到 OPF：$opfPath');
    final document = XmlDocument.parse(
      utf8.decode(file.content as List<int>, allowMalformed: true),
    );
    final manifest = <String, _ManifestInfo>{};
    String? navPath;
    String? ncxPath;
    for (final item in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'item',
    )) {
      final id = item.getAttribute('id')?.trim() ?? '';
      final href = item.getAttribute('href')?.trim() ?? '';
      if (id.isEmpty || href.isEmpty) continue;
      final mediaType = item.getAttribute('media-type')?.trim() ?? '';
      final path = NavigationEditorOperation._resolveHref(opfPath, href).path;
      manifest[id] = _ManifestInfo(path, mediaType);
      final properties = item.getAttribute('properties') ?? '';
      if (properties.split(RegExp(r'\s+')).contains('nav')) navPath = path;
      if (mediaType == 'application/x-dtbncx+xml') ncxPath = path;
    }
    final spine = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'spine')
        .firstOrNull;
    final tocId = spine?.getAttribute('toc');
    if (tocId != null && manifest[tocId] != null) {
      ncxPath = manifest[tocId]!.path;
    }
    final spinePaths = <String>[];
    for (final itemref
        in spine?.childElements.where(
              (element) => element.name.local == 'itemref',
            ) ??
            const <XmlElement>[]) {
      final idref = itemref.getAttribute('idref');
      final target = idref == null ? null : manifest[idref];
      if (target != null) spinePaths.add(target.path);
    }
    return _NavigationContext(
      opfPath: opfPath,
      opfDir: p.posix.dirname(opfPath),
      version: document.rootElement.getAttribute('version') ?? '',
      navPath: navPath,
      ncxPath: ncxPath,
      spinePaths: spinePaths,
    );
  }
}

class _ManifestInfo {
  final String path;
  final String mediaType;

  const _ManifestInfo(this.path, this.mediaType);
}

class _ResolvedHref {
  final String path;
  final String query;
  final String fragment;

  const _ResolvedHref(this.path, this.query, this.fragment);

  String get full {
    final withQuery = query.isEmpty ? path : '$path?$query';
    return fragment.isEmpty ? withQuery : '$withQuery#$fragment';
  }
}

class _NavigationNode {
  final NavigationEntry entry;
  final List<_NavigationNode> children = [];

  _NavigationNode(this.entry);
}
