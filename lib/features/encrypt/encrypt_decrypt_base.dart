import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';

/// Manifest 条目信息
class ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  ManifestItem(this.id, this.href, this.mediaType);
}

/// EPUB 加密/解密共享基类
///
/// 提供 OPF manifest 解析、加密检测、掌阅 DRM 检测、
/// 文件名映射、引用重写和 EPUB 目录重构等通用功能。
///
/// 加密原理：将 manifest item 的文件名通过 MD5 哈希转换为
/// 含 `*` 和 `:` 的混淆字符串，使编辑器无法打开修改。
/// 解密原理：用 manifest item 的原始 id 还原可读文件名。
class EncryptDecryptBase {
  EncryptDecryptBase._();

  /// Windows 非法文件名字符 + Flutter 加密混淆字符（用于检测是否已加密）
  static final _illegalChars = RegExp(r'[\\/:*?"<>|*]');

  /// 掌阅 DRM 标识
  static const zhangyueDrm = 'zhangyue_drm';

  /// 已加密标识
  static const encrypted = 'encrypted';

  /// 未加密标识
  static const notEncrypted = 'not_encrypted';

  /// 解析 OPF manifest，提取所有 item 的 id/href/media-type
  ///
  /// [opfContent] OPF 文件 XML 内容
  static List<ManifestItem> parseManifest(String opfContent) {
    final items = <ManifestItem>[];
    try {
      final document = xml.XmlDocument.parse(opfContent);
      for (final item in document.findAllElements('item', namespace: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (id.isNotEmpty && href.isNotEmpty) {
          items.add(ManifestItem(id, href, mediaType));
        }
      }
    } catch (_) {
      // OPF 解析失败，返回空列表
    }
    return items;
  }

  /// 检测 EPUB 是否已被名称混淆加密
  ///
  /// 扫描 manifest 中所有 href，若文件名部分含
  ///非法字符（* : 等）则判定为已加密
  static bool isEncrypted(String opfContent) {
    final items = parseManifest(opfContent);
    for (final item in items) {
      final basename = p.basename(item.href);
      if (_illegalChars.hasMatch(basename)) {
        return true;
      }
    }
    return false;
  }

  /// 检测掌阅 DRM
  ///
  /// 检查 META-INF/encryption.xml 中是否含 "zhangyue" 字样
  static bool checkZhangyueDrm(Archive archive) {
    final encFile = archive.findFile('META-INF/encryption.xml');
    if (encFile == null) return false;
    try {
      final content = utf8.decode(encFile.content as List<int>);
      return content.toLowerCase().contains('zhangyue');
    } catch (_) {
      return false;
    }
  }

  /// 生成加密混淆文件名
  ///
  /// 将 manifest item 的 id 通过 MD5 哈希转为二进制字符串，
  /// 再将 1 替换为 *、0 替换为 :，形成混淆文件名。
  ///
  /// [id] manifest item 的 id
  /// [href] 原始 href（用于提取扩展名和 slim 后缀）
  static String obfuscateName(String id, String href) {
    final ext = p.extension(href).toLowerCase();

    // 检查多看 slim 后缀
    var slim = '';
    if (href.toLowerCase().contains('~slim')) {
      slim = '~slim';
    }

    // MD5 哈希 → 大整数 → 二进制字符串
    final hashBytes = md5.convert(utf8.encode(id)).bytes;
    var bigInt = BigInt.zero;
    for (final byte in hashBytes) {
      bigInt = (bigInt << 8) | BigInt.from(byte);
    }

    // 转为二进制字符串（Dart 的 toRadixString(2) 无 0b 前缀）
    var binStr = bigInt.toRadixString(2);

    // 字符替换：1 → *, 0 → :
    binStr = binStr.replaceAll('1', '*').replaceAll('0', ':');

    return '_$binStr$slim$ext';
  }

  /// 生成解密还原文件名
  ///
  /// 使用 manifest item 的原始 id 作为文件名。
  /// 若 id 含非法字符，用 MD5 hex 摘要兜底。
  ///
  /// [id] manifest item 的 id
  /// [href] 加密后的 href（用于提取扩展名和 slim 后缀）
  static String deobfuscateName(String id, String href) {
    final ext = p.extension(href).toLowerCase();

    // 检查多看 slim 后缀
    var slim = '';
    if (href.toLowerCase().contains('~slim')) {
      slim = '~slim';
    }

    // 若 id 含非法字符，用 MD5 hex 兜底
    var idName = id;
    if (_illegalChars.hasMatch(idName)) {
      idName = md5.convert(utf8.encode(idName)).toString();
    }

    // 若 id 含点号（如 "x.y"），取最后一部分作为扩展名
    if (id.contains('.')) {
      final parts = id.split('.');
      final idExt = '.${parts.last.toLowerCase()}';
      // 如果 id 自带合法扩展名，直接用 id 作为文件名
      if (_isValidExt(idExt)) {
        return '$idName$slim';
      }
    }

    return '$idName$slim$ext';
  }

  /// 判断是否为合法文件扩展名
  static bool _isValidExt(String ext) {
    const validExts = [
      '.html',
      '.xhtml',
      '.htm',
      '.css',
      '.js',
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.svg',
      '.webp',
      '.bmp',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.mp4',
      '.wav',
      '.ogg',
      '.ncx',
      '.opf',
      '.xml',
      '.txt',
    ];
    return validExts.contains(ext.toLowerCase());
  }

  /// 根据文件类型推断目标目录
  ///
  /// 加密/解密时将文件重组织到标准化目录结构
  static String targetDir(String fileName, String mediaType) {
    final ext = p.extension(fileName).toLowerCase();
    final lowerName = fileName.toLowerCase();

    // mimetype 和 META-INF 保持原位
    if (lowerName == 'mimetype' || lowerName.startsWith('meta-inf/')) {
      return '';
    }

    // OPF 和 NCX 放在 OEBPS 根目录
    if (ext == '.opf' || ext == '.ncx') {
      return 'OEBPS/';
    }

    // HTML/XHTML
    if (['.html', '.xhtml', '.htm'].contains(ext) ||
        mediaType.contains('html')) {
      return 'OEBPS/Text/';
    }

    // CSS
    if (ext == '.css' || mediaType.contains('css')) {
      return 'OEBPS/Styles/';
    }

    // 图片
    if ([
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.svg',
          '.webp',
          '.bmp',
        ].contains(ext) ||
        mediaType.startsWith('image/')) {
      return 'OEBPS/Images/';
    }

    // 字体
    if (['.ttf', '.otf', '.woff', '.woff2'].contains(ext) ||
        mediaType.contains('font')) {
      return 'OEBPS/Fonts/';
    }

    // 音频
    if (['.mp3', '.wav', '.ogg', '.aac'].contains(ext) ||
        mediaType.startsWith('audio/')) {
      return 'OEBPS/Audio/';
    }

    // 视频
    if (['.mp4', '.webm', '.avi'].contains(ext) ||
        mediaType.startsWith('video/')) {
      return 'OEBPS/Video/';
    }

    // JS
    if (ext == '.js') {
      return 'OEBPS/Misc/';
    }

    return 'OEBPS/Misc/';
  }

  /// 构建 href 映射表
  ///
  /// [items] manifest 条目列表
  /// [mode] 'encrypt' 或 'decrypt'
  ///
  /// 返回 旧href → 新href 的映射
  static Map<String, String> buildHrefMap(
    List<ManifestItem> items,
    String mode,
  ) {
    final hrefMap = <String, String>{};

    for (final item in items) {
      String newBasename;
      if (mode == 'encrypt') {
        newBasename = obfuscateName(item.id, item.href);
      } else {
        newBasename = deobfuscateName(item.id, item.href);
      }

      // 保持相对路径结构，仅替换文件名
      final oldBasename = p.basename(item.href);
      final dir = p.dirname(item.href);
      if (dir != '.' && dir.isNotEmpty) {
        hrefMap[item.href] = '$dir/$newBasename';
      } else {
        hrefMap[oldBasename] = newBasename;
      }
      // 同时映射 basename
      hrefMap[oldBasename] = newBasename;
    }

    return hrefMap;
  }

  /// 重写 EPUB 中所有文件的引用
  ///
  /// [archive] EPUB Archive 对象
  /// [hrefMap] 旧文件名 → 新文件名映射
  /// [opfPath] OPF 文件路径
  static void rewriteReferences(
    Archive archive,
    Map<String, String> hrefMap,
    String opfPath,
  ) {
    // 快照文件列表，避免遍历中 addOrReplaceFile 修改列表导致并发异常
    var workingArchive = archive;
    for (final file in archive.files.toList()) {
      if (file.name.isEmpty) continue;
      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.html') &&
          !lowerName.endsWith('.xhtml') &&
          !lowerName.endsWith('.htm') &&
          !lowerName.endsWith('.css') &&
          !lowerName.endsWith('.ncx') &&
          !lowerName.endsWith('.opf')) {
        continue;
      }

      var content = utf8.decode(file.content as List<int>);
      var modified = false;

      // 替换所有 href 引用
      // 注意：不能用简单的 String.replaceAll，因为会误伤正文文本、JS 字符串
      // 字面量、CSS class 名等。这里用正则只匹配 href/xlink:href/src/url/manifest
      // 等 URL 引用属性中的值。
      for (final entry in hrefMap.entries) {
        final oldName = entry.key;
        final newName = entry.value;

        // 取 basename（hrefMap key 是 basename，匹配时也用 basename 避免误伤）
        final oldBase = _basename(oldName);
        final newBase = _basename(newName);
        if (oldBase.isEmpty || newBase.isEmpty) continue;
        if (oldBase == newBase) continue; // 无变化

        // 匹配 URL 引用属性中的 basename：href="..." / xlink:href="..." / src="..." / url("...")
        // 以及 CSS @font-face / background / list-style 等 url()
        // 模式：(attr)=(["'])(.../)?oldBase\2
        final oldBaseEscaped = RegExp.escape(oldBase);
        final patterns = <RegExp>[
          // href="...old" / xlink:href="...old" / src="...old"
          RegExp(
            '(\\b(?:href|xlink:href|src)\\s*=\\s*["\'])([^"\']*?)'
            '$oldBaseEscaped'
            '(["\'])',
            caseSensitive: false,
          ),
          // CSS url(...old...) — 形式 url("...old") 或 url('...old') 或 url(...old)
          RegExp(
            '(url\\s*\\(\\s*["\']?)([^"\')\\s]*?)'
            '$oldBaseEscaped'
            '(["\']?\\s*\\))',
            caseSensitive: false,
          ),
          // CSS @import "..." 或 @import url(...)
          RegExp(
            '(@import\\s+["\'])([^"\']*?)'
            '$oldBaseEscaped'
            '(["\'])',
            caseSensitive: false,
          ),
        ];

        for (final pattern in patterns) {
          // 替换时保留属性包裹部分（$1）和旧文件名前的相对路径
          final replaced = content.replaceAllMapped(pattern, (m) {
            final prefix = m.group(1)!;
            final before = m.group(2) ?? '';
            final suffix = m.group(3)!;
            return '$prefix$before$newBase$suffix';
          });
          if (replaced != content) {
            content = replaced;
            modified = true;
          }
        }

        // URL 编码的情况（对每个 URL 编码变体单独处理）
        final encoded = Uri.encodeComponent(oldBase);
        if (encoded != oldBase) {
          final newEncoded = Uri.encodeComponent(newBase);
          final encodedEscaped = RegExp.escape(encoded);
          final encodedPatterns = <RegExp>[
            // href="...old" / xlink:href="...old" / src="...old" (URL 编码)
            RegExp(
              '(\\b(?:href|xlink:href|src)\\s*=\\s*["\'])([^"\']*?)'
              '$encodedEscaped'
              '(["\'])',
              caseSensitive: false,
            ),
            // CSS url(...old...) (URL 编码)
            RegExp(
              '(url\\s*\\(\\s*["\']?)([^"\')\\s]*?)'
              '$encodedEscaped'
              '(["\']?\\s*\\))',
              caseSensitive: false,
            ),
            // CSS @import "..." 或 @import url(...) (URL 编码)
            RegExp(
              '(@import\\s+["\'])([^"\']*?)'
              '$encodedEscaped'
              '(["\'])',
              caseSensitive: false,
            ),
          ];
          for (final encodedPattern in encodedPatterns) {
            final replaced = content.replaceAllMapped(encodedPattern, (m) {
              final prefix = m.group(1)!;
              final before = m.group(2) ?? '';
              final suffix = m.group(3)!;
              return '$prefix$before$newEncoded$suffix';
            });
            if (replaced != content) {
              content = replaced;
              modified = true;
            }
          }
        }
      }

      if (modified) {
        final bytes = utf8.encode(content);
        workingArchive = EpubImageHelper.addOrReplaceFileSafe(
          workingArchive,
          ArchiveFile(file.name, bytes.length, bytes),
        );
      }
    }

    // 如果中途 archive 被重建，需要把重建后的状态写回原 archive。
    // 注意：addOrReplaceFileSafe 返回的可能是新 archive，调用方应使用返回值。
    // 但本方法签名为 void，调用方在外部持有原 archive 引用。
    // 这里通过全局副作用把 workingArchive 状态同步回原 archive。
    if (!identical(workingArchive, archive)) {
      _syncArchiveState(archive, workingArchive);
    }
  }

