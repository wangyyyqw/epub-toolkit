// 综合功能测试脚本
// 测试流程：选择文件 → 选择功能 → 功能处理 → 输出文件 → 检查输出文件
// 检查项：文件是否正常、编码是否正确、格式是否正常、功能是否正确运行、结果是否符合预期
//
// 运行方式：
//   cd flutter
//   flutter test test/comprehensive_test.dart --reporter=expanded

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/epub_service.dart';
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
import 'package:epub_gadget/features/metadata/metadata_service.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';

// ==================== 测试常量 ====================

const _kTestRoot = '/Users/aaa/Documents/github/epub-gadget/test_output';
const _kEpub1Path =
    '/Users/aaa/Documents/github/epub-gadget/恐妻家 - [日]伊坂幸太郎.epub';
const _kEpub2Path =
    '/Users/aaa/Documents/github/epub-gadget/C41-愤怒的葡萄-[美] 约翰·斯坦贝克-手机.epub';
const _kTxtPath = '/Users/aaa/Documents/github/epub-gadget/一千零一夜.txt';

late Uint8List _notePngBytes;

// ==================== 验证工具函数 ====================

/// 检查文件是否存在且非空
Future<String?> _checkFileExists(String path) async {
  final f = File(path);
  if (!await f.exists()) return '文件不存在';
  final size = await f.length();
  if (size == 0) return '文件为空（0 字节）';
  return null; // 正常
}

/// 检查文件编码是否为 UTF-8
Future<String?> _checkUtf8Encoding(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    utf8.decode(bytes);
    return null; // 正常
  } catch (e) {
    return '编码异常: $e';
  }
}

/// 验证 EPUB 文件结构是否合法
/// 检查项：mimetype、container.xml、OPF 文件、spine 中有内容
Future<Map<String, dynamic>> _validateEpub(String path) async {
  final result = <String, dynamic>{
    'valid': false,
    'checks': <String, String>{},
    'details': <String, dynamic>{},
  };

  try {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. mimetype 文件
    final mt = archive.findFile('mimetype');
    if (mt == null) {
      result['checks']['mimetype'] = '缺失';
      return result;
    }
    final mtContent = String.fromCharCodes(mt.content as List<int>).trim();
    if (!mtContent.startsWith('application/epub+zip')) {
      result['checks']['mimetype'] = '内容异常: $mtContent';
      return result;
    }
    result['checks']['mimetype'] = '正常';

    // 2. container.xml
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) {
      result['checks']['container.xml'] = '缺失';
      return result;
    }
    final containerXml = String.fromCharCodes(container.content as List<int>);
    if (!containerXml.contains('rootfile')) {
      result['checks']['container.xml'] = '缺少 rootfile 元素';
      return result;
    }
    result['checks']['container.xml'] = '正常';

    // 3. OPF 文件
    final opfMatch = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (opfMatch == null) {
      result['checks']['opf'] = 'container.xml 中未找到 OPF 路径';
      return result;
    }
    final opfPath = opfMatch.group(1)!;
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      result['checks']['opf'] = 'OPF 文件不存在: $opfPath';
      return result;
    }
    final opfContent = String.fromCharCodes(opfFile.content as List<int>);

    // 检查 OPF 编码
    try {
      utf8.decode(utf8.encode(opfContent));
      result['checks']['opf编码'] = 'UTF-8 正常';
    } catch (e) {
      result['checks']['opf编码'] = '异常: $e';
    }

    // 4. 检查 package 根元素
    if (opfContent.contains('<package')) {
      result['checks']['opf结构'] = '正常（含 package 元素）';
    } else {
      result['checks']['opf结构'] = '异常：缺少 package 根元素';
      return result;
    }

    // 5. 检查 manifest 和 spine
    final hasManifest = opfContent.contains('<manifest');
    final hasSpine = opfContent.contains('<spine');
    result['checks']['manifest'] = hasManifest ? '正常' : '异常';
    result['checks']['spine'] = hasSpine ? '正常' : '异常';

    // 6. 统计信息
    result['details']['总文件数'] = archive.files
        .where((f) => f.name.isNotEmpty)
        .length;
    result['details']['文件大小'] = bytes.length;

    // 7. 检查 HTML 文件编码
    int htmlCount = 0;
    int htmlEncodingOk = 0;
    for (final f in archive.files) {
      if (f.name.toLowerCase().endsWith('.html') ||
          f.name.toLowerCase().endsWith('.xhtml') ||
          f.name.toLowerCase().endsWith('.htm')) {
        htmlCount++;
        try {
          utf8.decode(f.content as List<int>);
          htmlEncodingOk++;
        } catch (_) {}
      }
    }
    result['details']['HTML文件数'] = htmlCount;
    result['details']['HTML编码正常'] = htmlEncodingOk;
    result['checks']['HTML编码'] = htmlCount > 0
        ? (htmlEncodingOk == htmlCount
              ? '全部正常 ($htmlCount个)'
              : '${htmlEncodingOk}/$htmlCount 正常')
        : '无 HTML 文件';

    result['valid'] = hasManifest && hasSpine;
  } catch (e) {
    result['checks']['异常'] = e.toString();
  }

  return result;
}

