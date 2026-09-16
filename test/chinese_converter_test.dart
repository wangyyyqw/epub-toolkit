import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compressed dictionaries load and preserve identity phrases', () async {
    expect(await ChineseConverter.s2t('皇后头发发展'), '皇后頭髮發展');
    expect(await ChineseConverter.t2s('頭髮發展'), '头发发展');
    expect(ChineseConverter.s2tPhrases.length, 49951);
    expect(ChineseConverter.t2sCharacters.length, 4270);
  });

  test('union matching is longest-first without re-converting output', () {
    expect(
      ChineseConverter.s2tWithDict(
        '甲乙丙丁𠀀',
        phrases: {'甲乙': '甲乙', '丙': '甲'},
        characters: {'甲': '乙', '丁': '戊', '𠀀': '中'},
        phraseMaxLen: 2,
        charMaxLen: 2,
      ),
      '甲乙甲戊中',
    );
  });
}