  /// 提取路径中的 basename（最后一段文件名）
  static String _basename(String path) {
    final idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /// 将工作 archive 的文件状态同步回原 archive
  ///
  /// 由于 archive 包的 Archive 类没有公开的「重建」API，
  /// 当 addOrReplaceFileSafe 因索引损坏返回新 archive 时，
  /// 我们把新 archive 的所有文件复制到原 archive 中。
  ///
  /// 这种方法虽然低效（逐文件复制），但能保持原 archive 引用不变，
  /// 避免破坏外部调用方的 archive 状态。
  static void _syncArchiveState(Archive original, Archive updated) {
    // 先清空原 archive 的文件（通过移除每个文件）
    for (final file in original.files.toList()) {
      try {
        original.removeFile(file);
      } catch (_) {
        // ignore: 某些场景下 removeFile 失败
      }
    }
    // 再把新 archive 的文件逐一加入
    for (final file in updated.files) {
      try {
        original.addFile(
          ArchiveFile(
            file.name,
            file.size,
            file.content is List<int>
                ? file.content as List<int>
                : (file.content as dynamic).toList() as List<int>,
          ),
        );
      } catch (_) {
        // ignore
      }
    }
  }

  /// 获取文件所在目录（含尾部 /）
  static String _getDir(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx + 1) : '';
  }

