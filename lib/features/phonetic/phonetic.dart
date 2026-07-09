import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../core/epub_packer.dart';
import 'package:pinyin/pinyin.dart';

import 'epub_image_helper.dart';

/// 拼音标注操作
///
/// 遍历 EPUB 中的 HTML/XHTML/HTM 文件，对中文文本添加拼音标注。
/// 使用标准 HTML5 `ruby` + `rt` 标签格式输出注音。
/// 跳过 script/style 标签内容，避免重复注音已有 ruby 标签。
class PhoneticOperation {
  PhoneticOperation._();

  /// 声调模式：带音标
  static const toneModeMark = 'mark';

  /// 声调模式：不带声调
  static const toneModeNone = 'none';

  /// 声调模式：数字声调
  static const toneModeNumber = 'number';

  /// 执行拼音标注
  ///
  /// [epubPath] 输入 EPUB 路径
  /// [outputPath] 输出 EPUB 路径
  /// [toneMode] 声调模式：mark=带音标, none=不带声调, number=数字声调
  /// [annotateAll] true=全文注音, false=仅生僻字注音
  ///
  /// 返回处理结果摘要字符串
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    String toneMode = toneModeMark,
    bool annotateAll = true,
  }) async {
    // 确定 PinyinFormat
    final format = _parseFormat(toneMode);

    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final log = StringBuffer();
    log.writeln('开始拼音标注...');
    log.writeln('声调模式: ${_toneModeName(toneMode)}');
    log.writeln('标注范围: ${annotateAll ? "全文注音" : "仅生僻字"}');

    var fileCount = 0;
    var annotateCount = 0;
    var charCount = 0;
    var failCount = 0;

    // 快照文件列表，避免遍历中 addOrReplaceFile 修改列表导致并发异常。
    // 使用 addOrReplaceFileSafe 在 archive._fileMap 损坏时返回新 archive，
    // 确保循环能持续处理后续文件（不会被吞错中断）。
    var workingArchive = archive;
    for (final file in archive.files.toList()) {
      if (file.name.isEmpty) continue;

      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.html') &&
          !lowerName.endsWith('.xhtml') &&
          !lowerName.endsWith('.htm')) {
        continue;
      }

      fileCount++;

      try {
        final content = utf8.decode(file.content as List<int>);
        final (annotatedContent, wasModified, chars) = _annotateHtml(
          content,
          format,
          annotateAll,
        );

        if (wasModified) {
          annotateCount++;
          charCount += chars;
          workingArchive = EpubImageHelper.addOrReplaceFileSafe(
            workingArchive,
            ArchiveFile(
              file.name,
              annotatedContent.length,
              utf8.encode(annotatedContent),
            ),
          );
        }
      } catch (e) {
        failCount++;
        log.writeln('  文件 ${file.name} 标注失败: $e');
      }
    }

    // 保存
    await EpubPacker.pack(archive: workingArchive, outputPath: outputPath);

    log.writeln(
      '\n拼音标注完成: 处理 $fileCount 个 HTML 文件, '
      '$annotateCount 个文件有标注, 共标注 $charCount 个字符'
      '${failCount > 0 ? '，$failCount 个文件失败' : ''}',
    );
    log.writeln('输出文件: $outputPath');

    return log.toString();
  }

  /// 解析声调模式为 PinyinFormat
  static PinyinFormat _parseFormat(String toneMode) {
    switch (toneMode) {
      case toneModeMark:
        return PinyinFormat.WITH_TONE_MARK;
      case toneModeNumber:
        return PinyinFormat.WITH_TONE_NUMBER;
      case toneModeNone:
      default:
        return PinyinFormat.WITHOUT_TONE;
    }
  }

  /// 获取声调模式中文名称
  static String _toneModeName(String toneMode) {
    switch (toneMode) {
      case toneModeMark:
        return '带音标';
      case toneModeNumber:
        return '数字声调';
      case toneModeNone:
      default:
        return '不带声调';
    }
  }

  /// 对 HTML 内容进行拼音标注
  ///
  /// 返回 (标注后的内容, 是否有修改, 标注字符数)
  static (String, bool, int) _annotateHtml(
    String content,
    PinyinFormat format,
    bool annotateAll,
  ) {
    var result = content;
    var modified = false;
    var charCount = 0;

    // 1. 临时替换 script 和 style 内容，避免处理
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

    // 2. 临时替换已有 ruby 标签内容，避免重复注音
    final rubyContents = <String>[];
    result = result.replaceAllMapped(
      RegExp(r'<ruby\b[^>]*>[\s\S]*?</ruby>', caseSensitive: false),
      (m) {
        rubyContents.add(m.group(0)!);
        return '@@RUBY${rubyContents.length - 1}@@';
      },
    );

    // 3. 对标签之间的文本进行拼音标注
    // 匹配 >文本< 之间的内容
    result = result.replaceAllMapped(RegExp(r'>([^<]+)<'), (m) {
      final text = m.group(1)!;
      if (text.trim().isEmpty) return m.group(0)!;

      final (annotated, count) = _annotateText(text, format, annotateAll);
      if (count > 0) {
        modified = true;
        charCount += count;
      }
      return '>$annotated<';
    });

    // 4. 恢复 ruby 标签内容
    for (var i = 0; i < rubyContents.length; i++) {
      result = result.replaceFirst('@@RUBY$i@@', rubyContents[i]);
    }

    // 5. 恢复 script 和 style 内容
    for (var i = 0; i < scriptContents.length; i++) {
      result = result.replaceFirst('@@SCRIPT$i@@', scriptContents[i]);
    }
    for (var i = 0; i < styleContents.length; i++) {
      result = result.replaceFirst('@@STYLE$i@@', styleContents[i]);
    }

    return (result, modified, charCount);
  }

  /// 对文本进行拼音标注
  ///
  /// 遍历文本中的每个字符，对中文字符添加 `ruby` 标签。
  /// [annotateAll] 为 true 时所有中文字符都标注；
  /// 为 false 时仅标注生僻字（GB2312 一级字 U+4E00-U+5535 之外的字符）。
  ///
  /// 返回 (标注后的文本, 标注字符数)
  static (String, int) _annotateText(
    String text,
    PinyinFormat format,
    bool annotateAll,
  ) {
    final result = StringBuffer();
    var count = 0;

    // GB2312 一级字范围（U+4E00-U+5535），是「仅生僻字」模式下要跳过的部分。
    // 注：CJK 扩展 A 区（U+3400-U+4DBF）虽然码点 < 0x5535，但属于生僻字，
    // 应被标注，不能简单按码点大小比较，否则会被错误跳过。
    const commonCharStart = 0x4E00;
    const commonCharEnd = 0x5535;

    final runes = text.runes.toList();
    var i = 0;

    while (i < runes.length) {
      // 使用 runes 重建完整字符（避免辅助平面字符被截断为高低位乱码）
      final char = String.fromCharCode(runes[i]);

      // 判断是否为中文字符
      if (_isChinese(char)) {
        // 仅生僻字模式：跳过 GB2312 一级字（必须同时是 CJK 基本区，
        // 否则扩展 A 区字会被错误当作「常用字」跳过）
        if (!annotateAll &&
            runes[i] >= commonCharStart &&
            runes[i] <= commonCharEnd) {
          result.write(char);
          i++;
          continue;
        }

        // 获取拼音（用 try/catch 防御 pinyin 库对生僻字/扩展区字符的内部异常）
        List<String> pinyinList = const [];
        try {
          pinyinList = PinyinHelper.convertToPinyinArray(char, format);
        } catch (_) {
          // pinyin 库对某些生僻字会抛 RangeError，跳过该字符
        }
        if (pinyinList.isNotEmpty) {
          // 用 <ruby> 标签包裹
          result.write('<ruby>$char<rt>${pinyinList[0]}</rt></ruby>');
          count++;
        } else {
          // 无法转换拼音，保留原字
          result.write(char);
        }
      } else {
        // 非中文字符原样保留
        result.write(char);
      }
      i++;
    }

    return (result.toString(), count);
  }

  /// 判断字符是否为中文
  ///
  /// 包括 CJK 基本区（U+4E00-U+9FFF）和扩展 A 区（U+3400-U+4DBF）
  static bool _isChinese(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }
}