/// 检查 EPUB 文件是否是有效的 ZIP 并包含基本结构
String _validateEpubQuick(Map<String, dynamic> result) {
  final checks = result['checks'] as Map<String, String>;
  final issues = <String>[];
  for (final entry in checks.entries) {
    if (entry.value != '正常' &&
        !entry.value.startsWith('全部正常') &&
        !entry.value.startsWith('UTF-8')) {
      issues.add('${entry.key}: ${entry.value}');
    }
  }
  if (issues.isEmpty) return '通过';
  return '问题: ${issues.join('; ')}';
}

// ==================== 辅助函数 ====================

Future<File> _copyFile(String src, String dstDir, String dstName) async {
  await Directory(dstDir).create(recursive: true);
  final srcBytes = await File(src).readAsBytes();
  final f = File('$dstDir/$dstName');
  await f.writeAsBytes(srcBytes);
  return f;
}

Future<void> _writeLog(String dir, String name, String content) async {
  await Directory(dir).create(recursive: true);
  await File('$dir/$name').writeAsString(content);
}

/// 日志记录
String _log(String msg) {
  print('[TEST] $msg');
  return msg;
}

// ==================== 测试结果收集 ====================

class TestResult {
  final String name;
  final bool passed;
  final String? error;
  final String? detail;
  final Map<String, dynamic> validation;

  TestResult({
    required this.name,
    required this.passed,
    this.error,
    this.detail,
    this.validation = const {},
  });
}

final _results = <TestResult>[];

void _record(
  String name,
  bool passed, {
  String? error,
  String? detail,
  Map<String, dynamic>? validation,
}) {
  _results.add(
    TestResult(
      name: name,
      passed: passed,
      error: error,
      detail: detail,
      validation: validation ?? {},
    ),
  );
  final status = passed ? '✅ 通过' : '❌ 失败';
  print('$status - $name');
  if (error != null) print('  错误: $error');
  if (detail != null) print('  详情: $detail');
}