  /// 重写 OPF manifest 中的 href
  ///
  /// [opfContent] OPF XML 内容
  /// [hrefMap] 旧文件名 → 新文件名映射
  static String rewriteOpfManifest(
    String opfContent,
    Map<String, String> hrefMap,
  ) {
    try {
      final document = xml.XmlDocument.parse(opfContent);

      for (final item in document.findAllElements('item', namespace: '*')) {
        final href = item.getAttribute('href');
        if (href == null) continue;

        final basename = p.basename(href);
        final newBasename = hrefMap[basename];
        if (newBasename != null) {
          final dir = p.dirname(href);
          final newHref = dir != '.' && dir.isNotEmpty
              ? '$dir/$newBasename'
              : newBasename;
          item.setAttribute('href', newHref);
        }
      }

      return document.toXmlString(pretty: true);
    } catch (_) {
      // XML 解析失败，做简单字符串替换
      var result = opfContent;
      for (final entry in hrefMap.entries) {
        result = result.replaceAll(entry.key, entry.value);
      }
      return result;
    }
  }

  /// 执行完整的加密/解密流程
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// [mode] 'encrypt' 或 'decrypt'
  ///
  /// 返回处理结果摘要字符串。
  /// 若检测到掌阅 DRM 返回 'zhangyue_drm'。
  /// 若未加密尝试解密返回 'not_encrypted'。
  /// 若已加密尝试加密返回 'encrypted'。
  static Future<String> process({
    required String epubPath,
    required String outputPath,
    required String mode,
  }) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final log = StringBuffer();
    log.writeln(mode == 'encrypt' ? '开始加密...' : '开始解密...');

