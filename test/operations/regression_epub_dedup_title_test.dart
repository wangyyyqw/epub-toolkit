// 回归测试：EPUB 章节正文首段与标题相同时应去重
//
// 之前的 bug：splitTitle=false 模式下，Chapter.content 首行
// 包含标题（chapter_splitter.dart:165 写入），EPUB 渲染时
// _generateChapterXhtml 又写 <h1>title</h1>，导致：
//   顶部 h1: 第1章 xxx
//   正文首段: 第1章 xxx
// 标题重复显示在阅读器中。
//
// 修复：_generateChapterXhtml 检测首段与标题完全相同则跳过。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EPUB 章节正文去重标题', () {
    test('splitTitle=false 时，正文首段=标题应被去重', () async {
      // 模拟：用户传入 splitTitle=false 模式
      final text = '第1章 被你们城里人吓亖\n本月9日，柏清集团宣布...'
          '\n第2章 第二章标题\n第二章正文内容';
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        text,
        r'^第\S+章\s*.+',
        splitTitle: false,
      );

      // 验证 Chapter.content 首行是标题
      // 实际章节数依赖分隔器内部实现，验证首章即可
      expect(chapters, isNotEmpty);
      expect(chapters.first.title, '第1章 被你们城里人吓亖');
      expect(chapters.first.content.startsWith('第1章 被你们城里人吓亖'), true,
          reason: 'splitTitle=false 时标题应在 content 首行');

      // 生成 EPUB
      final outputPath = '${Directory.systemTemp.path}/dedup_test.epub';
      final (log, userVisiblePath) = await EpubGenerator.generate(
        outputPath: outputPath,
        title: '测试书',
        author: '测试作者',
        chapters: chapters,
      );

      // 读取生成的 EPUB 中第一个章节 XHTML
      final bytes = await File(outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final xhtmlFiles = archive.files
          .where((f) =>
              f.name.endsWith('.xhtml') &&
              !f.name.endsWith('nav.xhtml') &&
              !f.name.endsWith('title.xhtml'))
          .toList();
      expect(xhtmlFiles, isNotEmpty);
      final firstXhtml = utf8.decode(xhtmlFiles.first.content as List<int>);

      // 关键验证：标题应只出现 1 次（在 <h1> 中），不应在 <p> 中重复
      final h1MatchCount = RegExp(r'<h1>[^<]*</h1>').allMatches(firstXhtml).length;
      final titleInP =
          RegExp(r'<p>\s*第1章\s*被你们城里人吓亖\s*</p>').hasMatch(firstXhtml);

      expect(h1MatchCount, 1, reason: '应只有 1 个 <h1>');
      expect(titleInP, false,
          reason: '正文首段与标题相同时应被去重（不应有 <p>第1章...</p>）');
      // 同时验证正文仍然存在（去重不能误删全部内容）
      expect(firstXhtml, contains('本月9日，柏清集团宣布'),
          reason: '正文首段（与标题不同时）应正常显示');
    });

    test('splitTitle=true 时，正文无重复标题（首段不是标题）', () async {
      final text = '第1章 标题A\n正文段落1\n第2章 标题B\n正文段落2';
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        text,
        r'^第\S+章\s*.+',
        splitTitle: true,
      );

      // splitTitle=true 时 content 不应包含标题
      expect(chapters.first.content, isNot(contains('第1章')));
      expect(chapters.first.content, contains('正文段落1'));

      final outputPath = '${Directory.systemTemp.path}/dedup_test2.epub';
      await EpubGenerator.generate(
        outputPath: outputPath,
        title: '测试书',
        author: '测试作者',
        chapters: chapters,
      );

      final bytes = await File(outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final xhtmlFiles = archive.files
          .where((f) =>
              f.name.endsWith('.xhtml') &&
              !f.name.endsWith('nav.xhtml') &&
              !f.name.endsWith('title.xhtml'))
          .toList();
      final firstXhtml = utf8.decode(xhtmlFiles.first.content as List<int>);

      // <h1>标题A</h1> 在顶部，正文应直接是"正文段落1"
      expect(firstXhtml, contains('<h1>'));
      expect(firstXhtml, contains('<p>'));
      // 验证第一个 xhtml 只有一个 <h1>（章节自己的标题）
      expect(RegExp(r'<h1>[^<]*</h1>').allMatches(firstXhtml).length, 1);
      // 验证正文内容是 "正文段落1"，不是 "第1章 标题A"（splitTitle=true 不会重复）
      expect(firstXhtml, contains('<p>正文段落1</p>'));
    });

    test('章节正文为空时，不应输出空段落', () async {
      // 边界：title 和 content 都不为空，但 content 是空字符串
      final ch = Chapter(title: '第1章 标题', content: '');
      final outputPath = '${Directory.systemTemp.path}/dedup_test3.epub';
      await EpubGenerator.generate(
        outputPath: outputPath,
        title: '测试',
        author: '作者',
        chapters: [ch],
      );
      final bytes = await File(outputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final xhtmlFiles = archive.files
          .where((f) =>
              f.name.endsWith('.xhtml') &&
              !f.name.endsWith('nav.xhtml') &&
              !f.name.endsWith('title.xhtml'))
          .toList();
      final firstXhtml = utf8.decode(xhtmlFiles.first.content as List<int>);

      expect(firstXhtml, contains('<h1>第1章 标题</h1>'));
      expect(RegExp(r'<p>').hasMatch(firstXhtml), false,
          reason: '空 content 不应输出 <p> 标签');
    });
  });
}