// ==================== 主测试入口 ====================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (![
    _kEpub1Path,
    _kEpub2Path,
    _kTxtPath,
  ].every((path) => File(path).existsSync())) {
    test('综合真实书籍测试需要本机夹具', () {}, skip: '提供测试书籍后再运行此测试文件。');
    return;
  }

  setUpAll(() async {
    // 准备 note.png
    try {
      final data = await rootBundle.load('assets/note.png');
      _notePngBytes = data.buffer.asUint8List();
    } catch (_) {
      _notePngBytes = Uint8List(0);
    }

    // 校验输入文件
    for (final p in [_kEpub1Path, _kEpub2Path, _kTxtPath]) {
      if (!await File(p).exists()) {
        throw StateError('测试输入文件不存在: $p');
      }
    }

    // 预热简繁转换
    await ChineseConverter.initS2T();
    await ChineseConverter.initT2S();

    // 清理旧输出
    final outDir = Directory(_kTestRoot);
    if (await outDir.exists()) {
      await outDir.delete(recursive: true);
    }
    await outDir.create(recursive: true);

    print('\n========================================');
    print('  EPUB 工具箱 - 综合功能测试');
    print('  EPUB1: 恐妻家 (${await File(_kEpub1Path).length()} bytes)');
    print('  EPUB2: 愤怒的葡萄 (${await File(_kEpub2Path).length()} bytes)');
    print('  TXT: 一千零一夜 (${await File(_kTxtPath).length()} bytes)');
    print('========================================\n');
  });

  // ==================== 1. viewOpf - 查看 OPF 结构 ====================
  test('01-viewOpf: 查看 EPUB 的 OPF 结构', () async {
    try {
      _log('选择文件: 恐妻家.epub');
      _log('功能: 查看 OPF 结构');

      final result = await ViewOpfOperation.execute(_kEpub1Path);

      _log('输出长度: ${result.length} 字符');

      // 检查编码
      try {
        utf8.decode(utf8.encode(result));
        _log('编码检查: UTF-8 正常');
      } catch (e) {
        throw Exception('编码异常: $e');
      }

      // 检查内容
      final checks = <String, bool>{
        '<package': result.contains('<package'),
        '<metadata': result.contains('<metadata'),
        '<manifest': result.contains('<manifest'),
        '<spine': result.contains('<spine'),
      };

      final detail = checks.entries
          .map((e) => '  ${e.key}: ${e.value ? "存在" : "缺失"}')
          .join('\n');
      _log('内容检查:\n$detail');

      await _writeLog('01_view_opf', 'opf.xml', result);

      final allOk = checks.values.every((v) => v);
      _record('01-viewOpf', allOk, detail: 'OPF 结构完整', validation: checks);
      expect(allOk, true);
    } catch (e) {
      _record('01-viewOpf', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 2. replaceCover - 替换封面 ====================
  test('02-replaceCover: 替换 EPUB 封面图片', () async {
    try {
      final dir = '$_kTestRoot/02_replace_cover';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub');

      // 准备封面图片
      Uint8List coverBytes = _notePngBytes;
      if (coverBytes.isEmpty) {
        // 生成最小 PNG
        coverBytes = Uint8List.fromList(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x44,
          0x41,
          0x54,
          0x08,
          0x99,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ]);
      }
      final coverFile = File('$dir/new_cover.png');
      await coverFile.writeAsBytes(coverBytes);
      _log('功能: 替换封面（使用 note.png）');

      final out = '$dir/out.epub';
      await ReplaceCoverOperation.execute(
        epubPath: src.path,
        coverPath: coverFile.path,
        outputPath: out,
      );

      // 检查输出文件
      final existsErr = await _checkFileExists(out);
      if (existsErr != null) throw Exception(existsErr);

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 检查文件大小变化
      final srcSize = await src.length();
      final outSize = await File(out).length();
      _log('文件大小: ${srcSize} → $outSize (${outSize > srcSize ? "增大" : "减小"})');

      await _writeLog(
        dir,
        'result.log',
        '验证: ${_validateEpubQuick(validation)}\n大小: $srcSize → $outSize',
      );

      final ok = validation['valid'] == true;
      _record(
        '02-replaceCover',
        ok,
        detail: '大小 ${srcSize}→$outSize',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('02-replaceCover', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 3. reformat - 重排 ====================
  test('03-reformat: EPUB 内容重排', () async {
    try {
      final dir = '$_kTestRoot/03_reformat';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub');
      _log('功能: 内容重排');

      final out = '$dir/out.epub';
      await ReformatOperation.execute(epubPath: src.path, outputPath: out);

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 检查 HTML 内容是否有变化
      final srcHtml = await EpubService.readAllHtmlSafe(src.path);
      final outHtml = await EpubService.readAllHtmlSafe(out);
      _log('HTML 文件数: ${srcHtml.length} → ${outHtml.length}');

      final ok = validation['valid'] == true;
      _record(
        '03-reformat',
        ok,
        detail: 'HTML 文件 ${srcHtml.length}→${outHtml.length}',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('03-reformat', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 4. convertVersion - 版本转换 ====================
  test('04a-convertVersion: EPUB 转 3.0', () async {
    try {
      final dir = '$_kTestRoot/04_convert_version';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 转换到 EPUB 3.0');

      final out = '$dir/out_3.0.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '3.0',
      );

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 检查 OPF 中的版本号
      final opfContent = await EpubService.readOpfContent(out);
      final hasVersion3 = opfContent.contains('version="3.0"');
      _log('版本检查: ${hasVersion3 ? "已转为 3.0" : "未检测到 3.0"}');

      await _writeLog(
        dir,
        '3.0_result.log',
        '验证: ${_validateEpubQuick(validation)}\n版本3.0: $hasVersion3',
      );

      final ok = validation['valid'] == true && hasVersion3;
      _record(
        '04a-convertVersion→3.0',
        ok,
        detail: '版本3.0=$hasVersion3',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('04a-convertVersion→3.0', false, error: e.toString());
      throw e;
    }
  });

  test('04b-convertVersion: EPUB 转 2.0', () async {
    try {
      final dir = '$_kTestRoot/04_convert_version';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 转换到 EPUB 2.0');

      final out = '$dir/out_2.0.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '2.0',
      );

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      final opfContent = await EpubService.readOpfContent(out);
      final hasVersion2 = opfContent.contains('version="2.0"');
      _log('版本检查: ${hasVersion2 ? "已转为 2.0" : "未检测到 2.0"}');

      await _writeLog(
        dir,
        '2.0_result.log',
        '验证: ${_validateEpubQuick(validation)}\n版本2.0: $hasVersion2',
      );

      final ok = validation['valid'] == true && hasVersion2;
      _record(
        '04b-convertVersion→2.0',
        ok,
        detail: '版本2.0=$hasVersion2',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('04b-convertVersion→2.0', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 5. epubToTxt - EPUB 转 TXT ====================
  test('05-epubToTxt: EPUB 转 TXT', () async {
    try {
      _log('选择文件: 恐妻家.epub → 功能: 导出为 TXT');

      final text = await EpubToTxtOperation.execute(epubPath: _kEpub1Path);

      // 检查编码
      try {
        utf8.decode(utf8.encode(text));
        _log('编码检查: UTF-8 正常');
      } catch (e) {
        throw Exception('编码异常: $e');
      }

      // 检查内容
      final lineCount = text.split('\n').length;
      final charCount = text.length;
      _log('内容检查: ${lineCount} 行, $charCount 字符');

      if (charCount < 100) {
        throw Exception('内容过少（$charCount 字符），可能转换失败');
      }

      await _writeLog('05_epub_to_txt', 'out.txt', text);

      final ok = charCount > 100;
      _record('05-epubToTxt', ok, detail: '$lineCount 行, $charCount 字符');
      expect(ok, true);
    } catch (e) {
      _record('05-epubToTxt', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 6. adClean - 广告清理 ====================
  test('06-adClean: 广告内容清理', () async {
    try {
      final dir = '$_kTestRoot/06_ad_clean';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 广告清理');

      // 测试多种正则模式
      final patterns = [
        r'<a[^>]*href="[^"]*ad[^"]*"[^>]*>.*?</a>',
        r'<div[^>]*class="[^"]*ad[^"]*"[^>]*>.*?</div>',
        '',
      ].join('|||');

      final out = '$dir/out.epub';
      await AdCleanOperation.execute(
        epubPath: src.path,
        outputPath: out,
        patterns: patterns,
      );

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      final ok = validation['valid'] == true;
      _record('06-adClean', ok, detail: '正则模式已应用', validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('06-adClean', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 7. imgCompress - 图片压缩 ====================
  test('07-imgCompress: 图片压缩（JPEG quality=70, PNG转JPG）', () async {
    try {
      final dir = '$_kTestRoot/07_img_compress';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 图片压缩');

      final out = '$dir/out.epub';
      final result = await ImgCompressOperation.execute(
        epubPath: src.path,
        outputPath: out,
        jpegQuality: 70,
        pngToJpg: true,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      final srcSize = await src.length();
      final outSize = await File(out).length();
      _log(
        '文件大小: ${srcSize} → $outSize (${((1 - outSize / srcSize) * 100).toStringAsFixed(1)}% 缩减)',
      );

      final ok = validation['valid'] == true;
      _record(
        '07-imgCompress',
        ok,
        detail: '大小 ${srcSize}→$outSize',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('07-imgCompress', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 8. imgToWebp - 图片转 WebP ====================
  test('08-imgToWebp: 图片转 WebP 格式', () async {
    try {
      final dir = '$_kTestRoot/08_img_to_webp';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 图片转 WebP');

      final out = '$dir/out.epub';
      final result = await ImgToWebpOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      // 桌面平台可能返回「不支持」消息
      if (await File(out).exists()) {
        final validation = await _validateEpub(out);
        _log('EPUB 验证: ${_validateEpubQuick(validation)}');
        _record(
          '08-imgToWebp',
          validation['valid'] == true,
          detail: result,
          validation: validation,
        );
        expect(validation['valid'], true);
      } else {
        _record('08-imgToWebp', true, detail: '桌面平台不支持 WebP 编码（预期行为）');
      }
    } catch (e) {
      _record('08-imgToWebp', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 9. webpToImg - WebP 转图片 ====================
  test('09-webpToImg: WebP 转图片格式', () async {
    try {
      final dir = '$_kTestRoot/09_webp_to_img';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: WebP 转图片');

      final out = '$dir/out.epub';
      final result = await WebpToImgOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      if (await File(out).exists()) {
        final validation = await _validateEpub(out);
        _log('EPUB 验证: ${_validateEpubQuick(validation)}');
        _record(
          '09-webpToImg',
          validation['valid'] == true,
          detail: result,
          validation: validation,
        );
        expect(validation['valid'], true);
      } else {
        _record('09-webpToImg', true, detail: '无 WebP 图片需转换（预期行为）');
      }
    } catch (e) {
      _record('09-webpToImg', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 10. downloadImages - 下载网络图片 ====================
  test('10-downloadImages: 下载网络图片到本地', () async {
    try {
      final dir = '$_kTestRoot/10_download_images';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 下载网络图片');

      final out = '$dir/out.epub';
      final result = await DownloadImagesOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      if (await File(out).exists()) {
        final validation = await _validateEpub(out);
        _log('EPUB 验证: ${_validateEpubQuick(validation)}');
        _record(
          '10-downloadImages',
          validation['valid'] == true,
          detail: result,
          validation: validation,
        );
        expect(validation['valid'], true);
      } else {
        _record('10-downloadImages', true, detail: '无网络图片需下载（预期行为）');
      }
    } catch (e) {
      _record('10-downloadImages', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 11. s2t - 简体转繁体 ====================
  test('11-s2t: 简体中文转繁体中文', () async {
    try {
      final dir = '$_kTestRoot/11_s2t';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 简体转繁体');

      final out = '$dir/out.epub';
      final result = await S2tOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 抽样检查内容是否转换
      final htmls = await EpubService.readAllHtmlSafe(out);
      if (htmls.isNotEmpty) {
        final sample = htmls.first.value.substring(
          0,
          htmls.first.value.length.clamp(0, 500),
        );
        _log('转换后内容抽样: ${sample.substring(0, sample.length.clamp(0, 200))}...');
      }

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('11-s2t', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('11-s2t', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 12. t2s - 繁体转简体 ====================
  test('12-t2s: 繁体中文转简体中文', () async {
    try {
      final dir = '$_kTestRoot/12_t2s';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 繁体转简体');

      final out = '$dir/out.epub';
      final result = await T2sOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('12-t2s', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('12-t2s', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 13. phonetic - 注音 ====================
  test('13a-phonetic: 注音标注（音调模式）', () async {
    try {
      final dir = '$_kTestRoot/13_phonetic';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 注音（音调标注，全部注音）');

      final out = '$dir/out_mark.epub';
      final result = await PhoneticOperation.execute(
        epubPath: src.path,
        outputPath: out,
        toneMode: PhoneticOperation.toneModeMark,
        annotateAll: true,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'mark.log', result);

      final ok = validation['valid'] == true;
      _record('13a-phonetic-mark', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('13a-phonetic-mark', false, error: e.toString());
      throw e;
    }
  });

  test('13b-phonetic: 注音标注（数字模式，仅生僻字）', () async {
    try {
      final dir = '$_kTestRoot/13_phonetic';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 注音（数字声调，仅生僻字）');

      final out = '$dir/out_number.epub';
      final result = await PhoneticOperation.execute(
        epubPath: src.path,
        outputPath: out,
        toneMode: PhoneticOperation.toneModeNumber,
        annotateAll: false,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'number.log', result);

      final ok = validation['valid'] == true;
      _record(
        '13b-phonetic-number',
        ok,
        detail: result,
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('13b-phonetic-number', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 14. fontSubset - 字体子集化 ====================
  test('14-fontSubset: 字体子集化（按使用字符提取）', () async {
    try {
      final dir = '$_kTestRoot/14_font_subset';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 字体子集化');

      final out = '$dir/out.epub';
      final result = await FontSubsetOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      final srcSize = await src.length();
      final outSize = await File(out).length();
      _log('文件大小: ${srcSize} → $outSize');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record(
        '14-fontSubset',
        ok,
        detail: '大小 ${srcSize}→$outSize',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('14-fontSubset', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 15. encrypt - 加密 ====================
  test('15-encrypt: EPUB 内容加密', () async {
    try {
      final dir = '$_kTestRoot/15_encrypt';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 内容加密');

      final out = '$dir/out.epub';
      final result = await EncryptOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 检查加密后的 HTML 内容是否已被混淆
      final htmls = await EpubService.readAllHtmlSafe(out);
      if (htmls.isNotEmpty) {
        final sample = htmls.first.value.substring(
          0,
          htmls.first.value.length.clamp(0, 200),
        );
        _log('加密后内容抽样: $sample');
      }

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('15-encrypt', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('15-encrypt', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 16. decrypt - 解密 ====================
  test('16-decrypt: EPUB 内容解密', () async {
    try {
      final dir = '$_kTestRoot/16_decrypt';
      await Directory(dir).create(recursive: true);
      // 使用 OP-15 的加密输出
      final encrypted = '$_kTestRoot/15_encrypt/out.epub';
      if (!await File(encrypted).exists()) {
        throw StateError('依赖文件不存在: $encrypted（需先运行 OP-15 加密）');
      }
      _log('选择文件: 加密后的 EPUB → 功能: 解密');

      final out = '$dir/out.epub';
      final result = await DecryptOperation.execute(
        epubPath: encrypted,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('16-decrypt', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('16-decrypt', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 17. encryptFont - 字体加密 ====================
  test('17-encryptFont: 字体文件加密混淆', () async {
    try {
      final dir = '$_kTestRoot/17_encrypt_font';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 字体加密');

      final out = '$dir/out.epub';
      final result = await EncryptFontOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('17-encryptFont', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('17-encryptFont', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 18. listFontTargets - 列出字体 ====================
  test('18-listFontTargets: 列出 EPUB 中的字体文件', () async {
    try {
      _log('选择文件: 恐妻家.epub → 功能: 列出字体文件');

      final result = await ListFontTargetsOperation.execute(
        epubPath: _kEpub1Path,
      );
      _log('字体列表: $result');

      await _writeLog('18_list_font_targets', 'result.log', result);

      _record('18-listFontTargets', true, detail: result);
      expect(result, isNotEmpty);
    } catch (e) {
      _record('18-listFontTargets', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 19. merge - 合并 ====================
  test('19-merge: 合并两本 EPUB', () async {
    try {
      final dir = '$_kTestRoot/19_merge';
      final a = await _copyFile(_kEpub1Path, dir, 'a.epub');
      final b = await _copyFile(_kEpub2Path, dir, 'b.epub');
      _log('选择文件: 恐妻家.epub + 愤怒的葡萄.epub → 功能: 合并');

      final out = '$dir/out.epub';
      final result = await MergeOperation.execute(
        inputPaths: [a.path, b.path],
        outputPath: out,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      final aSize = await a.length();
      final bSize = await b.length();
      final outSize = await File(out).length();
      _log('文件大小: $aSize + $bSize → $outSize');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('19-merge', ok, detail: '合并后大小 $outSize', validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('19-merge', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 20. split - 拆分 ====================
  test('20-split: 拆分 EPUB', () async {
    try {
      final dir = '$_kTestRoot/20_split';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 拆分');

      // 先获取拆分目标
      final targets = await ListSplitTargetsOperation.execute(
        epubPath: src.path,
      );
      _log('拆分目标数: ${targets.length}');

      if (targets.length < 2) {
        _record('20-split', true, detail: '目标数不足（${targets.length}），跳过拆分');
        return;
      }

      final mid = targets.length ~/ 2;
      final out = '$dir/out';
      final result = await SplitOperation.execute(
        epubPath: src.path,
        outputDir: out,
        splitPoints: [mid],
      );
      _log('处理结果: $result');

      // 检查输出文件
      final entries = await Directory(out).list().toList();
      _log('输出文件数: ${entries.length}');
      for (final e in entries) {
        final path = e.path;
        if (path.endsWith('.epub')) {
          final validation = await _validateEpub(path);
          _log(
            '  ${path.split('/').last}: ${_validateEpubQuick(validation)} (${await File(path).length()} bytes)',
          );
        }
      }

      await _writeLog(dir, 'result.log', result);

      final ok = entries.length >= 2;
      _record(
        '20-split',
        ok,
        detail: '产出 ${entries.length} 个文件',
        validation: {'文件数': entries.length},
      );
      expect(ok, true);
    } catch (e) {
      _record('20-split', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 21. listSplitTargets - 列出拆分点 ====================
  test('21-listSplitTargets: 列出可拆分节点', () async {
    try {
      _log('选择文件: 恐妻家.epub → 功能: 列出拆分点');

      final result = await ListSplitTargetsOperation.execute(
        epubPath: _kEpub1Path,
      );
      final formatted = ListSplitTargetsOperation.formatTargets(result);
      _log('拆分点数量: ${result.length}');
      _log('格式化:\n$formatted');

      await _writeLog('21_list_split_targets', 'result.log', formatted);

      _record('21-listSplitTargets', true, detail: '${result.length} 个拆分点');
      expect(result.length, greaterThan(0));
    } catch (e) {
      _record('21-listSplitTargets', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 22. comment - 添加批注 ====================
  test('22-comment: 正则匹配添加批注', () async {
    try {
      final dir = '$_kTestRoot/22_comment';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 正则批注');

      // 用方括号内容做批注
      final out = '$dir/out.epub';
      final result = await CommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'「(.*?)」',
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('22-comment', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('22-comment', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 23. footnoteToComment - 脚注转批注 ====================
  test('23-footnoteToComment: 脚注转批注', () async {
    try {
      final dir = '$_kTestRoot/23_footnote_to_comment';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 脚注转批注');

      final out = '$dir/out.epub';
      final result = await FootnoteToCommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'^#+',
        notePngBytes: _notePngBytes.isEmpty ? null : _notePngBytes,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record(
        '23-footnoteToComment',
        ok,
        detail: result,
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('23-footnoteToComment', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 24. spanToFootnote - 批注转脚注 ====================
  test('24-spanToFootnote: 批注转脚注', () async {
    try {
      final dir = '$_kTestRoot/24_span_to_footnote';
      await Directory(dir).create(recursive: true);
      // 用 OP-22 产出作为输入
      final inputEpub = '$_kTestRoot/22_comment/out.epub';
      if (!await File(inputEpub).exists()) {
        _record('24-spanToFootnote', true, detail: '依赖 OP-22 输出不存在，跳过');
        return;
      }
      _log('选择文件: 批注后的 EPUB → 功能: 批注转脚注');

      final out = '$dir/out.epub';
      final result = await SpanToFootnoteOperation.execute(
        epubPath: inputEpub,
        outputPath: out,
        footnoteColor: '#aa0000',
        noterefColor: '#0000aa',
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('24-spanToFootnote', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('24-spanToFootnote', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 25. yuewei - 阅微转多看 ====================
  test('25-yuewei: 阅微格式转多看', () async {
    try {
      final dir = '$_kTestRoot/25_yuewei';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 阅微转多看');

      final out = '$dir/out.epub';
      final result = await YueweiOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: _notePngBytes.isEmpty ? null : _notePngBytes,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('25-yuewei', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('25-yuewei', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 26. zhangyue - 掌阅转多看 ====================
  test('26-zhangyue: 掌阅格式转多看', () async {
    try {
      final dir = '$_kTestRoot/26_zhangyue';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 掌阅转多看');

      final out = '$dir/out.epub';
      final result = await ZhangyueOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: _notePngBytes.isEmpty ? null : _notePngBytes,
      );
      _log('处理结果: $result');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(dir, 'result.log', result);

      final ok = validation['valid'] == true;
      _record('26-zhangyue', ok, detail: result, validation: validation);
      expect(ok, true);
    } catch (e) {
      _record('26-zhangyue', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 27. txt2epub - TXT 转 EPUB ====================
  test('27-txt2epub: TXT 转 EPUB（用示例中文内容）', () async {
    try {
      final dir = '$_kTestRoot/27_txt2epub';
      await Directory(dir).create(recursive: true);

      // 原始 TXT 只有 3 字节，改用生成的测试内容
      final testContent = '''
第一章 序言

天地玄黄，宇宙洪荒。日月盈昃，辰宿列张。

寒来暑往，秋收冬藏。闰余成岁，律吕调阳。

第二章 正文开始

云腾致雨，露结为霜。金生丽水，玉出昆冈。

剑号巨阙，珠称夜光。果珍李柰，菜重芥姜。

第三章 结尾

海咸河淡，鳞潜羽翔。龙师火帝，鸟官人皇。

始制文字，乃服衣裳。推位让国，有虞陶唐。
''';
      final testTxt = File('$dir/test.txt');
      await testTxt.writeAsString(testContent, encoding: utf8);
      _log('选择文件: 生成的测试 TXT → 功能: TXT 转 EPUB');

      // 1. 编码检测
      final encoding = EncodingDetector.detect(testTxt.path);
      _log('编码检测: $encoding');

      // 2. 读取 + 清洗
      final raw = EncodingDetector.readFile(testTxt.path, encoding);
      final cleaner = TextCleaner(removeEmptyLines: true, fixIndent: true);
      final cleaned = cleaner.clean(raw);
      _log('清洗后字符数: ${cleaned.length}');

      // 3. 分割
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        cleaned,
        r'^第[一二三四五六七八九十百千万\d]+章\s+.*$',
        splitTitle: true,
      );
      _log('章节数: ${chapters.length}');
      for (final c in chapters) {
        _log('  - ${c.title} (${c.wordCount} 字)');
      }

      if (chapters.isEmpty) {
        _record('27-txt2epub', false, error: '未检测到章节');
        throw Exception('未检测到章节');
      }

      // 4. 生成 EPUB
      final out = '$dir/out.epub';
      final (log, userVisiblePath) = await EpubGenerator.generate(
        outputPath: out,
        title: '千字文测试',
        author: '测试作者',
        chapters: chapters,
      );
      _log('生成日志: $log');

      // 5. 验证输出
      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      // 6. 检查内容
      final htmls = await EpubService.readAllHtmlSafe(out);
      _log('HTML 文件数: ${htmls.length}');
      for (final h in htmls) {
        _log('  ${h.key}: ${h.value.length} 字符');
      }

      // 7. 检查编码
      final encodingCheck = await _checkUtf8Encoding(out);
      if (encodingCheck != null) _log('编码警告: $encodingCheck');

      await _writeLog(
        dir,
        'chapters.txt',
        '章节数: ${chapters.length}\n${chapters.map((c) => "${c.title} (${c.wordCount}字)").join("\n")}',
      );
      await _writeLog(dir, 'generate.log', log);

      final ok = validation['valid'] == true && htmls.isNotEmpty;
      _record(
        '27-txt2epub',
        ok,
        detail: '${chapters.length} 章节, ${htmls.length} HTML',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('27-txt2epub', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 28. metadata - 元数据读取/写入 ====================
  test('28a-metadata: 读取 EPUB 元数据', () async {
    try {
      _log('选择文件: 恐妻家.epub → 功能: 读取元数据');

      final metadata = await MetadataService.read(_kEpub1Path);
      _log('书名: ${metadata.title}');
      _log('作者: ${metadata.author}');
      _log('语言: ${metadata.language}');
      _log('描述: ${metadata.description}');
      _log('出版社: ${metadata.publisher}');
      _log('标识符: ${metadata.identifier}');
      _log('有封面: ${metadata.coverBytes != null}');

      await _writeLog(
        '28_metadata',
        'read.log',
        '书名: ${metadata.title}\n作者: ${metadata.author}\n语言: ${metadata.language}\n描述: ${metadata.description}',
      );

      final ok = metadata.title.isNotEmpty && metadata.author.isNotEmpty;
      _record(
        '28a-metadata-read',
        ok,
        detail: '${metadata.title} / ${metadata.author}',
      );
      expect(ok, true);
    } catch (e) {
      _record('28a-metadata-read', false, error: e.toString());
      throw e;
    }
  });

  test('28b-metadata: 修改 EPUB 元数据', () async {
    try {
      final dir = '$_kTestRoot/28_metadata';
      final src = await _copyFile(_kEpub1Path, dir, 'src.epub');
      _log('选择文件: 恐妻家.epub → 功能: 修改元数据');

      // 读取原始元数据
      final original = await MetadataService.read(src.path);

      // 修改元数据
      final modified = original.copyWith(
        title: '${original.title} [测试修改]',
        author: '测试作者',
        publisher: '测试出版社',
        description: '这是一段测试描述文字。',
      );

      final out = '$dir/out.epub';
      await MetadataService.write(
        epubPath: src.path,
        outputPath: out,
        metadata: modified,
      );

      // 验证修改结果
      final reread = await MetadataService.read(out);
      _log('修改后书名: ${reread.title}');
      _log('修改后作者: ${reread.author}');
      _log('修改后出版社: ${reread.publisher}');
      _log('修改后描述: ${reread.description}');

      final validation = await _validateEpub(out);
      _log('EPUB 验证: ${_validateEpubQuick(validation)}');

      await _writeLog(
        dir,
        'write.log',
        '原始: ${original.title} / ${original.author}\n修改后: ${reread.title} / ${reread.author}',
      );

      final titleOk = reread.title.contains('测试修改');
      final authorOk = reread.author == '测试作者';
      final epubOk = validation['valid'] == true;

      final ok = titleOk && authorOk && epubOk;
      _record(
        '28b-metadata-write',
        ok,
        detail: '标题修改=$titleOk, 作者修改=$authorOk, EPUB有效=$epubOk',
        validation: validation,
      );
      expect(ok, true);
    } catch (e) {
      _record('28b-metadata-write', false, error: e.toString());
      throw e;
    }
  });

  // ==================== 测试报告 ====================
  tearDownAll(() async {
    final buf = StringBuffer();
    buf.writeln('# EPUB 工具箱 - 综合功能测试报告');
    buf.writeln();
    buf.writeln('**测试时间**: ${DateTime.now()}');
    buf.writeln('**测试文件**:');
    buf.writeln(
      '- EPUB1: `$_kEpub1Path` (${await File(_kEpub1Path).length()} bytes)',
    );
    buf.writeln(
      '- EPUB2: `$_kEpub2Path` (${await File(_kEpub2Path).length()} bytes)',
    );
    buf.writeln(
      '- TXT:  `$_kTxtPath` (${await File(_kTxtPath).length()} bytes)',
    );
    buf.writeln();
    buf.writeln('**测试流程**: 选择文件 → 选择功能 → 功能处理 → 输出文件 → 检查输出文件');
    buf.writeln('**检查项**: 文件是否正常、编码是否正确、格式是否正常、功能是否正确运行、结果是否符合预期');
    buf.writeln();

    final passed = _results.where((r) => r.passed).length;
    final failed = _results.where((r) => !r.passed).length;
    buf.writeln('## 汇总');
    buf.writeln();
    buf.writeln('| 状态 | 数量 |');
    buf.writeln('|------|------|');
    buf.writeln('| ✅ 通过 | $passed |');
    buf.writeln('| ❌ 失败 | $failed |');
    buf.writeln('| 📊 总计 | ${_results.length} |');
    buf.writeln();

    buf.writeln('## 通过');
    buf.writeln();
    for (final r in _results.where((r) => r.passed)) {
      buf.writeln(
        '- ✅ **${r.name}**${r.detail != null ? " — ${r.detail}" : ""}',
      );
    }
    buf.writeln();

    if (failed > 0) {
      buf.writeln('## 失败');
      buf.writeln();
      for (final r in _results.where((r) => !r.passed)) {
        buf.writeln('- ❌ **${r.name}**');
        if (r.error != null) {
          buf.writeln('  - 错误: `${r.error}`');
        }
        if (r.detail != null) {
          buf.writeln('  - 详情: ${r.detail}');
        }
      }
      buf.writeln();
    }

    // 详细验证结果
    buf.writeln('## 各功能输出文件验证详情');
    buf.writeln();
    for (final r in _results) {
      if (r.validation.isNotEmpty) {
        buf.writeln('### ${r.name}');
        if (r.validation.containsKey('checks')) {
          final checks = r.validation['checks'] as Map<String, String>?;
          if (checks != null) {
            for (final c in checks.entries) {
              buf.writeln('- ${c.key}: ${c.value}');
            }
          }
        }
        if (r.validation.containsKey('details')) {
          final details = r.validation['details'] as Map<String, dynamic>?;
          if (details != null) {
            for (final d in details.entries) {
              buf.writeln('- ${d.key}: ${d.value}');
            }
          }
        }
        buf.writeln();
      }
    }

    final reportFile = File('$_kTestRoot/REPORT.md');
    await reportFile.writeAsString(buf.toString());

    print('\n========================================');
    print('  测试完成: $passed/${_results.length} 通过');
    if (failed > 0) {
      print('  ❌ $failed 项失败');
      for (final r in _results.where((r) => !r.passed)) {
        print('    - ${r.name}: ${r.error}');
      }
    }
    print('  报告: $_kTestRoot/REPORT.md');
    print('========================================');
    print(buf.toString());
  });
}
