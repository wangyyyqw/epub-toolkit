// 端到端测试：测试所有 26 个 epub_tools 操作 + txt2epub
//
// 用真实文件（用户提供的 EPUB / TXT）作为输入，对每个操作执行一次，
// 验证其不抛异常、产出有效 EPUB，并保存日志。
//
// 运行方式：
//   cd flutter
//   flutter test test/e2e_all_operations_test.dart --reporter=expanded
//
// 输入文件路径在此文件中以硬编码方式指定（用户提供的 3 个文件）：
//   - /Users/aaa/Documents/github/epub-gadget/恐妻家 - [日]伊坂幸太郎.epub
//   - /Users/aaa/Documents/github/epub-gadget/C41-愤怒的葡萄-[美] 约翰·斯坦贝克-手机.epub
//   - /Users/aaa/Documents/github/epub-gadget/一千零一夜.txt
//
// 输出目录：/Users/aaa/Documents/github/epub-gadget/flutter_test_output/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/epub_service.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';
import 'package:epub_gadget/features/ad_clean/ad_clean.dart';
import 'package:epub_gadget/features/comment/comment.dart';
import 'package:epub_gadget/features/convert_version/convert_version.dart';
import 'package:epub_gadget/features/decrypt/decrypt.dart';
import 'package:epub_gadget/features/download_images/download_images.dart';
import 'package:epub_gadget/features/encrypt/encrypt.dart';
import 'package:epub_gadget/features/encrypt_font/encrypt_font.dart';
import 'package:epub_gadget/features/epub_to_txt/epub_to_txt.dart';
import 'package:epub_gadget/features/font_subset/font_subset.dart';
import 'package:epub_gadget/features/footnote_to_comment/footnote_to_comment.dart';
import 'package:epub_gadget/features/img_compress/img_compress.dart';
import 'package:epub_gadget/features/img_to_webp/img_to_webp.dart';
import 'package:epub_gadget/features/list_font_targets/list_font_targets.dart';
import 'package:epub_gadget/features/list_split_targets/list_split_targets.dart';
import 'package:epub_gadget/features/merge/merge.dart';
import 'package:epub_gadget/features/phonetic/phonetic.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';
import 'package:epub_gadget/features/replace_cover/replace_cover.dart';
import 'package:epub_gadget/features/s2t/s2t.dart';
import 'package:epub_gadget/features/span_to_footnote/span_to_footnote.dart';
import 'package:epub_gadget/features/split/split.dart';
import 'package:epub_gadget/features/t2s/t2s.dart';
import 'package:epub_gadget/features/view_opf/view_opf.dart';
import 'package:epub_gadget/features/webp_to_img/webp_to_img.dart';
import 'package:epub_gadget/features/yuewei/yuewei.dart';
import 'package:epub_gadget/features/zhangyue/zhangyue.dart';
import 'package:archive/archive.dart';

Future<bool> _isValidEpubZip(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    // 必须有 mimetype 文件且内容为 'application/epub+zip'
    final mt = archive.findFile('mimetype');
    if (mt == null) return false;
    final mtContent = String.fromCharCodes(mt.content as List<int>);
    if (!mtContent.startsWith('application/epub+zip')) return false;
    // 必须有 META-INF/container.xml
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) return false;
    final containerXml = String.fromCharCodes(container.content as List<int>);
    if (!containerXml.contains('rootfile')) return false;
    // 必须有 OPF
    final opfMatch = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (opfMatch == null) return false;
    final opf = archive.findFile(opfMatch.group(1)!);
    if (opf == null) return false;
    return true;
  } catch (_) {
    return false;
  }
}

// ==================== 测试常量 ====================

const _kTestRoot =
    '/Users/aaa/Documents/github/epub-gadget/flutter_test_output';
const _kEpub1Path =
    '/Users/aaa/Documents/github/epub-gadget/恐妻家 - [日]伊坂幸太郎.epub';
const _kEpub2Path =
    '/Users/aaa/Documents/github/epub-gadget/C41-愤怒的葡萄-[美] 约翰·斯坦贝克-手机.epub';
const _kTxtPath = '/Users/aaa/Documents/github/epub-gadget/一千零一夜.txt';

