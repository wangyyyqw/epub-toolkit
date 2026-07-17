import 'dart:io';

import 'package:path/path.dart' as p;

/// WiFi 传书支持的电子书扩展名（Kindle 浏览器可下载的常见格式）。
const Set<String> kWifiBookExtensions = {
  'epub',
  'mobi',
  'azw',
  'azw3',
  'pdf',
  'txt',
  'doc',
  'docx',
  'html',
  'htm',
  'rtf',
};

/// 书库中的一本电子书元数据。
class WifiBook {
  /// 稳定 ID，用于 URL 与本地存储文件名。
  final String id;

  /// 展示标题（通常为去掉扩展名的原文件名，可重命名）。
  final String title;

  /// 用户看到的原始文件名（含扩展名）。
  final String originalFilename;

  /// 书库目录内的实际存储文件名（通常为 id.ext）。
  final String storedFilename;

  /// 大写格式标签，如 EPUB / PDF。
  final String format;

  /// 文件字节数。
  final int byteCount;

  /// 导入时间。
  final DateTime importedAt;

  const WifiBook({
    required this.id,
    required this.title,
    required this.originalFilename,
    required this.storedFilename,
    required this.format,
    required this.byteCount,
    required this.importedAt,
  });

  /// 人类可读的文件大小。
  String get formattedSize {
    if (byteCount < 1024) return '$byteCount B';
    if (byteCount < 1024 * 1024) {
      return '${(byteCount / 1024).toStringAsFixed(1)} KB';
    }
    return '${(byteCount / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'originalFilename': originalFilename,
        'storedFilename': storedFilename,
        'format': format,
        'byteCount': byteCount,
        'importedAt': importedAt.toIso8601String(),
      };

  /// 从 JSON 反序列化。
  factory WifiBook.fromJson(Map<String, dynamic> json) {
    return WifiBook(
      id: json['id'] as String,
      title: json['title'] as String,
      originalFilename: json['originalFilename'] as String,
      storedFilename: json['storedFilename'] as String,
      format: json['format'] as String,
      byteCount: (json['byteCount'] as num).toInt(),
      importedAt: DateTime.parse(json['importedAt'] as String),
    );
  }

  /// 重命名展示标题，保留原扩展名。
  WifiBook copyWithTitle(String newTitle) {
    final ext = p.extension(originalFilename);
    final filename = ext.isEmpty ? newTitle : '$newTitle$ext';
    return WifiBook(
      id: id,
      title: newTitle,
      originalFilename: filename,
      storedFilename: storedFilename,
      format: format,
      byteCount: byteCount,
      importedAt: importedAt,
    );
  }
}

/// Kindle Experimental Browser 对下载文件名与 MIME 较挑剔。
/// 使用 ASCII 短名 + 兼容扩展名，避免中文名与部分固件白名单问题。
class KindleDownloadCompat {
  KindleDownloadCompat._();

  /// 生成 Kindle 友好的下载文件名（纯 ASCII）。
  static String filename(WifiBook book) {
    final ext = downloadExtension(book.format);
    final shortId = book.id.replaceAll('-', '').toLowerCase();
    return 'ebook-$shortId.$ext';
  }

  /// AZW3 在部分固件上需伪装成 azw 扩展名才能被浏览器接受。
  static String downloadExtension(String format) {
    switch (format.toUpperCase()) {
      case 'AZW3':
        return 'azw';
      case 'HTM':
        return 'html';
      default:
        return format.toLowerCase();
    }
  }

  /// 按格式返回 Content-Type。
  /// MOBI/AZW 用 octet-stream，让 Kindle 按扩展名识别。
  static String contentType(String format) {
    switch (format.toUpperCase()) {
      case 'PDF':
        return 'application/pdf';
      case 'TXT':
        return 'text/plain; charset=utf-8';
      case 'EPUB':
        return 'application/epub+zip';
      case 'HTML':
      case 'HTM':
        return 'text/html; charset=utf-8';
      case 'RTF':
        return 'application/rtf';
      case 'DOC':
        return 'application/msword';
      case 'DOCX':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  /// 判断路径扩展名是否受支持。
  static bool isSupportedPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return kWifiBookExtensions.contains(ext);
  }

  /// 从文件路径读取大小。
  static Future<int> fileSize(File file) async {
    final stat = await file.stat();
    return stat.size;
  }
}
