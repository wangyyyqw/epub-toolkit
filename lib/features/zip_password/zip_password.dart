import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// 解包 EPUB 内容，再使用 WinZip AES-256 密码重新打包或恢复普通包。
///
/// 加密后的文件保留 `.epub` 扩展名，但不再是普通阅读器可直接打开的标准
/// EPUB；必须先解除密码并重新打包为标准 OCF ZIP。
class ZipPasswordOperation {
  ZipPasswordOperation._();

  static final RegExp _printableAscii = RegExp(r'^[\x20-\x7E]+$');

  /// 读取并解压原 EPUB 的所有条目，再输出 AES-256 加密 EPUB ZIP。
  static Future<String> addPassword({
    required String epubPath,
    required String outputPath,
    required String password,
  }) async {
    _validateAddPassword(password);
    _ensureDifferentPaths(epubPath, outputPath);

    final inputBytes = await File(epubPath).readAsBytes();
    if (_hasEncryptedEntries(inputBytes)) {
      throw const ZipPasswordException('该 EPUB 已包含 ZIP 密码，请勿重复加密');
    }

    final archive = _decodeArchive(inputBytes);
    _validateEpub(archive);
    final ordered = _orderedArchive(archive);

    await _writeAtomically(outputPath, (partPath) async {
      await _writeZip(ordered, partPath, password: password);

      final encryptedBytes = await File(partPath).readAsBytes();
      if (!_hasEncryptedEntries(encryptedBytes)) {
        throw const ZipPasswordException('加密验证失败：输出文件未标记为加密 ZIP');
      }
      final verified = _decodeArchive(encryptedBytes, password: password);
      _validateEpub(verified);
    });

    return 'EPUB 已解包并使用密码重新打包（WinZip AES-256）\n'
        '输出文件: $outputPath\n'
        '提示: 支持密码 ZIP 的阅读器可输入密码后直接解压阅读。';
  }

  /// 解除 ZIP 密码并恢复标准 EPUB 包结构。
  static Future<String> removePassword({
    required String epubPath,
    required String outputPath,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const ZipPasswordException('请输入密码');
    }
    _ensureDifferentPaths(epubPath, outputPath);

    final inputBytes = await File(epubPath).readAsBytes();
    if (!_hasEncryptedEntries(inputBytes)) {
      throw const ZipPasswordException('该 EPUB 未检测到 ZIP 密码');
    }

    late Archive archive;
    try {
      archive = _decodeArchive(inputBytes, password: password);
      _validateEpub(archive);
    } catch (_) {
      throw const ZipPasswordException('密码错误或加密 EPUB 已损坏');
    }

    final ordered = _orderedArchive(archive);
    await _writeAtomically(outputPath, (partPath) async {
      await _writeZip(ordered, partPath);
      final restoredBytes = await File(partPath).readAsBytes();
      if (_hasEncryptedEntries(restoredBytes)) {
        throw const ZipPasswordException('解除密码失败：输出仍包含加密条目');
      }
      final restored = _decodeArchive(restoredBytes);
      _validateEpub(restored);
      _validateStandardMimetype(restoredBytes);
    });

    return 'ZIP 密码已解除，EPUB 标准结构已恢复\n输出文件: $outputPath';
  }

  static void _validateAddPassword(String password) {
    if (password.length < 8 || password.length > 64) {
      throw const ZipPasswordException('密码长度必须为 8–64 个字符');
    }
    if (!_printableAscii.hasMatch(password)) {
      throw const ZipPasswordException(
        '为确保与 7-Zip、WinRAR 兼容，密码目前仅支持可打印 ASCII 字符',
      );
    }
  }

  static void _ensureDifferentPaths(String inputPath, String outputPath) {
    if (p.canonicalize(inputPath) == p.canonicalize(outputPath)) {
      throw const ZipPasswordException('输出路径不能覆盖输入文件');
    }
  }

  static Archive _decodeArchive(Uint8List bytes, {String? password}) {
    final archive = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      password: password,
    );

