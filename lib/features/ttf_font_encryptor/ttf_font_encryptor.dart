import 'dart:math';
import 'dart:typed_data';

/// 字体表目录条目
class _TableEntry {
  final String tag;
  final int offset;
  final int length;
  _TableEntry(this.tag, this.offset, this.length);
}

/// 字体加密结果
class EncryptResult {
  /// 加密后的字体数据，失败为 null
  final Uint8List? fontData;

  /// 字符→影子码点的映射表（用于 HTML 替换）
  final Map<int, int> charToShadow;

  EncryptResult(this.fontData, this.charToShadow);
}

/// TTF 字体加密器（纯 Dart 实现）
///
/// 通过修改字体的 cmap 表实现字形混淆加密：
/// 1. 解析原始 cmap，获取字符→字形ID 映射
/// 2. 为每个待加密字符随机分配一个韩文 Hangul 码点（影子码点）
/// 3. 在 cmap 中添加影子码点→原字形ID 的映射
/// 4. 重建字体文件（含正确的 checksum 和 format 4/12 双子表）
///
/// 效果：HTML 中用影子码点实体（如 &#xAC00;）替换明文字符，
/// 显示正常（影子码点指向原字形），但复制出来是韩文乱码。
class TtfFontEncryptor {
  TtfFontEncryptor._();

  /// 韩文 Hangul 码点范围（0xAC00-0xD7AF，共 11172 个）
  static const int _hangulStart = 0xAC00;
  static const int _hangulEnd = 0xD7AF;

  /// 加密 TTF 字体
  ///
  /// [fontData] 原始字体二进制数据
  /// [characters] 需要加密的字符集合
  ///
  /// 返回加密结果，包含新字体数据和字符→影子码点映射。
  /// 失败返回 null（fontData 为 null）。
  static EncryptResult encrypt(Uint8List fontData, Set<int> characters) {
    try {
      final parser = _FontParser(fontData);

      if (!parser.isValidFont()) {
        return EncryptResult(null, {});
      }

      parser.parseTables();

      // 仅支持含 glyf 表的 TTF 字体
      if (!parser.hasTable('glyf')) {
        return EncryptResult(null, {});
      }

      // 1. 解析 cmap，获取字符→字形ID 映射
      final charToGlyph = parser.parseCmap(characters);
      if (charToGlyph.isEmpty) {
        return EncryptResult(null, {});
      }

      // 2. 生成随机韩文影子码点
      final random = Random();
      final availableCodes = List.generate(
        _hangulEnd - _hangulStart + 1,
        (i) => _hangulStart + i,
      );
      availableCodes.shuffle(random);

      final charToShadow = <int, int>{};
      final shadowToGlyph = <int, int>{};
      var shadowIdx = 0;

      for (final entry in charToGlyph.entries) {
        final charCode = entry.key;
        final glyphId = entry.value;
        if (glyphId == 0) continue; // 跳过未映射字符

        if (shadowIdx >= availableCodes.length) break;

        final shadowCode = availableCodes[shadowIdx++];
        charToShadow[charCode] = shadowCode;
        shadowToGlyph[shadowCode] = glyphId;
      }

      if (charToShadow.isEmpty) {
        return EncryptResult(null, {});
      }

      // 3. 重建 cmap 表（同时包含 format 4 和 format 12 子表）
      final newCmapData = parser.buildEncryptedCmap(shadowToGlyph);

      // 4. 重建字体（含正确 checksum）
      final newFontData = parser.rebuildFontWithCmap(newCmapData);

      return EncryptResult(newFontData, charToShadow);
    } catch (e) {
      return EncryptResult(null, {});
    }
  }
}

/// 字体解析器（用于字体加密）
///
/// 解析 TTF 字体文件，支持 cmap 解析和加密重建
class _FontParser {
  final Uint8List data;
  final ByteData byteData;
  final Map<String, _TableEntry> tables = {};

  _FontParser(this.data) : byteData = ByteData.sublistView(data);

