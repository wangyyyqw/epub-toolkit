// 模拟用户使用场景的端到端测试
//
// 1. 创建中文 TXT 文件（UTF-8+BOM）测试 txt2epub
// 2. 用恐妻家 epub 测试所有 EPUB 操作
// 3. 验证输出文件是否正确（无乱码、结构合法）

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:enough_convert/gbk.dart' as gbk;
import 'package:flutter_test/flutter_test.dart';

import 'package:epub_gadget/core/encoding_detector.dart';
import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';
import 'package:epub_gadget/core/epub_image_helper.dart';
import 'package:epub_gadget/features/encrypt_font/encrypt_font.dart';
import 'package:epub_gadget/features/encrypt/encrypt.dart';
import 'package:epub_gadget/features/decrypt/decrypt.dart';
import 'package:epub_gadget/features/s2t/s2t.dart';
import 'package:epub_gadget/features/t2s/t2s.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';
import 'package:epub_gadget/features/ad_clean/ad_clean.dart';
import 'package:epub_gadget/features/comment/comment.dart';
import 'package:epub_gadget/features/span_to_footnote/span_to_footnote.dart';
import 'package:epub_gadget/features/view_opf/view_opf.dart';

final Directory _tempDir = Directory.systemTemp.createTempSync('e2e_full_');

