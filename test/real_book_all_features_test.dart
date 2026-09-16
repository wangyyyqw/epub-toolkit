import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:epub_gadget/core/encoding_detector.dart';
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
import 'package:epub_gadget/features/image_watermark/image_watermark.dart';
import 'package:epub_gadget/features/list_font_targets/list_font_targets.dart';
import 'package:epub_gadget/features/list_split_targets/list_split_targets.dart';
import 'package:epub_gadget/features/merge/merge.dart';
import 'package:epub_gadget/features/metadata/metadata_service.dart';
import 'package:epub_gadget/features/phonetic/phonetic.dart';
import 'package:epub_gadget/features/reformat/reformat.dart';
import 'package:epub_gadget/features/replace_cover/replace_cover.dart';
import 'package:epub_gadget/features/s2t/s2t.dart';
import 'package:epub_gadget/features/span_to_footnote/span_to_footnote.dart';
import 'package:epub_gadget/features/split/split.dart';
import 'package:epub_gadget/features/t2s/t2s.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:epub_gadget/features/txt2epub/services/text_cleaner.dart';
import 'package:epub_gadget/features/view_opf/view_opf.dart';
import 'package:epub_gadget/features/webp_to_img/webp_to_img.dart';
import 'package:epub_gadget/features/yuewei/yuewei.dart';
import 'package:epub_gadget/features/zhangyue/zhangyue.dart';
import 'package:epub_gadget/features/zip_password/zip_password.dart';

const _fixtureDirectory = '测试文件';
final _specifiedInput = Platform.environment['REAL_EPUB_INPUT'];
final _outputRoot =
    Platform.environment['REAL_EPUB_OUTPUT'] ??
    'build/real_epub_${DateTime.now().microsecondsSinceEpoch}';

final _fixtureNames = [
  'G196-西出玉门2.0[尾鱼][重置版][悬疑][by鬼鬼].epub',
  'G299-奥术神座1.2[爱潜水的乌贼][西幻][by鬼鬼].epub',
  'G556-灵境行者1.0[卖报小郎君][都市副本后宫][by鬼鬼].epub',
  'JP-10-08-大医1.2[破晓篇+日出篇][马伯庸][实体][by鬼鬼].epub',
];

String get _inputEpub =>
    _specifiedInput ?? '$_fixtureDirectory/${_fixtureNames.first}';
String _fixturePath(int index) =>
    _specifiedInput ?? '$_fixtureDirectory/${_fixtureNames[index]}';

class _Result {
  _Result(
    this.id,
    this.name,
    this.ok,
    this.detail, {
    required this.elapsed,
    this.outputPath = '',
  });

  final String id;
  final String name;
  final bool ok;
  final String detail;
  final Duration elapsed;
  final String outputPath;
  bool get notExercised =>
      ok &&
      (detail.contains('预期跳过') ||
          detail.contains('共转换 0 个链接') ||
          detail.contains('字体子集化完成: 子集化 0 个'));
}

final _results = <_Result>[];

Future<void> _writeText(String path, String content) async {
  await File(path).parent.create(recursive: true);
  await File(path).writeAsString(content);
}

Future<File> _copyInput(String dir, String name, {String? sourcePath}) async {
  await Directory(dir).create(recursive: true);
  final file = File('$dir/$name');
  await file.writeAsBytes(await File(sourcePath ?? _inputEpub).readAsBytes());
  return file;
}

Uint8List _fileBytes(ArchiveFile file) {
  final content = file.content;
  if (content is Uint8List) return content;
  return Uint8List.fromList((content as List<int>).toList());
}

String _decode(ArchiveFile file) {
  return utf8.decode(_fileBytes(file), allowMalformed: true);
}

Archive _readZip(String path) {
  return ZipDecoder().decodeBytes(File(path).readAsBytesSync(), verify: true);
}

