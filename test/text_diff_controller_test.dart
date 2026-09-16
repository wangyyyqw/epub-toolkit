import 'package:epub_gadget/features/text_diff/text_diff_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copying one edit preserves blank lines outside its original range', () {
    final controller = TextDiffController();
    addTearDown(controller.dispose);
    const left = 'before\n\nfirst paragraph\n\nafter\n\n\nend';
    const right = 'before\n\nfirst paragraph EDIT\n\nafter\n\n\nend';
    controller.setTexts(left: left, right: right);
    expect(controller.activeBlocks, hasLength(1));
    controller.copyBlock(0, toLeft: false);
    expect(controller.rightText, left);
    expect(controller.activeBlocks, isEmpty);
  });

  test(
    'unmatched ignored blank lines outside the copied block are preserved',
    () {
      final controller = TextDiffController();
      addTearDown(controller.dispose);
      controller.setTexts(
        left: 'before\n\nold\n\nafter',
        right: 'before\n\n\nnew\n\nafter\n\n',
      );
      controller.copyBlock(0, toLeft: false);
      expect(controller.rightText, 'before\n\n\nold\n\nafter\n\n');
    },
  );

  test('copying an insertion or deletion works in both directions', () {
    for (final toLeft in [false, true]) {
      final controller = TextDiffController();
      controller.setTexts(left: 'a\nb\nc', right: 'a\nc');
      expect(controller.activeBlocks, hasLength(1));
      controller.copyBlock(0, toLeft: toLeft);
      expect(controller.leftText, controller.rightText);
      controller.dispose();
    }
  });
}
