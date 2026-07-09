import 'dart:typed_data';

import '../../core/background_task.dart';
import '../ad_clean/ad_clean.dart';
import '../comment/comment.dart';
import '../convert_version/convert_version.dart';
import '../decrypt/decrypt.dart';
import '../download_images/download_images.dart';
import '../encrypt/encrypt.dart';
import '../encrypt_font/encrypt_font.dart';
import '../epub_to_txt/epub_to_txt.dart';
import '../font_subset/font_subset.dart';
import '../footnote_to_comment/footnote_to_comment.dart';
import '../img_compress/img_compress.dart';
import '../list_font_targets/list_font_targets.dart';
import '../list_split_targets/list_split_targets.dart';
import '../merge/merge.dart';
import '../phonetic/phonetic.dart';
import '../reformat/reformat.dart';
import '../replace_cover/replace_cover.dart';
import '../span_to_footnote/span_to_footnote.dart';
import '../split/split.dart';
import '../view_opf/view_opf.dart';
import '../webp_to_img/webp_to_img.dart';
import '../yuewei/yuewei.dart';
import '../zhangyue/zhangyue.dart';

enum EpubBackgroundOperation {
  viewOpf,
  replaceCover,
  reformat,
  convertVersion,
  epubToTxt,
  adClean,
  imgCompress,
  webpToImg,
  downloadImages,
  phonetic,
  fontSubset,
  encrypt,
  decrypt,
  encryptFont,
  listFontTargets,
  merge,
  split,
  listSplitTargets,
  comment,
  footnoteToComment,
  spanToFootnote,
  yuewei,
  zhangyue,
}

Future<T> runEpubBackgroundOperation<T>(
  EpubBackgroundOperation operation,
  Map<String, Object?> args,
) async {
  final result = await runBackgroundTask(_runEpubOperation, {
    'operation': operation.name,
    'args': args,
  });
  return result as T;
}

Future<Object?> _runEpubOperation(Map<String, Object?> message) async {
  final operation = message['operation'] as String;
  final args = message['args'] as Map<String, Object?>;

  switch (operation) {
    case 'viewOpf':
      return ViewOpfOperation.execute(args['epubPath'] as String);
    case 'replaceCover':
      await ReplaceCoverOperation.execute(
        epubPath: args['epubPath'] as String,
        coverPath: args['coverPath'] as String,
        outputPath: args['outputPath'] as String,
      );
      return null;
    case 'reformat':
      return ReformatOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'convertVersion':
      await ConvertVersionOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        targetVersion: args['targetVersion'] as String,
      );
      return null;
    case 'epubToTxt':
      return EpubToTxtOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'adClean':
      await AdCleanOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        patterns: args['patterns'] as String,
      );
      return null;
    case 'imgCompress':
      return ImgCompressOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        jpegQuality: args['jpegQuality'] as int,
        pngToJpg: args['pngToJpg'] as bool,
      );
    case 'webpToImg':
      return WebpToImgOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'downloadImages':
      return DownloadImagesOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'phonetic':
      return PhoneticOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        toneMode: args['toneMode'] as String,
        annotateAll: args['annotateAll'] as bool,
      );
    case 'fontSubset':
      return FontSubsetOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'encrypt':
      return EncryptOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'decrypt':
      return DecryptOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
      );
    case 'encryptFont':
      return EncryptFontOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        targetFontFamilies: (args['targetFontFamilies'] as List?)
            ?.cast<String>(),
        targetXhtmlFiles: (args['targetXhtmlFiles'] as List?)?.cast<String>(),
      );
    case 'listFontTargets':
      return ListFontTargetsOperation.execute(
        epubPath: args['epubPath'] as String,
      );
    case 'merge':
      return MergeOperation.execute(
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
      );
    case 'split':
      return SplitOperation.execute(
        epubPath: args['epubPath'] as String,
        outputDir: args['outputDir'] as String,
        splitPoints: (args['splitPoints'] as List).cast<int>(),
      );
    case 'listSplitTargets':
      final targets = await ListSplitTargetsOperation.execute(
        epubPath: args['epubPath'] as String,
      );
      return {
        'formatted': ListSplitTargetsOperation.formatTargets(targets),
        'length': targets.length,
      };
    case 'comment':
      return CommentOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        regexPattern: args['regexPattern'] as String,
      );
    case 'footnoteToComment':
      return FootnoteToCommentOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        regexPattern: args['regexPattern'] as String,
        notePngBytes: args['notePngBytes'] as Uint8List?,
      );
    case 'spanToFootnote':
      return SpanToFootnoteOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        footnoteColor: args['footnoteColor'] as String,
        noterefColor: args['noterefColor'] as String,
      );
    case 'yuewei':
      return YueweiOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        notePngBytes: args['notePngBytes'] as Uint8List?,
      );
    case 'zhangyue':
      return ZhangyueOperation.execute(
        epubPath: args['epubPath'] as String,
        outputPath: args['outputPath'] as String,
        notePngBytes: args['notePngBytes'] as Uint8List?,
      );
  }

  throw ArgumentError.value(operation, 'operation', '未知 EPUB 后台操作');
}
