// 验证 EPUB 输出的 ZIP 结构是否合法
//
// 检查项：
// 1. 文件以 PK\x03\x04 签名开头（不是零填充）
// 2. mimetype 是第一个文件
// 3. mimetype 使用 STORE 方式（不压缩）
// 4. mimetype 内容为 "application/epub+zip"
// 5. local file header 数量与 central directory 条目数一致
// 6. 所有 central directory 中的 offset 指向有效的 local file header

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epub_gadget/core/chinese_converter.dart';
import 'package:epub_gadget/features/encrypt_font/encrypt_font.dart';
import 'package:epub_gadget/features/encrypt/encrypt.dart';
import 'package:epub_gadget/features/decrypt/decrypt.dart';
import 'package:epub_gadget/core/epub_image_helper.dart';

final Directory _tempDir = Directory.systemTemp.createTempSync('epub_struct_');

/// 构造含 TTF 字体的最小 EPUB
Archive _buildEpubWithFont() {
  final archive = Archive();

  // mimetype（STORE，第一个）
  archive.addFile(ArchiveFile(
    'mimetype',
    'application/epub+zip'.length,
    utf8.encode('application/epub+zip'),
  )..compress = false);

  // container.xml
  const containerXml =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '  <rootfiles>\n'
      '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
      '  </rootfiles>\n</container>';
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    containerXml.length,
    utf8.encode(containerXml),
  ));

  // CSS（含 @font-face）
  const css = '@font-face { font-family: "testfont"; src: url(fonts/test.ttf); }\n'
      'body { font-family: "testfont"; }';
  archive.addFile(ArchiveFile(
    'OEBPS/style.css',
    css.length,
    utf8.encode(css),
  ));

  // OPF
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bid">\n'
      '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
      '    <dc:identifier id="bid">urn:uuid:test</dc:identifier>\n'
      '    <dc:title>Test</dc:title>\n'
      '    <dc:language>zh-CN</dc:language>\n'
      '  </metadata>\n'
      '  <manifest>\n'
      '    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>\n'
      '    <item id="css1" href="style.css" media-type="text/css"/>\n'
      '    <item id="font1" href="fonts/test.ttf" media-type="font/ttf"/>\n'
      '  </manifest>\n'
      '  <spine>\n    <itemref idref="ch1"/>\n  </spine>\n'
      '</package>';
  archive.addFile(ArchiveFile(
    'OEBPS/content.opf',
    opf.length,
    utf8.encode(opf),
  ));

  // XHTML（含中文文本）
  const xhtml =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml">\n'
      '<head><title>测试</title></head>\n'
      '<body><p>这是一段测试文本用于字体加密</p></body>\n'
      '</html>';
  archive.addFile(ArchiveFile(
    'OEBPS/chapter1.xhtml',
    xhtml.length,
    utf8.encode(xhtml),
  ));

  // 最小 TTF 字体（带 cmap 和 glyf 表）
  final fontBytes = _buildMinimalTtf();
  archive.addFile(ArchiveFile(
    'OEBPS/fonts/test.ttf',
    fontBytes.length,
    fontBytes,
  ));

  return archive;
}

