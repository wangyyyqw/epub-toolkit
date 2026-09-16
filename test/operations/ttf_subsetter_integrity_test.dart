import 'dart:io';
import 'dart:typed_data';

import 'package:epub_gadget/features/ttf_subsetter/ttf_subsetter.dart';
import 'package:flutter_test/flutter_test.dart';

int checksum(List<int> bytes) {
  var sum = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    var word = 0;
    for (var j = 0; j < 4; j++) {
      word = (word << 8) | (i + j < bytes.length ? bytes[i + j] : 0);
    }
    sum = (sum + word) & 0xffffffff;
  }
  return sum;
}

Map<String, Uint8List> tables(Uint8List font) {
  final data = ByteData.sublistView(font);
  return {
    for (var i = 0; i < data.getUint16(4); i++)
      String.fromCharCodes(font.sublist(12 + i * 16, 16 + i * 16)): font
          .sublist(
            data.getUint32(20 + i * 16),
            data.getUint32(20 + i * 16) + data.getUint32(24 + i * 16),
          ),
  };
}

List<int> loca(Map<String, Uint8List> font) {
  final format = ByteData.sublistView(font['head']!).getInt16(50);
  final count = ByteData.sublistView(font['maxp']!).getUint16(4);
  final data = ByteData.sublistView(font['loca']!);
  return [
    for (var i = 0; i <= count; i++)
      format == 0 ? data.getUint16(i * 2) * 2 : data.getUint32(i * 4),
  ];
}

void main() {
  for (final character in [66, 0x20000]) {
    test(
      'subset preserves glyph IDs, composites and checksums for $character',
      () async {
        final original = await File(
          'test/fixtures/subset_probe.ttf',
        ).readAsBytes();
        final subset = TtfSubsetter.subset(original, {character});
        expect(subset, isNotNull);
        final before = tables(original);
        final after = tables(subset!);
        expect(after['cmap'], orderedEquals(before['cmap']!));
        expect(after['maxp'], orderedEquals(before['maxp']!));
        final oldLoca = loca(before);
        final newLoca = loca(after);
        for (final id in [0, 1, 3, 4]) {
          final oldGlyph = before['glyf']!.sublist(
            oldLoca[id],
            oldLoca[id + 1],
          );
          final newGlyph = after['glyf']!.sublist(newLoca[id], newLoca[id + 1]);
          expect(newGlyph.take(oldGlyph.length), orderedEquals(oldGlyph));
        }
        for (final id in [2, 5]) {
          expect(newLoca[id], newLoca[id + 1]);
        }
        expect(checksum(subset), 0xb1b0afba);
        final header = ByteData.sublistView(subset);
        for (var i = 0; i < header.getUint16(4); i++) {
          final tag = String.fromCharCodes(
            subset.sublist(12 + i * 16, 16 + i * 16),
          );
          final table = Uint8List.fromList(after[tag]!);
          if (tag == 'head') ByteData.sublistView(table).setUint32(8, 0);
          expect(checksum(table), header.getUint32(16 + i * 16), reason: tag);
        }
      },
    );
  }
}