String _epubSummary(String path) {
  final archive = _readZip(path);
  final mimetype = archive.findFile('mimetype');
  if (mimetype == null ||
      !_decode(mimetype).startsWith('application/epub+zip')) {
    throw StateError('缺少有效 mimetype');
  }
  final container = archive.findFile('META-INF/container.xml');
  if (container == null) throw StateError('缺少 META-INF/container.xml');
  final containerXml = _decode(container);
  final match = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
  if (match == null) throw StateError('container.xml 未声明 OPF 路径');
  final opfPath = match.group(1)!;
  final opf = archive.findFile(opfPath);
  if (opf == null) throw StateError('缺少 OPF: $opfPath');
  final package = XmlDocument.parse(_decode(opf));
  final manifest = package.findAllElements('item').toList();
  final ids = manifest.map((item) => item.getAttribute('id')).toSet();
  for (final item in manifest) {
    final href = item.getAttribute('href')!;
    final uri = Uri.parse(opfPath).resolve(href);
    if (!uri.hasScheme &&
        archive.findFile(Uri.decodeComponent(uri.path)) == null) {
      throw StateError('manifest 引用缺失: $href');
    }
  }
  for (final item in package.findAllElements('itemref')) {
    if (!ids.contains(item.getAttribute('idref'))) {
      throw StateError('spine 引用不存在: ${item.getAttribute('idref')}');
    }
  }

  var html = 0;
  var css = 0;
  var images = 0;
  var fonts = 0;
  for (final file in archive.files) {
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm')) {
      html++;
    } else if (lower.endsWith('.css')) {
      css++;
    } else if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      images++;
    } else if (lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.woff') ||
        lower.endsWith('.woff2')) {
      fonts++;
    }
  }
  final size = File(path).lengthSync();
  return '有效 EPUB；size=$size；files=${archive.files.length}；opf=$opfPath；html=$html；css=$css；images=$images；fonts=$fonts';
}

bool _epubContains(String path, String needle) {
  final archive = _readZip(path);
  for (final file in archive.files) {
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.css') ||
        lower.endsWith('.opf')) {
      if (_decode(file).contains(needle)) return true;
    }
  }
  return false;
}

String _outputFolderName(String id, String name) {
  final number = id.split('_').first;
  final safeName = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
  return '${number}_$safeName';
}

Future<void> _run(
  String id,
  String name,
  Future<String> Function(String dir) body, {
  String outputPath = '',
}) async {
  final dir = '$_outputRoot/${_outputFolderName(id, name)}';
  final stopwatch = Stopwatch()..start();
  try {
    await Directory(dir).create(recursive: true);
    final detail = await body(dir);
    stopwatch.stop();
    _results.add(
      _Result(
        id,
        name,
        true,
        detail,
        elapsed: stopwatch.elapsed,
        outputPath: outputPath,
      ),
    );
    // ignore: avoid_print
    print('${_results.last.notExercised ? "NOT_EXERCISED" : "PASS"} $id $name');
  } catch (e, st) {
    final detail = '$e\n$st';
    await _writeText('$dir/error.log', detail);
    _results.add(
      _Result(
        id,
        name,
        false,
        e.toString(),
        elapsed: stopwatch.elapsed,
        outputPath: outputPath,
      ),
    );
    // ignore: avoid_print
    print('FAIL $id $name: $e');
  }
}

Future<String> _validateOutputEpub(String path, {String extra = ''}) async {
  if (!await File(path).exists()) throw StateError('输出文件不存在: $path');
  final summary = _epubSummary(path);
  return extra.isEmpty ? summary : '$summary\n$extra';
}

void _validateLog(String log, String operation) {
  if (log.trim().isEmpty) throw StateError('$operation 日志为空');
  if (log.contains('Instance of ') || log.contains('Stack Overflow')) {
    throw StateError('$operation 日志包含不可读错误信息: $log');
  }
}