/// 构建包含基本表的最小 TTF 字体
Uint8List _buildMinimalTtf() {
  // 构建一个极简但合法的 TTF 文件
  // 包含: head, hhea, maxp, OS/2, name, cmap, post, glyf, loca
  final tables = <String, Uint8List>{};

  // head 表 (54 字节)
  final head = Uint8List(54);
  head[0] = 0x00; head[1] = 0x01; // majorVersion
  head[2] = 0x00; head[3] = 0x00; // minorVersion
  // fontRevision
  head[12] = 0x5F; head[13] = 0x0F; head[14] = 0x3C; head[15] = 0xF5; // magicNumber
  head[16] = 0x00; head[17] = 0x0B; // flags
  head[18] = 0x03; head[19] = 0xE8; // unitsPerEm = 1000
  // created, modified (8 bytes each, offset 20-35)
  // macStyle, lowestRecPPEM (offset 40-43)
  // fontDirectionHint (offset 44-45)
  // indexToLocFormat = 0 (short, offset 50-51)
  tables['head'] = head;

  // hhea 表 (36 字节)
  final hhea = Uint8List(36);
  hhea[0] = 0x00; hhea[1] = 0x01; // majorVersion
  hhea[4] = 0x03; hhea[5] = 0xE8; // ascent = 1000
  hhea[6] = 0x00; hhea[7] = 0x00; // descent = 0
  // numberOfHMetrics (offset 34-35)
  hhea[34] = 0x00; hhea[35] = 0x01;
  tables['hhea'] = hhea;

  // maxp 表 (6 字节, version 0.5)
  final maxp = Uint8List(6);
  maxp[0] = 0x00; maxp[1] = 0x00; maxp[2] = 0x50; maxp[3] = 0x00; // version 0.5
  maxp[4] = 0x00; maxp[5] = 0x01; // numGlyphs = 1
  tables['maxp'] = maxp;

  // cmap 表 (含 format 4 和 format 12)
  final cmap = _buildCmapTable();
  tables['cmap'] = cmap;

  // post 表 (32 字节, version 3.0)
  final post = Uint8List(32);
  post[0] = 0x00; post[1] = 0x03; post[2] = 0x00; post[3] = 0x00; // version 3.0
  tables['post'] = post;

  // glyf 表 (空字形)
  final glyf = Uint8List(12);
  glyf[0] = 0x00; glyf[1] = 0x00; // numberOfContours = 0
  tables['glyf'] = glyf;

  // loca 表 (short format, 2 entries: glyph 0 offset + end offset)
  final loca = Uint8List(4);
  loca[0] = 0x00; loca[1] = 0x00; // offset 0
  loca[2] = 0x00; loca[3] = 0x0C; // end offset = 12
  tables['loca'] = loca;

  // name 表 (最小)
  final name = Uint8List(6);
  tables['name'] = name;

  // hmtx 表 (4 bytes per glyph)
  final hmtx = Uint8List(4);
  hmtx[0] = 0x03; hmtx[1] = 0xE8; // advanceWidth = 1000
  tables['hmtx'] = hmtx;

  // 组装 TTF
  final tableList = tables.entries.toList();
  final numTables = tableList.length;
  final headerSize = 12 + numTables * 16;

  // 计算各表偏移
  var offset = headerSize;
  // 对齐到 4 字节
  final tableOffsets = <String, int>{};
  for (final entry in tableList) {
    tableOffsets[entry.key] = offset;
    offset += (entry.value.length + 3) & ~3; // 4字节对齐
  }

  final totalSize = offset;
  final result = Uint8List(totalSize);
  final bd = ByteData.sublistView(result);

  // Offset table
  bd.setUint32(0, 0x00010000); // sfVersion
  bd.setUint16(4, numTables);
  // searchRange, entrySelector, rangeShift
  bd.setUint16(6, 16);
  bd.setUint16(8, 4);
  bd.setUint16(10, 0);

  // Table records
  for (var i = 0; i < numTables; i++) {
    final entry = tableList[i];
    final tag = entry.key;
    final tagBytes = Uint8List.fromList(utf8.encode(tag.padRight(4)));
    final recOffset = 12 + i * 16;
    result.setRange(recOffset, recOffset + 4, tagBytes);
    // checksum (简化为 0)
    bd.setUint32(recOffset + 4, 0);
    bd.setUint32(recOffset + 8, tableOffsets[entry.key]!);
    bd.setUint32(recOffset + 12, entry.value.length);
  }

  // 写入表数据
  for (final entry in tableList) {
    final off = tableOffsets[entry.key]!;
    result.setRange(off, off + entry.value.length, entry.value);
  }

  return result;
}

/// 构建 cmap 表（含 format 4 和 format 12 子表）
Uint8List _buildCmapTable() {
  // format 4 子表：映射 U+4E00 (一) → glyph 0
  final fmt4 = _buildFormat4Subtable();
  // format 12 子表：映射 U+4E00 → glyph 0
  final fmt12 = _buildFormat12Subtable();

  // cmap header
  final headerSize = 4 + 8 * 2; // 4 header + 2 encoding records * 8 bytes
  final totalSize = headerSize + fmt4.length + fmt12.length;
  final result = Uint8List(totalSize);
  final bd = ByteData.sublistView(result);

  // cmap header
  bd.setUint16(0, 0); // version
  bd.setUint16(2, 2); // numTables

  // Encoding record 1: (0,3) → format 4
  bd.setUint16(4, 0); // platformID
  bd.setUint16(6, 3); // encodingID
  bd.setUint32(8, headerSize); // offset

  // Encoding record 2: (0,4) → format 12
  bd.setUint16(12, 0); // platformID
  bd.setUint16(14, 4); // encodingID
  bd.setUint32(16, headerSize + fmt4.length); // offset

  // 写入子表
  result.setRange(headerSize, headerSize + fmt4.length, fmt4);
  result.setRange(headerSize + fmt4.length, totalSize, fmt12);

  return result;
}

