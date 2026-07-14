import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文件选择服务
///
/// 封装 file_picker 包，提供统一的文件选择接口。
/// 支持单选、多选、目录选择和保存对话框。
class FileService {
  FileService._();

  static Future<Directory> _documentsBooksDirectory() async {
    if (Platform.isMacOS) {
      final user = Platform.environment['USER'];
      final homeDir = (user != null && user.isNotEmpty)
          ? p.join('/Users', user)
          : (Platform.environment['HOME'] ?? '/tmp');
      final outDir = Directory(p.join(homeDir, 'Documents', 'books'));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      return outDir;
    }

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'books'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    return outDir;
  }

  static Future<String> _uniquePath(String directory, String filename) async {
    final extension = p.extension(filename);
    final basename = p.basenameWithoutExtension(filename);
    var candidate = p.join(directory, filename);
    var index = 1;
    while (await File(candidate).exists() ||
        await Directory(candidate).exists()) {
      candidate = p.join(directory, '${basename}_$index$extension');
      index++;
    }
    return candidate;
  }

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static List<String>? _pendingDroppedPaths;

  static void primeDroppedPaths(List<String> paths) {
    _pendingDroppedPaths = paths
        .where((path) => path.trim().isNotEmpty)
        .toList();
  }

  static List<String>? _takePendingDroppedPaths() {
    final paths = _pendingDroppedPaths;
    _pendingDroppedPaths = null;
    if (paths == null || paths.isEmpty) return null;
    return paths;
  }

