import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/epub_packer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:epub_gadget/core/file_service.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';

/// 章节头图针对不同阅读器的排版样式。
enum ChapterHeaderImageStyle { yuewei, kindle }

/// 打开 EPUB 时显示在正文之前的全屏首页模板。
enum FullScreenCoverStyle { yuewei, kindle }

/// EPUB 生成器
///
/// 移植自 Python epub_creator.py，使用 archive 库直接构建 ZIP 结构。
/// 不使用 epubx 库，因为 epubx 对中文支持有问题。
///
/// 生成的 EPUB 同时兼容 EPUB2（toc.ncx）和 EPUB3（nav.xhtml）标准。
class EpubGenerator {
  EpubGenerator._();

  /// 生成 EPUB 文件
  ///
  /// 完整流程：
  /// 1. 生成 mimetype（不压缩，必须为 ZIP 中第一个文件）
  /// 2. 生成 META-INF/container.xml（指向 OPF）
  /// 3. 生成 OEBPS/content.opf（元数据、manifest、spine）
  /// 4. 生成 OEBPS/toc.ncx（EPUB2 目录）
  /// 5. 生成 OEBPS/nav.xhtml（EPUB3 导航）
  /// 6. 每章生成 OEBPS/Chapter{XXXX}.xhtml
  /// 7. 内嵌 CSS 样式（段落 text-indent:2em, 标题居中）
  /// 8. 封面图片写入 OEBPS/Images/cover.{ext}
  /// 9. 用 ZipEncoder 打包，mimetype 用 STORED（不压缩）
  ///
  /// [outputPath] 输出文件路径（应用专属目录，由调用方通过
  /// [FileService.getSafeOutputPath] 取得，确保 File API 可写）
  /// [title] 书名
  /// [author] 作者
  /// [chapters] 章节列表
  /// [coverPath] 封面图片路径（可选）
  /// [headerImagePath] 每章标题前显示的头图路径（可选）
  /// [headerImageStyle] 头图排版样式，支持阅微和 Kindle
  /// [fullScreenCoverImagePath] 全屏首页独立图片；未传入时兼容性复用 [coverPath]
  /// [fullScreenCoverStyle] 全屏首页模板；null 表示不生成
  /// [lang] 语言代码，默认 zh-CN
  ///
  /// 返回 (生成过程的日志字符串, 用户可见路径)。
  /// - 在 Android 上，会自动通过 MediaStore.Downloads 复制到公共
  ///   Download/books/，用户可见路径 = 公共路径。
  /// - 其他平台，用户可见路径 = outputPath。
  static Future<(String, String)> generate({
    required String outputPath,
    required String title,
    required String author,
    required List<Chapter> chapters,
    String? coverPath,
    String? headerImagePath,
    ChapterHeaderImageStyle headerImageStyle = ChapterHeaderImageStyle.yuewei,
    String? fullScreenCoverImagePath,
    FullScreenCoverStyle? fullScreenCoverStyle,
    String lang = 'zh-CN',
  }) async {
    final log = StringBuffer();
    final archive = Archive();

    // 确保至少有一个章节
    if (chapters.isEmpty) {
      chapters = [Chapter(title: title, content: '', level: 1)];
    }

    // 1. 生成 mimetype（不压缩，必须为第一个文件）
    final mimeBytes = utf8.encode('application/epub+zip');
    final mimeFile = ArchiveFile('mimetype', mimeBytes.length, mimeBytes);
    mimeFile.compress = false; // EPUB 规范要求 mimetype 不压缩
    archive.addFile(mimeFile);
    log.writeln('PROGRESS: 已生成 mimetype');

    // 2. 生成 META-INF/container.xml
    final containerXml = _generateContainerXml();
    _addStringFile(archive, 'META-INF/container.xml', containerXml);
    log.writeln('PROGRESS: 已生成 container.xml');

    // 3. 扁平化章节列表（深度优先），为每章分配序号
    final flatChapters = _flattenChapters(chapters);
    log.writeln('PROGRESS: 共 ${flatChapters.length} 个章节');

    // 4. 处理章节头图。选中头图后必须成功写入，避免生成引用缺失资源的 EPUB。
    String? headerImageFileName;
    String? headerImageMediaType;
    if (headerImagePath != null && headerImagePath.trim().isNotEmpty) {
      final imageInfo = _chapterHeaderImageInfo(headerImagePath);
      final headerImageBytes = await File(headerImagePath).readAsBytes();
      headerImageFileName = 'logo.${imageInfo.extension}';
      headerImageMediaType = imageInfo.mediaType;
      archive.addFile(
        ArchiveFile(
          'OEBPS/Images/$headerImageFileName',
          headerImageBytes.length,
          headerImageBytes,
        ),
      );
      log.writeln(
        'PROGRESS: 已添加${headerImageStyle == ChapterHeaderImageStyle.yuewei ? '阅微' : 'Kindle'}章节头图 ($headerImageFileName)',
      );
    }

    // 5. 使用独立图片生成可选的全屏首页资源。
    String? fullScreenCoverImageHref;
    if (fullScreenCoverStyle != null) {
      final sourceImagePath =
          fullScreenCoverImagePath?.trim().isNotEmpty == true
          ? fullScreenCoverImagePath!.trim()
          : coverPath?.trim();
      if (sourceImagePath == null || sourceImagePath.isEmpty) {
        throw const FormatException('添加全屏首页前请先选择首页图片');
      }
      final prepared = await _prepareFullScreenCoverImage(
        sourceImagePath,
        fullScreenCoverStyle,
      );
      if (fullScreenCoverStyle == FullScreenCoverStyle.yuewei) {
        archive.addFile(
          ArchiveFile('cover~slim.png', prepared.bytes.length, prepared.bytes),
        );
        fullScreenCoverImageHref = '../cover~slim.png';
      } else {
        archive.addFile(
          ArchiveFile(
            'OEBPS/Images/fullscreen-cover.png',
            prepared.bytes.length,
            prepared.bytes,
          ),
        );
        fullScreenCoverImageHref = 'Images/fullscreen-cover.png';
      }
      _addStringFile(
        archive,
        'OEBPS/Styles/main.css',
        _generateFullScreenCoverCss(fullScreenCoverStyle),
      );
      _addStringFile(
        archive,
        'OEBPS/Text/fullscreen-cover.xhtml',
        _generateFullScreenCoverXhtml(fullScreenCoverStyle),
      );
      log.writeln(
        'PROGRESS: 已添加${fullScreenCoverStyle == FullScreenCoverStyle.yuewei ? '阅微' : 'Kindle'}全屏首页（${prepared.width}×${prepared.height}）',
      );
    }

    // 6. 生成 CSS 样式文件
    final cssContent = _generateCss(
      headerImageStyle: headerImageFileName == null ? null : headerImageStyle,
    );
    _addStringFile(archive, 'OEBPS/style.css', cssContent);

    // 7. 处理封面图片
    String? coverExt;
    String? coverMediaType;
    bool hasCover = false;
    if (coverPath != null && coverPath.isNotEmpty) {
      try {
        final coverBytes = await File(coverPath).readAsBytes();
        coverExt = coverPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        coverMediaType = coverExt == 'png' ? 'image/png' : 'image/jpeg';
        final coverArchivePath = 'OEBPS/Images/cover.$coverExt';
        if (archive.findFile(coverArchivePath) == null) {
          archive.addFile(
            ArchiveFile(coverArchivePath, coverBytes.length, coverBytes),
          );
        }
        hasCover = true;
        log.writeln('PROGRESS: 已添加封面图片 (cover.$coverExt)');
      } catch (e) {
        log.writeln('WARNING: 封面图片读取失败: $e');
      }
    }

    // 8. 生成封面页 XHTML（如果有封面）
    if (hasCover) {
      final coverXhtml = _generateCoverXhtml(coverExt!);
      _addStringFile(archive, 'OEBPS/cover.xhtml', coverXhtml);
    }

    // 9. 生成每章的 XHTML 文件
    for (var i = 0; i < flatChapters.length; i++) {
      final chapter = flatChapters[i];
      final fileName = _chapterFileName(i);
      final xhtml = _generateChapterXhtml(
        chapter,
        headerImageFileName: headerImageFileName,
      );
      _addStringFile(archive, 'OEBPS/$fileName', xhtml);
    }
    log.writeln('PROGRESS: 已生成 ${flatChapters.length} 个章节文件');

    // 10. 生成 content.opf（元数据、manifest、spine）
    final bookId = _generateBookId(title);
    final opf = _generateOpf(
      title: title,
      author: author,
      lang: lang,
      bookId: bookId,
      flatChapters: flatChapters,
      hasCover: hasCover,
      coverExt: coverExt,
      coverMediaType: coverMediaType,
      headerImageFileName: headerImageFileName,
      headerImageMediaType: headerImageMediaType,
      fullScreenCoverStyle: fullScreenCoverStyle,
      fullScreenCoverImageHref: fullScreenCoverImageHref,
    );
    _addStringFile(archive, 'OEBPS/content.opf', opf);
    log.writeln('PROGRESS: 已生成 content.opf');

    // 11. 生成 toc.ncx（EPUB2 目录）
    final ncx = _generateNcx(title: title, bookId: bookId, chapters: chapters);
    _addStringFile(archive, 'OEBPS/toc.ncx', ncx);
    log.writeln('PROGRESS: 已生成 toc.ncx');

    // 12. 生成 nav.xhtml（EPUB3 导航）
    final nav = _generateNav(chapters);
    _addStringFile(archive, 'OEBPS/nav.xhtml', nav);
    log.writeln('PROGRESS: 已生成 nav.xhtml');

    // 13. 写入 EPUB。统一走 EpubPacker，确保阅读器可导入的 OCF ZIP 结构。
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
    final fileSize = await File(outputPath).length();
    log.writeln(
      'PROGRESS: EPUB 打包完成（${(fileSize / 1024).toStringAsFixed(1)} KB）',
    );

    // 14. 复制到用户可见位置
    // - 在 Android 上：先写到 outputPath（应用专属目录，File API 可写），
    //   然后通过 MediaStore.Downloads 复制到公共 Download/books/，
    //   返回用户可见的公共路径。这是 Android 11+ Scoped Storage 唯一
    //   合法的方式（无需 WRITE_EXTERNAL_STORAGE 权限）。
    // - 其他平台：直接写到 outputPath。
    String userVisiblePath = outputPath;
    log.writeln('PROGRESS: 已写入 $outputPath');

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final filename = outputPath.split(Platform.pathSeparator).last;
        // 优先走流式：避免 Dart 堆里再 copy 一份 epubBytes。
        // Uint8List.fromList 会复制整个数组，47MB → 47MB 浪费一倍内存。
        // MethodChannel 传递时还会再复制一次，所以 47MB 文件峰值接近 200MB。
        // 流式：原生直接从 outputPath 读磁盘写 MediaStore，Dart 零开销。
        if (fileSize > 10 * 1024 * 1024) {
          userVisiblePath = await FileService.copyFileToPublicDownload(
            sourcePath: outputPath,
            filename: filename,
          );
          log.writeln(
            'PROGRESS: 大文件（${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB）已流式复制到公共 Download: $userVisiblePath',
          );
        } else {
          final epubBytes = await File(outputPath).readAsBytes();
          userVisiblePath = await FileService.writeToPublicDownload(
            filename: filename,
            bytes: epubBytes,
          );
          log.writeln('PROGRESS: 已复制到公共 Download: $userVisiblePath');
        }

        // 复制成功后删除应用专属目录的临时副本，
        // 避免 /Android/data/.../files/books/ 里堆满重复文件。
        // 失败不影响主流程（公共 Download 已有副本）。
        try {
          final tempFile = File(outputPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
            log.writeln('PROGRESS: 已清理临时文件: $outputPath');
          }
        } catch (e) {
          log.writeln('WARN: 清理临时文件失败：$e');
        }
      } catch (e) {
        log.writeln('WARN: 复制到公共 Download 失败：$e（文件已保存到应用专属目录 $outputPath）');
      }
    }

    log.writeln('PROGRESS: EPUB 生成完成，已保存到 $userVisiblePath');

    return (log.toString(), userVisiblePath);
  }

  /// 生成 META-INF/container.xml
  ///
  /// 指向 OEBPS/content.opf 作为根文件。
  static String _generateContainerXml() {
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
        '  </rootfiles>\n'
        '</container>';
  }

  /// 生成 CSS 样式
  ///
  /// 段落首行缩进 2em；标题居中；封面图片自适应宽度。
  /// 不注入全局 body 边距、字体或行高，由阅读器和用户设置决定。
  static String _generateCss({ChapterHeaderImageStyle? headerImageStyle}) {
    final css = StringBuffer()
      ..write(
        'p {\n'
        '  text-indent: 2em;\n'
        '  margin: 0;\n'
        '  padding: 0;\n'
        '}\n'
        'h1, h2, h3, h4, h5, h6 {\n'
        '  text-align: center;\n'
        '  margin: 1em 0;\n'
        '}\n'
        '.cover {\n'
        '  text-align: center;\n'
        '  margin: 0;\n'
        '  padding: 0;\n'
        '}\n'
        '.cover img {\n'
        '  max-width: 100%;\n'
        '  height: auto;\n'
        '}\n',
      );

    if (headerImageStyle == ChapterHeaderImageStyle.yuewei) {
      css.write(
        'div {\n'
        '  margin: 0;\n'
        '}\n'
        '.logo {\n'
        '  text-align: center;\n'
        '  text-indent: 0;\n'
        '  duokan-text-indent: 0;\n'
        '  duokan-bleed: lefttopright;\n'
        '}\n'
        '.logo .responsive-image {\n'
        '  width: 100%;\n'
        '}\n',
      );
    } else if (headerImageStyle == ChapterHeaderImageStyle.kindle) {
      css.write(
        'div {\n'
        '  margin: 0;\n'
        '}\n'
        'div.logo {\n'
        '  width: 122%;\n'
        '  margin: -8% -11% 0;\n'
        '  max-width: none;\n'
        '  text-align: center;\n'
        '}\n'
        'img.responsive-image {\n'
        '  width: 100%;\n'
        '  height: auto;\n'
        '  display: block;\n'
        '}\n',
      );
    }

    return css.toString();
  }

  static ({String extension, String mediaType}) _chapterHeaderImageInfo(
    String path,
  ) {
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return switch (extension) {
      'png' => (extension: 'png', mediaType: 'image/png'),
      'jpg' || 'jpeg' => (extension: 'jpg', mediaType: 'image/jpeg'),
      _ => throw const FormatException('章节头图仅支持 PNG、JPG 或 JPEG 图片'),
    };
  }

  static Future<({Uint8List bytes, int width, int height})>
  _prepareFullScreenCoverImage(String path, FullScreenCoverStyle style) async {
    final sourceBytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('无法读取全屏首页图片');
    }
    final requiredWidth = style == FullScreenCoverStyle.yuewei ? 1080 : 1536;
    final requiredHeight = style == FullScreenCoverStyle.yuewei ? 2400 : 2048;
    if (decoded.width != requiredWidth || decoded.height != requiredHeight) {
      final name = style == FullScreenCoverStyle.yuewei ? '阅微' : 'Kindle';
      throw FormatException(
        '$name 全屏首页图片必须为 $requiredWidth×$requiredHeight，'
        '当前为 ${decoded.width}×${decoded.height}',
      );
    }
    final isPng = p.extension(path).toLowerCase() == '.png';
    return (
      bytes: isPng
          ? sourceBytes
          : Uint8List.fromList(img.encodePng(decoded, level: 9)),
      width: decoded.width,
      height: decoded.height,
    );
  }

  static String _generateFullScreenCoverXhtml(FullScreenCoverStyle style) {
    final body = style == FullScreenCoverStyle.yuewei
        ? '  <body class="cover-page">\n'
              '    <div class="fm">\n'
              '      <p>&#160;</p>\n'
              '    </div>\n'
              '    <h2 class="none">封面</h2>\n'
              '  </body>\n'
        : '  <body class="epub-cover">\n'
              '    <div class="cover-image-container">\n'
              '      <img alt="cover" src="../Images/fullscreen-cover.png"/>\n'
              '    </div>\n'
              '  </body>\n';
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head>\n'
        '  <title>封面</title>\n'
        '  <style>\n'
        '    html, body {\n'
        '      height: 100%;\n'
        '      margin: 0;\n'
        '      padding: 0;\n'
        '      overflow: hidden;\n'
        '    }\n'
        '  </style>\n'
        '  <link href="../Styles/main.css" type="text/css" rel="stylesheet"/>\n'
        '</head>\n'
        '$body'
        '</html>';
  }

  static String _generateFullScreenCoverCss(FullScreenCoverStyle style) {
    if (style == FullScreenCoverStyle.yuewei) {
      return '/* ===== 封面页样式 ==== */\n'
          '.cover-page {\n'
          '  background-image: url("../../cover~slim.png");\n'
          '  background-repeat: no-repeat;\n'
          '  background-size: cover;\n'
          '  background-position: center;\n'
          '  width: 100%;\n'
          '  min-height: 100%;\n'
          '  display: block;\n'
          '  margin: 0;\n'
          '  padding: 0;\n'
          '}\n'
          '.fm p {\n'
          '  color: rgba(255, 255, 255, 0);\n'
          '}\n'
          '.none {\n'
          '  display: none;\n'
          '}\n';
    }
    return 'body.epub-cover {\n'
        '  margin: 0;\n'
        '  padding: 0;\n'
        '  text-align: center;\n'
        '  background-color: #000;\n'
        '}\n'
        'body.epub-cover .cover-image-container {\n'
        '  display: block;\n'
        '  width: 100%;\n'
        '  height: 100vh;\n'
        '  display: flex;\n'
        '  justify-content: center;\n'
        '  align-items: center;\n'
        '}\n'
        'body.epub-cover .cover-image-container img {\n'
        '  max-width: 100%;\n'
        '  max-height: 95vh;\n'
        '  height: auto;\n'
        '  width: auto;\n'
        '  margin: auto;\n'
        '  display: block;\n'
        '}\n';
  }

  /// 生成封面页 XHTML
  ///
  /// [coverExt] 封面图片扩展名（jpg 或 png）
  static String _generateCoverXhtml(String coverExt) {
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head>\n'
        '  <title>封面</title>\n'
        '  <link rel="stylesheet" type="text/css" href="style.css"/>\n'
        '</head>\n'
        '<body>\n'
        '  <div class="cover">\n'
        '    <img src="Images/cover.$coverExt" alt="封面"/>\n'
        '  </div>\n'
        '</body>\n'
        '</html>';
  }

  /// 生成章节 XHTML 文件
  ///
  /// 标题使用 h{level} 标签，正文按段落分割为 <p> 标签。
  ///
  /// **去重处理**：当正文首行（或首段）与标题相同时，跳过该行，
  /// 避免 EPUB 顶部 <h1> 与正文首行重复显示同一标题。
  /// （常见于 splitTitle=false 模式：用户希望"保留标题在正文"，
  /// 但 EPUB 渲染时标题已由 <h1> 单独展示，正文中保留会导致重复。）
  ///
  /// [chapter] 章节数据
  static String _generateChapterXhtml(
    Chapter chapter, {
    String? headerImageFileName,
  }) {
    final title = _escapeXml(chapter.title);
    // 标题层级限制在 1-6 之间（h1-h6）
    final level = chapter.level.clamp(1, 6);
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
    sb.writeln('<head>');
    sb.writeln('  <title>$title</title>');
    sb.writeln('  <link rel="stylesheet" type="text/css" href="style.css"/>');
    sb.writeln('</head>');
    sb.writeln('<body>');
    if (headerImageFileName != null) {
      sb.writeln('  <div class="logo">');
      sb.writeln(
        '    <img class="responsive-image" alt="logo" src="Images/$headerImageFileName"/>',
      );
      sb.writeln('  </div>');
    }
    sb.writeln('  <h$level>$title</h$level>');

    // 将正文按换行分割为段落
    if (chapter.content.isNotEmpty) {
      final paragraphs = chapter.content.split('\n');
      final inlineHeadingLevels = {
        for (final heading in chapter.inlineHeadings)
          heading.lineIndex: heading.level.clamp(1, 6),
      };
      // 比较用：标题去除所有空白后的形式
      final titleCompact = title.replaceAll(RegExp(r'\s+'), '');
      var skippedFirst = false;

      for (var lineIndex = 0; lineIndex < paragraphs.length; lineIndex++) {
        final para = paragraphs[lineIndex];
        final trimmed = para.trim();
        if (trimmed.isEmpty) continue;

        // 正文首段与标题完全相同：跳过（避免 <h1> 与首段重复）
        if (!skippedFirst) {
          final trimmedCompact = trimmed.replaceAll(RegExp(r'\s+'), '');
          if (trimmedCompact == titleCompact) {
            skippedFirst = true;
            continue;
          }
          skippedFirst = true;
        }

        final inlineLevel = inlineHeadingLevels[lineIndex];
        if (inlineLevel != null) {
          sb.writeln('  <h$inlineLevel>${_escapeXml(trimmed)}</h$inlineLevel>');
        } else {
          sb.writeln('  <p>${_escapeXml(trimmed)}</p>');
        }
      }
    }

    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  /// 生成 content.opf（OPF 包文件）
  ///
  /// 包含 metadata（书名、作者、语言、标识符）、manifest（所有文件清单）、spine（阅读顺序）。
  static String _generateOpf({
    required String title,
    required String author,
    required String lang,
    required String bookId,
    required List<Chapter> flatChapters,
    required bool hasCover,
    String? coverExt,
    String? coverMediaType,
    String? headerImageFileName,
    String? headerImageMediaType,
    FullScreenCoverStyle? fullScreenCoverStyle,
    String? fullScreenCoverImageHref,
  }) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">',
    );

    // metadata
    sb.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"');
    sb.writeln('           xmlns:opf="http://www.idpf.org/2007/opf">');
    sb.writeln('    <dc:title>${_escapeXml(title)}</dc:title>');
    sb.writeln('    <dc:creator>${_escapeXml(author)}</dc:creator>');
    sb.writeln('    <dc:language>$lang</dc:language>');
    sb.writeln('    <dc:identifier id="bookid">$bookId</dc:identifier>');
    if (hasCover && coverExt != null && coverMediaType != null) {
      sb.writeln('    <meta name="cover" content="cover-image"/>');
    }
    sb.writeln('  </metadata>');

    // manifest
    sb.writeln('  <manifest>');
    sb.writeln(
      '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    );
    sb.writeln(
      '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    );
    sb.writeln('    <item id="css" href="style.css" media-type="text/css"/>');
    if (hasCover && coverExt != null && coverMediaType != null) {
      sb.writeln(
        '    <item id="cover-image" href="Images/cover.$coverExt" media-type="$coverMediaType" properties="cover-image"/>',
      );
      sb.writeln(
        '    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>',
      );
    }
    if (headerImageFileName != null && headerImageMediaType != null) {
      sb.writeln(
        '    <item id="chapter-header-image" href="Images/$headerImageFileName" media-type="$headerImageMediaType"/>',
      );
    }
    if (fullScreenCoverStyle != null && fullScreenCoverImageHref != null) {
      sb.writeln(
        '    <item id="fullscreen-cover" href="Text/fullscreen-cover.xhtml" media-type="application/xhtml+xml"/>',
      );
      sb.writeln(
        '    <item id="fullscreen-cover-css" href="Styles/main.css" media-type="text/css"/>',
      );
      sb.writeln(
        '    <item id="fullscreen-cover-image" href="$fullScreenCoverImageHref" media-type="image/png"/>',
      );
    }
    for (var i = 0; i < flatChapters.length; i++) {
      final fileName = _chapterFileName(i);
      final itemId = _chapterItemId(i);
      sb.writeln(
        '    <item id="$itemId" href="$fileName" media-type="application/xhtml+xml"/>',
      );
    }
    sb.writeln('  </manifest>');

    // spine
    sb.writeln('  <spine toc="ncx">');
    if (fullScreenCoverStyle != null) {
      sb.writeln('    <itemref idref="fullscreen-cover"/>');
    }
    if (hasCover) {
      sb.writeln('    <itemref idref="cover" linear="no"/>');
    }
    for (var i = 0; i < flatChapters.length; i++) {
      final itemId = _chapterItemId(i);
      sb.writeln('    <itemref idref="$itemId"/>');
    }
    sb.writeln('  </spine>');

    sb.writeln('</package>');
    return sb.toString();
  }

  /// 生成 toc.ncx（EPUB2 目录）
  ///
  /// 保留章节层级结构，使用嵌套 navPoint。
  static String _generateNcx({
    required String title,
    required String bookId,
    required List<Chapter> chapters,
  }) {
    final counter = _IndexCounter();
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
    );
    sb.writeln('  <head>');
    sb.writeln('    <meta name="dtb:uid" content="$bookId"/>');
    sb.writeln('  </head>');
    sb.writeln('  <docTitle><text>${_escapeXml(title)}</text></docTitle>');
    sb.writeln('  <navMap>');
    sb.write(_buildNcxNavPoints(chapters, counter));
    sb.writeln('  </navMap>');
    sb.writeln('</ncx>');
    return sb.toString();
  }

  /// 递归构建 NCX navPoint 列表
  ///
  /// [chapters] 当前层级的章节列表
  /// [counter] 全局序号计数器（深度优先递增）
  static String _buildNcxNavPoints(
    List<Chapter> chapters,
    _IndexCounter counter,
  ) {
    final sb = StringBuffer();
    for (final chapter in chapters) {
      final idx = counter.value;
      counter.value++;
      final chapterFile = _chapterFileName(idx);
      sb.writeln('    <navPoint id="nav${idx + 1}" playOrder="${idx + 1}">');
      sb.writeln(
        '      <navLabel><text>${_escapeXml(chapter.title)}</text></navLabel>',
      );
      sb.writeln('      <content src="$chapterFile"/>');
      if (chapter.children.isNotEmpty) {
        sb.write(_buildNcxNavPoints(chapter.children, counter));
      }
      sb.writeln('    </navPoint>');
    }
    return sb.toString();
  }

  /// 生成 nav.xhtml（EPUB3 导航文档）
  ///
  /// 保留章节层级结构，使用嵌套 <ol> 列表。
  static String _generateNav(List<Chapter> chapters) {
    final counter = _IndexCounter();
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">',
    );
    sb.writeln('<head>');
    sb.writeln('  <title>目录</title>');
    sb.writeln('  <link rel="stylesheet" type="text/css" href="style.css"/>');
    sb.writeln('</head>');
    sb.writeln('<body>');
    sb.writeln('  <nav epub:type="toc">');
    sb.writeln('    <h1>目录</h1>');
    sb.write(_buildNavList(chapters, counter));
    sb.writeln('  </nav>');
    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  /// 递归构建导航列表（<ol><li> 结构）
  ///
  /// [chapters] 当前层级的章节列表
  /// [counter] 全局序号计数器（深度优先递增）
  static String _buildNavList(List<Chapter> chapters, _IndexCounter counter) {
    final sb = StringBuffer();
    sb.writeln('    <ol>');
    for (final chapter in chapters) {
      final idx = counter.value;
      counter.value++;
      final chapterFile = _chapterFileName(idx);
      sb.writeln('      <li>');
      sb.writeln(
        '        <a href="$chapterFile">${_escapeXml(chapter.title)}</a>',
      );
      if (chapter.children.isNotEmpty) {
        sb.write(_buildNavList(chapter.children, counter));
      }
      sb.writeln('      </li>');
    }
    sb.writeln('    </ol>');
    return sb.toString();
  }

  /// 扁平化章节列表（深度优先遍历）
  ///
  /// 将嵌套的章节结构展开为扁平列表，用于生成 XHTML 文件和 manifest/spine。
  /// 遍历顺序：父节点 → 子节点（深度优先）。
  ///
  /// [chapters] 嵌套的章节列表
  /// 返回扁平化的章节列表
  static List<Chapter> _flattenChapters(List<Chapter> chapters) {
    final result = <Chapter>[];
    void flatten(List<Chapter> chs) {
      for (final ch in chs) {
        result.add(ch);
        if (ch.children.isNotEmpty) {
          flatten(ch.children);
        }
      }
    }

    flatten(chapters);
    return result;
  }

  /// 生成章节文件名
  ///
  /// [index] 章节序号（从 0 开始）
  /// 返回如 "Chapter0001.xhtml"
  static String _chapterFileName(int index) {
    return 'Chapter${(index + 1).toString().padLeft(4, '0')}.xhtml';
  }

  /// 生成章节 manifest item id
  ///
  /// [index] 章节序号（从 0 开始）
  /// 返回如 "chapter1"
  static String _chapterItemId(int index) {
    return 'chapter${index + 1}';
  }

  /// 生成唯一标识符（UUID 格式）
  ///
  /// 使用 MD5 哈希生成 UUID，确保 EPUB 标识符唯一。
  ///
  /// [title] 书名（用于增加随机性）
  static String _generateBookId(String title) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('epub-$title-$now'));
    final hex = hash.toString();
    // 格式化为标准 UUID：xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// XML/HTML 特殊字符转义
  ///
  /// 转义 &、<、>、"、' 五个特殊字符，确保内容可安全嵌入 XML。
  ///
  /// [text] 待转义的文本
  /// 返回转义后的文本
  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 将字符串以 UTF-8 编码添加到 Archive 中
  ///
  /// [archive] 目标 Archive
  /// [name] 文件路径
  /// [content] 文件内容字符串
  static void _addStringFile(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, Uint8List.fromList(bytes)));
  }
}

/// 序号计数器（用于递归遍历时分配全局序号）
class _IndexCounter {
  int value = 0;
}