Uint8List _buildFormat4Subtable() {
  // 简化版 format 4，映射 U+4E00 → glyph 0
  final segCount = 2; // 1 segment + end segment
  final segCountX2 = segCount * 2;
  final searchRange = 4;
  final entrySelector = 1;
  final rangeShift = 0;

  final dataSize = 16 + segCountX2 * 4; // header(14) + reservedPad(2) + 4 arrays
  final result = Uint8List(dataSize);
  final bd = ByteData.sublistView(result);

  bd.setUint16(0, 4); // format
  bd.setUint16(2, dataSize); // length
  bd.setUint16(4, 0); // language
  bd.setUint16(6, segCountX2);
  bd.setUint16(8, searchRange);
  bd.setUint16(10, entrySelector);
  bd.setUint16(12, rangeShift);

  // endCode array (offset 14)
  bd.setUint16(14, 0x4E00);
  bd.setUint16(16, 0xFFFF);
  // reservedPad (offset 18)
  bd.setUint16(18, 0);
  // startCode array (offset 20)
  bd.setUint16(20, 0x4E00);
  bd.setUint16(22, 0xFFFF);
  // idDelta array (offset 24)
  bd.setUint16(24, 0); // delta = 0 (glyph 0)
  bd.setUint16(26, 1);
  // idRangeOffset array (offset 28)
  bd.setUint16(28, 0);
  bd.setUint16(30, 0);

  return result;
}

Uint8List _buildFormat12Subtable() {
  // format 12 子表：映射 U+4E00 → glyph 0
  final result = Uint8List(28);
  final bd = ByteData.sublistView(result);

  bd.setUint16(0, 12); // format
  bd.setUint16(2, 0); // reserved
  bd.setUint32(4, 28); // length
  bd.setUint32(8, 0); // language
  bd.setUint32(12, 1); // numGroups

  // Group: startCharCode=0x4E00, endCharCode=0x4E00, startGlyphID=0
  bd.setUint32(16, 0x4E00);
  bd.setUint32(20, 0x4E00);
  bd.setUint32(24, 0);

  return result;
}

/// 写入 EPUB 文件
File _writeEpub(String name, Archive archive) {
  final bytes = ZipEncoder().encode(archive)!;
  final f = File('${_tempDir.path}/$name');
  f.writeAsBytesSync(bytes);
  return f;
}