  /// 验证字体格式
  bool isValidFont() {
    if (data.length < 12) return false;
    final sfVersion = byteData.getUint32(0);
    return sfVersion == 0x00010000 || sfVersion == 0x4F54544F;
  }

  /// 解析表目录
  void parseTables() {
    final numTables = byteData.getUint16(4);
    var offset = 12;

    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(data.sublist(offset, offset + 4));
      final tableOffset = byteData.getUint32(offset + 8);
      final tableLength = byteData.getUint32(offset + 12);
      tables[tag] = _TableEntry(tag, tableOffset, tableLength);
      offset += 16;
    }
  }

  /// 检查是否存在指定表
  bool hasTable(String tag) => tables.containsKey(tag);

  /// 解析 cmap 表
  ///
  /// 将指定字符集合映射到字形ID。
  Map<int, int> parseCmap(Set<int> characters) {
    final entry = tables['cmap'];
    if (entry == null) return {};

    final cmapOffset = entry.offset;
    final numSubtables = byteData.getUint16(cmapOffset + 2);

    int? format12Offset;
    int? format4Offset;

    for (var i = 0; i < numSubtables; i++) {
      final recordOffset = cmapOffset + 4 + i * 8;
      final platformID = byteData.getUint16(recordOffset);
      final encodingID = byteData.getUint16(recordOffset + 2);
      final subtableOffset = cmapOffset + byteData.getUint32(recordOffset + 4);

      if (platformID == 0 || (platformID == 3 && encodingID <= 1)) {
        final format = byteData.getUint16(subtableOffset);
        if (format == 12 && format12Offset == null) {
          format12Offset = subtableOffset;
        } else if (format == 4 && format4Offset == null) {
          format4Offset = subtableOffset;
        }
      }
    }

    if (format12Offset != null) {
      return _parseCmapFormat12(format12Offset, characters);
    } else if (format4Offset != null) {
      return _parseCmapFormat4(format4Offset, characters);
    }

    return {};
  }

  /// 解析 cmap format 4
  Map<int, int> _parseCmapFormat4(int offset, Set<int> characters) {
    final result = <int, int>{};
    final segCountX2 = byteData.getUint16(offset + 6);
    final segCount = segCountX2 ~/ 2;

    final endCodeOffset = offset + 14;
    final startCodeOffset = endCodeOffset + segCountX2 + 2;
    final idDeltaOffset = startCodeOffset + segCountX2;
    final idRangeOffsetOffset = idDeltaOffset + segCountX2;

    for (var seg = 0; seg < segCount; seg++) {
      final endCode = byteData.getUint16(endCodeOffset + seg * 2);
      final startCode = byteData.getUint16(startCodeOffset + seg * 2);
      final idDelta = byteData.getInt16(idDeltaOffset + seg * 2);
      final idRangeOffset = byteData.getUint16(idRangeOffsetOffset + seg * 2);

      if (startCode == 0xFFFF && endCode == 0xFFFF) break;

      for (final char in characters) {
        if (char < startCode || char > endCode || char > 0xFFFF) continue;

        int glyphId;
        if (idRangeOffset == 0) {
          glyphId = (char + idDelta) & 0xFFFF;
        } else {
          final glyphIndexOffset =
              idRangeOffsetOffset +
              seg * 2 +
              idRangeOffset +
              (char - startCode) * 2;
          if (glyphIndexOffset + 2 > data.length) continue;
          final glyphIndex = byteData.getUint16(glyphIndexOffset);
          if (glyphIndex == 0) continue;
          glyphId = (glyphIndex + idDelta) & 0xFFFF;
        }

        if (glyphId != 0) {
          result[char] = glyphId;
        }
      }
    }

    return result;
  }

  /// 解析 cmap format 12
  Map<int, int> _parseCmapFormat12(int offset, Set<int> characters) {
    final result = <int, int>{};
    final numGroups = byteData.getUint32(offset + 12);

    for (var group = 0; group < numGroups; group++) {
      final groupOffset = offset + 16 + group * 12;
      final startCharCode = byteData.getUint32(groupOffset);
      final endCharCode = byteData.getUint32(groupOffset + 4);
      final startGlyphID = byteData.getUint32(groupOffset + 8);

      for (final char in characters) {
        if (char >= startCharCode && char <= endCharCode) {
          result[char] = startGlyphID + (char - startCharCode);
        }
      }
    }

    return result;
  }

  /// 构建加密后的 cmap 表
  ///
  /// 同时生成 format 4 和 format 12 子表，确保最大兼容性。
  /// 所有影子码点均在 BMP 范围内（Hangul 0xAC00-0xD7AF），
  /// 因此 format 4 和 format 12 均可完整表示。
  ///
  /// [shadowToGlyph] 影子码点→字形ID 映射
  /// 返回完整的 cmap 表二进制数据
  Uint8List buildEncryptedCmap(Map<int, int> shadowToGlyph) {
    // 将映射按码点排序，合并连续码点为分组
    final sortedEntries = shadowToGlyph.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // 构建分组（用于 format 12）
    final groups = <List<int>>[]; // [startCode, endCode, startGlyphID]
    for (final entry in sortedEntries) {
      final code = entry.key;
      final glyphId = entry.value;

      if (groups.isNotEmpty) {
        final lastGroup = groups.last;
        final lastCode = lastGroup[1];
        final lastGlyph = lastGroup[2];
        if (code == lastCode + 1 && glyphId == lastGlyph + (code - lastCode)) {
          lastGroup[1] = code;
          continue;
        }
      }
      groups.add([code, code, glyphId]);
    }

    // 构建 format 12 子表
    final f12Subtable = _buildFormat12Subtable(groups);

    // 构建 format 4 子表（所有码点都在 BMP 内）
    final f4Subtable = _buildFormat4Subtable(sortedEntries);

    // cmap 表头：4 个子表记录（platform 0 + platform 3，各含 format 4 和 12）
    final numSubtables = 4;
    final headerLength = 4 + numSubtables * 8;
    final cmapData = Uint8List(
      headerLength + f4Subtable.length + f12Subtable.length,
    );
    final cmapBd = ByteData.sublistView(cmapData);

    cmapBd.setUint16(0, 0); // version
    cmapBd.setUint16(2, numSubtables); // numSubtables

    final f4Offset = headerLength;
    final f12Offset = headerLength + f4Subtable.length;

    // 子表记录 1: platformID=0, encodingID=3 (Unicode BMP) → format 4
    cmapBd.setUint16(4, 0);
    cmapBd.setUint16(6, 3);
    cmapBd.setUint32(8, f4Offset);

    // 子表记录 2: platformID=0, encodingID=4 (Unicode full) → format 12
    cmapBd.setUint16(12, 0);
    cmapBd.setUint16(14, 4);
    cmapBd.setUint32(16, f12Offset);

    // 子表记录 3: platformID=3, encodingID=1 (Windows BMP) → format 4
    cmapBd.setUint16(20, 3);
    cmapBd.setUint16(22, 1);
    cmapBd.setUint32(24, f4Offset);

    // 子表记录 4: platformID=3, encodingID=10 (Windows Unicode full) → format 12
    cmapBd.setUint16(28, 3);
    cmapBd.setUint16(30, 10);
    cmapBd.setUint32(32, f12Offset);

    // 复制子表数据
    cmapData.setRange(f4Offset, f4Offset + f4Subtable.length, f4Subtable);
    cmapData.setRange(f12Offset, f12Offset + f12Subtable.length, f12Subtable);

    return cmapData;
  }

  /// 构建 format 12 子表
  Uint8List _buildFormat12Subtable(List<List<int>> groups) {
    final numGroups = groups.length;
    final subtableLength = 16 + numGroups * 12;
    final subtable = Uint8List(subtableLength);
    final bd = ByteData.sublistView(subtable);

    bd.setUint16(0, 12); // format
    bd.setUint16(2, 0); // reserved
    bd.setUint32(4, subtableLength); // length
    bd.setUint32(8, 0); // language
    bd.setUint32(12, numGroups); // numGroups

    for (var i = 0; i < numGroups; i++) {
      final g = groups[i];
      bd.setUint32(16 + i * 12, g[0]); // startCharCode
      bd.setUint32(16 + i * 12 + 4, g[1]); // endCharCode
      bd.setUint32(16 + i * 12 + 8, g[2]); // startGlyphID
    }

    return subtable;
  }

  /// 构建 format 4 子表
  ///
  /// 将影子码点映射转换为 format 4 的段表示。
  /// 所有码点都在 BMP 范围（0xAC00-0xD7AF），可完整表示。
  Uint8List _buildFormat4Subtable(List<MapEntry<int, int>> sortedEntries) {
    // 构建段（与 format 12 分组逻辑相同，但用 16 位）
    final segments = <List<int>>[]; // [startCode, endCode, startGlyphID]
    for (final entry in sortedEntries) {
      final code = entry.key;
      final glyphId = entry.value;

      if (segments.isNotEmpty) {
        final lastSeg = segments.last;
        final lastCode = lastSeg[1];
        final lastGlyph = lastSeg[2];
        if (code == lastCode + 1 && glyphId == lastGlyph + (code - lastCode)) {
          lastSeg[1] = code;
          continue;
        }
      }
      segments.add([code, code, glyphId]);
    }

    // 添加终止段 (0xFFFF)
    segments.add([0xFFFF, 0xFFFF, 0]);

    final segCount = segments.length;
    final segCountX2 = segCount * 2;

    // 计算 searchRange/entrySelector/rangeShift
    var searchRange = 1;
    var entrySelector = 0;
    while (searchRange * 2 <= segCount) {
      searchRange *= 2;
      entrySelector++;
    }
    searchRange *= 2;
    final rangeShift = segCountX2 - searchRange;

    // 构建 format 4 子表
    // 布局: header(14) + endCode(segCountX2) + reserved(2) + startCode(segCountX2) + idDelta(segCountX2) + idRangeOffset(segCountX2)
    final subtableLength = 14 + segCountX2 * 4 + 2;
    final subtable = Uint8List(subtableLength);
    final bd = ByteData.sublistView(subtable);

    bd.setUint16(0, 4); // format
    bd.setUint16(2, subtableLength); // length
    bd.setUint16(4, 0); // language
    bd.setUint16(6, segCountX2); // segCountX2
    bd.setUint16(8, searchRange); // searchRange
    bd.setUint16(10, entrySelector); // entrySelector
    bd.setUint16(12, rangeShift); // rangeShift

    var offset = 14;
    // endCode 数组
    for (final seg in segments) {
      bd.setUint16(offset, seg[1]);
      offset += 2;
    }
    // reservedPad
    bd.setUint16(offset, 0);
    offset += 2;
    // startCode 数组
    for (final seg in segments) {
      bd.setUint16(offset, seg[0]);
      offset += 2;
    }
    // idDelta 数组（使用 delta 编码：glyphId - startCode）
    for (final seg in segments) {
      final delta = (seg[2] - seg[0]) & 0xFFFF;
      bd.setUint16(offset, delta);
      offset += 2;
    }
    // idRangeOffset 数组（全部为 0，使用 delta 模式）
    for (var i = 0; i < segCount; i++) {
      bd.setUint16(offset, 0);
      offset += 2;
    }

    return subtable;
  }

  /// 用新的 cmap 表重建字体
  ///
  /// 复制所有原始表，仅替换 cmap 表，
  /// 计算正确的表 checksum 和 head.checkSumAdjustment。
  Uint8List rebuildFontWithCmap(Uint8List newCmapData) {
    final tableTags = <String, Uint8List>{};

    // 替换 cmap 表
    tableTags['cmap'] = newCmapData;

    // 原样复制其他表
    for (final entry in tables.entries) {
      final tag = entry.key;
      if (tag == 'cmap') continue;
      final te = entry.value;
      tableTags[tag] = Uint8List.fromList(
        data.sublist(te.offset, te.offset + te.length),
      );
    }

    final numTables = tableTags.length;
    var searchRange = 1;
    var entrySelector = 0;
    while (searchRange * 2 <= numTables) {
      searchRange *= 2;
      entrySelector++;
    }
    searchRange *= 16;
    final rangeShift = numTables * 16 - searchRange;

    final sortedTags = tableTags.keys.toList()..sort();
    final headerSize = 12 + numTables * 16;

    // 计算每个表的偏移（4 字节对齐）
    final tableOffsets = <String, int>{};
    var currentOffset = headerSize;

    for (final tag in sortedTags) {
      while (currentOffset % 4 != 0) {
        currentOffset++;
      }
      tableOffsets[tag] = currentOffset;
      currentOffset += tableTags[tag]!.length;
    }

    final totalSize = currentOffset;
    final output = Uint8List(totalSize);
    final bd = ByteData.sublistView(output);

    // offset table
    bd.setUint32(0, 0x00010000);
    bd.setUint16(4, numTables);
    bd.setUint16(6, searchRange);
    bd.setUint16(8, entrySelector);
    bd.setUint16(10, rangeShift);

    // 表数据先写入（需要计算 checksum）
    for (final tag in sortedTags) {
      final offset = tableOffsets[tag]!;
      final td = tableTags[tag]!;
      output.setRange(offset, offset + td.length, td);
    }

    // 先将 head 表的 checkSumAdjustment 置 0
    // （TTF 规范要求计算 head 表 checksum 和文件 checksum 时该字段为 0）
    final headEntry = tableOffsets['head'];
    if (headEntry != null) {
      bd.setUint32(headEntry + 8, 0);
    }

    // 计算每个表的 checksum 并写入表目录
    var dirOffset = 12;
    for (final tag in sortedTags) {
      final tagBytes = tag.codeUnits;
      output[dirOffset] = tagBytes[0];
      output[dirOffset + 1] = tagBytes[1];
      output[dirOffset + 2] = tagBytes[2];
      output[dirOffset + 3] = tagBytes[3];

      // 计算表数据的 checksum
      final tableOffset = tableOffsets[tag]!;
      final tableData = tableTags[tag]!;
      final checksum = _calculateChecksum(
        output,
        tableOffset,
        tableData.length,
      );
      bd.setUint32(dirOffset + 4, checksum);
      bd.setUint32(dirOffset + 8, tableOffset);
      bd.setUint32(dirOffset + 12, tableData.length);
      dirOffset += 16;
    }

    // 计算 head 表的 checkSumAdjustment
    // checkSumAdjustment = 0xB1B0AFBA - 整个文件的 checksum（checkSumAdjustment 为 0 时）
    if (headEntry != null) {
      final fileChecksum = _calculateChecksum(output, 0, totalSize);
      final adjustment = (0xB1B0AFBA - fileChecksum) & 0xFFFFFFFF;
      bd.setUint32(headEntry + 8, adjustment);
    }

    return output;
  }

  /// 计算 TTF 表 checksum
  ///
  /// 将数据按 uint32 求和，不足 4 字节末尾补 0。
  static int _calculateChecksum(Uint8List data, int offset, int length) {
    int sum = 0;
    final paddedLength = (length + 3) & ~3; // 向上对齐到 4 字节

    for (var i = 0; i < paddedLength; i += 4) {
      int val = 0;
      for (var j = 0; j < 4; j++) {
        val <<= 8;
        final pos = offset + i + j;
        if (pos < offset + length && pos < data.length) {
          val |= data[pos];
        }
      }
      sum = (sum + val) & 0xFFFFFFFF;
    }
    return sum;
  }
}
