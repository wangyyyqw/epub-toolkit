import 'dart:math';

import 'package:epub_gadget/features/weread_thoughts/chapter_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

// Literal full scans provide an independent oracle for the indexed search.
List<(String, String, bool)> _reference(
  Map<String, String> files,
  List<ChapterInput> chapters,
) {
  final titles = chapters.map((c) => ChapterMapper.titleKey(c.title)).toList();
  final allTitles = titles.where((t) => t.length >= 6).toSet();
  final threshold = max(2, (allTitles.length * 0.5).ceil());
  final texts = files.map(
    (key, value) => MapEntry(key, ChapterMapper.normalize(value)),
  );
  final output = <(String, String, bool)>[];
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (chapter.underlines.isEmpty) continue;
    final quotes = ChapterMapper.quotesOf(chapter.underlines);
    final strong = min(2, quotes.length);
    var targets = texts.entries
        .where((entry) {
          final score = quotes.where(entry.value.contains).length;
          return score > 0 && score >= strong;
        })
        .map((entry) => entry.key)
        .take(4)
        .toList();
    if (strong == 1 && targets.length > 1) targets = [];
    final voteSingle = targets.length == 1;
    if (targets.isEmpty && titles[i].length >= 6) {
      final hits = texts.entries.where(
        (entry) =>
            entry.value.contains(titles[i]) &&
            allTitles.where(entry.value.contains).length < threshold,
      );
      if (hits.length <= 3) targets = hits.map((e) => e.key).toList();
    }
    for (final href in targets) {
      output.add((chapter.uid, href, !voteSingle));
    }
  }
  return output;
}

void main() {
  test(
    'indexed mapping preserves votes, ambiguity, TOC and title fallback',
    () {
      final random = Random(47);
      for (var trial = 0; trial < 35; trial++) {
        final chapters = List.generate(
          24,
          (i) => ChapterInput(
            uid: '$i',
            title: '第${i + 1}章 章节标题号码$i',
            underlines: List.generate(
              i % 9,
              (j) => UnderlineInput(
                range: '$j',
                markText: '共用前缀测试${i % 12}引文内容段落$j😀',
              ),
            ),
            reviewMap: {},
          ),
        );
        final files = <String, String>{
          'toc': chapters.map((c) => c.title).join('<br/>'),
          for (var f = 0; f < 14; f++)
            'file$f': chapters
                .expand(
                  (chapter) => [
                    if (random.nextBool()) chapter.title,
                    for (final underline in chapter.underlines)
                      if (random.nextInt(4) == 0) underline.markText,
                  ],
                )
                .join('<p>&nbsp;</p>'),
        };
        final (mapped, unmatched) = ChapterMapper.build(
          files.keys.toList(),
          (href) => files[href]!,
          chapters,
        );
        expect(
          mapped.map((m) => (m.chapterUid, m.href, m.quoteOnly)).toList(),
          _reference(files, chapters),
          reason: 'trial $trial',
        );
        expect(
          {
            ...mapped.map((m) => m.chapterUid),
            ...unmatched.map((m) => m.uid),
          }.length,
          chapters.length,
        );
      }
    },
  );
}
