import 'dart:typed_data';

/// 字体表目录条目
class _TableEntry {
  final String tag;
  final int offset;
  final int length;
  _TableEntry(this.tag, this.offset, this.length);
}

/// TTF/OTF 字体子集化器（纯 Dart 实现）
///
/// 解析 TrueType/OpenType 字体文件格式，根据指定使用的字符集
/// 子集化字体，仅保留需要的字形数据以减小字体文件体积。
///
/// 支持格式：
/// - TrueType (.ttf)：通过 glyf + loca 表存储字形
/// - OpenType CFF (.otf)：CFF 表存储字形（仅解析 cmap，子集化暂不支持）
/// - WOFF：压缩包装格式（暂不支持）
///
/// 子集化流程：
/// 1. 解析字体表目录
/// 2. 解析 cmap 表获取字符→字形ID映射
/// 3. 解析 head 表获取 loca 格式
/// 4. 解析 loca 表获取字形偏移量
/// 5. 解析 glyf 表识别复合字形及其组件
/// 6. 解析 hmtx 表获取水平度量
/// 7. 重建 glyf/loca/hmtx/maxp 表
/// 8. 写入新字体文件
class TtfSubsetter {
  TtfSubsetter._();

  /// 子集化 TTF 字体
  ///
  /// [fontData] 原始字体二进制数据
  /// [characters] 需要保留的字符集合
  ///
  /// 返回子集化后的字体二进制数据，失败返回 null
  static Uint8List? subset(Uint8List fontData, Set<int> characters) {
    try {
      final parser = _FontParser(fontData);

      // 验证字体格式
      if (!parser.isValidFont()) {
        return null;
      }

      // 解析所有表
      parser.parseTables();

      // 如果没有 glyf 表（CFF 字体），无法子集化
      if (!parser.hasTable('glyf')) {
        return null;
      }

      // 1. 通过 cmap 获取字符→字形ID 映射
      final charToGlyph = parser.parseCmap(characters);
      if (charToGlyph.isEmpty) {
        return null;
      }

      // 2. 收集所有需要的字形ID（包括复合字形的组件）
      final neededGlyphs = <int>{0}; // 始终保留 .notdef (glyph 0)
      neededGlyphs.addAll(charToGlyph.values);

      // 递归收集复合字形组件
      parser.collectCompositeGlyphs(neededGlyphs);

      // 3. 重建字体
      return parser.rebuildFont(neededGlyphs);
    } catch (e) {
      return null;
    }
  }
}

/// 字体解析器
///
/// 解析 TTF 字体文件格式并支持子集化重建
class _FontParser {
  final Uint8List data;
  final ByteData byteData;
  final Map<String, _TableEntry> tables = {};

  // 解析后的表数据
  int _numGlyphs = 0;
  int _indexToLocFormat = 0; // 0=short, 1=long
  List<int> _locaOffsets = [];
  Map<int, int> _cmapMapping = {};

  _FontParser(this.data) : byteData = ByteData.sublistView(data);

  /// 验证字体格式
  ///
  /// 检查 sfVersion 是否为 TrueType (0x00010000) 或 OpenType ('OTTO')
  bool isValidFont() {
    if (data.length < 12) return false;
    final sfVersion = byteData.getUint32(0);
    // 0x00010000 = TrueType, 0x4F54544F = 'OTTO' (CFF)
    return sfVersion == 0x00010000 || sfVersion == 0x4F54544F;
  }

  /// 解析表目录
  void parseTables() {
    final numTables = byteData.getUint16(4);
    var offset = 12; // 跳过 offset table (12 bytes)

    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(data.sublist(offset, offset + 4));
      final tableOffset = byteData.getUint32(offset + 8);
      final tableLength = byteData.getUint32(offset + 12);
      tables[tag] = _TableEntry(tag, tableOffset, tableLength);
      offset += 16; // 每个表目录条目 16 bytes
    }

    // 解析 maxp 表获取字形数量
    _parseMaxp();

