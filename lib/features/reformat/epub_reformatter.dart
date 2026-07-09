// EPUB 深度重构：完全对齐原 Wail (Python) 项目的 reformat_epub.py
//
// 实现以下功能（与 wail 版一一对应）：
// 1. 将 EPUB 内部结构规范化到 Sigil 规范目录（OEBPS/Text、Styles、Images、Fonts、Audio、Video、Misc）
// 2. 将没有列入 manifest 的有效文件自动列入 manifest
// 3. 自动清除 manifest 中重复 ID / 无效 ID 的项
// 4. 自动检查并提示 spine 引用无效 ID 的项
// 5. 自动检查 manifest 中 xhtml 类型不被 spine 引用的情况
// 6. 自动检测并纠正文件名大小写不一致导致的链接错误
// 7. 自动检查找不到对应文件的链接
// 8. 自动补齐 xhtml 缺少的 <?xml> 声明和 XHTML 1.1 DOCTYPE
// 9. 自动重写 xhtml 中的 <a href>、<img src>、<video poster>、<input placeholder>
//    以及 CSS 中的 url()、@import，指向规范化后的新路径
// 10. 修正 container.xml 的 media-type 为 application/oebps-package+xml
// 11. mimetype 强制 STORED 且为 ZIP 第一个文件（沿用 EpubPacker.pack）

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_packer.dart';

/// EPUB 深度重构工具
///
/// 对齐原 Wail (Python) 项目 `reformat_epub.py` 的功能集。
/// 设计目标：处理来源不规范的 EPUB（如 zhangyue 转换器、在线转换器输出），
/// 把内部结构修复为 Sigil 规范的多看/Kindle/标准阅读器都能正常导入的形式。
class EpubReformatter {
  /// 输入 EPUB 路径
  final String epubPath;

  /// 输出 EPUB 路径
  final String outputPath;

  /// 错误与日志收集器
  final List<String> logLines = [];

  /// OPF 级别的结构化错误
  ///   (errorType, value) 如 ('duplicate_id', 'cover_img')
  final List<({String type, String value})> opfErrors = [];

  /// 链接错误：filePath -> [(linkHref, correctPathOrNull)]
  final Map<String, List<({String href, String? correct})>> linkErrors = {};

  /// 规范化目录
  /// （与 wail 版的 OEBPS/Text / Styles / Images / Fonts / Audio / Video / Misc 一致）
  static const _dirText = 'OEBPS/Text/';
  static const _dirCss = 'OEBPS/Styles/';
  static const _dirImage = 'OEBPS/Images/';
  static const _dirFont = 'OEBPS/Fonts/';
  static const _dirAudio = 'OEBPS/Audio/';
  static const _dirVideo = 'OEBPS/Video/';
  static const _dirMisc = 'OEBPS/Misc/';
  static const _opfOutPath = 'OEBPS/content.opf';
  static const _ncxOutPath = 'OEBPS/toc.ncx';

  /// MIME 映射
  static const _mimeMap = {
    '.html': 'application/xhtml+xml',
    '.xhtml': 'application/xhtml+xml',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.bmp': 'image/bmp',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ncx': 'application/x-dtbncx+xml',
    '.mp3': 'audio/mpeg',
    '.mp4': 'video/mp4',
    '.smil': 'application/smil+xml',
    '.pls': 'application/pls+xml',
  };

  EpubReformatter({required this.epubPath, required this.outputPath});

  /// 写日志
  void _log(String msg) {
    logLines.add(msg);
  }