    // archive 对 ZIP 内容采用延迟解码，主动访问所有文件以校验密码和 AES MAC。
    for (final file in archive.files.where((file) => file.isFile)) {
      final content = file.content;
      if (content is! List<int>) {
        throw const ZipPasswordException('ZIP 条目内容无效');
      }
    }
    return archive;
  }

  static void _validateEpub(Archive archive) {
    final mimetype = archive.findFile('mimetype');
    final container = archive.findFile('META-INF/container.xml');
    final hasOpf = archive.files.any(
      (file) => file.isFile && file.name.toLowerCase().endsWith('.opf'),
    );
    if (mimetype == null || container == null || !hasOpf) {
      throw const ZipPasswordException('文件不是有效 EPUB：缺少必要结构');
    }
    final value = utf8.decode(mimetype.content as List<int>);
    if (value != 'application/epub+zip') {
      throw const ZipPasswordException('文件不是有效 EPUB：mimetype 内容错误');
    }
  }

  static Archive _orderedArchive(Archive source) {
    final output = Archive()..comment = source.comment;
    final mimetype = source.findFile('mimetype')!;
    output.addFile(_copyFile(mimetype, compress: false));
    for (final file in source.files) {
      if (!file.isFile || file.name.isEmpty || file.name == 'mimetype') {
        continue;
      }
      output.addFile(_copyFile(file));
    }
    return output;
  }

  static ArchiveFile _copyFile(ArchiveFile source, {bool? compress}) {
    final bytes = Uint8List.fromList(source.content as List<int>);
    return ArchiveFile(source.name, bytes.length, bytes)
      ..compress = compress ?? source.compress
      ..comment = source.comment
      ..lastModTime = source.lastModTime
      ..mode = source.mode;
  }

  static Future<void> _writeZip(
    Archive archive,
    String outputPath, {
    String? password,
  }) async {
    final output = OutputFileStream(outputPath);
    try {
      ZipEncoder(
        password: password,
      ).encode(archive, output: output, autoClose: false);
    } finally {
      await output.close();
    }
  }

  static Future<void> _writeAtomically(
    String outputPath,
    Future<void> Function(String partPath) write,
  ) async {
    final output = File(outputPath);
    final part = File('$outputPath.part');
    if (await part.exists()) await part.delete();
    try {
      await part.parent.create(recursive: true);
      await write(part.path);
      if (await output.exists()) await output.delete();
      await part.rename(outputPath);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  static bool _hasEncryptedEntries(Uint8List bytes) {
    const centralSignature = 0x02014B50;
    for (var i = 0; i + 46 <= bytes.length; i++) {
      if (_uint32(bytes, i) != centralSignature) continue;
      final flags = _uint16(bytes, i + 8);
      if ((flags & 0x0001) != 0) return true;
      final nameLength = _uint16(bytes, i + 28);
      final extraLength = _uint16(bytes, i + 30);
      final commentLength = _uint16(bytes, i + 32);
      i += 45 + nameLength + extraLength + commentLength;
    }
    return false;
  }

  static void _validateStandardMimetype(Uint8List bytes) {
    if (bytes.length < 38 || _uint32(bytes, 0) != 0x04034B50) {
      throw const ZipPasswordException('恢复后的 EPUB ZIP 头无效');
    }
    final flags = _uint16(bytes, 6);
    final method = _uint16(bytes, 8);
    final nameLength = _uint16(bytes, 26);
    final extraLength = _uint16(bytes, 28);
    final name = utf8.decode(bytes.sublist(30, 30 + nameLength));
    if (name != 'mimetype' ||
        flags & 1 != 0 ||
        method != 0 ||
        extraLength != 0) {
      throw const ZipPasswordException('恢复后的 EPUB mimetype 不符合 OCF 规范');
    }
  }

  static int _uint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _uint32(Uint8List bytes, int offset) {
    return _uint16(bytes, offset) | (_uint16(bytes, offset + 2) << 16);
  }
}

class ZipPasswordException implements Exception {
  const ZipPasswordException(this.message);

  final String message;

  @override
  String toString() => message;
}