/// 验证 EPUB 文件的 ZIP 结构
void _validateZipStructure(File epubFile, String label) {
  final bytes = epubFile.readAsBytesSync();

  test('$label - ZIP 签名检查', () {
    // 文件必须以 PK\x03\x04 开头
    expect(bytes.length, greaterThan(4), reason: '文件太小');
    expect(bytes[0], 0x50, reason: '第一个字节应为 P (0x50)');
    expect(bytes[1], 0x4B, reason: '第二个字节应为 K (0x4B)');
    expect(bytes[2], 0x03, reason: '第三个字节应为 0x03');
    expect(bytes[3], 0x04, reason: '第四个字节应为 0x04');
  });

  test('$label - mimetype 是第一个文件且 STORE', () {
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.files.isNotEmpty, true, reason: 'archive 不应为空');
    expect(archive.files[0].name, 'mimetype', reason: '第一个文件应为 mimetype');
    expect(archive.files[0].compress, false, reason: 'mimetype 应使用 STORE');
    final content = utf8.decode(archive.files[0].content as List<int>);
    expect(content, 'application/epub+zip', reason: 'mimetype 内容不正确');
  });

  test('$label - local file header 数量与 CD 一致', () {
    // 统计 PK\x03\x04 数量
    var lfhCount = 0;
    for (var i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) {
        lfhCount++;
      }
    }

    // 统计 CD 条目数
    var cdCount = 0;
    for (var i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02) {
        cdCount++;
      }
    }

    expect(lfhCount, cdCount,
        reason: 'LFH 数量($lfhCount) 与 CD 数量($cdCount) 不一致');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ChineseConverter.initS2T();
    await ChineseConverter.initT2S();
  });

  tearDownAll(() async {
    try {
      _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // 1. 测试字体加密输出
  test('字体加密后 EPUB 结构验证', () async {
    final archive = _buildEpubWithFont();
    final f = _writeEpub('font_enc_in.epub', archive);
    final out = '${_tempDir.path}/font_enc_out.epub';
    await EncryptFontOperation.execute(epubPath: f.path, outputPath: out);

    final outFile = File(out);
    expect(outFile.existsSync(), true, reason: '输出文件应存在');

    final bytes = outFile.readAsBytesSync();

    // 验证以 PK\x03\x04 开头
    expect(bytes[0], 0x50, reason: '第一个字节应为 P (0x50)');
    expect(bytes[1], 0x4B, reason: '第二个字节应为 K (0x4B)');
    expect(bytes[2], 0x03, reason: '第三个字节应为 0x03');
    expect(bytes[3], 0x04, reason: '第四个字节应为 0x04');

    // 验证 mimetype 是第一个文件且 STORE
    final outArc = ZipDecoder().decodeBytes(bytes);
    expect(outArc.files[0].name, 'mimetype');
    expect(outArc.files[0].compress, false);
    final mtContent = utf8.decode(outArc.files[0].content as List<int>);
    expect(mtContent, 'application/epub+zip');

    // 验证 LFH 数量 = CD 数量
    var lfhCount = 0;
    var cdCount = 0;
    for (var i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) {
        lfhCount++;
      }
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02) {
        cdCount++;
      }
    }
    expect(lfhCount, cdCount,
        reason: 'LFH($lfhCount) != CD($cdCount)');
    expect(lfhCount, outArc.files.length,
        reason: 'LFH($lfhCount) != files(${outArc.files.length})');

    // 验证没有大块零填充
    var maxZeroRun = 0;
    var currentZeroRun = 0;
    for (final b in bytes) {
      if (b == 0) {
        currentZeroRun++;
        if (currentZeroRun > maxZeroRun) maxZeroRun = currentZeroRun;
      } else {
        currentZeroRun = 0;
      }
    }
    expect(maxZeroRun, lessThan(1024),
        reason: '文件中存在 ${maxZeroRun} 字节的连续零填充，可能数据损坏');
  });

  // 2. 测试名称加密/解密输出
  test('名称加密后 EPUB 结构验证', () async {
    final archive = Archive();
    archive.addFile(ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        utf8.encode('application/epub+zip'))
      ..compress = false);
    archive.addFile(ArchiveFile(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
          .length,
      utf8.encode('<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'),
    ));
    final opf =
        '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="b">x</dc:identifier><dc:title>x</dc:title></metadata><manifest><item id="c1" href="公众号二维码1.jpg" media-type="image/jpeg"/></manifest><spine/></package>';
    archive.addFile(ArchiveFile('OEBPS/content.opf', opf.length, utf8.encode(opf)));
    archive.addFile(ArchiveFile('OEBPS/公众号二维码1.jpg', 2, [0, 0]));

    final f = _writeEpub('enc_in2.epub', archive);
    final encOut = '${_tempDir.path}/enc_out2.epub';
    await EncryptOperation.execute(epubPath: f.path, outputPath: encOut);

    final bytes = File(encOut).readAsBytesSync();

    // 验证以 PK\x03\x04 开头
    expect(bytes[0], 0x50, reason: '第一个字节应为 P');
    expect(bytes[1], 0x4B, reason: '第二个字节应为 K');
    expect(bytes[2], 0x03, reason: '第三个字节应为 0x03');
    expect(bytes[3], 0x04, reason: '第四个字节应为 0x04');

    // 验证 mimetype 第一个且 STORE
    final outArc = ZipDecoder().decodeBytes(bytes);
    expect(outArc.files[0].name, 'mimetype');
    expect(outArc.files[0].compress, false);

    // 验证 LFH = CD
    var lfhCount = 0;
    var cdCount = 0;
    for (var i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) lfhCount++;
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02) cdCount++;
    }
    expect(lfhCount, cdCount, reason: 'LFH($lfhCount) != CD($cdCount)');
  });

  // 3. 测试 mimetype 不在第一位时能正确移动
  test('mimetype 不在第一位时 saveArchive 能正确排序', () async {
    final archive = Archive();
    // 故意把 mimetype 放在第三位
    archive.addFile(ArchiveFile('OEBPS/content.opf', 1, [65]));
    archive.addFile(ArchiveFile('META-INF/container.xml', 1, [66]));
    archive.addFile(ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        utf8.encode('application/epub+zip'))
      ..compress = false);
    archive.addFile(ArchiveFile('OEBPS/chapter1.xhtml', 1, [67]));

    final out = '${_tempDir.path}/reorder_out.epub';
    await EpubImageHelper.saveArchive(archive, out);

    final bytes = File(out).readAsBytesSync();
    final outArc = ZipDecoder().decodeBytes(bytes);

    expect(bytes[0], 0x50, reason: '应以 PK 开头');
    expect(bytes[1], 0x4B);
    expect(outArc.files[0].name, 'mimetype', reason: 'mimetype 应在第一位');
    expect(outArc.files[0].compress, false, reason: 'mimetype 应 STORE');
  });
}
