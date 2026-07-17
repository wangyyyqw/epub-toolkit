import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'wifi_book.dart';

/// WiFi 传书本地书库：负责导入、重命名、删除与元数据持久化。
class WifiBookLibrary extends ChangeNotifier {
  WifiBookLibrary({Directory? baseDirectory}) : _customBaseDir = baseDirectory;

  static const _uuid = Uuid();

  final Directory? _customBaseDir;

  final List<WifiBook> _books = [];
  String? errorMessage;

  Directory? _booksDir;
  File? _metadataFile;
  bool _ready = false;

  /// 是否已完成初始化。
  bool get isReady => _ready;

  /// 当前书库列表（按导入时间倒序）。
  List<WifiBook> get books => List.unmodifiable(_books);

  /// 书库根目录（初始化后可用）。
  Directory? get booksDirectory => _booksDir;

  /// 初始化书库目录并加载元数据。
  Future<void> init() async {
    if (_ready) return;
    try {
      final root = _customBaseDir ??
          Directory(p.join(
            (await getApplicationSupportDirectory()).path,
            'wifi_transfer',
          ));
      _booksDir = Directory(p.join(root.path, 'books'));
      _metadataFile = File(p.join(root.path, 'library.json'));
      if (!await _booksDir!.exists()) {
        await _booksDir!.create(recursive: true);
      }
      await _load();
      _ready = true;
      notifyListeners();
    } catch (e) {
      errorMessage = '初始化书库失败：$e';
      notifyListeners();
    }
  }

  /// 返回书籍对应的本地文件路径。
  File fileFor(WifiBook book) {
    final dir = _booksDir;
    if (dir == null) {
      throw StateError('书库尚未初始化');
    }
    return File(p.join(dir.path, book.storedFilename));
  }

  /// 从多条路径导入书籍，跳过不支持格式。
  Future<int> importPaths(List<String> paths) async {
    await _ensureReady();
    var imported = 0;
    final failures = <String>[];
    for (final path in paths) {
      try {
        if (!KindleDownloadCompat.isSupportedPath(path)) {
          failures.add('${p.basename(path)}：不支持的格式');
          continue;
        }
        await _importOne(File(path));
        imported++;
      } catch (e) {
        failures.add('${p.basename(path)}：$e');
      }
    }
    _books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    await _save();
    if (failures.isNotEmpty) {
      errorMessage = failures.join('\n');
    }
    notifyListeners();
    return imported;
  }

  /// 删除一本书及其文件。
  Future<void> delete(WifiBook book) async {
    await _ensureReady();
    try {
      final file = fileFor(book);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 文件可能已被手动删除，继续移除元数据。
    }
    _books.removeWhere((b) => b.id == book.id);
    await _save();
    notifyListeners();
  }

  /// 重命名展示标题。
  Future<void> rename(WifiBook book, String newTitle) async {
    final title = newTitle.trim();
    if (title.isEmpty) return;
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index < 0) return;
    _books[index] = book.copyWithTitle(title);
    await _save();
    notifyListeners();
  }

  /// 按标题 / 文件名 / 格式过滤。
  List<WifiBook> filter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return books;
    return _books.where((b) {
      return b.title.toLowerCase().contains(q) ||
          b.originalFilename.toLowerCase().contains(q) ||
          b.format.toLowerCase().contains(q);
    }).toList();
  }

  /// 清除错误提示。
  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _ensureReady() async {
    if (!_ready) await init();
  }

  Future<void> _importOne(File source) async {
    final dir = _booksDir!;
    if (!await source.exists()) {
      throw StateError('文件不存在');
    }
    final ext = p.extension(source.path).toLowerCase().replaceFirst('.', '');
    final id = _uuid.v4();
    final stored = '$id.$ext';
    final dest = File(p.join(dir.path, stored));
    await source.copy(dest.path);
    final size = await KindleDownloadCompat.fileSize(dest);
    final filename = p.basename(source.path);
    final title = p.basenameWithoutExtension(source.path);
    _books.add(
      WifiBook(
        id: id,
        title: title.isEmpty ? filename : title,
        originalFilename: filename,
        storedFilename: stored,
        format: ext.toUpperCase(),
        byteCount: size,
        importedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _load() async {
    final meta = _metadataFile;
    if (meta == null || !await meta.exists()) {
      _books.clear();
      return;
    }
    final raw = await meta.readAsString();
    if (raw.trim().isEmpty) {
      _books.clear();
      return;
    }
    final list = jsonDecode(raw) as List<dynamic>;
    final dir = _booksDir!;
    _books
      ..clear()
      ..addAll(
        list
            .map((e) => WifiBook.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((b) => File(p.join(dir.path, b.storedFilename)).existsSync()),
      );
    _books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
  }

  Future<void> _save() async {
    final meta = _metadataFile;
    if (meta == null) return;
    final data = jsonEncode(_books.map((b) => b.toJson()).toList());
    await meta.writeAsString(data, flush: true);
  }
}
