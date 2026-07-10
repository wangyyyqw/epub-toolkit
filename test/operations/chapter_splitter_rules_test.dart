import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:epub_gadget/features/txt2epub/services/epub_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const volumeRule = ChapterSplitRule(
    pattern: r'^第[一二三四五六七八九十]+卷.*$',
    level: 1,
    split: true,
  );
  const chapterRule = ChapterSplitRule(
    pattern: r'^第\d+章.*$',
    level: 2,
    split: true,
  );

  test('多级规则按标题级别构建目录树并保留父级正文', () {
    const text = '''第一卷 起点
卷首文字
第1章 相遇
正文一
第2章 继续
正文二
第二卷 新篇
卷二文字
第3章 结尾
正文三''';

    final analysis = ChapterSplitter().analyzeAndSplit(text, const [
      volumeRule,
      chapterRule,
    ]);

    expect(analysis.matches, hasLength(5));
    expect(analysis.matchCounts, [2, 3]);
    expect(analysis.chapters, hasLength(2));
    expect(analysis.chapters.first.title, '第一卷 起点');
    expect(analysis.chapters.first.content, '卷首文字');
    expect(analysis.chapters.first.matchedRuleIndex, 0);
    expect(analysis.chapters.first.sourceLineIndex, 0);
    expect(analysis.chapters.first.children, hasLength(2));
    expect(analysis.chapters.first.children.first.title, '第1章 相遇');
    expect(analysis.chapters.first.children.first.matchedRuleIndex, 1);
    expect(analysis.chapters.first.children.first.sourceLineIndex, 2);
    expect(analysis.chapters.last.title, '第二卷 新篇');
    expect(analysis.chapters.last.children.single.title, '第3章 结尾');
  });

  test('靠前规则优先，同一标题不会被后续宽泛规则重复处理', () {
    const text = '第二卷 第1章 诬陷\n正文';
    final analysis = ChapterSplitter().analyzeAndSplit(text, const [
      ChapterSplitRule(pattern: r'^第.卷 第.章.*$', level: 2, split: true),
      ChapterSplitRule(pattern: r'^第.卷.*$', level: 1, split: true),
    ]);

    expect(analysis.matches, hasLength(1));
    expect(analysis.matches.single.ruleIndex, 0);
    expect(analysis.matches.single.level, 2);
    expect(analysis.matchCounts, [1, 0]);
  });

  test('取消分割的规则输出页内标题而不是新建页面', () async {
    const text = '第1章 开始\n正文一\n第一节 小标题\n节内正文';
    final analysis = ChapterSplitter().analyzeAndSplit(text, const [
      chapterRule,
      ChapterSplitRule(pattern: r'^第[一二三四五六七八九十]+节.*$', level: 3, split: false),
    ]);

    expect(analysis.chapters, hasLength(1));
    final chapter = analysis.chapters.single;
    expect(chapter.inlineHeadings, hasLength(1));
    expect(chapter.inlineHeadings.single.level, 3);

    final tempDir = await Directory.systemTemp.createTemp('inline_heading_');
    addTearDown(() async => tempDir.delete(recursive: true));
    final output = '${tempDir.path}/inline.epub';
    await EpubGenerator.generate(
      outputPath: output,
      title: '页内标题测试',
      author: '作者',
      chapters: analysis.chapters,
    );
    final archive = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
    final xhtml = utf8.decode(
      archive.findFile('OEBPS/Chapter0001.xhtml')!.content as List<int>,
    );
    expect(xhtml, contains('<h3>第一节 小标题</h3>'));
    expect(xhtml, isNot(contains('<p>第一节 小标题</p>')));
  });

  test('清理段首空行后页内标题位置仍正确', () {
    const text = '\n\n序言\n序言内容';
    final analysis = ChapterSplitter().analyzeAndSplit(text, const [
      ChapterSplitRule(pattern: r'^序言$', level: 2, split: false),
    ]);

    final chapter = analysis.chapters.single;
    expect(chapter.content, '序言\n序言内容');
    expect(chapter.inlineHeadings.single.lineIndex, 0);
  });

  test('预览中忽略误识别标题后，该行恢复为普通正文', () {
    const text = '第1章 正常\n正文\n第999章 其实是正文引用\n后续正文';
    final splitter = ChapterSplitter();
    final initial = splitter.analyzeAndSplit(text, const [chapterRule]);
    expect(initial.chapters, hasLength(2));
    final falsePositive = initial.matches.last;

    final corrected = splitter.analyzeAndSplit(
      text,
      const [chapterRule],
      ignoredLineIndexes: {falsePositive.lineIndex},
    );
    expect(corrected.chapters, hasLength(1));
    expect(corrected.matches.last.ignored, isTrue);
    expect(corrected.chapters.single.content, contains('第999章 其实是正文引用'));
  });

  test('整类取消的标题不会被后续宽泛正则再次识别', () {
    const text = '第1章 开始\n正文';
    final analysis = ChapterSplitter().analyzeAndSplit(
      text,
      const [
        chapterRule,
        ChapterSplitRule(pattern: r'^第.*章.*$', level: 1, split: true),
      ],
      suppressedLineIndexes: const {0},
    );

    expect(analysis.matches, isEmpty);
    expect(analysis.matchCounts, [0, 0]);
    expect(analysis.chapters.single.title, '简介');
    expect(analysis.chapters.single.matchedRuleIndex, isNull);
    expect(analysis.chapters.single.content, contains('第1章 开始'));
  });

  test('无效正则会被报告，其余有效规则仍正常工作', () {
    const text = '第1章 正常\n正文';
    final analysis = ChapterSplitter().analyzeAndSplit(text, const [
      ChapterSplitRule(pattern: '[', level: 1, split: true),
      chapterRule,
    ]);
    expect(analysis.invalidRuleIndexes, [0]);
    expect(analysis.matchCounts, [0, 1]);
    expect(analysis.chapters.single.title, '第1章 正常');
  });
}
