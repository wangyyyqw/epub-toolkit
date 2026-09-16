import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/font_subset/font_subset.dart';
import 'package:epub_gadget/features/font_subset/harfbuzz_subsetter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi.dart' as hb;

List<int> shape(
  Uint8List font,
  String text,
  String feature, {
  bool vertical = false,
}) {
  return using((arena) {
    final bytes = arena<Uint8>(font.length)
      ..asTypedList(font.length).setAll(0, font);
    final blob = hb.hb_blob_create(
      bytes.cast(),
      font.length,
      hb.hb_memory_mode_t.HB_MEMORY_MODE_DUPLICATE,
      nullptr,
      nullptr,
    );
    final face = hb.hb_face_create(blob, 0);
    final hbFont = hb.hb_font_create(face);
    final buffer = hb.hb_buffer_create();
    try {
      final string = text.toNativeUtf8(allocator: arena);
      hb.hb_buffer_add_utf8(buffer, string.cast(), -1, 0, -1);
      hb.hb_buffer_guess_segment_properties(buffer);
      if (vertical) {
        hb.hb_buffer_set_direction(buffer, hb.hb_direction_t.HB_DIRECTION_TTB);
      }
      final settings = arena<hb.hb_feature_t>();
      hb.hb_feature_from_string(
        feature.toNativeUtf8(allocator: arena).cast(),
        -1,
        settings,
      );
      hb.hb_shape(hbFont, buffer, settings, 1);
      final length = arena<UnsignedInt>();
      final glyphs = hb.hb_buffer_get_glyph_infos(buffer, length);
      final positions = hb.hb_buffer_get_glyph_positions(buffer, nullptr);
      final names = arena<Char>(256);
      final result = <int>[];
      for (var i = 0; i < length.value; i++) {
        hb.hb_font_glyph_to_string(hbFont, glyphs[i].codepoint, names, 256);
        result.addAll(names.cast<Utf8>().toDartString().codeUnits);
        result.addAll([
          -1,
          positions[i].x_advance,
          positions[i].y_advance,
          positions[i].x_offset,
          positions[i].y_offset,
        ]);
      }
      return result;
    } finally {
      hb.hb_buffer_destroy(buffer);
      hb.hb_font_destroy(hbFont);
      hb.hb_face_destroy(face);
      hb.hb_blob_destroy(blob);
    }
  });
}

void main() {
  for (final ext in ['ttf', 'otf']) {
    test(
      '$ext retains ligatures, vertical and optional GSUB features',
      () async {
        final original = await File(
          'test/fixtures/complex_probe.$ext',
        ).readAsBytes();
        final subset = HarfBuzzSubsetter.subset(original, {32, 65, 66});
        expect(subset, isNotNull);
        for (final feature in ['liga=1', 'vert=1', 'ss01=1']) {
          expect(
            shape(subset!, 'AB A', feature),
            shape(original, 'AB A', feature),
          );
        }
        expect(
          shape(subset!, 'AB A', 'liga=1', vertical: true),
          shape(original, 'AB A', 'liga=1', vertical: true),
          reason:
              'Pruning an empty GPOS vert must not change vertical fallback.',
        );
        expect(subset!.length, lessThan(original.length));
      },
    );
  }
  test('invalid fonts fail safely', () {
    expect(HarfBuzzSubsetter.subset(Uint8List(1024), {65}), isNull);
    expect(HarfBuzzSubsetter.subset(Uint8List(1), {65}), isNull);
  });
  test('native font asset works in a background isolate', () async {
    final data = await File('test/fixtures/complex_probe.otf').readAsBytes();
    final output = await Isolate.run(
      () => HarfBuzzSubsetter.subset(data, {65, 66}),
    );
    expect(output, isNotNull);
  });
  final input = Platform.environment['REAL_EPUB_INPUT'];
  final output = Platform.environment['FONT_EPUB_OUTPUT'];
  test(
    'real book CFF and GSUB fonts both shrink',
    () async {
      final target = File(output!);
      expect(
        target.existsSync(),
        isFalse,
        reason: 'Do not overwrite an output.',
      );
      await target.parent.create(recursive: true);
      final log = await FontSubsetOperation.execute(
        epubPath: input!,
        outputPath: output,
      );
      await File('$output.log').writeAsString(log);
      final original = ZipDecoder().decodeBytes(
        await File(input).readAsBytes(),
      );
      final processed = ZipDecoder().decodeBytes(await target.readAsBytes());
      for (final font in original.files.where(
        (f) => f.name.endsWith('.otf') || f.name.endsWith('.ttf'),
      )) {
        expect(
          processed.findFile(font.name)!.size,
          lessThan(font.size),
          reason: font.name,
        );
      }
      expect(log, contains('子集化 2 个'));
    },
    skip: input == null || output == null ? 'Set real-book paths.' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