    // 1. 查找 OPF 文件
    String? opfPath;
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith('.opf')) {
        opfPath = file.name;
        break;
      }
    }

    if (opfPath == null) {
      log.writeln('错误: 找不到 OPF 文件');
      return log.toString();
    }

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      log.writeln('错误: 无法读取 OPF 文件');
      return log.toString();
    }

    final opfContent = utf8.decode(opfFile.content as List<int>);

    // 2. 检测掌阅 DRM（仅解密时检测）
    if (mode == 'decrypt') {
      if (checkZhangyueDrm(archive)) {
        log.writeln('检测到掌阅 DRM，不支持解密');
        return zhangyueDrm;
      }
    }

    // 3. 检测加密状态
    final encrypted = isEncrypted(opfContent);

    if (mode == 'encrypt' && encrypted) {
      log.writeln('该 EPUB 已被加密，跳过');
      return EncryptDecryptBase.encrypted;
    }

    if (mode == 'decrypt' && !encrypted) {
      log.writeln('该 EPUB 未被加密，无需解密');
      return EncryptDecryptBase.notEncrypted;
    }

    // 4. 解析 manifest
    final items = parseManifest(opfContent);
    log.writeln('解析到 ${items.length} 个 manifest 条目');

    // 5. 构建 href 映射表
    final hrefMap = buildHrefMap(items, mode);
    log.writeln('生成 ${hrefMap.length} 个文件名映射');

    // 6. 重写 OPF manifest 中的 href
    final updatedOpf = rewriteOpfManifest(opfContent, hrefMap);
    final updatedOpfBytes = utf8.encode(updatedOpf);
    EpubImageHelper.addOrReplaceFile(
      archive,
      ArchiveFile(opfPath, updatedOpfBytes.length, updatedOpfBytes),
    );

    // 7. 重写其他文件中的引用
    rewriteReferences(archive, hrefMap, opfPath);

    // 8. 重命名文件
    _renameFiles(archive, hrefMap, items, mode);

    // 9. 保存
    await EpubPacker.pack(archive: archive, outputPath: outputPath);

    log.writeln('\n${mode == "encrypt" ? "加密" : "解密"}完成');
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 重命名 EPUB 中的文件
  ///
  /// 根据 hrefMap 将旧文件名改为新文件名
  static void _renameFiles(
    Archive archive,
    Map<String, String> hrefMap,
    List<ManifestItem> items,
    String mode,
  ) {
    // 为每个 manifest item 构建旧路径→新路径映射
    final pathMap = <String, String>{};

    for (final item in items) {
      final oldBasename = p.basename(item.href);
      final newBasename = hrefMap[oldBasename];
      if (newBasename == null) continue;

      // 在 archive 中查找匹配的文件
      for (final file in archive.files) {
        if (p.basename(file.name) == oldBasename) {
          final dir = _getDir(file.name);
          pathMap[file.name] = '$dir$newBasename';
        }
      }
    }

    // 执行重命名（通过索引运算符避免 removeFile 的 _fileMap 索引损坏 bug）
    for (final entry in pathMap.entries) {
      final oldPath = entry.key;
      final newPath = entry.value;
      if (oldPath == newPath) continue;

      // 通过遍历查找旧文件索引（不依赖 findFile，避免 _fileMap 可能过期）
      for (var i = 0; i < archive.files.length; i++) {
        if (archive.files[i].name == oldPath) {
          final data = archive.files[i].content as List<int>;
          // archive[i] = newFile 会正确更新 _fileMap（移除旧名、添加新名）
          archive[i] = ArchiveFile(newPath, data.length, data);
          break;
        }
      }
    }
  }
}