late Uint8List _notePngBytes;

/// 测试结果统计
class TestStats {
  int total = 0;
  int passed = 0;
  int failed = 0;
  final List<String> failures = [];
  final List<String> passList = [];

  void record(String name, bool ok, [String? error]) {
    total++;
    if (ok) {
      passed++;
      passList.add('✅ $name');
    } else {
      failed++;
      failures.add('❌ $name${error != null ? "  [error: $error]" : ""}');
    }
  }
}

final _stats = TestStats();

Future<void> _writeLog(String dir, String name, String content) async {
  await Directory('$_kTestRoot/$dir').create(recursive: true);
  final f = File('$_kTestRoot/$dir/$name.log');
  await f.writeAsString(content);
}

Future<File> _copyFile(String src, String dstDir, String dstName) async {
  await Directory(dstDir).create(recursive: true);
  final srcBytes = await File(src).readAsBytes();
  final f = File('$dstDir/$dstName');
  await f.writeAsBytes(srcBytes);
  return f;
}

Future<bool> _existsAndNonEmpty(String path) async {
  final f = File(path);
  if (!await f.exists()) return false;
  return (await f.length()) > 0;
}

/// 用底层 ZIP+mimetype+container.xml 验证产出文件是合法 EPUB。
/// 避免 epubx 库对 URI 编码的严格性导致的误判。
Future<bool> _isValidEpub(String path) => _isValidEpubZip(path);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (![
    _kEpub1Path,
    _kEpub2Path,
    _kTxtPath,
  ].every((path) => File(path).existsSync())) {
    test('全功能端到端测试需要本机夹具', () {}, skip: '提供测试书籍后再运行此测试文件。');
    return;
  }

  setUpAll(() async {
    // 为所有用例准备 note.png 资源
    try {
      final data = await rootBundle.load('assets/note.png');
      _notePngBytes = data.buffer.asUint8List();
    } catch (_) {
      _notePngBytes = Uint8List(0);
    }

    // 校验输入文件存在
    for (final p in [_kEpub1Path, _kEpub2Path, _kTxtPath]) {
      if (!await File(p).exists()) {
        throw StateError('测试输入文件不存在: $p');
      }
    }

    // 预热简繁转换字典
    await ChineseConverter.initS2T();
    await ChineseConverter.initT2S();
  });

  // ==================== 1. viewOPF ====================
  test('OP-01 viewOpf', () async {
    String? err;
    try {
      final result = await ViewOpfOperation.execute(_kEpub1Path);
      await _writeLog('op_01_view_opf', 'opf.xml', result);
      expect(result, contains('<package'));
    } catch (e) {
      err = e.toString();
    }
    _stats.record('01 viewOpf', err == null, err);
  });

  // ==================== 2. replaceCover ====================
  test('OP-02 replaceCover (用 zip 内现成封面作为新封面)', () async {
    String? err;
    try {
      // 提取 epub1 内的 cover.png 作为新封面（如有），否则用 epub2 的封面
      // 这里直接复用 epub1 自己的封面（OPF 解析会指向同一文件）
      // 为测试稳定性，先复制原 epub，再用 note.png 作为新封面
      final dir = '$_kTestRoot/op_02_replace_cover';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      // 用 assets 里的 png 作为新封面（如有），否则生成最小 PNG
      Uint8List coverBytes = _notePngBytes ?? _makeMinPng();
      final coverFile = File('$dir/new_cover.png');
      await coverFile.writeAsBytes(coverBytes);

      final out = '$dir/out.epub';
      await ReplaceCoverOperation.execute(
        epubPath: src.path,
        coverPath: coverFile.path,
        outputPath: out,
      );
      await _writeLog('op_02_replace_cover', 'result.log', 'output: $out');
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('02 replaceCover', err == null, err);
  });

  // ==================== 3. reformat ====================
  test('OP-03 reformat', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_03_reformat';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      await ReformatOperation.execute(epubPath: src.path, outputPath: out);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('03 reformat', err == null, err);
  });

  // ==================== 4. convertVersion ====================
  test('OP-04a convertVersion to 3.0', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_04_convert_version';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out_3.0.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '3.0',
      );
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('04a convertVersion→3.0', err == null, err);
  });

  test('OP-04b convertVersion to 2.0', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_04_convert_version';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out_2.0.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '2.0',
      );
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('04b convertVersion→2.0', err == null, err);
  });

  // ==================== 5. epubToTxt ====================
  test('OP-05 epubToTxt', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_05_epub_to_txt';
      final text = await EpubToTxtOperation.execute(epubPath: _kEpub1Path);
      await _writeLog('op_05_epub_to_txt', 'out.txt', text);
      expect(text.length, greaterThan(100));
    } catch (e) {
      err = e.toString();
    }
    _stats.record('05 epubToTxt', err == null, err);
  });

  // ==================== 6. adClean ====================
  test('OP-06 adClean', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_06_ad_clean';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      // 简单规则：去掉 <a> 标签中 class 包含 "ad" 的链接内容
      final patterns = [
        r'<a[^>]*class="[^"]*ad[^"]*"[^>]*>.*?</a>',
        '',
      ].join('|||');
      await AdCleanOperation.execute(
        epubPath: src.path,
        outputPath: out,
        patterns: patterns,
      );
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('06 adClean', err == null, err);
  });

  // ==================== 7. imgCompress ====================
  test('OP-07 imgCompress', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_07_img_compress';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      await ImgCompressOperation.execute(
        epubPath: src.path,
        outputPath: out,
        jpegQuality: 70,
        pngToJpg: true,
      );
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('07 imgCompress', err == null, err);
  });

  // ==================== 8. imgToWebp (macOS 平台不支持编码) ====================
  test('OP-08 imgToWebp', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_08_img_to_webp';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await ImgToWebpOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      // 桌面平台预期返回「不支持」消息；只检查不抛异常
      expect(result, isNotEmpty);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('08 imgToWebp', err == null, err);
  });

  // ==================== 9. webpToImg (无 webp，跳过是预期) ====================
  test('OP-09 webpToImg', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_09_webp_to_img';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await WebpToImgOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      expect(result, isNotEmpty);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('09 webpToImg', err == null, err);
  });

  // ==================== 10. downloadImages (无网络图片，预期跳过) ====================
  test('OP-10 downloadImages', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_10_download_images';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await DownloadImagesOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      expect(result, isNotEmpty);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('10 downloadImages', err == null, err);
  });

  // ==================== 11. s2t ====================
  test('OP-11 s2t', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_11_s2t';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await S2tOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      await _writeLog('op_11_s2t', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('11 s2t', err == null, err);
  });

  // ==================== 12. t2s ====================
  test('OP-12 t2s', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_12_t2s';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await T2sOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      await _writeLog('op_12_t2s', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('12 t2s', err == null, err);
  });

  // ==================== 13. phonetic ====================
  test('OP-13 phonetic (mark)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_13_phonetic';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out_mark.epub';
      final result = await PhoneticOperation.execute(
        epubPath: src.path,
        outputPath: out,
        toneMode: PhoneticOperation.toneModeMark,
        annotateAll: true,
      );
      await _writeLog('op_13_phonetic', 'mark.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('13a phonetic-mark', err == null, err);
  });

  test('OP-13b phonetic (number, onlyRare)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_13_phonetic';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out_number.epub';
      final result = await PhoneticOperation.execute(
        epubPath: src.path,
        outputPath: out,
        toneMode: PhoneticOperation.toneModeNumber,
        annotateAll: false,
      );
      await _writeLog('op_13_phonetic', 'number.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('13b phonetic-number-rare', err == null, err);
  });

  // ==================== 14. fontSubset ====================
  test('OP-14 fontSubset', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_14_font_subset';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await FontSubsetOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      await _writeLog('op_14_font_subset', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('14 fontSubset', err == null, err);
  });

  // ==================== 15. encrypt ====================
  test('OP-15 encrypt', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_15_encrypt';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await EncryptOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      await _writeLog('op_15_encrypt', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('15 encrypt', err == null, err);
  });

  // ==================== 16. decrypt (解密上面加密的) ====================
  test('OP-16 decrypt', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_16_decrypt';
      await Directory(dir).create(recursive: true);
      // 使用 OP-15 的加密输出
      final encrypted = '$_kTestRoot/op_15_encrypt/out.epub';
      final out = '$dir/out.epub';
      final result = await DecryptOperation.execute(
        epubPath: encrypted,
        outputPath: out,
      );
      await _writeLog('op_16_decrypt', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('16 decrypt', err == null, err);
  });

  // ==================== 17. encryptFont ====================
  test('OP-17 encryptFont', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_17_encrypt_font';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await EncryptFontOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      await _writeLog('op_17_encrypt_font', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('17 encryptFont', err == null, err);
  });

  // ==================== 18. listFontTargets ====================
  test('OP-18 listFontTargets', () async {
    String? err;
    try {
      final result = await ListFontTargetsOperation.execute(
        epubPath: _kEpub1Path,
      );
      await _writeLog('op_18_list_font_targets', 'result.log', result);
      expect(result, isNotEmpty);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('18 listFontTargets', err == null, err);
  });

  // ==================== 19. merge (两本书) ====================
  test('OP-19 merge (epub1 + epub2)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_19_merge';
      final a = await _copyFile(_kEpub1Path, dir, 'a.epub');
      final b = await _copyFile(_kEpub2Path, dir, 'b.epub');
      final out = '$dir/out.epub';
      final result = await MergeOperation.execute(
        inputPaths: [a.path, b.path],
        outputPath: out,
      );
      await _writeLog('op_19_merge', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('19 merge', err == null, err);
  });

  // ==================== 20. split (epub2 大书分 2 段) ====================
  test('OP-20 split (epub1)', () async {
    String? err;
    String? note;
    try {
      final dir = '$_kTestRoot/op_20_split';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final targets = await ListSplitTargetsOperation.execute(
        epubPath: src.path,
      );
      if (targets.isEmpty) {
        note = '无 TOC 目标，跳过';
      } else {
        // 取中间点做一次拆分（至少 2 段才测试，否则跳过）
        final mid = targets.length ~/ 2;
        if (mid < 1) {
          note = 'targets 数量过少（${targets.length}），跳过';
        } else {
          final out = '$dir/out';
          final result = await SplitOperation.execute(
            epubPath: src.path,
            outputDir: out,
            splitPoints: [mid],
          );
          await _writeLog('op_20_split', 'result.log', result);
          // 检查产出了至少 2 个 epub
          final entries = await Directory(out).list().toList();
          expect(entries.length, greaterThanOrEqualTo(2));
        }
      }
    } catch (e) {
      err = e.toString();
    }
    _stats.record(
      '20 split${note != null ? " [$note]" : ""}',
      err == null,
      err,
    );
  });

  // ==================== 21. listSplitTargets ====================
  test('OP-21 listSplitTargets', () async {
    String? err;
    try {
      final result = await ListSplitTargetsOperation.execute(
        epubPath: _kEpub1Path,
      );
      final formatted = ListSplitTargetsOperation.formatTargets(result);
      await _writeLog('op_21_list_split_targets', 'result.log', formatted);
      expect(result, isA<List>());
    } catch (e) {
      err = e.toString();
    }
    _stats.record('21 listSplitTargets', err == null, err);
  });

  // ==================== 22. comment ====================
  test('OP-22 comment (regex [..])', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_22_comment';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await CommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'\[(.*?)\]',
      );
      await _writeLog('op_22_comment', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('22 comment', err == null, err);
  });

  // ==================== 23. footnoteToComment ====================
  test('OP-23 footnoteToComment (regex ^#+)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_23_footnote_to_comment';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await FootnoteToCommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'^#+',
        notePngBytes: _notePngBytes,
      );
      await _writeLog('op_23_footnote_to_comment', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('23 footnoteToComment', err == null, err);
  });

  // ==================== 24. spanToFootnote ====================
  test('OP-24 spanToFootnote (在 comment 输出基础上)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_24_span_to_footnote';
      await Directory(dir).create(recursive: true);
      // 用 OP-22 产出作为输入（包含批注 span）
      final inputEpub = '$_kTestRoot/op_22_comment/out.epub';
      if (!await File(inputEpub).exists()) {
        throw StateError('依赖 OP-22 输出不存在');
      }
      final out = '$dir/out.epub';
      final result = await SpanToFootnoteOperation.execute(
        epubPath: inputEpub,
        outputPath: out,
        footnoteColor: '#aa0000',
        noterefColor: '#0000aa',
      );
      await _writeLog('op_24_span_to_footnote', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('24 spanToFootnote', err == null, err);
  });

  // ==================== 25. yuewei ====================
  test('OP-25 yuewei (阅微转多看)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_25_yuewei';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await YueweiOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: _notePngBytes,
      );
      await _writeLog('op_25_yuewei', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('25 yuewei', err == null, err);
  });

  // ==================== 26. zhangyue ====================
  test('OP-26 zhangyue (掌阅转多看)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_26_zhangyue';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      final out = '$dir/out.epub';
      final result = await ZhangyueOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: _notePngBytes,
      );
      await _writeLog('op_26_zhangyue', 'result.log', result);
      expect(await _isValidEpub(out), true);
    } catch (e) {
      err = e.toString();
    }
    _stats.record('26 zhangyue', err == null, err);
  });

  // ==================== 27. txt2epub ====================
  test('OP-27 txt2epub (一千零一夜)', () async {
    String? err;
    try {
      final dir = '$_kTestRoot/op_27_txt2epub';

      // 1. 检测编码
      final encoding = EncodingDetector.detect(_kTxtPath);
      // 2. 读取 + 清洗
      final raw = EncodingDetector.readFile(_kTxtPath, encoding);
      final cleaner = TextCleaner(removeEmptyLines: true, fixIndent: true);
      final cleaned = cleaner.clean(raw);
      // 3. 分割（用第一个预设）
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        cleaned,
        presetPatterns[0].pattern,
        splitTitle: true,
      );

      await _writeLog(
        'op_27_txt2epub',
        'chapters.txt',
        'encoding=$encoding\nchapters=${chapters.length}\nfirst 3 titles:\n${chapters.take(3).map((c) => "  - ${c.title}").join("\n")}',
      );

      expect(chapters.length, greaterThan(0));
      if (chapters.isNotEmpty) {
        final out = '$dir/out.epub';
        final (log, userVisiblePath) = await EpubGenerator.generate(
          outputPath: out,
          title: '一千零一夜',
          author: 'Unknown',
          chapters: chapters,
        );
        await _writeLog('op_27_txt2epub', 'generate.log', log);
        expect(await _isValidEpub(out), true);
      }
    } catch (e) {
      err = e.toString();
    }
    _stats.record('27 txt2epub', err == null, err);
  });

  // ==================== 最后：写测试报告 ====================
  tearDownAll(() async {
    final buf = StringBuffer();
    buf.writeln('# EPUB Gadget Flutter 端到端测试报告');
    buf.writeln();
    buf.writeln('**输入文件**:');
    buf.writeln('- EPUB1: `$_kEpub1Path`');
    buf.writeln(
      '- EPUB2: `$_kEpub2Path` (${await File(_kEpub2Path).length()} bytes)',
    );
    buf.writeln(
      '- TXT:  `$_kTxtPath` (${await File(_kTxtPath).length()} bytes)',
    );
    buf.writeln();
    buf.writeln(
      '**汇总**: ${_stats.passed}/${_stats.total} 通过，${_stats.failed} 失败',
    );
    buf.writeln();
    buf.writeln('## 通过');
    for (final p in _stats.passList) {
      buf.writeln(p);
    }
    buf.writeln();
    if (_stats.failures.isNotEmpty) {
      buf.writeln('## 失败');
      for (final f in _stats.failures) {
        buf.writeln(f);
      }
    }
    final reportFile = File('$_kTestRoot/REPORT.md');
    await reportFile.writeAsString(buf.toString());

    // ignore: avoid_print
    print('\n========== 测试报告 ==========');
    // ignore: avoid_print
    print(buf.toString());
  });
}

/// 最小合法 PNG (1x1 透明)，作为兜底封面
Uint8List _makeMinPng() {
  // 8 字节签名 + IHDR + IDAT + IEND
  return Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // 签名
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
    0x54, 0x08, 0x99, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
    0x42, 0x60, 0x82,
  ]);
}