  /// 执行完整重构流程
  Future<void> execute() async {
    _log('开始重构 EPUB: $epubPath');

    // 1. 读取并解析
    final bytes = await File(epubPath).readAsBytes();
    var srcArchive = ZipDecoder().decodeBytes(bytes);

    // 2. 定位 OPF
    final opfPath = _locateOpfPath(srcArchive);
    final opfDir = p.dirname(opfPath);
    final opfDirWithSlash = opfDir == '.' ? '' : '$opfDir/';
    _log('OPF 路径: $opfPath (所在目录: $opfDir)');

    // 3. 读取 OPF 并解析 manifest / spine / metadata
    final opfFile = srcArchive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('EPUB 结构异常：找不到 OPF 文件 $opfPath');
    }
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);
    final package = opfDoc.rootElement;

    // 4. 收集所有文件 lowercase 索引（用于大小写检查）
    final lowerPathToOrigin = <String, String>{};
    for (final f in srcArchive.files) {
      if (f.name.isEmpty) continue;
      lowerPathToOrigin[f.name.toLowerCase()] = f.name;
    }

    // 5. 解析 manifest + metadata + spine
    final idToHmp = _parseManifest(package);
    var idToHref = {
      for (final e in idToHmp.entries) e.key: e.value.$1.toLowerCase(),
    };
    var hrefToId = {
      for (final e in idToHmp.entries) e.value.$1.toLowerCase(): e.key,
    };
    final spineList = _parseSpine(package);
    final metadata = _parseMetadata(package);
    final tocId =
        package.findElements('spine').firstOrNull?.getAttribute('toc') ?? '';

    // 6. 检测版本（与 wail 一致：2.0 / 3.0）
    final version = package.getAttribute('version');
    if (version == null || !['2.0', '3.0'].contains(version)) {
      throw Exception('此脚本不支持的 EPUB 版本: $version（仅支持 2.0 / 3.0）');
    }

    // 7. 重复 ID 处理（保留 spine 引用的、删被覆盖的）
    _clearDuplicateIdHref(
      spineList,
      idToHmp,
      idToHref,
      hrefToId,
      metadata['cover'] ?? '',
    );

    // 8. OPF 引用但文件不存在 → 删 id
    _removeHrefsNotInArchive(
      srcArchive,
      opfDirWithSlash,
      idToHmp,
      idToHref,
      hrefToId,
    );

    // 9. ZIP 中存在但 OPF 未引用 → 自动补全
    _addFilesNotInOpf(srcArchive, opfPath, idToHmp, idToHref, hrefToId);

    // 10. 重新构建 manifest 列表
    final manifestList = [
      for (final id in idToHmp.keys)
        (id, idToHmp[id]!.$1, idToHmp[id]!.$2, idToHmp[id]!.$3),
    ];

    // 11. 按 mime 分类（与 wail 一致）
    final textList = <_ItemRec>[];
    final cssList = <_ItemRec>[];
    final imageList = <_ItemRec>[];
    final fontList = <_ItemRec>[];
    final audioList = <_ItemRec>[];
    final videoList = <_ItemRec>[];
    final otherList = <_OtherRec>[];

    String tocHref = '';
    for (final (id, href, mime, prop) in manifestList) {
      if (mime == 'application/xhtml+xml') {
        textList.add((id: id, href: href, prop: prop));
      } else if (mime == 'text/css') {
        cssList.add((id: id, href: href, prop: prop));
      } else if (mime.startsWith('image/') ||
          href.toLowerCase().endsWith('.svg')) {
        imageList.add((id: id, href: href, prop: prop));
      } else if (mime.startsWith('font/') ||
          href.toLowerCase().endsWith('.ttf') ||
          href.toLowerCase().endsWith('.otf') ||
          href.toLowerCase().endsWith('.woff')) {
        fontList.add((id: id, href: href, prop: prop));
      } else if (mime.startsWith('audio/')) {
        audioList.add((id: id, href: href, prop: prop));
      } else if (mime.startsWith('video/')) {
        videoList.add((id: id, href: href, prop: prop));
      } else if (id == tocId) {
        tocHref = href;
      } else {
        otherList.add((id: id, href: href, mime: mime, prop: prop));
      }
    }

    // 12. 检查 manifest/spine 一致性
    _checkManifestAndSpine(spineList, manifestList);

    // 13. auto_rename：每个类型按顺序命名
    final rePathMap = <String, Map<String, String>>{
      'text': _autoRenameList(textList, 'text', opfDirWithSlash),
      'css': _autoRenameList(cssList, 'css', opfDirWithSlash),
      'image': _autoRenameList(imageList, 'image', opfDirWithSlash),
      'font': _autoRenameList(fontList, 'font', opfDirWithSlash),
      'audio': _autoRenameList(audioList, 'audio', opfDirWithSlash),
      'video': _autoRenameList(videoList, 'video', opfDirWithSlash),
      'other': _autoRenameList(otherList, 'other', opfDirWithSlash),
    };

    // 14. 重新计算 lowerPathToOrigin（增加规范化目录映射）
    final normPathMap = <String, String>{}; // 规范化后新路径 -> 实际 ZIP 内路径
    for (final cat in rePathMap.keys) {
      for (final entry in rePathMap[cat]!.entries) {
        final newName = entry.value;
        final dir = _categoryDir(cat);
        normPathMap['$dir$newName'] = entry.key; // 旧路径 -> 实际位置
      }
    }

    // 15. 构造目标 archive（重建）
    final tgtArchive = Archive();

    // 16. mimetype 强制 STORED
    tgtArchive.addFile(
      ArchiveFile('mimetype', _mimetypeBytes.length, _mimetypeBytes)
        ..compress = false,
    );

    // 17. 写入 container.xml（修正 media-type）
    final containerXml = utf8.decode(
      srcArchive.findFile('META-INF/container.xml')!.content as List<int>,
    );
    final newContainer = containerXml.replaceAll(
      RegExp(
        r'<rootfile[^>]*media-type="application/oebps-[^>]*/>',
        caseSensitive: false,
      ),
      '<rootfile full-path="$_opfOutPath" media-type="application/oebps-package+xml"/>',
    );
    tgtArchive.addFile(
      ArchiveFile(
        'META-INF/container.xml',
        newContainer.length,
        Uint8List.fromList(utf8.encode(newContainer)),
      )..compress = true,
    );

    // 18. 写 toc.ncx（链接重写）
    if (tocHref.isNotEmpty) {
      final tocPath = _resolveBookPath(tocHref, opfDirWithSlash);
      final tocFile = srcArchive.findFile(tocPath);
      if (tocFile != null) {
        var toc = utf8.decode(tocFile.content as List<int>);
        // 改 src=... 指向规范化后的文件
        toc = _rewriteTocSrc(toc, rePathMap, lowerPathToOrigin, opfPath);
        tgtArchive.addFile(
          ArchiveFile(
            _ncxOutPath,
            toc.length,
            Uint8List.fromList(utf8.encode(toc)),
          )..compress = true,
        );
      }
    }

    // 19. 写 xhtml（链接重写 + DOCTYPE 补齐）
    for (final textRec in textList) {
      final oldPath = _resolveBookPath(textRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;

      var text = utf8.decode(file.content as List<int>);

      // 补 <?xml>
      if (!text.startsWith('<?xml')) {
        text = '<?xml version="1.0" encoding="utf-8"?>\n$text';
      }
      // 补 XHTML 1.1 DOCTYPE
      if (!RegExp(r".*<!DOCTYPE\s+html", dotAll: true).hasMatch(text)) {
        text = text.replaceFirstMapped(
          RegExp(r"(<\?xml.*?>)\n*"),
          (m) =>
              '${m.group(1)}\n<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
        );
      }

      // 重写链接
      text = _rewriteXhtmlHref(
        text,
        oldPath,
        rePathMap,
        lowerPathToOrigin,
        false,
      );
      text = _rewriteXhtmlSrc(text, oldPath, rePathMap, lowerPathToOrigin);
      text = _rewriteXhtmlPoster(text, oldPath, rePathMap, lowerPathToOrigin);
      text = _rewriteXhtmlMediaAttr(
        text,
        oldPath,
        rePathMap,
        lowerPathToOrigin,
      );
      text = _rewriteXhtmlUrl(text, oldPath, rePathMap, lowerPathToOrigin);

      final newName = rePathMap['text']![oldPath.toLowerCase()] ?? textRec.href;
      final newPath = '$_dirText$newName';
      tgtArchive.addFile(
        ArchiveFile(newPath, text.length, Uint8List.fromList(utf8.encode(text)))
          ..compress = true,
      );
    }

    // 20. 写 css（@import / url() 重写）
    for (final cssRec in cssList) {
      final oldPath = _resolveBookPath(cssRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;

      var css = utf8.decode(file.content as List<int>);
      css = _rewriteCssImport(css);
      css = _rewriteCssUrl(css, oldPath, rePathMap, lowerPathToOrigin);

      final newName = rePathMap['css']![oldPath.toLowerCase()] ?? cssRec.href;
      final newPath = '$_dirCss$newName';
      tgtArchive.addFile(
        ArchiveFile(newPath, css.length, Uint8List.fromList(utf8.encode(css)))
          ..compress = true,
      );
    }

    // 21. 写图片
    for (final imgRec in imageList) {
      final oldPath = _resolveBookPath(imgRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;
      final newName = rePathMap['image']![oldPath.toLowerCase()] ?? imgRec.href;
      tgtArchive.addFile(
        ArchiveFile(
          '$_dirImage$newName',
          file.size,
          Uint8List.fromList(file.content as List<int>),
        )..compress = true,
      );
    }

    // 22. 写字体
    for (final fontRec in fontList) {
      final oldPath = _resolveBookPath(fontRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;
      final newName = rePathMap['font']![oldPath.toLowerCase()] ?? fontRec.href;
      tgtArchive.addFile(
        ArchiveFile(
          '$_dirFont$newName',
          file.size,
          Uint8List.fromList(file.content as List<int>),
        )..compress = true,
      );
    }

    // 23. 写音频
    for (final aRec in audioList) {
      final oldPath = _resolveBookPath(aRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;
      final newName = rePathMap['audio']![oldPath.toLowerCase()] ?? aRec.href;
      tgtArchive.addFile(
        ArchiveFile(
          '$_dirAudio$newName',
          file.size,
          Uint8List.fromList(file.content as List<int>),
        )..compress = true,
      );
    }

    // 24. 写视频
    for (final vRec in videoList) {
      final oldPath = _resolveBookPath(vRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;
      final newName = rePathMap['video']![oldPath.toLowerCase()] ?? vRec.href;
      tgtArchive.addFile(
        ArchiveFile(
          '$_dirVideo$newName',
          file.size,
          Uint8List.fromList(file.content as List<int>),
        )..compress = true,
      );
    }

    // 25. 写其他
    for (final oRec in otherList) {
      final oldPath = _resolveBookPath(oRec.href, opfDirWithSlash);
      final file = srcArchive.findFile(oldPath);
      if (file == null) continue;
      final newName = rePathMap['other']![oldPath.toLowerCase()] ?? oRec.href;
      tgtArchive.addFile(
        ArchiveFile(
          '$_dirMisc$newName',
          file.size,
          Uint8List.fromList(file.content as List<int>),
        )..compress = true,
      );
    }

    // 26. 写新 OPF（重写 manifest 指向规范化目录）
    final newOpf = _rewriteOpf(
      originalOpf: opfDoc,
      opfPath: opfPath,
      textList: textList,
      cssList: cssList,
      imageList: imageList,
      fontList: fontList,
      audioList: audioList,
      videoList: videoList,
      otherList: otherList,
      tocId: tocId,
      rePathMap: rePathMap,
      opfDirWithSlash: opfDirWithSlash,
    );
    tgtArchive.addFile(
      ArchiveFile(
        _opfOutPath,
        newOpf.length,
        Uint8List.fromList(utf8.encode(newOpf)),
      )..compress = true,
    );

    // 27. 输出错误日志
    _emitOpfErrors();
    _emitLinkErrors();

    // 28. 打包
    await EpubPacker.pack(archive: tgtArchive, outputPath: outputPath);
    _log('重构完成 → $outputPath');
  }

  // ==================== 解析器 ====================

  /// 从 container.xml 找 OPF 路径（找不到则扫描 namelist）
  String _locateOpfPath(Archive archive) {
    final cFile = archive.findFile('META-INF/container.xml');
    if (cFile != null) {
      final xml = utf8.decode(cFile.content as List<int>);
      final m = RegExp(r'full-path="([^"]+)"').firstMatch(xml);
      if (m != null) return m.group(1)!;
    }
    for (final f in archive.files) {
      if (f.name.toLowerCase().endsWith('.opf')) return f.name;
    }
    throw Exception('无法发现 OPF 文件');
  }

  /// 解析 manifest 元素
  /// 返回 { id -> (href, mime, properties) }
  Map<String, (String, String, String)> _parseManifest(XmlElement package) {
    final result = <String, (String, String, String)>{};
    final manifestList = package.findAllElements('manifest');
    if (manifestList.isEmpty) return result;
    for (final item in manifestList.first.findAllElements('item')) {
      final id = item.getAttribute('id');
      var href = item.getAttribute('href') ?? '';
      // URL 解码 href
      try {
        href = Uri.decodeFull(href);
      } catch (_) {}
      final mime = item.getAttribute('media-type') ?? '';
      final prop = item.getAttribute('properties') ?? '';
      if (id != null) result[id] = (href, mime, prop);
    }
    return result;
  }

  /// 解析 spine 元素
  /// 返回 [(id, linear, properties), ...]
  List<(String, String, String)> _parseSpine(XmlElement package) {
    final spines = package.findAllElements('spine');
    if (spines.isEmpty) return [];
    return [
      for (final r in spines.first.findAllElements('itemref'))
        (
          r.getAttribute('idref') ?? '',
          r.getAttribute('linear') ?? '',
          r.getAttribute('properties') ?? '',
        ),
    ];
  }

  /// 解析 metadata（cover 等）
  Map<String, String> _parseMetadata(XmlElement package) {
    final result = <String, String>{};
    final mList = package.findAllElements('metadata');
    if (mList.isEmpty) return result;
    for (final m in mList.first.childElements) {
      final tag = m.name.local;
      if ([
        'title',
        'creator',
        'language',
        'subject',
        'source',
        'identifier',
      ].contains(tag)) {
        result[tag] = m.innerText;
      } else if (tag == 'meta') {
        final name = m.getAttribute('name');
        final content = m.getAttribute('content');
        if (name == 'cover' && content != null) {
          result['cover'] = content;
        }
      }
    }
    return result;
  }

  // ==================== 修复器 ====================

  /// 重复 ID 处理（与 wail `_clear_duplicate_id_href` 一致）
  void _clearDuplicateIdHref(
    List<(String, String, String)> spineList,
    Map<String, (String, String, String)> idToHmp,
    Map<String, String> idToHref,
    Map<String, String> hrefToId,
    String coverId,
  ) {
    final idUsed = <String>[for (final s in spineList) s.$1];
    if (coverId.isNotEmpty) idUsed.add(coverId);

    final delId = <String>[];
    for (final entry in idToHref.entries) {
      final id = entry.key;
      final href = entry.value;
      if (hrefToId[href] != id) {
        // 该 href 有多个 id
        if (idUsed.contains(id) && !idUsed.contains(hrefToId[href]!)) {
          if (!delId.contains(hrefToId[href])) {
            delId.add(hrefToId[href]!);
          }
          hrefToId[href] = id;
        } else if (idUsed.contains(id) && idUsed.contains(hrefToId[href]!)) {
          continue;
        } else {
          if (!delId.contains(id)) {
            delId.add(id);
          }
        }
      }
    }
    for (final id in delId) {
      opfErrors.add((type: 'duplicate_id', value: id));
      idToHref.remove(id);
      idToHmp.remove(id);
    }
  }

  /// 移除 manifest 引用但 ZIP 内不存在的 id
  void _removeHrefsNotInArchive(
    Archive archive,
    String opfDir,
    Map<String, (String, String, String)> idToHmp,
    Map<String, String> idToHref,
    Map<String, String> hrefToId,
  ) {
    final delId = <String>[];
    final namelistLower = [for (final f in archive.files) f.name.toLowerCase()];
    for (final entry in idToHref.entries) {
      final bkpath = _resolveBookPath(entry.value, opfDir);
      if (!namelistLower.contains(bkpath.toLowerCase())) {
        delId.add(entry.key);
        hrefToId.remove(entry.value);
      }
    }
    for (final id in delId) {
      idToHref.remove(id);
      idToHmp.remove(id);
    }
  }

  /// ZIP 中存在但 OPF 未引用的有效文件自动补全
  void _addFilesNotInOpf(
    Archive archive,
    String opfPath,
    Map<String, (String, String, String)> idToHmp,
    Map<String, String> idToHref,
    Map<String, String> hrefToId,
  ) {
    final opfDir = p.dirname(opfPath);
    final opfDirSlash = opfDir == '.' ? '' : '$opfDir/';
    final validExts = const {
      '.html',
      '.xhtml',
      '.css',
      '.jpg',
      '.jpeg',
      '.bmp',
      '.gif',
      '.png',
      '.webp',
      '.svg',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.js',
      '.mp3',
      '.mp4',
      '.smil',
    };
    final hrefsNotInOpf = <String>[];
    for (final f in archive.files) {
      final lower = f.name.toLowerCase();
      if (!validExts.any((e) => lower.endsWith(e))) continue;
      if (lower == 'mimetype') continue;
      if (lower.endsWith('content.opf')) continue;
      // 计算 OPF 相对路径
      final opfHref = lower.startsWith(opfDirSlash.toLowerCase())
          ? f.name.substring(opfDirSlash.length)
          : f.name;
      if (!hrefToId.containsKey(opfHref.toLowerCase())) {
        hrefsNotInOpf.add(opfHref);
      }
    }
    String allocateId(String href) {
      final basename = p.basename(href);
      final code =
          basename.isNotEmpty &&
              ((basename.codeUnitAt(0) >= 0x41 &&
                      basename.codeUnitAt(0) <= 0x5A) ||
                  (basename.codeUnitAt(0) >= 0x61 &&
                      basename.codeUnitAt(0) <= 0x7A))
          ? basename
          : 'x$basename';
      final pre = p.withoutExtension(code);
      final suf = p.extension(code);
      var preWithSep = pre;
      var i = 0;
      while (idToHref.containsKey('$preWithSep$suf')) {
        i += 1;
        preWithSep = '${pre}_$i';
      }
      return '$preWithSep$suf';
    }

    for (final href in hrefsNotInOpf) {
      final newId = allocateId(href);
      final ext = p.extension(href).toLowerCase();
      final mime = _mimeMap[ext] ?? 'text/plain';
      idToHref[newId] = href.toLowerCase();
      hrefToId[href.toLowerCase()] = newId;
      idToHmp[newId] = (href, mime, '');
    }
  }

  /// 检查 manifest/spine 一致性
  void _checkManifestAndSpine(
    List<(String, String, String)> spineList,
    List<(String, String, String, String)> manifestList,
  ) {
    final spineIdrefs = {for (final s in spineList) s.$1};
    for (final idref in spineIdrefs) {
      if (!manifestList.any((m) => m.$1 == idref)) {
        opfErrors.add((type: 'invalid_idref', value: idref));
      }
    }
    for (final m in manifestList) {
      final id = m.$1;
      final mime = m.$3;
      if (mime == 'application/xhtml+xml' && !spineIdrefs.contains(id)) {
        opfErrors.add((type: 'xhtml_not_in_spine', value: id));
      }
    }
  }

  // ==================== 资源命名 ====================

  /// auto_rename：返回 { 旧完整路径（小写）-> 新 basename }
  /// 接受 List<_ItemRec> 或 List<_OtherRec>（两者都有 id + href）
  /// [opfDirWithSlash] OPF 所在目录（如 'OEBPS/'），用于把 href 解析为完整路径
  Map<String, String> _autoRenameList(
    List<dynamic> items,
    String category,
    String opfDirWithSlash,
  ) {
    final used = <String>{};
    final result = <String, String>{};
    for (final rec in items) {
      final id = rec.id as String;
      final href = rec.href as String;
      // 用 id 作为 basename 基础（与 wail 行为一致：_parse_opf 中先按 id 累加 basename_log）
      // wail 是这样：id 可能有 .xhtml 扩展，自动去掉
      var base = id;
      // base 可能含扩展名，去掉再补
      final ext = p.extension(href);
      base = p.withoutExtension(base);
      var newName = '$base$ext';
      var n = 0;
      while (used.contains(newName.toLowerCase())) {
        n += 1;
        newName = '${base}_$n$ext';
      }
      used.add(newName.toLowerCase());
      // key 用完整 bkpath 小写，与 oldPath = _resolveBookPath(href, opfDir) 一致
      final bkpath = _resolveBookPath(href, opfDirWithSlash);
      result[bkpath.toLowerCase()] = newName;
    }
    return result;
  }

  /// 类目 → 规范化目录
  String _categoryDir(String cat) {
    switch (cat) {
      case 'text':
        return _dirText;
      case 'css':
        return _dirCss;
      case 'image':
        return _dirImage;
      case 'font':
        return _dirFont;
      case 'audio':
        return _dirAudio;
      case 'video':
        return _dirVideo;
      default:
        return _dirMisc;
    }
  }

  // ==================== 链接重写 ====================

  /// 把相对于 OPF 目录的 href 解析为 ZIP 内完整路径
  String _resolveBookPath(String href, String opfDir) {
    final pathPart = href.split(RegExp(r"[?#]")).first;
    final combined = opfDir + pathPart;
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

  /// 把链接路径解析回目标文件，并检查大小写
  /// 返回最终 bkpath（修正大小写后）；找不到时记录 linkErrors 并返回 null
  String? _checkLink({
    required String fromFile,
    required String href,
    required Map<String, String> lowerPathToOrigin, // lowercase 路径 -> 原始路径
    String targetAnchor = '',
  }) {
    if (href.isEmpty ||
        href.startsWith('http://') ||
        href.startsWith('https://') ||
        href.startsWith('res:/') ||
        href.startsWith('file:/') ||
        href.startsWith('data:')) {
      return null;
    }
    // 解析 bkpath
    final bkpath = _resolveBookPath(href, '${p.dirname(fromFile)}/');
    final lower = bkpath.toLowerCase();
    if (lowerPathToOrigin.containsKey(lower)) {
      final origin = lowerPathToOrigin[lower]!;
      if (origin != bkpath) {
        // 大小写不一致
        linkErrors.putIfAbsent(fromFile, () => []).add((
          href: '$href$targetAnchor',
          correct: origin,
        ));
      }
      return origin;
    }
    // 找不到对应文件
    linkErrors.putIfAbsent(fromFile, () => []).add((
      href: '$href$targetAnchor',
      correct: null,
    ));
    return null;
  }

  /// 在 xhtml 中重写 `<a href=...>` 链接
  String _rewriteXhtmlHref(
    String text,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
    bool isToc,
  ) {
    final pattern = RegExp(
      r'''(<[^>]*href=(["']+))(.*?)(\2[^>]*>)''',
      dotAll: true,
    );
    return text.replaceAllMapped(pattern, (m) {
      var href = m.group(3)!;
      try {
        href = Uri.decodeFull(href);
      } catch (_) {}
      var targetAnchor = '';
      if (href.contains('#')) {
        final parts = href.split('#');
        href = parts[0];
        targetAnchor = '#${parts[1]}';
      }
      href = href.trim();
      final bkpath = _checkLink(
        fromFile: xhtmlPath,
        href: href,

        lowerPathToOrigin: lowerPathToOrigin,
        targetAnchor: targetAnchor,
      );
      if (bkpath == null) return m.group(0)!;

      final lower = bkpath.toLowerCase();
      if (_endsWithAny(lower, const [
        '.jpg',
        '.jpeg',
        '.png',
        '.bmp',
        '.gif',
        '.webp',
        '.svg',
      ])) {
        final n = rePathMap['image']![lower];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Images/$n${m.group(4)}';
      } else if (lower.endsWith('.css')) {
        final n = rePathMap['css']![lower];
        if (n == null) return m.group(0)!;
        return '<link href="../Styles/$n" type="text/css" rel="stylesheet"/>';
      } else if (lower.endsWith('.xhtml') || lower.endsWith('.html')) {
        final n = rePathMap['text']![lower];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}$n$targetAnchor${m.group(4)}';
      }
      return m.group(0)!;
    });
  }

  /// 重写 `<... src=...>` 链接
  String _rewriteXhtmlSrc(
    String text,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
  ) {
    final pattern = RegExp(
      r'''(<[^>]*\s+src=(["']))(.*?)(\2[^>]*>)''',
      dotAll: true,
    );
    return _rewriteMediaLike(
      text,
      pattern,
      xhtmlPath,
      rePathMap,
      lowerPathToOrigin,
      'src',
    );
  }

  /// 重写 `<... poster=...>` 链接
  String _rewriteXhtmlPoster(
    String text,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
  ) {
    final pattern = RegExp(
      r'''(<[^>]*\s+poster=(["']))(.*?)(\2[^>]*>)''',
      dotAll: true,
    );
    return _rewriteMediaLike(
      text,
      pattern,
      xhtmlPath,
      rePathMap,
      lowerPathToOrigin,
      'poster',
    );
  }

  /// 重写 placeholder / activestate / zy-cover-pic 等媒体属性
  String _rewriteXhtmlMediaAttr(
    String text,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
  ) {
    String out = text;
    for (final attr in ['placeholder', 'activestate', 'zy-cover-pic']) {
      final pattern = RegExp(
        '(<[^>]*\\s+$attr=([\\\'"]))(.*?)(\\2[^>]*>)',
        dotAll: true,
      );
      out = _rewriteMediaLike(
        out,
        pattern,
        xhtmlPath,
        rePathMap,
        lowerPathToOrigin,
        attr,
      );
    }
    return out;
  }

  /// 通用 src/poster/placeholder 等媒体属性重写
  String _rewriteMediaLike(
    String text,
    RegExp pattern,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
    String attrName,
  ) {
    return text.replaceAllMapped(pattern, (m) {
      var href = m.group(3)!;
      try {
        href = Uri.decodeFull(href);
      } catch (_) {}
      href = href.trim();
      final bkpath = _checkLink(
        fromFile: xhtmlPath,
        href: href,

        lowerPathToOrigin: lowerPathToOrigin,
      );
      if (bkpath == null) return m.group(0)!;

      final lower = bkpath.toLowerCase();
      if (_endsWithAny(lower, const [
        '.jpg',
        '.jpeg',
        '.png',
        '.bmp',
        '.gif',
        '.webp',
        '.svg',
      ])) {
        final n = rePathMap['image']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Images/$n${m.group(4)}';
      } else if (lower.endsWith('.mp3')) {
        final n = rePathMap['audio']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Audio/$n${m.group(4)}';
      } else if (lower.endsWith('.mp4')) {
        final n = rePathMap['video']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Video/$n${m.group(4)}';
      } else if (lower.endsWith('.js')) {
        final n = rePathMap['other']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Misc/$n${m.group(4)}';
      }
      return m.group(0)!;
    });
  }

  /// 重写 `url(...)`
  String _rewriteXhtmlUrl(
    String text,
    String xhtmlPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
  ) {
    final pattern = RegExp(r'''(url\(["']?)(.*?)(["']?\))''', dotAll: true);
    return text.replaceAllMapped(pattern, (m) {
      var url = m.group(2)!;
      try {
        url = Uri.decodeFull(url);
      } catch (_) {}
      url = url.trim();
      final bkpath = _checkLink(
        fromFile: xhtmlPath,
        href: url,

        lowerPathToOrigin: lowerPathToOrigin,
      );
      if (bkpath == null) return m.group(0)!;
      final lower = bkpath.toLowerCase();
      if (_endsWithAny(lower, const ['.ttf', '.otf', '.woff', '.woff2'])) {
        final n = rePathMap['font']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Fonts/$n${m.group(3)}';
      } else if (_endsWithAny(lower, const [
        '.jpg',
        '.jpeg',
        '.png',
        '.bmp',
        '.gif',
        '.webp',
        '.svg',
      ])) {
        final n = rePathMap['image']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Images/$n${m.group(3)}';
      }
      return m.group(0)!;
    });
  }

  /// toc.ncx 的 src= 改写
  String _rewriteTocSrc(
    String toc,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
    String opfPath,
  ) {
    final pattern = RegExp(r'''src=(["\'])(.*?)\1''', dotAll: true);
    return toc.replaceAllMapped(pattern, (m) {
      var href = m.group(2)!;
      try {
        href = Uri.decodeFull(href);
      } catch (_) {}
      href = href.trim();
      var targetAnchor = '';
      if (href.contains('#')) {
        final parts = href.split('#');
        href = parts[0];
        targetAnchor = '#${parts[1]}';
      }
      final bkpath = _checkLink(
        fromFile: opfPath,
        href: href,

        lowerPathToOrigin: lowerPathToOrigin,
        targetAnchor: targetAnchor,
      );
      if (bkpath == null) return m.group(0)!;
      final n = rePathMap['text']![bkpath.toLowerCase()];
      if (n == null) return m.group(0)!;
      return 'src="Text/$n"$targetAnchor';
    });
  }

  /// CSS @import 重写
  String _rewriteCssImport(String css) {
    final pattern = RegExp(
      r'''@import (["'])(.*?)\1|@import url\(["']?(.*?)["']?\)''',
      dotAll: true,
    );
    return css.replaceAllMapped(pattern, (m) {
      final href = m.group(2) ?? m.group(3) ?? '';
      if (!href.toLowerCase().endsWith('.css')) return m.group(0)!;
      final filename = p.basename(href);
      return '@import "$filename"';
    });
  }

  /// CSS url() 重写
  String _rewriteCssUrl(
    String css,
    String cssPath,
    Map<String, Map<String, String>> rePathMap,
    Map<String, String> lowerPathToOrigin,
  ) {
    final pattern = RegExp(r'''(url\(["']?)(.*?)(["']?\))''', dotAll: true);
    return css.replaceAllMapped(pattern, (m) {
      var url = m.group(2)!;
      try {
        url = Uri.decodeFull(url);
      } catch (_) {}
      url = url.trim();
      final bkpath = _checkLink(
        fromFile: cssPath,
        href: url,

        lowerPathToOrigin: lowerPathToOrigin,
      );
      if (bkpath == null) return m.group(0)!;
      final lower = bkpath.toLowerCase();
      if (_endsWithAny(lower, const ['.ttf', '.otf', '.woff', '.woff2'])) {
        final n = rePathMap['font']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Fonts/$n${m.group(3)}';
      } else if (_endsWithAny(lower, const [
        '.jpg',
        '.jpeg',
        '.png',
        '.bmp',
        '.gif',
        '.webp',
        '.svg',
      ])) {
        final n = rePathMap['image']![bkpath.toLowerCase()];
        if (n == null) return m.group(0)!;
        return '${m.group(1)}../Images/$n${m.group(3)}';
      }
      return m.group(0)!;
    });
  }

  bool _endsWithAny(String s, List<String> suffixes) {
    for (final suf in suffixes) {
      if (s.endsWith(suf)) return true;
    }
    return false;
  }

  // ==================== OPF 重写 ====================

  /// 重新生成 OPF manifest（指向规范化目录）
  String _rewriteOpf({
    required XmlDocument originalOpf,
    required String opfPath,
    required List<_ItemRec> textList,
    required List<_ItemRec> cssList,
    required List<_ItemRec> imageList,
    required List<_ItemRec> fontList,
    required List<_ItemRec> audioList,
    required List<_ItemRec> videoList,
    required List<_OtherRec> otherList,
    required String tocId,
    required Map<String, Map<String, String>> rePathMap,
    required String opfDirWithSlash,
  }) {
    final manifestParts = ['<manifest>'];

    String propAttr(String prop) => prop.isEmpty ? '' : ' properties="$prop"';

    // 用完整 bkpath 小写查找，与 _autoRenameList 的 key 一致
    String bkkey(String href) =>
        _resolveBookPath(href, opfDirWithSlash).toLowerCase();

    for (final t in textList) {
      final n = rePathMap['text']![bkkey(t.href)]!;
      manifestParts.add(
        '<item id="${_xmlAttr(t.id)}" href="Text/$n" media-type="application/xhtml+xml"${propAttr(t.prop)}/>',
      );
    }
    for (final c in cssList) {
      final n = rePathMap['css']![bkkey(c.href)]!;
      manifestParts.add(
        '<item id="${_xmlAttr(c.id)}" href="Styles/$n" media-type="text/css"${propAttr(c.prop)}/>',
      );
    }
    for (final i in imageList) {
      final n = rePathMap['image']![bkkey(i.href)]!;
      manifestParts.add(
        '<item id="${_xmlAttr(i.id)}" href="Images/$n" media-type="image/${_imgSubtype(i.href)}"${propAttr(i.prop)}/>',
      );
    }
    for (final f in fontList) {
      final n = rePathMap['font']![bkkey(f.href)]!;
      final ext = p.extension(f.href).toLowerCase();
      final mime = _mimeMap[ext] ?? 'font/ttf';
      manifestParts.add(
        '<item id="${_xmlAttr(f.id)}" href="Fonts/$n" media-type="$mime"${propAttr(f.prop)}/>',
      );
    }
    for (final a in audioList) {
      final n = rePathMap['audio']![bkkey(a.href)]!;
      final ext = p.extension(a.href).toLowerCase();
      final mime = _mimeMap[ext] ?? 'audio/mpeg';
      manifestParts.add(
        '<item id="${_xmlAttr(a.id)}" href="Audio/$n" media-type="$mime"${propAttr(a.prop)}/>',
      );
    }
    for (final v in videoList) {
      final n = rePathMap['video']![bkkey(v.href)]!;
      final ext = p.extension(v.href).toLowerCase();
      final mime = _mimeMap[ext] ?? 'video/mp4';
      manifestParts.add(
        '<item id="${_xmlAttr(v.id)}" href="Video/$n" media-type="$mime"${propAttr(v.prop)}/>',
      );
    }
    if (tocId.isNotEmpty) {
      manifestParts.add(
        '<item id="${_xmlAttr(tocId)}" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
      );
    }
    for (final o in otherList) {
      final n = rePathMap['other']![bkkey(o.href)]!;
      manifestParts.add(
        '<item id="${_xmlAttr(o.id)}" href="Misc/$n" media-type="${_xmlAttr(o.mime)}"${propAttr(o.prop)}/>',
      );
    }
    manifestParts.add('</manifest>');
    final newManifest = manifestParts.join('\n  ');

    // 替换原 OPF 中的 <manifest>...</manifest>
    final original = originalOpf.toXmlString(indent: '  ');
    final replaced = original.replaceFirst(
      RegExp(r"<manifest[^>]*>.*?</manifest>", dotAll: true),
      newManifest,
    );

    // 同时修 OPF 中 <reference href=...> 路径
    final fixedRef = replaced.replaceAllMapped(
      RegExp(r'''(<reference[^>]*href=(["\']))(.*?)(\2[^>]*/>)'''),
      (m) {
        var href = m.group(3)!;
        try {
          href = Uri.decodeFull(href);
        } catch (_) {}
        href = href.trim();
        final bn = p.basename(href);
        if (bn.toLowerCase().endsWith('.ncx')) return m.group(0)!;
        return '${m.group(1)}../Text/$bn${m.group(4)}';
      },
    );

    return fixedRef;
  }

  String _imgSubtype(String href) {
    final ext = p.extension(href).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'jpeg';
      case '.svg':
        return 'svg+xml';
      default:
        return ext.substring(1); // .png -> png
    }
  }

  String _xmlAttr(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // ==================== 错误日志输出 ====================

  void _emitOpfErrors() {
    if (opfErrors.isEmpty) return;
    _log('--- OPF 结构问题 ---');
    for (final err in opfErrors) {
      switch (err.type) {
        case 'duplicate_id':
          _log('问题: manifest 节点内部存在重复 ID ${err.value}');
          _log('措施: 已自动清除重复 ID 对应的 manifest 项');
          break;
        case 'invalid_idref':
          _log('问题: spine 节点内部存在无效引用 ID ${err.value}');
          _log(
            '措施: 请自行检查 spine 内的 itemref 节点并手动修改，确保引用的 ID 存在于 manifest 的 item 项（大小写不一致也会导致引用无效）',
          );
          break;
        case 'xhtml_not_in_spine':
          _log(
            '问题: ID 为 ${err.value} 的文件 manifest 中登记为 xhtml 类型，但不被 spine 节点的项所引用',
          );
          _log(
            '措施: 自行检查该文件是否需要被 spine 引用。部分阅读器中，如果存在 xhtml 文件不被 spine 引用，可能导致 epub 无法打开',
          );
          break;
      }
    }
  }

  void _emitLinkErrors() {
    if (linkErrors.isEmpty) return;
    _log('--- 链接问题 ---');
    for (final entry in linkErrors.entries) {
      // 跳过所有链接都已纠正（correct != null）的纯大小写问题
      final allFixed = entry.value.every((e) => e.correct != null);
      if (allFixed) {
        // 仅记录有手动纠正的（用户能看到信息）
        for (final e in entry.value) {
          _log('链接 ${e.href} 大小写已自动纠正为 ${e.correct}');
        }
      } else {
        _log('在 ${p.basename(entry.key)} 中发现问题链接:');
        for (final e in entry.value) {
          if (e.correct != null) {
            _log('链接 ${e.href} 大小写不一致，已自动纠正为 ${e.correct}');
          } else {
            _log('链接 ${e.href} 未能找到对应文件！！！');
          }
        }
      }
    }
  }

  // ==================== 常量 ====================

  static final Uint8List _mimetypeBytes = Uint8List.fromList(
    utf8.encode('application/epub+zip'),
  );
}

/// manifest 内部 item 记录
/// text/css/image/font/audio/video 用此 3 元记录
typedef _ItemRec = ({String id, String href, String prop});

/// other 类型额外带 mime
typedef _OtherRec = ({String id, String href, String mime, String prop});
