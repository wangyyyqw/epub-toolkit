import 'dart:typed_data';

import '../../core/operation.dart';
import '../ad_clean/ad_clean.dart';
import '../comment/comment.dart';
import '../convert_version/convert_version.dart';
import '../decrypt/decrypt.dart';
import '../download_images/download_images.dart';
import '../encrypt/encrypt.dart';
import '../encrypt_font/encrypt_font.dart';
import '../epub_health/epub_health.dart';
import '../epub_health/epub_health_repair.dart';
import '../epub_to_txt/epub_to_txt.dart';
import '../font_subset/font_subset.dart';
import '../footnote_to_comment/footnote_to_comment.dart';
import '../image_watermark/image_watermark.dart';
import '../img_compress/img_compress.dart';
import '../list_font_targets/list_font_targets.dart';
import '../list_split_targets/list_split_targets.dart';
import '../merge/merge.dart';
import '../navigation_editor/navigation_editor.dart';
import '../navigation_editor/navigation_model.dart';
import '../phonetic/phonetic.dart';
import '../reformat/reformat.dart';
import '../replace_cover/replace_cover.dart';
import '../span_to_footnote/span_to_footnote.dart';
import '../split/split.dart';
import '../view_opf/view_opf.dart';
import '../webp_to_img/webp_to_img.dart';
import '../yuewei/yuewei.dart';
import '../zhangyue/zhangyue.dart';
import '../zip_password/zip_password.dart';