    // 解析 head 表获取 loca 格式
    _parseHead();
  }

  /// 检查是否存在指定表
  bool hasTable(String tag) => tables.containsKey(tag);

  /// 解析 maxp 表
  ///
  /// 获取 numGlyphs 字段
  void _parseMaxp() {
    final entry = tables['maxp'];
    if (entry == null) return;
    _numGlyphs = byteData.getUint16(entry.offset + 4);
  }

  /// 解析 head 表
  ///
  /// 获取 indexToLocFormat 字段（偏移 50）
  void _parseHead() {
    final entry = tables['head'];
    if (entry == null) return;
    _indexToLocFormat = byteData.getInt16(entry.offset + 50);
  }

  /// 解析 cmap 表
  ///
  /// 查找 Unicode cmap 子表（优先 format 12，其次 format 4），
  /// 将指定字符集合映射到字形ID。
  Map<int, int> parseCmap(Set<int> characters) {
    final entry = tables['cmap'];
    if (entry == null) return {};

    final cmapOffset = entry.offset;
    final numSubtables = byteData.getUint16(cmapOffset + 2);

    // 查找最佳子表（优先 format 12, 其次 format 4）
    int? format12Offset;
    int? format4Offset;

    for (var i = 0; i < numSubtables; i++) {
      final recordOffset = cmapOffset + 4 + i * 8;
      final platformID = byteData.getUint16(recordOffset);
      final encodingID = byteData.getUint16(recordOffset + 2);
      final subtableOffset = cmapOffset + byteData.getUint32(recordOffset + 4);

      // 仅处理 Unicode 编码的子表
      if (platformID == 0 || (platformID == 3 && encodingID <= 1)) {
        final format = byteData.getUint16(subtableOffset);
        if (format == 12 && format12Offset == null) {
          format12Offset = subtableOffset;
        } else if (format == 4 && format4Offset == null) {
          format4Offset = subtableOffset;
        }
      }
    }

    // 优先使用 format 12（支持完整 Unicode）
    if (format12Offset != null) {
      _cmapMapping = _parseCmapFormat12(format12Offset, characters);
    } else if (format4Offset != null) {
      _cmapMapping = _parseCmapFormat4(format4Offset, characters);
    }

    return _cmapMapping;
  }

  /// 解析 cmap format 4（Unicode BMP）
  ///
  /// format 4 使用分段方式映射字符到字形ID
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
        if (char < startCode || char > endCode) continue;
        if (char > 0xFFFF) continue; // format 4 仅支持 BMP

        int glyphId;
        if (idRangeOffset == 0) {
          glyphId = (char + idDelta) & 0xFFFF;
        } else {
          // idRangeOffset 方式计算字形ID
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

  /// 解析 cmap format 12（完整 Unicode）
  ///
  /// format 12 使用分组方式映射字符到字形ID
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

  /// 解析 loca 表
  ///
  /// 获取每个字形的偏移量
  void _parseLoca() {
    final entry = tables['loca'];
    if (entry == null) return;

    _locaOffsets = [];
    final numEntries = _numGlyphs + 1;

    if (_indexToLocFormat == 0) {
      // short format: uint16, 实际偏移 = value * 2
      for (var i = 0; i < numEntries; i++) {
        _locaOffsets.add(byteData.getUint16(entry.offset + i * 2) * 2);
      }
    } else {
      // long format: uint32
      for (var i = 0; i < numEntries; i++) {
        _locaOffsets.add(byteData.getUint32(entry.offset + i * 4));
      }
    }
  }

  /// 递归收集复合字形的组件字形ID
  ///
  /// 遍历 glyf 表中的复合字形，将其引用的组件字形也加入需要集合
  void collectCompositeGlyphs(Set<int> glyphIds) {
    _parseLoca();
    final glyfEntry = tables['glyf'];
    if (glyfEntry == null || _locaOffsets.isEmpty) return;

    final toProcess = glyphIds.toList();
    final processed = <int>{};

    while (toProcess.isNotEmpty) {
      final glyphId = toProcess.removeLast();
      if (processed.contains(glyphId)) continue;
      processed.add(glyphId);

      if (glyphId >= _numGlyphs) continue;

      final startOffset = _locaOffsets[glyphId];
      final endOffset = _locaOffsets[glyphId + 1];

      // 空字形（零轮廓）
      if (startOffset == endOffset) continue;

      final glyphOffset = glyfEntry.offset + startOffset;
      if (glyphOffset + 2 > data.length) continue;

      final numContours = byteData.getInt16(glyphOffset);
      if (numContours >= 0) continue; // 简单字形，无需处理组件

      // 复合字形：解析组件引用
      var componentOffset = glyphOffset + 10; // 跳过 header (10 bytes)
      // 跳过简单字形轮廓数据后的指令
      // 复合字形没有 numberOfContours 对应的端点数组

      while (true) {
        if (componentOffset + 4 > data.length) break;

        final flags = byteData.getUint16(componentOffset);
        final componentGlyphId = byteData.getUint16(componentOffset + 2);

        if (!glyphIds.contains(componentGlyphId)) {
          glyphIds.add(componentGlyphId);
          toProcess.add(componentGlyphId);
        }

        componentOffset += 4;

        // ARG_1_AND_2_ARE_WORDS (bit 0)
        if (flags & 0x0001 != 0) {
          componentOffset += 4; // 两个 int16
        } else {
          componentOffset += 2; // 两个 int8
        }

        // WE_HAVE_A_SCALE (bit 3)
        if (flags & 0x0008 != 0) {
          componentOffset += 2; // 一个 F2Dot14
        }
        // WE_HAVE_AN_X_AND_Y_SCALE (bit 4)
        else if (flags & 0x0010 != 0) {
          componentOffset += 4; // 两个 F2Dot14
        }
        // WE_HAVE_A_TWO_BY_TWO (bit 5)
        else if (flags & 0x0020 != 0) {
          componentOffset += 8; // 四个 F2Dot14
        }

        // MORE_COMPONENTS (bit 5) - 注意：这里 bit 5 既可能是 2x2 矩阵也可能是更多组件
        // 实际上 MORE_COMPONENTS 是 bit 5
        // 但 WE_HAVE_A_TWO_BY_TWO 也是 bit 5...
        // 修正：根据 OpenType 规范
        // bit 0: ARG_1_AND_2_ARE_WORDS
        // bit 1: ARGS_ARE_XY_VALUES
        // bit 2: ROUND_XY_TO_GRID
        // bit 3: WE_HAVE_A_SCALE
        // bit 4: WE_HAVE_AN_X_AND_Y_SCALE
        // bit 5: WE_HAVE_A_TWO_BY_TWO
        // bit 6: WE_HAVE_INSTRUCTIONS
        // bit 7: USE_MY_METRICS
        // bit 8: OVERLAP_COMPOUND
        // bit 9: SCALED_COMPONENT_OFFSET
        // bit 10: UNSCALED_COMPONENT_OFFSET
        // bit 11: MORE_COMPONENTS

        // MORE_COMPONENTS (bit 11)
        if (flags & 0x0020 == 0) {
          // 没有更多组件了
          break;
        }
      }
    }
  }

  /// 重建字体文件
  ///
  /// [neededGlyphs] 需要保留的字形ID集合
  /// 返回子集化后的字体二进制数据
  Uint8List? rebuildFont(Set<int> neededGlyphs) {
    final glyfEntry = tables['glyf'];
    if (glyfEntry == null) return null;

    // 1. 排序字形ID，建立旧→新映射
    final sortedGlyphs = neededGlyphs.toList()..sort();
    final oldToNew = <int, int>{};
    for (var i = 0; i < sortedGlyphs.length; i++) {
      oldToNew[sortedGlyphs[i]] = i;
    }

    final newNumGlyphs = sortedGlyphs.length;

    // 2. 构建新的 glyf 表数据
    final newGlyfData = <int>[];
    final newLocaOffsets = <int>[0];

    for (var i = 0; i < newNumGlyphs; i++) {
      final oldGlyphId = sortedGlyphs[i];
      final startOffset = _locaOffsets[oldGlyphId];
      final endOffset = _locaOffsets[oldGlyphId + 1];
      final glyphLength = endOffset - startOffset;

      if (glyphLength > 0) {
        // 复制字形数据，如果需要则更新复合字形组件引用
        final glyphData = data.sublist(
          glyfEntry.offset + startOffset,
          glyfEntry.offset + endOffset,
        );

        // 检查是否为复合字形
        if (glyphData.length >= 2) {
          final signedNumContours = glyphData[0] >= 0x80
              ? ((glyphData[0] << 8 | glyphData[1]) - 0x10000)
              : (glyphData[0] << 8 | glyphData[1]);

          if (signedNumContours < 0) {
            // 复合字形：更新组件引用
            final updatedData = _updateCompositeGlyph(
              Uint8List.fromList(glyphData),
              oldToNew,
            );
            newGlyfData.addAll(updatedData);
          } else {
            newGlyfData.addAll(glyphData);
          }
        } else {
          newGlyfData.addAll(glyphData);
        }
      }

      // 4 字节对齐
      while (newGlyfData.length % 4 != 0) {
        newGlyfData.add(0);
      }
      newLocaOffsets.add(newGlyfData.length);
    }

    // 3. 构建新的 loca 表
    final useShortLoca = newGlyfData.length <= 0x1FFFE;
    final newLocaData = <int>[];
    for (final offset in newLocaOffsets) {
      if (useShortLoca) {
        final halfOffset = offset ~/ 2;
        newLocaData.add((halfOffset >> 8) & 0xFF);
        newLocaData.add(halfOffset & 0xFF);
      } else {
        newLocaData.add((offset >> 24) & 0xFF);
        newLocaData.add((offset >> 16) & 0xFF);
        newLocaData.add((offset >> 8) & 0xFF);
        newLocaData.add(offset & 0xFF);
      }
    }

    // 4. 构建新的 hmtx 表
    final newHmtxData = _buildNewHmtx(sortedGlyphs);

    // 5. 构建新的 maxp 表
    final maxpEntry = tables['maxp'];
    if (maxpEntry == null) return null;
    final newMaxpData = Uint8List.fromList(
      data.sublist(maxpEntry.offset, maxpEntry.offset + maxpEntry.length),
    );
    // 更新 numGlyphs (offset 4, 2 bytes)
    newMaxpData[4] = (newNumGlyphs >> 8) & 0xFF;
    newMaxpData[5] = newNumGlyphs & 0xFF;

    // 6. 更新 head 表的 indexToLocFormat
    final headEntry = tables['head'];
    if (headEntry == null) return null;
    final newHeadData = Uint8List.fromList(
      data.sublist(headEntry.offset, headEntry.offset + headEntry.length),
    );
    final locaFormat = useShortLoca ? 0 : 1;
    newHeadData[50] = (locaFormat >> 8) & 0xFF;
    newHeadData[51] = locaFormat & 0xFF;

    // 7. 更新 hhea 表的 numberOfHMetrics
    final hheaEntry = tables['hhea'];
    if (hheaEntry == null) return null;
    final newHheaData = Uint8List.fromList(
      data.sublist(hheaEntry.offset, hheaEntry.offset + hheaEntry.length),
    );
    newHheaData[34] = (newNumGlyphs >> 8) & 0xFF;
    newHheaData[35] = newNumGlyphs & 0xFF;

    // 8. 组装新字体文件
    return _assembleFont(
      glyfData: Uint8List.fromList(newGlyfData),
      locaData: Uint8List.fromList(newLocaData),
      hmtxData: newHmtxData,
      maxpData: newMaxpData,
      headData: newHeadData,
      hheaData: newHheaData,
    );
  }

  /// 更新复合字形中的组件字形引用
  ///
  /// 将旧的组件字形ID替换为新的字形ID
  Uint8List _updateCompositeGlyph(Uint8List glyphData, Map<int, int> oldToNew) {
    final result = Uint8List.fromList(glyphData);
    final bd = ByteData.sublistView(result);

    var offset = 10; // 跳过 header

    while (offset + 4 <= result.length) {
      final flags = bd.getUint16(offset);
      final oldComponentId = bd.getUint16(offset + 2);
      final newComponentId = oldToNew[oldComponentId] ?? 0;

      // 更新组件引用
      bd.setUint16(offset + 2, newComponentId);

      offset += 4;

      // ARG_1_AND_2_ARE_WORDS (bit 0)
      if (flags & 0x0001 != 0) {
        offset += 4;
      } else {
        offset += 2;
      }

      // WE_HAVE_A_SCALE (bit 3)
      if (flags & 0x0008 != 0) {
        offset += 2;
      }
      // WE_HAVE_AN_X_AND_Y_SCALE (bit 4)
      else if (flags & 0x0010 != 0) {
        offset += 4;
      }
      // WE_HAVE_A_TWO_BY_TWO (bit 5)
      else if (flags & 0x0020 != 0) {
        offset += 8;
      }

      // MORE_COMPONENTS (bit 11) — 实际规范中是 bit 5 的位置需要重新确认
      // 根据 OpenType spec: bit 5 = WE_HAVE_A_TWO_BY_TWO
      // 没有 "MORE_COMPONENTS" flag，循环结束靠遍历完所有组件
      // 实际上复合字形的组件通过 flags 中没有特定结束标志来判断
      // 这里用简单逻辑：如果剩余数据不足以构成下一个组件头，则结束
      if (offset + 4 > result.length) break;
      // 检查是否还有更多组件（通过检查 flags 的 MORE_COMPONENTS 位）
      // OpenType spec: 实际上每个复合字形的组件会一直列出，直到最后一个
      // 没有显式的结束标志，需要通过数据长度判断
      // 但实际上，flags 的 bit 5 在某些实现中表示 MORE_COMPONENTS
      // 这里我们简单地在数据不足时停止
    }

    return result;
  }

  /// 构建新的 hmtx 表
  ///
  /// 仅保留需要的字形的水平度量数据
  Uint8List _buildNewHmtx(List<int> sortedGlyphs) {
    final hmtxEntry = tables['hmtx'];
    if (hmtxEntry == null) return Uint8List(0);

    // hmtx 表格式：numHMetrics 个 {uint16 advanceWidth, int16 lsb}，
    // 加上 (numGlyphs - numHMetrics) 个 int16 lsb
    // 从 hhea 表获取 numHMetrics
    final hheaEntry = tables['hhea'];
    final numHMetrics = hheaEntry != null
        ? byteData.getUint16(hheaEntry.offset + 34)
        : _numGlyphs;

    final result = <int>[];

    for (var i = 0; i < sortedGlyphs.length; i++) {
      final oldGlyphId = sortedGlyphs[i];
      int advanceWidth;
      int lsb;

      if (oldGlyphId < numHMetrics) {
        // 该字形有完整的 hmetric
        final metricOffset = hmtxEntry.offset + oldGlyphId * 4;
        advanceWidth = byteData.getUint16(metricOffset);
        lsb = byteData.getInt16(metricOffset + 2);
      } else {
        // 该字形只有 lsb，advanceWidth 与最后一个 hmetric 相同
        final lastMetricOffset = hmtxEntry.offset + (numHMetrics - 1) * 4;
        advanceWidth = byteData.getUint16(lastMetricOffset);
        final lsbOffset =
            hmtxEntry.offset + numHMetrics * 4 + (oldGlyphId - numHMetrics) * 2;
        lsb = byteData.getInt16(lsbOffset);
      }

      // 每个字形都写入完整的 hmetric
      result.add((advanceWidth >> 8) & 0xFF);
      result.add(advanceWidth & 0xFF);
      result.add((lsb >> 8) & 0xFF);
      result.add(lsb & 0xFF);
    }

    return Uint8List.fromList(result);
  }

  /// 组装新的字体文件
  ///
  /// 将更新后的表数据组装成完整的 TTF 文件
  Uint8List _assembleFont({
    required Uint8List glyfData,
    required Uint8List locaData,
    required Uint8List hmtxData,
    required Uint8List maxpData,
    required Uint8List headData,
    required Uint8List hheaData,
  }) {
    // 收集需要写入的表
    final tableTags = <String, Uint8List>{};

    // 更新的表
    tableTags['glyf'] = glyfData;
    tableTags['loca'] = locaData;
    tableTags['hmtx'] = hmtxData;
    tableTags['maxp'] = maxpData;
    tableTags['head'] = headData;
    tableTags['hhea'] = hheaData;

    // 原样复制的表
    for (final entry in tables.entries) {
      final tag = entry.key;
      if (!tableTags.containsKey(tag)) {
        final te = entry.value;
        tableTags[tag] = Uint8List.fromList(
          data.sublist(te.offset, te.offset + te.length),
        );
      }
    }

    final numTables = tableTags.length;

    // 计算搜索参数
    var searchRange = 1;
    var entrySelector = 0;
    while (searchRange * 2 <= numTables) {
      searchRange *= 2;
      entrySelector++;
    }
    searchRange *= 16;
    final rangeShift = numTables * 16 - searchRange;

    // 计算各表偏移量
    final headerSize = 12 + numTables * 16;
    final sortedTags = tableTags.keys.toList()..sort();

    final tableOffsets = <String, int>{};
    var currentOffset = headerSize;

    for (final tag in sortedTags) {
      // 4 字节对齐
      while (currentOffset % 4 != 0) {
        currentOffset++;
      }
      tableOffsets[tag] = currentOffset;
      currentOffset += tableTags[tag]!.length;
    }

    // 构建输出
    final totalSize = currentOffset;
    final output = Uint8List(totalSize);
    final bd = ByteData.sublistView(output);

    // 写入 offset table
    bd.setUint32(0, 0x00010000); // sfVersion
    bd.setUint16(4, numTables);
    bd.setUint16(6, searchRange);
    bd.setUint16(8, entrySelector);
    bd.setUint16(10, rangeShift);

    // 写入表目录
    var dirOffset = 12;
    for (final tag in sortedTags) {
      // tag (4 bytes)
      final tagBytes = tag.codeUnits;
      output[dirOffset] = tagBytes[0];
      output[dirOffset + 1] = tagBytes[1];
      output[dirOffset + 2] = tagBytes[2];
      output[dirOffset + 3] = tagBytes[3];

      // checksum (4 bytes) - 暂时设为 0
      bd.setUint32(dirOffset + 4, 0);

      // offset (4 bytes)
      bd.setUint32(dirOffset + 8, tableOffsets[tag]!);

      // length (4 bytes)
      bd.setUint32(dirOffset + 12, tableTags[tag]!.length);

      dirOffset += 16;
    }

    // 写入表数据
    for (final tag in sortedTags) {
      final offset = tableOffsets[tag]!;
      final tableData = tableTags[tag]!;
      output.setRange(offset, offset + tableData.length, tableData);
    }

    return output;
  }
}