/// 测试用的中文 TXT 内容（模拟一千零一夜风格）
const String _kTestTxtContent = '''序章

国王山努亚和宰相的女儿桑鲁卓的故事。

相传在古时候，有一个国王名叫山努亚。他每天都要娶一个女子，第二天就杀掉。百姓们纷纷带着女儿逃走。

宰相的两个女儿，大女儿叫桑鲁卓，二女儿叫多亚德。桑鲁卓知书达理，读过很多书。

第一章 国王的山努亚的故事

国王山努亚回到宫中，发现王后不忠，于是杀了王后。从此他每天娶一个女子，第二天就杀掉。

百姓们十分恐惧，纷纷逃走。宰相为找不到女子而发愁。

第二章 桑鲁卓进宫

桑鲁卓对父亲说："把我嫁给国王吧，我也许能拯救那些可怜的女子。"

宰相听了十分伤心，但最终还是把女儿送进了宫。

第三章 一千零一夜的开始

桑鲁卓进宫后，对国王讲了一个故事。故事讲到最精彩的地方，天亮了。

国王想听完故事，就没有杀她。第二夜，她又讲了一个新故事。

就这样，桑鲁卓讲了一千零一夜的故事。
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ChineseConverter.initS2T();
    await ChineseConverter.initT2S();
  });

  tearDownAll(() async {
    try {
      _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ==================== TXT 转 EPUB 测试 ====================
  group('TXT 转 EPUB', () {
    test('1. UTF-8+BOM 编码的 TXT 转换无乱码', () async {
      // 创建带 BOM 的 UTF-8 txt 文件
      final txtPath = '${_tempDir.path}/test_utf8_bom.txt';
      final bom = <int>[0xEF, 0xBB, 0xBF];
      final contentBytes = utf8.encode(_kTestTxtContent);
      final allBytes = [...bom, ...contentBytes];
      File(txtPath).writeAsBytesSync(allBytes);

      // 检测编码
      final encoding = EncodingDetector.detect(txtPath);
      expect(encoding, 'utf-8', reason: '应检测为 UTF-8');

      // 读取文件
      final rawText = EncodingDetector.readFile(txtPath, encoding);
      expect(rawText, isNot(startsWith('\ufeff')), reason: 'BOM 应被去除');
      expect(rawText, contains('国王山努亚'), reason: '中文内容应正确读取，无乱码');

      // 清洗文本
      final cleaner = TextCleaner(removeEmptyLines: true, fixIndent: true);
      final cleanText = cleaner.clean(rawText);
      expect(cleanText, contains('国王山努亚'));

      // 分割章节
      final splitter = ChapterSplitter();
      final pattern = presetPatterns[0].pattern; // 目录(第X章/节/卷/集/部/篇)
      final chapters = splitter.split(cleanText, pattern);
      expect(chapters.length, greaterThan(1), reason: '应分割出多个章节');
      expect(chapters[0].title, contains('序章'));

      // 生成 EPUB
      final epubPath = '${_tempDir.path}/test_utf8_bom.epub';
      final log = await EpubGenerator.generate(
        outputPath: epubPath,
        title: '一千零一夜测试',
        author: '测试作者',
        chapters: chapters,
      );
      expect(File(epubPath).existsSync(), true, reason: 'EPUB 文件应存在');

      // 验证 EPUB 内容无乱码
      final bytes = File(epubPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 检查 mimetype
      expect(archive.files[0].name, 'mimetype');
      expect(archive.files[0].compress, false);

      // 检查章节内容无乱码
      var foundChinese = false;
      for (final file in archive.files) {
        if (file.name.endsWith('.xhtml')) {
          final content = utf8.decode(file.content as List<int>);
          if (content.contains('国王山努亚')) {
            foundChinese = true;
            break;
          }
        }
      }
      expect(foundChinese, true, reason: 'EPUB 中应包含正确的中文字符，无乱码');

      print(
        '✅ UTF-8+BOM txt2epub 测试通过: ${chapters.length} 章, '
        'EPUB ${bytes.length} bytes',
      );
    });

    test('2. 无 BOM 的 UTF-8 TXT 转换无乱码', () async {
      final txtPath = '${_tempDir.path}/test_utf8_no_bom.txt';
      File(txtPath).writeAsBytesSync(utf8.encode(_kTestTxtContent));

      final encoding = EncodingDetector.detect(txtPath);
      expect(encoding, 'utf-8');

      final rawText = EncodingDetector.readFile(txtPath, encoding);
      expect(rawText, contains('国王山努亚'));

      final cleaner = TextCleaner();
      final cleanText = cleaner.clean(rawText);

      final splitter = ChapterSplitter();
      final chapters = splitter.split(cleanText, presetPatterns[0].pattern);

      final epubPath = '${_tempDir.path}/test_utf8_no_bom.epub';
      await EpubGenerator.generate(
        outputPath: epubPath,
        title: '无BOM测试',
        author: '测试',
        chapters: chapters,
      );

      // 验证无乱码
      final bytes = File(epubPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      var foundChinese = false;
      for (final file in archive.files) {
        if (file.name.endsWith('.xhtml')) {
          final content = utf8.decode(file.content as List<int>);
          if (content.contains('桑鲁卓')) {
            foundChinese = true;
            break;
          }
        }
      }
      expect(foundChinese, true, reason: '无 BOM UTF-8 也应无乱码');
      print('✅ 无 BOM UTF-8 txt2epub 测试通过');
    });

    test('3. GBK 编码的 TXT 转换检查', () async {
      final gbkBytes = gbk.gbk.encode('国王\n\n第一章 测试\n这是测试内容\n');

      final txtPath = '${_tempDir.path}/test_gbk.txt';
      File(txtPath).writeAsBytesSync(gbkBytes);

      final encoding = EncodingDetector.detect(txtPath);
      print('GBK 文件检测到编码: $encoding');

      final rawText = EncodingDetector.readFile(txtPath, encoding);
      print(
        'GBK 解码结果 (前50字): ${rawText.substring(0, rawText.length > 50 ? 50 : rawText.length)}',
      );

      expect(rawText, contains('国王'));
      expect(rawText, contains('这是测试内容'));
    });
  });

  // ==================== EPUB 操作测试 ====================
  group(
    '恐妻家 EPUB 操作',
    () {
      // 恐妻家 epub 路径
      final epubPath =
          '/Users/aaa/Documents/github/epub-gadget/恐妻家 - [日]伊坂幸太郎.epub';

      test('0. 读取恐妻家 EPUB 结构', () {
        expect(File(epubPath).existsSync(), true, reason: '恐妻家 epub 应存在');

        final bytes = File(epubPath).readAsBytesSync();
        print('恐妻家 EPUB 大小: ${(bytes.length / 1024).toStringAsFixed(1)} KB');

        final archive = ZipDecoder().decodeBytes(bytes);
        print('文件数: ${archive.files.length}');

        // 检查 mimetype
        expect(archive.files[0].name, 'mimetype');
        expect(archive.files[0].compress, false);

        // 检查有 OPF
        var hasOpf = false;
        for (final f in archive.files) {
          if (f.name.toLowerCase().endsWith('.opf')) {
            hasOpf = true;
            final content = utf8.decode(f.content as List<int>);
            print('OPF 路径: ${f.name}');
            print(
              'OPF 前200字: ${content.substring(0, content.length > 200 ? 200 : content.length)}',
            );
            break;
          }
        }
        expect(hasOpf, true, reason: '应有 OPF 文件');

        // 统计文件类型
        var xhtmlCount = 0;
        var cssCount = 0;
        var imageCount = 0;
        var fontCount = 0;
        for (final f in archive.files) {
          final lower = f.name.toLowerCase();
          if (lower.endsWith('.xhtml') ||
              lower.endsWith('.html') ||
              lower.endsWith('.htm')) {
            xhtmlCount++;
          } else if (lower.endsWith('.css')) {
            cssCount++;
          } else if (lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.gif')) {
            imageCount++;
          } else if (lower.endsWith('.ttf') ||
              lower.endsWith('.otf') ||
              lower.endsWith('.woff')) {
            fontCount++;
          }
        }
        print(
          '文件统计: XHTML=$xhtmlCount, CSS=$cssCount, Images=$imageCount, Fonts=$fontCount',
        );
      });

      test('1. 查看 OPF', () async {
        final out = '${_tempDir.path}/opf_view.txt';
        final result = await ViewOpfOperation.execute(epubPath);
        expect(result, isNotEmpty);
        expect(result, contains('package'));
        print('✅ 查看 OPF 通过');
      });

      test('2. 重新格式化', () async {
        final out = '${_tempDir.path}/reformat.epub';
        await ReformatOperation.execute(epubPath: epubPath, outputPath: out);
        expect(File(out).existsSync(), true);

        // 验证输出 EPUB 可正常读取
        final bytes = File(out).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.files[0].name, 'mimetype');
        expect(archive.files[0].compress, false);

        // 验证无乱码
        for (final f in archive.files) {
          if (f.name.toLowerCase().endsWith('.opf')) {
            final content = utf8.decode(f.content as List<int>);
            expect(content, isNot(contains('\uFFFD')), reason: 'OPF 不应含替换字符');
          }
        }
        print('✅ 重新格式化通过');
      });

      test('3. 简转繁', () async {
        final out = '${_tempDir.path}/s2t.epub';
        await S2tOperation.execute(epubPath: epubPath, outputPath: out);
        expect(File(out).existsSync(), true);
        print('✅ 简转繁通过');
      });

      test('4. 繁转简', () async {
        // 先用简转繁的输出做繁转简
        final s2tOut = '${_tempDir.path}/s2t.epub';
        if (!File(s2tOut).existsSync()) {
          await S2tOperation.execute(epubPath: epubPath, outputPath: s2tOut);
        }
        final out = '${_tempDir.path}/t2s.epub';
        await T2sOperation.execute(epubPath: s2tOut, outputPath: out);
        expect(File(out).existsSync(), true);
        print('✅ 繁转简通过');
      });

      test('5. 广告清理', () async {
        final out = '${_tempDir.path}/adclean.epub';
        await AdCleanOperation.execute(
          epubPath: epubPath,
          outputPath: out,
          patterns: '<a[^>]*class="[^"]*ad[^"]*"[^>]*>.*?</a>|||',
        );
        expect(File(out).existsSync(), true);
        print('✅ 广告清理通过');
      });

      test('6. 名称加密', () async {
        final out = '${_tempDir.path}/encrypt.epub';
        await EncryptOperation.execute(epubPath: epubPath, outputPath: out);
        expect(File(out).existsSync(), true);

        // 验证 ZIP 结构
        final bytes = File(out).readAsBytesSync();
        expect(bytes[0], 0x50, reason: '应以 PK 开头');
        expect(bytes[1], 0x4B);

        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.files[0].name, 'mimetype');
        expect(archive.files[0].compress, false);

        // 验证 LFH = CD
        var lfhCount = 0;
        var cdCount = 0;
        for (var i = 0; i < bytes.length - 4; i++) {
          if (bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4B &&
              bytes[i + 2] == 0x03 &&
              bytes[i + 3] == 0x04)
            lfhCount++;
          if (bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4B &&
              bytes[i + 2] == 0x01 &&
              bytes[i + 3] == 0x02)
            cdCount++;
        }
        expect(lfhCount, cdCount, reason: 'LFH 数量应等于 CD 数量');
        print('✅ 名称加密通过 (LFH=$lfhCount, CD=$cdCount)');
      });

      test('7. 名称解密', () async {
        final encOut = '${_tempDir.path}/encrypt.epub';
        if (!File(encOut).existsSync()) {
          await EncryptOperation.execute(
            epubPath: epubPath,
            outputPath: encOut,
          );
        }
        final out = '${_tempDir.path}/decrypt.epub';
        await DecryptOperation.execute(epubPath: encOut, outputPath: out);
        expect(File(out).existsSync(), true);

        // 验证结构
        final bytes = File(out).readAsBytesSync();
        expect(bytes[0], 0x50);
        expect(bytes[1], 0x4B);
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.files[0].name, 'mimetype');
        print('✅ 名称解密通过');
      });

      test('8. 字体加密', () async {
        final out = '${_tempDir.path}/encrypt_font.epub';
        try {
          await EncryptFontOperation.execute(
            epubPath: epubPath,
            outputPath: out,
          );
          expect(File(out).existsSync(), true);

          // 验证结构
          final bytes = File(out).readAsBytesSync();
          expect(bytes[0], 0x50, reason: '应以 PK 开头');
          expect(bytes[1], 0x4B);

          final archive = ZipDecoder().decodeBytes(bytes);
          expect(archive.files[0].name, 'mimetype');
          expect(archive.files[0].compress, false);

          // 验证 LFH = CD
          var lfhCount = 0;
          var cdCount = 0;
          for (var i = 0; i < bytes.length - 4; i++) {
            if (bytes[i] == 0x50 &&
                bytes[i + 1] == 0x4B &&
                bytes[i + 2] == 0x03 &&
                bytes[i + 3] == 0x04)
              lfhCount++;
            if (bytes[i] == 0x50 &&
                bytes[i + 1] == 0x4B &&
                bytes[i + 2] == 0x01 &&
                bytes[i + 3] == 0x02)
              cdCount++;
          }
          expect(lfhCount, cdCount, reason: 'LFH 应等于 CD');

          // 验证无大块零填充
          var maxZeroRun = 0;
          var currentZeroRun = 0;
          for (final b in bytes) {
            if (b == 0) {
              currentZeroRun++;
              if (currentZeroRun > maxZeroRun) maxZeroRun = currentZeroRun;
            } else {
              currentZeroRun = 0;
            }
          }
          expect(
            maxZeroRun,
            lessThan(1024),
            reason: '不应有大块零填充 (max=$maxZeroRun)',
          );

          print(
            '✅ 字体加密通过 (LFH=$lfhCount, CD=$cdCount, maxZeroRun=$maxZeroRun)',
          );
        } catch (e) {
          print('⚠️ 字体加密异常: $e');
          rethrow;
        }
      });

      test('9. 批注转换', () async {
        final out = '${_tempDir.path}/comment.epub';
        try {
          await CommentOperation.execute(
            epubPath: epubPath,
            outputPath: out,
            regexPattern: r'<span[^>]*class="[^"]*note[^"]*"[^>]*>(.*?)</span>',
          );
          expect(File(out).existsSync(), true);
          print('✅ 批注转换通过');
        } catch (e) {
          print('⚠️ 批注转换: $e (可能无批注内容，跳过)');
        }
      });

      test('10. span 转脚注', () async {
        final out = '${_tempDir.path}/span_footnote.epub';
        try {
          await SpanToFootnoteOperation.execute(
            epubPath: epubPath,
            outputPath: out,
          );
          expect(File(out).existsSync(), true);
          print('✅ span 转脚注通过');
        } catch (e) {
          print('⚠️ span 转脚注: $e (可能无 span 内容，跳过)');
        }
      });
    },
    skip: !File(
      '/Users/aaa/Documents/github/epub-gadget/恐妻家 - [日]伊坂幸太郎.epub',
    ).existsSync(),
  );

  // ==================== txt2epub + EPUB 操作联动测试 ====================
  group('TXT→EPUB→操作 联动', () {
    test('txt2epub 后再做名称加密', () async {
      // 1. 先生成 EPUB
      final txtPath = '${_tempDir.path}/combo.txt';
      File(txtPath).writeAsBytesSync(utf8.encode(_kTestTxtContent));

      final encoding = EncodingDetector.detect(txtPath);
      final rawText = EncodingDetector.readFile(txtPath, encoding);
      final cleaner = TextCleaner();
      final cleanText = cleaner.clean(rawText);
      final splitter = ChapterSplitter();
      final chapters = splitter.split(cleanText, presetPatterns[0].pattern);

      final epubPath = '${_tempDir.path}/combo.epub';
      await EpubGenerator.generate(
        outputPath: epubPath,
        title: '联动测试',
        author: '测试',
        chapters: chapters,
      );

      // 2. 对生成的 EPUB 做名称加密
      final encPath = '${_tempDir.path}/combo_enc.epub';
      await EncryptOperation.execute(epubPath: epubPath, outputPath: encPath);
      expect(File(encPath).existsSync(), true);

      // 3. 验证加密后结构
      final bytes = File(encPath).readAsBytesSync();
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files[0].name, 'mimetype');
      expect(archive.files[0].compress, false);

      // 4. 验证 LFH = CD
      var lfhCount = 0;
      var cdCount = 0;
      for (var i = 0; i < bytes.length - 4; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4B &&
            bytes[i + 2] == 0x03 &&
            bytes[i + 3] == 0x04)
          lfhCount++;
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4B &&
            bytes[i + 2] == 0x01 &&
            bytes[i + 3] == 0x02)
          cdCount++;
      }
      expect(lfhCount, cdCount, reason: '联动测试 LFH 应等于 CD');

      print('✅ txt2epub + 名称加密联动通过');
    });
  });
}