final EpubOperationRegistry epubOperationRegistry = EpubOperationRegistry([
  RegisteredEpubOperation(
    id: 'navigationLoad',
    displayName: '读取目录导航',
    description: '读取 NAV、NCX、地标和页码导航',
    category: 'structure',
    outputExtension: 'json',
    mode: EpubOperationMode.inspect,
    executor: (args) async {
      final document = await NavigationEditorOperation.load(
        args['epubPath'] as String,
      );
      return document.toJson();
    },
  ),
  RegisteredEpubOperation(
    id: 'navigationRegenerate',
    displayName: '从标题重建目录',
    description: '按 spine 顺序扫描 H1-H6 生成目录树',
    category: 'structure',
    outputExtension: 'json',
    mode: EpubOperationMode.inspect,
    executor: (args) async {
      final document = await NavigationEditorOperation.regenerateFromHeadings(
        args['epubPath'] as String,
      );
      return document.toJson();
    },
  ),
  RegisteredEpubOperation(
    id: 'navigationSave',
    displayName: '保存目录导航',
    description: '同步写入 NAV 与 NCX 并保留特殊导航区块',
    category: 'structure',
    outputExtension: 'epub',
    executor: (args) => NavigationEditorOperation.save(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      navigation: EpubNavigationDocument.fromJson(
        (args['navigation'] as Map).cast<String, Object?>(),
      ),
    ),
  ),
  RegisteredEpubOperation(
    id: 'navigationValidate',
    displayName: '检查目录导航',
    description: '检查空标题、重复条目、空章节与无效链接锚点',
    category: 'structure',
    outputExtension: 'json',
    mode: EpubOperationMode.inspect,
    executor: (args) async {
      final navigation = EpubNavigationDocument.fromJson(
        (args['navigation'] as Map).cast<String, Object?>(),
      );
      final issues = await NavigationEditorOperation.validate(
        args['epubPath'] as String,
        navigation.sections,
      );
      return issues.map((issue) => issue.toJson()).toList();
    },
  ),
  RegisteredEpubOperation(
    id: 'healthScan',
    displayName: 'EPUB 体检',
    description: '检查 EPUB 包结构、导航、资源、封面和字体引用',
    category: 'quality',
    outputExtension: 'json|html',
    mode: EpubOperationMode.inspect,
    supportsBatch: true,
    executor: (args) async {
      final report = await EpubHealthInspector.scan(args['epubPath'] as String);
      return report.toJson();
    },
  ),
  RegisteredEpubOperation(
    id: 'healthRepair',
    displayName: 'EPUB 选择性修复',
    description: '应用体检中选中的安全修复并自动复检',
    category: 'quality',
    outputExtension: 'epub',
    executor: (args) => EpubHealthRepairOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      selectedFixIds: (args['selectedFixIds'] as List).cast<String>(),
      reportDirectory: args['reportDirectory'] as String?,
    ),
  ),
  RegisteredEpubOperation(
    id: 'viewOpf',
    displayName: '查看 OPF',
    description: '读取并格式化 package document',
    category: 'structure',
    outputExtension: 'txt',
    mode: EpubOperationMode.inspect,
    executor: (args) => ViewOpfOperation.execute(args['epubPath'] as String),
  ),
  RegisteredEpubOperation(
    id: 'replaceCover',
    displayName: '更换封面',
    description: '替换 EPUB 封面资源及声明',
    category: 'structure',
    outputExtension: 'epub',
    executor: (args) => ReplaceCoverOperation.execute(
      epubPath: args['epubPath'] as String,
      coverPath: args['coverPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'reformat',
    displayName: '重新格式化',
    description: '规范化 EPUB 内部结构并清理冗余资源',
    category: 'structure',
    outputExtension: 'epub',
    supportsBatch: true,
    passThroughMessages: const ['无需再次处理'],
    executor: (args) => ReformatOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'convertVersion',
    displayName: '版本转换',
    description: '转换 EPUB 2.0 与 EPUB 3.0',
    category: 'conversion',
    outputExtension: 'epub',
    defaultArguments: const {'targetVersion': '3.0'},
    supportsBatch: true,
    executor: (args) => ConvertVersionOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      targetVersion: args['targetVersion'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'epubToTxt',
    displayName: 'EPUB 转 TXT',
    description: '按阅读顺序导出纯文本',
    category: 'conversion',
    outputExtension: 'txt',
    executor: (args) => EpubToTxtOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'adClean',
    displayName: '广告清理',
    description: '按正则规则清理正文广告',
    category: 'text',
    outputExtension: 'epub',
    executor: (args) => AdCleanOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      patterns: args['patterns'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'imgCompress',
    displayName: '图片压缩',
    description: '压缩 EPUB 图片并可将 PNG 转为 JPEG',
    category: 'image',
    outputExtension: 'epub',
    supportsBatch: true,
    defaultArguments: const {'jpegQuality': 82, 'pngToJpg': false},
    executor: (args) => ImgCompressOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      jpegQuality: args['jpegQuality'] as int,
      pngToJpg: args['pngToJpg'] as bool,
    ),
  ),
  RegisteredEpubOperation(
    id: 'embedImageWatermark',
    displayName: '写入图片水印',
    description: '向 EPUB 图片写入隐形水印',
    category: 'image',
    outputExtension: 'epub',
    executor: (args) => ImageWatermarkOperation.embed(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      watermarkText: args['watermarkText'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'inspectImageWatermark',
    displayName: '读取图片水印',
    description: '扫描 EPUB 图片中的隐形水印',
    category: 'image',
    outputExtension: 'txt',
    mode: EpubOperationMode.inspect,
    executor: (args) =>
        ImageWatermarkOperation.inspect(epubPath: args['epubPath'] as String),
  ),
  RegisteredEpubOperation(
    id: 'webpToImg',
    displayName: 'WebP 转图片',
    description: '将 WebP 转为兼容性更好的图片格式',
    category: 'image',
    outputExtension: 'epub',
    supportsBatch: true,
    passThroughMessages: const ['未找到 WebP 图片，无需转换'],
    executor: (args) => WebpToImgOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'downloadImages',
    displayName: '下载网络图片',
    description: '下载正文和 CSS 引用的远程图片并改写为本地引用',
    category: 'image',
    outputExtension: 'epub',
    supportsBatch: true,
    passThroughMessages: const ['未找到网络图片引用，无需下载'],
    executor: (args) => DownloadImagesOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'phonetic',
    displayName: '拼音标注',
    description: '为正文汉字添加 ruby 拼音标注',
    category: 'text',
    outputExtension: 'epub',
    defaultArguments: const {'toneMode': 'symbol', 'annotateAll': false},
    supportsBatch: true,
    executor: (args) => PhoneticOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      toneMode: args['toneMode'] as String,
      annotateAll: args['annotateAll'] as bool,
    ),
  ),
  RegisteredEpubOperation(
    id: 'fontSubset',
    displayName: '字体子集化',
    description: '按全书实际字符缩减内嵌字体',
    category: 'font',
    outputExtension: 'epub',
    supportsBatch: true,
    executor: (args) => FontSubsetOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'encrypt',
    displayName: '名称混淆加密',
    description: '混淆 EPUB 内部文件名并更新引用',
    category: 'security',
    outputExtension: 'epub',
    supportsBatch: true,
    passThroughMessages: const ['encrypted'],
    executor: (args) => EncryptOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'decrypt',
    displayName: '名称混淆解密',
    description: '恢复受支持的 EPUB 名称混淆',
    category: 'security',
    outputExtension: 'epub',
    supportsBatch: true,
    passThroughMessages: const ['not_encrypted'],
    executor: (args) => DecryptOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'encryptFont',
    displayName: '字体加密',
    description: '按 EPUB 标识符混淆内嵌字体',
    category: 'font',
    outputExtension: 'epub',
    executor: (args) => EncryptFontOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      targetFontFamilies: (args['targetFontFamilies'] as List?)?.cast<String>(),
      targetXhtmlFiles: (args['targetXhtmlFiles'] as List?)?.cast<String>(),
    ),
  ),
  RegisteredEpubOperation(
    id: 'addZipPassword',
    displayName: '添加 ZIP 密码',
    description: '为 EPUB ZIP 容器添加密码',
    category: 'security',
    outputExtension: 'epub',
    executor: (args) => ZipPasswordOperation.addPassword(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      password: args['password'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'removeZipPassword',
    displayName: '移除 ZIP 密码',
    description: '移除 EPUB ZIP 容器密码',
    category: 'security',
    outputExtension: 'epub',
    executor: (args) => ZipPasswordOperation.removePassword(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      password: args['password'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'scanFontTargets',
    displayName: '扫描字体目标',
    description: '读取可加密字体和正文目标',
    category: 'font',
    outputExtension: 'json',
    mode: EpubOperationMode.inspect,
    executor: (args) async {
      final targets = await ListFontTargetsOperation.scan(
        epubPath: args['epubPath'] as String,
      );
      return {
        'fontFamilies': targets.fontFamilies,
        'xhtmlFiles': targets.xhtmlFiles,
      };
    },
  ),
  RegisteredEpubOperation(
    id: 'listFontTargets',
    displayName: '列出字体目标',
    description: '格式化输出可加密字体和正文目标',
    category: 'font',
    outputExtension: 'txt',
    mode: EpubOperationMode.inspect,
    executor: (args) =>
        ListFontTargetsOperation.execute(epubPath: args['epubPath'] as String),
  ),
  RegisteredEpubOperation(
    id: 'merge',
    displayName: '合并 EPUB',
    description: '合并多本 EPUB 并重建目录和资源引用',
    category: 'structure',
    outputExtension: 'epub',
    mode: EpubOperationMode.multiInput,
    executor: (args) => MergeOperation.execute(
      inputPaths: (args['inputPaths'] as List).cast<String>(),
      outputPath: args['outputPath'] as String,
      options: MergeOptions(
        title: args['title'] as String?,
        author: args['author'] as String?,
        language: args['language'] as String?,
        publisher: args['publisher'] as String?,
        description: args['description'] as String?,
        coverPath: args['coverPath'] as String?,
      ),
    ),
  ),
  RegisteredEpubOperation(
    id: 'split',
    displayName: '拆分 EPUB',
    description: '按章节分割点生成多个 EPUB',
    category: 'structure',
    outputExtension: 'epub',
    executor: (args) async {
      final outputPaths = <String>[];
      final log = await SplitOperation.execute(
        epubPath: args['epubPath'] as String,
        outputDir: args['outputDir'] as String,
        splitPoints: (args['splitPoints'] as List).cast<int>(),
        onOutput: outputPaths.add,
      );
      return {'log': log, 'outputPaths': outputPaths};
    },
  ),
  RegisteredEpubOperation(
    id: 'listSplitTargets',
    displayName: '列出拆分目标',
    description: '读取 EPUB 目录并列出可拆分章节',
    category: 'structure',
    outputExtension: 'json',
    mode: EpubOperationMode.inspect,
    executor: (args) async {
      final targets = await ListSplitTargetsOperation.execute(
        epubPath: args['epubPath'] as String,
      );
      return {
        'formatted': ListSplitTargetsOperation.formatTargets(targets),
        'length': targets.length,
        'data': targets
            .map((target) => target.toJson())
            .toList(growable: false),
      };
    },
  ),
  RegisteredEpubOperation(
    id: 'comment',
    displayName: '批注提取',
    description: '按正则提取正文批注并生成弹窗注释',
    category: 'annotation',
    outputExtension: 'epub',
    executor: (args) => CommentOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      regexPattern: args['regexPattern'] as String,
      notePngBytes: args['notePngBytes'] as Uint8List?,
    ),
  ),
  RegisteredEpubOperation(
    id: 'footnoteToComment',
    displayName: '脚注转弹窗',
    description: '把标准脚注转换为弹窗注释',
    category: 'annotation',
    outputExtension: 'epub',
    executor: (args) => FootnoteToCommentOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      regexPattern: args['regexPattern'] as String,
      notePngBytes: args['notePngBytes'] as Uint8List?,
    ),
  ),
  RegisteredEpubOperation(
    id: 'spanToFootnote',
    displayName: '弹窗转脚注',
    description: '把弹窗注释转换为标准脚注',
    category: 'annotation',
    outputExtension: 'epub',
    executor: (args) => SpanToFootnoteOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      footnoteColor: args['footnoteColor'] as String,
      noterefColor: args['noterefColor'] as String,
    ),
  ),
  RegisteredEpubOperation(
    id: 'yuewei',
    displayName: '阅微转多看',
    description: '转换阅微批注为多看弹窗注释',
    category: 'annotation',
    outputExtension: 'epub',
    executor: (args) => YueweiOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      notePngBytes: args['notePngBytes'] as Uint8List?,
    ),
  ),
  RegisteredEpubOperation(
    id: 'zhangyue',
    displayName: '得到转多看',
    description: '转换得到或掌阅批注为多看弹窗注释',
    category: 'annotation',
    outputExtension: 'epub',
    executor: (args) => ZhangyueOperation.execute(
      epubPath: args['epubPath'] as String,
      outputPath: args['outputPath'] as String,
      notePngBytes: args['notePngBytes'] as Uint8List?,
    ),
  ),
]);
