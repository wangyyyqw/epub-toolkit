import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi.dart' as hb;

/// Subsets outlines and their layout dependencies together. No external process
/// or user-installed library is needed: HarfBuzz is a bundled native asset.
class HarfBuzzSubsetter {
  HarfBuzzSubsetter._();

  static Uint8List? subset(Uint8List data, Set<int> codePoints) {
    if (data.length < 12 || codePoints.isEmpty) return null;
    return using((arena) {
      final bytes = arena<Uint8>(data.length);
      bytes.asTypedList(data.length).setAll(0, data);
      final blob = hb.hb_blob_create_or_fail(
        bytes.cast(),
        data.length,
        hb.hb_memory_mode_t.HB_MEMORY_MODE_DUPLICATE,
        nullptr,
        nullptr,
      );
      if (blob == nullptr) return null;
      Pointer<hb.hb_face_t> face = nullptr;
      Pointer<hb.hb_subset_input_t> input = nullptr;
      Pointer<hb.hb_face_t> subset = nullptr;
      Pointer<hb.hb_blob_t> output = nullptr;
      try {
        face = hb.hb_face_create(blob, 0);
        if (hb.hb_face_get_glyph_count(face) == 0) return null;
        input = hb.hb_subset_input_create_or_fail();
        if (input == nullptr) return null;
        final unicodes = hb.hb_subset_input_unicode_set(input);
        for (final codePoint in codePoints) {
          if (codePoint >= 0 && codePoint <= 0x10ffff) {
            hb.hb_set_add(unicodes, codePoint);
          }
        }
        // Preserve optional typography (including vertical/CJK alternates),
        // not just HarfBuzz's default feature allowlist.
        for (final type in [
          hb.hb_subset_sets_t.HB_SUBSET_SETS_LAYOUT_FEATURE_TAG,
          hb.hb_subset_sets_t.HB_SUBSET_SETS_NAME_ID,
          hb.hb_subset_sets_t.HB_SUBSET_SETS_NAME_LANG_ID,
        ]) {
          final set = hb.hb_subset_input_set(input, type);
          hb.hb_set_clear(set);
          hb.hb_set_invert(set);
        }
        hb.hb_subset_input_set_flags(
          input,
          hb.hb_subset_flags_t.HB_SUBSET_FLAGS_NOTDEF_OUTLINE.value |
              hb.hb_subset_flags_t.HB_SUBSET_FLAGS_GLYPH_NAMES.value,
        );
        subset = hb.hb_subset_or_fail(face, input);
        if (subset == nullptr) return null;
        final required = hb.hb_set_create();
        final retained = hb.hb_set_create();
        try {
          hb.hb_face_collect_unicodes(face, required);
          hb.hb_set_intersect(required, unicodes);
          hb.hb_face_collect_unicodes(subset, retained);
          hb.hb_set_subtract(required, retained);
          if (hb.hb_set_is_empty(required) == 0) return null;
        } finally {
          hb.hb_set_destroy(required);
          hb.hb_set_destroy(retained);
        }
        output = hb.hb_face_reference_blob(subset);
        final length = arena<UnsignedInt>();
        final result = hb.hb_blob_get_data(output, length);
        if (result == nullptr || length.value == 0) return null;
        return Uint8List.fromList(
          result.cast<Uint8>().asTypedList(length.value),
        );
      } finally {
        if (output != nullptr) hb.hb_blob_destroy(output);
        if (subset != nullptr) hb.hb_face_destroy(subset);
        if (input != nullptr) hb.hb_subset_input_destroy(input);
        if (face != nullptr) hb.hb_face_destroy(face);
        hb.hb_blob_destroy(blob);
      }
    });
  }
}