  static bool hasExtension(String path, List<String> extensions) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return extensions
        .map((e) => e.toLowerCase().replaceFirst('.', ''))
        .contains(ext);
  }

  static List<String> filterPathsByExtensions(
    List<String> paths,
    List<String> extensions,
  ) {
    return paths.where((path) => hasExtension(path, extensions)).toList();
  }

  static String? firstPathByExtensions(
    List<String> paths,
    List<String> extensions,
  ) {
    final matches = filterPathsByExtensions(paths, extensions);
    return matches.isEmpty ? null : matches.first;
  }

  static Future<Directory> _existingOutputDirectory(
    String? directoryPath,
  ) async {
    if (directoryPath != null && directoryPath.trim().isNotEmpty) {
      final directory = Directory(directoryPath);
      if (await directory.exists()) return directory;
    }
    return _documentsBooksDirectory();
  }

  static Future<String> _uniqueFilenameInDirectory(
    Directory directory,
    String filename,
  ) async {
    return p.basename(await _uniquePath(directory.path, filename));
  }

  /// 选择单个文件
  ///
  /// [type] 文件类型限制，默认为任意文件
  /// [allowedExtensions] 允许的扩展名列表（当 type 为 FileType.custom 时生效）
  /// 返回文件路径，用户取消则返回 null
  static Future<String?> pickFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String title = '选择文件',
  }) async {
    final dropped = _takePendingDroppedPaths();
    if (dropped != null) {
      final matches = _filterDroppedPaths(
        dropped,
        type: type,
        allowedExtensions: allowedExtensions,
      );
      if (matches.isNotEmpty) return matches.first;
    }

    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      dialogTitle: title,
    );
    return result?.files.single.path;
  }

  /// 选择指定扩展名的文件（统一入口，传入 ['epub'] 即可限制系统选择器只显示 EPUB）
  ///
  /// [extensions] 扩展名列表（不含 `.`，如 ['epub']）
  /// [title] 对话框标题
  /// 返回文件路径，用户取消则返回 null
  static Future<String?> pickFileByExtensions(
    List<String> extensions, {
    String title = '选择文件',
  }) async {
    final droppedPath = _takeFirstDroppedPathByExtensions(extensions);
    if (droppedPath != null) return droppedPath;

    // 先用 custom 过滤；如 macOS 上 custom 过滤异常则降级到 any + 后置校验
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        dialogTitle: title,
      );
      final path = result?.files.single.path;
      if (path == null) return null;
      // 二次校验扩展名
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      if (extensions.map((e) => e.toLowerCase()).contains(ext)) {
        return path;
      }
      throw FormatException('请选择 .${extensions.join(' / .')} 文件');
    } on PlatformException {
      // macOS NSOpenPanel custom 过滤偶发异常 → 降级
      final path = await pickFile(type: FileType.any, title: title);
      if (path == null) return null;
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      if (extensions.map((e) => e.toLowerCase()).contains(ext)) {
        return path;
      }
      throw FormatException('请选择 .${extensions.join(' / .')} 文件');
    }
  }

  /// 选择多个文件
  ///
  /// 返回文件路径列表，用户取消则返回 null
  static Future<List<String>?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String title = '选择文件（可多选）',
  }) async {
    final dropped = _takePendingDroppedPaths();
    if (dropped != null) {
      final matches = _filterDroppedPaths(
        dropped,
        type: type,
        allowedExtensions: allowedExtensions,
      );
      if (matches.isNotEmpty) return matches;
    }

    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
      dialogTitle: title,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.map((f) => f.path).whereType<String>().toList();
  }

  /// 选择 EPUB 文件
  static Future<String?> pickEpub() async {
    // 文件选择器只显示 epub 后缀的文件
    return pickFileByExtensions(['epub'], title: '选择 EPUB 文件');
  }

  /// 选择多个 EPUB 文件（用于合并操作）
  ///
  /// 返回文件路径列表，用户取消则返回 null
  static Future<List<String>?> pickMultipleEpubs() async {
    final dropped = _takePendingDroppedPaths();
    if (dropped != null) {
      final matches = filterPathsByExtensions(dropped, ['epub']);
      if (matches.isNotEmpty) return matches;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      allowMultiple: true,
      dialogTitle: '选择 EPUB 文件（可多选）',
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.map((f) => f.path).whereType<String>().toList();
  }

  /// 选择图片文件
  static Future<String?> pickImage() async {
    return pickFile(type: FileType.image, title: '选择图片文件');
  }

  /// 选择 TXT 文件
  static Future<String?> pickTxt() async {
    return pickFileByExtensions(['txt'], title: '选择 TXT 文件');
  }

  static String? _takeFirstDroppedPathByExtensions(List<String> extensions) {
    final dropped = _takePendingDroppedPaths();
    if (dropped == null) return null;
    return firstPathByExtensions(dropped, extensions);
  }

  static List<String> _filterDroppedPaths(
    List<String> paths, {
    required FileType type,
    List<String>? allowedExtensions,
  }) {
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      return filterPathsByExtensions(paths, allowedExtensions);
    }
    if (type == FileType.image) {
      return filterPathsByExtensions(paths, [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'bmp',
        'gif',
      ]);
    }
    if (type == FileType.custom) return const [];
    return paths;
  }

  /// 保存文件对话框
  ///
  /// [defaultFileName] 默认文件名
  /// 返回用户选择的保存路径，取消则返回 null
  ///
  /// **Android** 11+ 走 SAF（Storage Access Framework）：
  /// - 需要 MainActivity 继承 FlutterFragmentActivity（否则系统 Intent 后闪退）
  /// - SAF 异常时降级到应用专属目录，不会崩溃
  static Future<String?> saveFile({
    String defaultFileName = 'output.epub',
    String? initialDirectory,
  }) async {
    final booksDir = await _documentsBooksDirectory();
    final pickerDir = await _existingOutputDirectory(initialDirectory);
    final safeFileName = await _uniqueFilenameInDirectory(
      pickerDir,
      defaultFileName,
    );
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        initialDirectory: pickerDir.path,
        fileName: safeFileName,
      );
      return result;
    } on PlatformException catch (e) {
      // SAF 异常：回退到应用专属目录（永不崩溃）
      debugPrint('[FileService] saveFile SAF failed, fallback to app dir: $e');
      final fallback = File(p.join(booksDir.path, safeFileName));
      return fallback.path;
    } catch (e) {
      debugPrint(
        '[FileService] saveFile unknown error, fallback to app dir: $e',
      );
      final fallback = File(p.join(booksDir.path, safeFileName));
      return fallback.path;
    }
  }

  /// 选择目录（Android 11+ 走 SAF）
  ///
  /// **注意**：在 Android 上使用 file_picker 的 getDirectoryPath 必须确保
  /// MainActivity 继承 FlutterFragmentActivity，否则系统启动 SAF Intent
  /// 后无法接收结果会闪退。本方法已做异常保护，SAF 失败时返回 null 而不崩溃。
  static Future<String?> pickDirectory({String title = '选择目录'}) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: title,
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint('[FileService] pickDirectory failed: $e');
      return null;
    } catch (e, st) {
      debugPrint('[FileService] pickDirectory unknown error: $e\n$st');
      return null;
    }
  }

  /// 获取沙盒安全输出路径
  ///
  /// **Android**：写入应用专属的外部存储目录（`getExternalFilesDir()`），
  /// 不需要任何运行时权限，符合 Android 11+ Scoped Storage 规范。
  /// 用户如需保存到公共 Download 目录，应使用 `saveFile()` 走 SAF 通道。
  ///
  /// **macOS**：写入真实用户目录 `/Users/<user>/Documents/books/`。
  ///
  /// **Windows/iOS**：写入应用文档目录。
  ///
  /// [filename] 输出文件名（如 book_output.epub）
  static Future<String> getSafeOutputPath(String filename) async {
    // Android：写入应用专属外部存储目录（getExternalFilesDir）
    // 该目录是 /storage/emulated/0/Android/data/<pkg>/files/
    // 无需任何权限，应用卸载时自动清理
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final outDir = Directory(p.join(extDir.path, 'books'));
          if (!await outDir.exists()) {
            await outDir.create(recursive: true);
          }
          return _uniquePath(outDir.path, filename);
        }
      } catch (_) {
        // 退化到 getApplicationDocumentsDirectory
      }
      // 退化：应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'books'));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      return _uniquePath(outDir.path, filename);
    }

    // macOS：输出到真实用户 Documents/books，避免沙盒 HOME 被重定向到
    // ~/Library/Containers/.../Data。
    if (Platform.isMacOS) {
      final outDir = await _documentsBooksDirectory();
      return _uniquePath(outDir.path, filename);
    }

    // Windows/iOS：应用文档目录
    final outDir = await _documentsBooksDirectory();
    return _uniquePath(outDir.path, filename);
  }

  /// 根据输入文件生成默认输出路径。
  ///
  /// macOS/Windows/Linux 默认输出到输入文件所在目录；移动端仍使用应用安全目录，
  /// 避免 Android Scoped Storage 与 iOS 沙盒限制导致写入失败。
  static Future<String> getDefaultOutputPathForInput({
    required String inputPath,
    required String filename,
  }) async {
    if (_isDesktop && inputPath.trim().isNotEmpty) {
      final inputDir = p.dirname(inputPath);
      if (await Directory(inputDir).exists()) {
        return _uniquePath(inputDir, filename);
      }
    }
    return getSafeOutputPath(filename);
  }

  /// 根据目录生成默认输出路径。用于合并、多文件操作等没有单一输入文件的场景。
  static Future<String> getDefaultOutputPathInDirectory({
    required String directoryPath,
    required String filename,
  }) async {
    if (_isDesktop && directoryPath.trim().isNotEmpty) {
      final outputDir = Directory(directoryPath);
      if (await outputDir.exists()) {
        return _uniquePath(outputDir.path, filename);
      }
    }
    return getSafeOutputPath(filename);
  }

  /// 将文件复制到公共 Download/books/ 目录（Android）
  ///
  /// **Android 10+ 限制**：应用无法直接通过 File API 写入公共 Download 目录。
  /// 通过 MethodChannel 调原生 [MediaStore.Downloads] API 写入，
  /// 这是 Google 官方推荐的「无需 WRITE_EXTERNAL_STORAGE 权限保存到公共 Download」方式。
  ///
  /// **非 Android 平台**：降级用 File.copy 写到应用文档目录，
  /// 然后返回源路径（不做实际复制，调用方应优先在 Android 上用此方法）。
  ///
  /// [filename] 文件名（如 "book.epub"）
  /// [bytes] 文件内容字节
  ///
  /// 返回用户可见的路径（Android 形如 "/storage/emulated/0/Download/books/book.epub"），
  /// 失败时抛出异常。
  ///
  /// **注意**：对大文件（如 >30MB），应改用
  /// [copyFileToPublicDownload] 直接传文件路径，避免 Dart 堆内存峰值
  /// （之前 47MB EPUB 在 MethodChannel 序列化时会复制 2 份，导致 OOM 闪退）。
  static Future<String> writeToPublicDownload({
    required String filename,
    required Uint8List bytes,
  }) async {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.epub_gadget/file_helper');
      final displayPath = await channel.invokeMethod<String>(
        'writeToPublicDownload',
        <String, dynamic>{'filename': filename, 'bytes': bytes},
      );
      if (displayPath == null) {
        throw Exception('写入公共 Download 失败：MethodChannel 返回 null');
      }
      return displayPath;
    }
    // macOS：直接写到真实用户 Documents/books
    if (Platform.isMacOS) {
      final outDir = await _documentsBooksDirectory();
      final destPath = p.join(outDir.path, filename);
      await File(destPath).writeAsBytes(bytes);
      return destPath;
    }

    // Windows/iOS：应用文档目录
    final outDir = await _documentsBooksDirectory();
    final destPath = p.join(outDir.path, filename);
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  /// 将已有文件流式复制到公共 Download/books/ 目录（Android）
  ///
  /// 与 [writeToPublicDownload] 的区别：**不在 Dart 堆里持有完整文件内容**。
  /// 原生端通过 `FileInputStream` 读取源文件并写入 MediaStore.OutputStream，
  /// Dart 仅传文件路径，整个过程 Dart 堆占用 < 1MB。
  ///
  /// 之前的 bug：47MB EPUB 用 `writeToPublicDownload(bytes: 47MB Uint8List)` 时，
  /// Dart 持有 47MB 副本 + MethodChannel 序列化时复制 47MB = 94MB 内存峰值，
  /// 超过 Android 默认 ART 堆 192MB 的 50%，叠加 UI Dart 堆 100MB，
  /// 在中低端设备上必闪退。
  ///
  /// 适用场景：
  /// - 任意大文件（首选）
  /// - 不需要修改内容的"复制"动作
  ///
  /// [sourcePath] 源文件绝对路径（应用专属目录下的临时文件）
  /// [filename] 目标文件名（如 "book.epub"）
  ///
  /// 返回用户可见的公共 Download 路径。
  static Future<String> copyFileToPublicDownload({
    required String sourcePath,
    required String filename,
  }) async {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.epub_gadget/file_helper');
      final displayPath = await channel.invokeMethod<String>(
        'copyFileToPublicDownload',
        <String, dynamic>{'sourcePath': sourcePath, 'filename': filename},
      );
      if (displayPath == null) {
        throw Exception('流式复制到公共 Download 失败：MethodChannel 返回 null');
      }
      return displayPath;
    }
    // macOS：直接复制文件到真实用户 Documents/books
    if (Platform.isMacOS) {
      final outDir = await _documentsBooksDirectory();
      final destPath = p.join(outDir.path, filename);
      await File(sourcePath).copy(destPath);
      return destPath;
    }

    // Windows/iOS：应用文档目录
    final outDir = await _documentsBooksDirectory();
    final destPath = p.join(outDir.path, filename);
    await File(sourcePath).copy(destPath);
    return destPath;
  }
}
