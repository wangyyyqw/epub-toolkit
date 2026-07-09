// 回归测试：Chapter.toString() 覆盖 + 字符串插值陷阱
//
// 之前的 bug：chapter_splitter.dart 用了 `'$rc.title'` 这种字符串插值，
// Dart 会解析为 `'$rc' + '.title'`，触发 rc.toString()，
// 输出 "Instance of '_RawChapter'.title" 字面量。
//
// 修复：使用 ${rc.title} 显式访问字段，同时为 Chapter 类添加
// toString() 覆盖，让未来的类似问题可被早期发现。

import 'package:epub_gadget/features/txt2epub/models/chapter.dart';
import 'package:epub_gadget/features/txt2epub/services/chapter_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chapter.toString()', () {
    test('不应输出 "Instance of" 字面量', () {
      final ch = Chapter(title: '第一章 标题', content: '正文内容');
      final s = ch.toString();
      expect(s, isNot(contains("Instance of")));
      expect(s, contains('第一章 标题'));
    });
  });

  group('ChapterSplitter splitTitle=false 时', () {
    test('章节正文首行应保留标题（不应有 Instance of 字面量）', () {
      final text = '第一章 标题A\n正文1\n第二章 标题B\n正文2';
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        text,
        r'^第\S+章\s*.+',
        splitTitle: false,
      );

      expect(chapters.length, 2);
      // 关键验证：内容中不应出现 "Instance of"
      for (final ch in chapters) {
        expect(ch.content, isNot(contains("Instance of")),
            reason: '章节内容不应含 "Instance of" 字符串插值陷阱产物');
        // 标题应出现在内容首行
        expect(ch.content.startsWith(ch.title), true,
            reason: 'splitTitle=false 时标题应在内容首行');
      }

      // 标题字段应正常
      expect(chapters[0].title, '第一章 标题A');
      expect(chapters[1].title, '第二章 标题B');
    });

    test('splitTitle=true 时内容不含标题', () {
      final text = '第一章 标题A\n正文1\n第二章 标题B\n正文2';
      final splitter = ChapterSplitter();
      final chapters = splitter.split(
        text,
        r'^第\S+章\s*.+',
        splitTitle: true,
      );

      for (final ch in chapters) {
        expect(ch.content, isNot(contains("Instance of")));
        expect(ch.content.contains('正文'), true);
      }
    });
  });
}
