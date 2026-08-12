import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';

import 'chinese_converter.dart';
import 'epub_image_helper.dart';

/// 后台 isolate 执行简转繁的顶层函数
///
/// 必须为顶层函数而非实例方法内的闭包:实例方法内定义的闭包会隐式捕获
/// this(State 及整棵 Widget 树),Isolate 序列化时抛 "Illegal argument in
/// isolate message: object is unsendable"。
/// 所有数据(路径、字典)通过消息参数传入;后台 isolate 中静态字典字段为
/// null,不能读取 ChineseConverter 的 getter,字典必须先由 UI isolate 加载。
///
/// [args] 顺序:epubPath, outputPath, phrases, characters, phraseMaxLen, charMaxLen
Future<String> runS2tTask(List<Object?> args) {
  return ChineseConvertBase.execute(
    epubPath: args[0] as String,
    outputPath: args[1] as String,
    mode: 's2t',
    phrases: args[2] as Map<String, String>,
    characters: args[3] as Map<String, String>,
    phraseMaxLen: args[4] as int,
    charMaxLen: args[5] as int,
  );
}

/// 简繁中文转换操作（共享逻辑）
///
/// 遍历 EPUB 中的 HTML/XHTML/HTM/NCX/OPF 文件，
/// 对文本内容进行简繁转换，跳过 script/style 标签内容。
/// 图片、CSS、字体等文件原样保留。
class ChineseConvertBase {
  ChineseConvertBase._();

  /// 执行简繁转换
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// [mode] 转换模式：'s2t' 简转繁，'t2s' 繁转简
  /// [phrases]/[characters]/[phraseMaxLen]/[charMaxLen] 外部字典参数：
  /// 在后台 Isolate 中 rootBundle 不可用，必须由 UI Isolate 先加载字典
  /// 再传入；不传时在当前 isolate 内加载（UI isolate 路径）。
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required String mode,
    Map<String, String>? phrases,
    Map<String, String>? characters,
    int phraseMaxLen = 1,
    int charMaxLen = 1,
  }) async {
    // 未传入字典时在当前 isolate 加载（rootBundle 仅在 UI isolate 可用）
    if (phrases == null || characters == null) {
      if (mode == 's2t') {
        await ChineseConverter.initS2T();
        phrases = ChineseConverter.s2tPhrases;
        characters = ChineseConverter.s2tCharacters;
        phraseMaxLen = ChineseConverter.s2tPhraseMaxLen;
        charMaxLen = ChineseConverter.s2tCharMaxLen;
      } else {
        await ChineseConverter.initT2S();
        phrases = ChineseConverter.t2sPhrases;
        characters = ChineseConverter.t2sCharacters;
        phraseMaxLen = ChineseConverter.t2sPhraseMaxLen;
        charMaxLen = ChineseConverter.t2sCharMaxLen;
      }
    }

    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final log = StringBuffer();
    final modeName = mode == 's2t' ? '简转繁' : '繁转简';
    log.writeln('开始$modeName转换...');

    var fileCount = 0;
    var convertCount = 0;
    var failCount = 0;

    // 快照文件列表，避免遍历中 addOrReplaceFile 修改列表导致并发异常。
    // 使用 addOrReplaceFileSafe 在 archive._fileMap 损坏时返回新 archive，
    // 确保循环能持续处理后续文件（不被吞错中断）。
    var workingArchive = archive;
    for (final file in archive.files.toList()) {
      if (file.name.isEmpty) continue;

      final lowerName = file.name.toLowerCase();
      final isTextFile =
          lowerName.endsWith('.html') ||
          lowerName.endsWith('.xhtml') ||
          lowerName.endsWith('.htm') ||
          lowerName.endsWith('.ncx') ||
          lowerName.endsWith('.opf');

      if (!isTextFile) continue;

      fileCount++;

      try {
        final content = utf8.decode(file.content as List<int>);
        final converted = _convertHtml(
          content,
          mode,
          phrases,
          characters,
          phraseMaxLen,
          charMaxLen,
        );

        if (converted != content) {
          convertCount++;
          workingArchive = EpubImageHelper.addOrReplaceFileSafe(
            workingArchive,
            ArchiveFile(file.name, utf8.encode(converted).length, utf8.encode(converted)),
          );
        }
      } catch (e) {
        failCount++;
        log.writeln('  文件 ${file.name} 转换失败: $e');
      }
    }

    // 保存
    await EpubPacker.pack(archive: workingArchive, outputPath: outputPath);

    log.writeln(
      '\n$modeName完成: 扫描 $fileCount 个文本文件, '
      '转换 $convertCount 个文件'
      '${failCount > 0 ? '，$failCount 个文件失败' : ''}',
    );
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 转换 HTML/XML 内容中的文本
  ///
  /// 使用正则提取标签之间的文本内容和属性值进行转换，
  /// 跳过 <script> 和 <style> 标签内容。
  /// 字典通过参数传入（支持后台 Isolate 场景）。
  static String _convertHtml(
    String content,
    String mode,
    Map<String, String> phrases,
    Map<String, String> characters,
    int phraseMaxLen,
    int charMaxLen,
  ) {
    var result = content;

    // 同步转换函数（使用外部字典，不依赖当前 isolate 的静态状态）
    String syncConvert(String text) {
      return mode == 's2t'
          ? ChineseConverter.s2tWithDict(
              text,
              phrases: phrases,
              characters: characters,
              phraseMaxLen: phraseMaxLen,
              charMaxLen: charMaxLen,
            )
          : ChineseConverter.t2sWithDict(
              text,
              phrases: phrases,
              characters: characters,
              phraseMaxLen: phraseMaxLen,
              charMaxLen: charMaxLen,
            );
    }

    // 1. 临时替换 script 和 style 内容
    final scriptContents = <String>[];
    final styleContents = <String>[];

    result = result.replaceAllMapped(
      RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
      (m) {
        scriptContents.add(m.group(0)!);
        return '@@SCRIPT${scriptContents.length - 1}@@';
      },
    );

    result = result.replaceAllMapped(
      RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
      (m) {
        styleContents.add(m.group(0)!);
        return '@@STYLE${styleContents.length - 1}@@';
      },
    );

    // 2. 转换标签之间的文本内容
    result = result.replaceAllMapped(RegExp(r'>([^<]+)<'), (m) {
      final text = m.group(1)!;
      if (text.trim().isEmpty) return m.group(0)!;
      return '>${syncConvert(text)}<';
    });

    // 3. 转换属性值中的中文（title, alt 属性）
    result = result.replaceAllMapped(
      RegExp(r'(title|alt)\s*=\s*"([^"]*)"', caseSensitive: false),
      (m) {
        final attr = m.group(1)!;
        final value = m.group(2)!;
        if (value.isEmpty) return m.group(0)!;
        return '$attr="${syncConvert(value)}"';
      },
    );

    // 4. 恢复 script 和 style 内容
    for (var i = 0; i < scriptContents.length; i++) {
      result = result.replaceFirst('@@SCRIPT$i@@', scriptContents[i]);
    }
    for (var i = 0; i < styleContents.length; i++) {
      result = result.replaceFirst('@@STYLE$i@@', styleContents[i]);
    }

    return result;
  }
}