void main() {
  if (_specifiedInput == null &&
      _fixtureNames.any(
        (name) => !File('$_fixtureDirectory/$name').existsSync(),
      )) {
    test('真实书籍全功能测试需要本机夹具', () {}, skip: '提供测试书籍后再运行此测试文件。');
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  test('使用指定真实 EPUB 逐项测试所有功能', () async {
    final input = File(_inputEpub);
    if (!await input.exists()) {
      throw StateError('输入 EPUB 不存在: $_inputEpub');
    }
    if (await Directory(_outputRoot).exists()) {
      throw StateError('输出目录已存在，拒绝覆盖: $_outputRoot');
    }
    await Directory(_outputRoot).create(recursive: true);

    await ChineseConverter.initS2T();
    await ChineseConverter.initT2S();
    final notePngBytes = await File('assets/note.png').readAsBytes();

    await _run('01_input_structure', '输入 EPUB 结构检查', (dir) async {
      final summaries = <String>[];
      for (
        var i = 0;
        i < (_specifiedInput == null ? _fixtureNames.length : 1);
        i++
      ) {
        final path = _fixturePath(i);
        final summary = _epubSummary(path);
        summaries.add('$path\n$summary');
      }
      final result = summaries.join('\n\n');
      await _writeText('$dir/structure.log', result);
      return result;
    });

    await _run('02_view_opf', '查看 OPF', (dir) async {
      final result = await ViewOpfOperation.execute(_inputEpub);
      await _writeText('$dir/content.opf.xml', result);
      if (!result.contains('<package')) throw StateError('OPF 不含 package 元素');
      return 'OPF 读取成功；length=${result.length}';
    });

    await _run('03_metadata', '元数据读取/写入', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final metadata = await MetadataService.read(src.path);
      await _writeText(
        '$dir/read.log',
        'title=${metadata.title}\nauthor=${metadata.author}\nlanguage=${metadata.language}\n',
      );
      final out = '$dir/out.epub';
      await MetadataService.write(
        epubPath: src.path,
        outputPath: out,
        metadata: metadata.copyWith(
          publisher: metadata.publisher.isEmpty
              ? 'EPUB Gadget Test'
              : '${metadata.publisher} EPUB Gadget Test',
        ),
      );
      final updated = await MetadataService.read(out);
      expect(updated.publisher, contains('EPUB Gadget Test'));
      expect(updated.title, metadata.title);
      expect(updated.author, metadata.author);
      return _validateOutputEpub(out, extra: '元数据写入完成');
    });

    await _run('04_replace_cover', '替换封面', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final cover = '$dir/note_cover.png';
      await File(cover).writeAsBytes(notePngBytes);
      final out = '$dir/out.epub';
      await ReplaceCoverOperation.execute(
        epubPath: src.path,
        coverPath: cover,
        outputPath: out,
      );
      return _validateOutputEpub(out);
    });

    await _run('05_reformat', '重新格式化 EPUB', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await ReformatOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '重新格式化');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('06_convert_v3', '转换版本到 EPUB3', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out_v3.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '3.0',
      );
      return _validateOutputEpub(out);
    });

    await _run('07_convert_v2', '转换版本到 EPUB2', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out_v2.epub';
      await ConvertVersionOperation.execute(
        epubPath: src.path,
        outputPath: out,
        targetVersion: '2.0',
      );
      return _validateOutputEpub(out);
    });

    String extractedTxt = '';
    await _run('08_epub_to_txt', 'EPUB 转 TXT', (dir) async {
      final out = '$dir/out.txt';
      extractedTxt = await EpubToTxtOperation.execute(
        epubPath: _inputEpub,
        outputPath: out,
      );
      if (!await File(out).exists()) throw StateError('TXT 输出文件不存在');
      if (extractedTxt.length < 1000) throw StateError('TXT 内容过短');
      return 'TXT 输出成功；chars=${extractedTxt.length}；path=$out';
    });

    await _run('09_txt_to_epub', 'TXT 转 EPUB', (dir) async {
      final txt = '$dir/input_from_epub.txt';
      await File(txt).writeAsString(extractedTxt);
      final encoding = EncodingDetector.detect(txt);
      final raw = EncodingDetector.readFile(txt, encoding);
      final cleaned = TextCleaner(
        removeEmptyLines: true,
        fixIndent: true,
      ).clean(raw);
      final chapters = ChapterSplitter().split(
        cleaned,
        presetPatterns.first.pattern,
        splitTitle: true,
      );
      if (chapters.isEmpty) throw StateError('未能从 TXT 分割章节');
      final out = '$dir/out.epub';
      final metadata = await MetadataService.read(_inputEpub);
      final (log, _) = await EpubGenerator.generate(
        outputPath: out,
        title: '${metadata.title} TXT 回转测试',
        author: metadata.author,
        chapters: chapters,
      );
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: 'chapters=${chapters.length}');
    });

    await _run('10_ad_clean', '广告清理', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      await AdCleanOperation.execute(
        epubPath: src.path,
        outputPath: out,
        patterns: r'</body>|||<!--ad-clean-test--></body>',
      );
      if (!_epubContains(out, 'ad-clean-test')) {
        throw StateError('未检测到广告清理替换标记');
      }
      return _validateOutputEpub(out, extra: '检测到替换标记 ad-clean-test');
    });

    await _run('11_img_compress', '图片压缩', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await ImgCompressOperation.execute(
        epubPath: src.path,
        outputPath: out,
        jpegQuality: 70,
        pngToJpg: true,
      );
      _validateLog(log, '图片压缩');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    String webpOutput = '';
    await _run('12_img_to_webp', '图片转 WebP', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      webpOutput = out;
      final log = await ImgToWebpOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '图片转 WebP');
      await _writeText('$dir/result.log', log);
      if (await File(out).exists()) return _validateOutputEpub(out, extra: log);
      if (!log.contains('不支持') && !log.contains('未找到')) {
        throw StateError('未生成输出文件，且日志不是预期跳过: $log');
      }
      return '当前平台/输入下预期跳过；未生成输出 EPUB；log=$log';
    });

    await _run('13_image_watermark', '图片隐形水印', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final embedLog = await ImageWatermarkOperation.embed(
        epubPath: src.path,
        outputPath: out,
        watermarkText: 'real-book-test-2026',
      );
      _validateLog(embedLog, '图片隐形水印写入');
      final inspectLog = await ImageWatermarkOperation.inspect(epubPath: out);
      _validateLog(inspectLog, '图片隐形水印读取');
      if (!inspectLog.contains('real-book-test-2026')) {
        throw StateError('未读取到刚写入的水印');
      }
      final log = '$embedLog\n$inspectLog';
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('14_webp_to_img', 'WebP 转图片', (dir) async {
      final src = await _copyInput(
        dir,
        'src.epub',
        sourcePath: File(webpOutput).existsSync() ? webpOutput : null,
      );
      final out = '$dir/out.epub';
      final log = await WebpToImgOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, 'WebP 转图片');
      await _writeText('$dir/result.log', log);
      if (await File(out).exists()) return _validateOutputEpub(out, extra: log);
      if (!log.contains('未找到 WebP')) {
        throw StateError('未生成输出文件，且日志不是预期跳过: $log');
      }
      return '输入 EPUB 无 WebP 图片，预期跳过；未生成输出 EPUB';
    });

    await _run('15_download_images', '下载网络图片', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await DownloadImagesOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '下载网络图片');
      await _writeText('$dir/result.log', log);
      if (await File(out).exists()) return _validateOutputEpub(out, extra: log);
      if (!log.contains('未找到网络图片')) {
        throw StateError('未生成输出文件，且日志不是预期跳过: $log');
      }
      return '输入 EPUB 无网络图片引用，预期跳过；未生成输出 EPUB';
    });

    String traditionalOutput = '';
    await _run('16_s2t', '简转繁', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      traditionalOutput = out;
      final log = await S2tOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '简转繁');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('17_t2s', '繁转简', (dir) async {
      final src = await _copyInput(
        dir,
        'src.epub',
        sourcePath: File(traditionalOutput).existsSync()
            ? traditionalOutput
            : null,
      );
      final out = '$dir/out.epub';
      final log = await T2sOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '繁转简');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('18_phonetic', '拼音标注', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await PhoneticOperation.execute(
        epubPath: src.path,
        outputPath: out,
        toneMode: PhoneticOperation.toneModeMark,
        annotateAll: false,
      );
      _validateLog(log, '拼音标注');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('19_font_subset', '字体子集化', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await FontSubsetOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '字体子集化');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    String encryptedEpub = '';
    await _run('20_encrypt', 'EPUB 加密', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      encryptedEpub = out;
      final log = await EncryptOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, 'EPUB 加密');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('21_decrypt', 'EPUB 解密', (dir) async {
      if (encryptedEpub.isEmpty || !await File(encryptedEpub).exists()) {
        throw StateError('依赖加密输出不存在');
      }
      final out = '$dir/out.epub';
      final log = await DecryptOperation.execute(
        epubPath: encryptedEpub,
        outputPath: out,
      );
      _validateLog(log, 'EPUB 解密');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('22_encrypt_font', '字体加密', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await EncryptFontOperation.execute(
        epubPath: src.path,
        outputPath: out,
      );
      _validateLog(log, '字体加密');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('23_list_font_targets', '列出字体加密目标', (dir) async {
      final log = await ListFontTargetsOperation.execute(epubPath: _inputEpub);
      await _writeText('$dir/result.log', log);
      if (log.trim().isEmpty) throw StateError('字体目标日志为空');
      return log;
    });

    await _run('24_merge', '合并 EPUB', (dir) async {
      final a = await _copyInput(dir, 'a.epub');
      final b = await _copyInput(dir, 'b.epub', sourcePath: _fixturePath(1));
      final out = '$dir/out.epub';
      final log = await MergeOperation.execute(
        inputPaths: [a.path, b.path],
        outputPath: out,
        options: const MergeOptions(title: '真实书籍 合并测试'),
      );
      _validateLog(log, '合并 EPUB');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('25_zip_password', 'ZIP 密码加密/解密', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final encrypted = '$dir/encrypted.epub';
      final restored = '$dir/restored.epub';
      final addLog = await ZipPasswordOperation.addPassword(
        epubPath: src.path,
        outputPath: encrypted,
        password: 'RealTest#2026',
      );
      final removeLog = await ZipPasswordOperation.removePassword(
        epubPath: encrypted,
        outputPath: restored,
        password: 'RealTest#2026',
      );
      _validateLog(addLog, 'ZIP 密码加密');
      _validateLog(removeLog, 'ZIP 密码解密');
      final original = _readZip(src.path);
      final roundtrip = _readZip(restored);
      expect(roundtrip.files.length, original.files.length);
      for (final entry in original.files.where((file) => file.isFile)) {
        expect(
          _fileBytes(roundtrip.findFile(entry.name)!),
          orderedEquals(_fileBytes(entry)),
          reason: '密码往返后内容发生变化: ${entry.name}',
        );
      }
      final log = '$addLog\n$removeLog';
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(restored, extra: log);
    });

    List<SplitTarget> splitTargets = [];
    await _run('26_list_split_targets', '列出拆分目标', (dir) async {
      splitTargets = await ListSplitTargetsOperation.execute(
        epubPath: _inputEpub,
      );
      final log = ListSplitTargetsOperation.formatTargets(splitTargets);
      await _writeText('$dir/result.log', log);
      if (splitTargets.isEmpty) throw StateError('未列出任何拆分目标');
      return '拆分目标数量=${splitTargets.length}\n$log';
    });

    await _run('27_split', '拆分 EPUB', (dir) async {
      if (splitTargets.length < 2) throw StateError('拆分目标不足');
      final outputDir = '$dir/out';
      final mid = splitTargets.length ~/ 2;
      final log = await SplitOperation.execute(
        epubPath: _inputEpub,
        outputDir: outputDir,
        splitPoints: [mid],
      );
      await _writeText('$dir/result.log', log);
      final outputs = await Directory(outputDir)
          .list()
          .where((entity) => entity.path.toLowerCase().endsWith('.epub'))
          .toList();
      if (outputs.length < 2) throw StateError('拆分输出 EPUB 少于 2 个');
      for (final entity in outputs) {
        _epubSummary(entity.path);
      }
      return '拆分输出 ${outputs.length} 个 EPUB；$log';
    });

    String commentOutput = '';
    await _run('28_comment', '弹窗批注提取', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      commentOutput = out;
      final log = await CommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'\[([^\]]+)\]',
        notePngBytes: notePngBytes,
      );
      _validateLog(log, '弹窗批注提取');
      await _writeText('$dir/result.log', log);
      if (log.contains('共替换 0 处')) {
        throw StateError('真实 EPUB 中存在方括号内容，但批注提取未命中');
      }
      if (!_epubContains(out, 'reader js_readerFooterNote')) {
        throw StateError('日志显示已替换，但输出未检测到弹窗批注结构');
      }
      return _validateOutputEpub(out, extra: log);
    });

    await _run('29_footnote_to_comment', '标准脚注转弹窗注释', (dir) async {
      final src = await _copyInput(dir, 'src.epub');
      final out = '$dir/out.epub';
      final log = await FootnoteToCommentOperation.execute(
        epubPath: src.path,
        outputPath: out,
        regexPattern: r'^#+',
        notePngBytes: notePngBytes,
      );
      _validateLog(log, '标准脚注转弹窗注释');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('30_span_to_footnote', '弹窗注释转脚注', (dir) async {
      if (commentOutput.isEmpty || !await File(commentOutput).exists()) {
        throw StateError('依赖弹窗批注输出不存在');
      }
      final out = '$dir/out.epub';
      final log = await SpanToFootnoteOperation.execute(
        epubPath: commentOutput,
        outputPath: out,
        footnoteColor: '#aa0000',
        noterefColor: '#0000aa',
      );
      _validateLog(log, '弹窗注释转脚注');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    String yueweiOutput = '';
    await _run('31_yuewei', '阅微转多看', (dir) async {
      final src = await _copyInput(dir, 'src.epub', sourcePath: commentOutput);
      final out = '$dir/out.epub';
      yueweiOutput = out;
      final log = await YueweiOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: notePngBytes,
      );
      _validateLog(log, '阅微转多看');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    await _run('32_zhangyue', '掌阅/得到转多看', (dir) async {
      final src = await _copyInput(dir, 'src.epub', sourcePath: yueweiOutput);
      final out = '$dir/out.epub';
      final log = await ZhangyueOperation.execute(
        epubPath: src.path,
        outputPath: out,
        notePngBytes: notePngBytes,
      );
      _validateLog(log, '掌阅转多看');
      await _writeText('$dir/result.log', log);
      return _validateOutputEpub(out, extra: log);
    });

    final report = StringBuffer();
    final passed = _results
        .where((result) => result.ok && !result.notExercised)
        .length;
    final notExercised = _results.where((result) => result.notExercised).length;
    final failed = _results.where((result) => !result.ok).length;
    report.writeln('# 指定真实 EPUB 全功能测试报告');
    report.writeln();
    report.writeln('- 输入文件: `$_inputEpub`');
    report.writeln('- 输出目录: `$_outputRoot`');
    report.writeln(
      '- 汇总: $passed/${_results.length} 通过，$failed 失败，$notExercised 项输入不适用或保护性保留',
    );
    report.writeln('- 反向转换使用正向输出；单文件合并使用同书两份副本。');
    report.writeln('- 阅微转换使用批注提取产物，掌阅转换使用阅微转换产物。');
    report.writeln('- PASS 是操作及基础结构断言；独立结构/阅读器检查见附加报告。');
    report.writeln();
    for (final result in _results) {
      report.writeln(
        '## ${result.notExercised
            ? "NOT_EXERCISED"
            : result.ok
            ? "PASS"
            : "FAIL"} ${result.id} ${result.name}',
      );
      report.writeln();
      report.writeln('耗时: ${result.elapsed.inMilliseconds} ms');
      report.writeln();
      report.writeln(result.detail.trim());
      report.writeln();
    }
    await _writeText('$_outputRoot/REPORT.md', report.toString());

    expect(failed, 0, reason: '存在失败功能，详情见 $_outputRoot/REPORT.md');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
