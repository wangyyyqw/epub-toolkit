import 'package:epub_gadget/features/epub_tools/epub_background_operation.dart';
import 'package:epub_gadget/features/epub_tools/epub_operation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry covers every legacy background operation', () {
    final registeredIds = epubOperationRegistry.operations
        .map((operation) => operation.id)
        .toSet();

    expect(
      registeredIds,
      containsAll(
        EpubBackgroundOperation.values.map((operation) => operation.name),
      ),
    );
  });

  test('registry operation IDs are unique', () {
    final ids = epubOperationRegistry.operations
        .map((operation) => operation.id)
        .toList();

    expect(ids.toSet(), hasLength(ids.length));
  });
}
