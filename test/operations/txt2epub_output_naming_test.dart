import 'package:epub_gadget/features/txt2epub/services/output_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TXT 转 EPUB 输出文件名', () {
    test('书名和作者同时存在时用连字符组合', () {
      expect(
        Txt2EpubNaming.buildFilename(
          title: '愤怒的葡萄',
          author: '[美] 约翰·斯坦贝克',
          inputPath: '/books/source.txt',
        ),
        '愤怒的葡萄-[美] 约翰·斯坦贝克.epub',
      );
    });

    test('只有书名时不附加作者', () {
      expect(
        Txt2EpubNaming.buildFilename(
          title: '愤怒的葡萄',
          author: '  ',
          inputPath: '/books/source.txt',
        ),
        '愤怒的葡萄.epub',
      );
    });

    test('书名和作者都为空时使用原文件名', () {
      expect(
        Txt2EpubNaming.buildFilename(
          title: '',
          author: '',
          inputPath: '/books/原始小说.txt',
        ),
        '原始小说.epub',
      );
      expect(
        Txt2EpubNaming.resolveTitle(title: '', inputPath: '/books/原始小说.txt'),
        '原始小说',
      );
    });

    test('文件名会替换跨平台非法字符', () {
      expect(
        Txt2EpubNaming.buildFilename(
          title: '书名:测试',
          author: '作者/甲',
          inputPath: '/books/source.txt',
        ),
        '书名 测试-作者 甲.epub',
      );
    });
  });
}
