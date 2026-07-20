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
  static final RegExp _safeBookId = RegExp(r'^[A-Za-z0-9_-]+$');

  final Directory? _customBaseDir;

  final List<WifiBook> _books = [];
  String? errorMessage;

  Directory? _booksDir;
  File? _metadataFile;
  bool _ready = false;
  Future<void> _saveQueue = Future<void>.value();

  /// 是否已完成初始化。
  bool get isReady => _ready;

  /// 当前书库列表（按导入时间倒序）。
  List<WifiBook> get books => List.unmodifiable(_books);

  /// 书库根目录（初始化后可用）。
  Directory? get booksDirectory => _booksDir;

  /// 初始化书库目录并加载元数据。
  Future<void> init() async {
    if (_ready) return;
    errorMessage = null;
    try {
      final root =
          _customBaseDir ??
          Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'wifi_transfer',
            ),
          );
      _booksDir = Directory(p.join(root.path, 'books'));
      _metadataFile = File(p.join(root.path, 'library.json'));
      if (!await _booksDir!.exists()) {
        await _booksDir!.create(recursive: true);
      }
      await _load();
      _ready = true;
      notifyListeners();
    } catch (e) {
      _ready = false;
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
    errorMessage = null;
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
    try {
      await _save();
    } catch (e) {
      failures.add('书库索引保存失败：$e');
    }
    if (failures.isNotEmpty) {
      errorMessage = failures.join('\n');
    }
    notifyListeners();
    return imported;
  }

  /// 删除一本书及其文件。
  Future<void> delete(WifiBook book) async {
    await _ensureReady();
    errorMessage = null;
    final file = fileFor(book);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException catch (e) {
        // 删除与存在检查之间文件可能已被外部移除；只有文件仍存在才算失败。
        if (await file.exists()) {
          errorMessage = '删除文件失败：$e';
          notifyListeners();
          rethrow;
        }
      }
    }
    _books.removeWhere((b) => b.id == book.id);
    try {
      await _save();
    } catch (e) {
      errorMessage = '书籍已删除，但书库索引保存失败：$e';
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  /// 重命名展示标题。
  Future<void> rename(WifiBook book, String newTitle) async {
    await _ensureReady();
    errorMessage = null;
    final title = newTitle.trim();
    if (title.isEmpty) return;
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index < 0) return;
    final previous = _books[index];
    _books[index] = previous.copyWithTitle(title);
    try {
      await _save();
    } catch (e) {
      _books[index] = previous;
      errorMessage = '重命名保存失败：$e';
      notifyListeners();
      rethrow;
    }
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
    if (!_ready) {
      throw StateError(errorMessage ?? '书库尚未初始化');
    }
  }

  Future<void> _importOne(File source) async {
    final dir = _booksDir!;
    final sourceType = await FileSystemEntity.type(
      source.path,
      followLinks: true,
    );
    if (sourceType != FileSystemEntityType.file) {
      throw StateError(
        sourceType == FileSystemEntityType.notFound ? '文件不存在' : '不是普通文件',
      );
    }
    final ext = p.extension(source.path).toLowerCase().replaceFirst('.', '');
    final id = _uuid.v4();
    final stored = '$id.$ext';
    final dest = File(p.join(dir.path, stored));
    int size;
    try {
      await source.copy(dest.path);
      size = await KindleDownloadCompat.fileSize(dest);
    } catch (_) {
      if (await dest.exists()) {
        try {
          await dest.delete();
        } on FileSystemException {
          // 初始化恢复流程会处理无法立即清理的孤立文件。
        }
      }
      rethrow;
    }
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

  /// 从磁盘加载书库；主元数据损坏时优先恢复备份，再扫描遗留文件。
  Future<void> _load() async {
    final meta = _metadataFile;
    if (meta == null) return;
    final backup = File('${meta.path}.bak');
    _MetadataReadResult? result;
    var needsRepair = false;
    var recoveredFromBackup = false;
    var primaryDamaged = false;

    if (await meta.exists()) {
      try {
        result = await _readMetadata(meta);
      } on Object {
        primaryDamaged = true;
        needsRepair = true;
      }
    } else if (await backup.exists()) {
      // 保存过程中进程退出可能留下备份但尚未生成新的主文件。
      primaryDamaged = true;
      needsRepair = true;
    }

    if (result == null && await backup.exists()) {
      try {
        result = await _readMetadata(backup);
        recoveredFromBackup = true;
      } on Object {
        // 主文件与备份均不可读时，后续根据 books 目录重建最小元数据。
      }
    }

    result ??= const _MetadataReadResult(<WifiBook>[], 0);
    final books = result.books.toList();
    final recoveredFiles = await _appendOrphanedBooks(books);
    if (result.invalidEntries > 0 || recoveredFiles > 0) {
      needsRepair = true;
    }

    _books
      ..clear()
      ..addAll(books);
    _books.sort((a, b) => b.importedAt.compareTo(a.importedAt));

    if (primaryDamaged) {
      errorMessage = recoveredFromBackup
          ? '检测到书库元数据损坏，已从备份恢复。'
          : '检测到书库元数据损坏，已根据现有文件重建书库。';
    } else if (result.invalidEntries > 0) {
      errorMessage = '已清理 ${result.invalidEntries} 条无效书库记录。';
    } else if (recoveredFiles > 0) {
      errorMessage = '检测到未登记的书籍文件，已恢复 $recoveredFiles 本书。';
    }

    if (needsRepair) {
      try {
        // 修复时不能用损坏的主文件覆盖仍可用的备份。
        await _save(preservePrevious: false);
      } catch (e) {
        final prefix = errorMessage == null ? '' : '${errorMessage!} ';
        errorMessage = '$prefix修复后的书库元数据保存失败：$e';
      }
    }
  }

  /// 读取并校验一个元数据文件，跳过缺失文件、危险路径与重复记录。
  Future<_MetadataReadResult> _readMetadata(File source) async {
    final raw = await source.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('书库元数据根节点必须是数组');
    }

    final dir = _booksDir!;
    final books = <WifiBook>[];
    final ids = <String>{};
    final filenames = <String>{};
    var invalidEntries = 0;
    for (final entry in decoded) {
      try {
        if (entry is! Map) throw const FormatException('书籍记录必须是对象');
        final book = WifiBook.fromJson(Map<String, dynamic>.from(entry));
        final safeFilename = p.basename(book.storedFilename);
        final extension = p
            .extension(safeFilename)
            .toLowerCase()
            .replaceFirst('.', '');
        final isSafePath =
            _isSafeId(book.id) &&
            safeFilename == book.storedFilename &&
            !book.storedFilename.contains('/') &&
            !book.storedFilename.contains('\\') &&
            safeFilename.isNotEmpty &&
            safeFilename != '.' &&
            safeFilename != '..' &&
            KindleDownloadCompat.isSupportedPath(safeFilename) &&
            book.format.toLowerCase() == extension &&
            book.byteCount >= 0;
        final isUnique =
            !ids.contains(book.id) && !filenames.contains(safeFilename);
        if (!isSafePath || !isUnique) {
          invalidEntries++;
          continue;
        }
        if (!await File(p.join(dir.path, safeFilename)).exists()) {
          invalidEntries++;
          continue;
        }
        ids.add(book.id);
        filenames.add(safeFilename);
        books.add(book);
      } on Object {
        invalidEntries++;
      }
    }
    return _MetadataReadResult(books, invalidEntries);
  }

  /// 将元数据未引用的书籍文件补回书库，尽量避免异常退出造成数据丢失。
  Future<int> _appendOrphanedBooks(List<WifiBook> books) async {
    final dir = _booksDir!;
    final knownFilenames = books.map((book) => book.storedFilename).toSet();
    final knownIds = books.map((book) => book.id).toSet();
    var recovered = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final filename = p.basename(entity.path);
      if (knownFilenames.contains(filename) ||
          !KindleDownloadCompat.isSupportedPath(filename)) {
        continue;
      }
      final stat = await entity.stat();
      final ext = p.extension(filename).toLowerCase().replaceFirst('.', '');
      final filenameId = p.basenameWithoutExtension(filename);
      final id = _isSafeId(filenameId) && !knownIds.contains(filenameId)
          ? filenameId
          : _uuid.v4();
      books.add(
        WifiBook(
          id: id,
          title: id,
          originalFilename: filename,
          storedFilename: filename,
          format: ext.toUpperCase(),
          byteCount: stat.size,
          importedAt: stat.modified,
        ),
      );
      knownFilenames.add(filename);
      knownIds.add(id);
      recovered++;
    }
    return recovered;
  }

  bool _isSafeId(String value) => _safeBookId.hasMatch(value);

  /// 将当前书库快照排队保存，避免并发修改互相覆盖元数据文件。
  Future<void> _save({bool preservePrevious = true}) {
    final data = jsonEncode(_books.map((book) => book.toJson()).toList());
    final operation = _saveQueue.then(
      (_) => _saveNow(data, preservePrevious: preservePrevious),
      onError: (_) => _saveNow(data, preservePrevious: preservePrevious),
    );
    _saveQueue = operation.catchError((_) {
      // 调用方会收到本次保存异常，队列本身继续接受后续保存任务。
    });
    return operation;
  }

  /// 先写临时文件再原子替换主文件，并保留上一份有效元数据作为恢复备份。
  Future<void> _saveNow(String data, {required bool preservePrevious}) async {
    final meta = _metadataFile;
    if (meta == null) return;
    final temp = File('${meta.path}.tmp');
    final backup = File('${meta.path}.bak');
    final backupTemp = File('${backup.path}.tmp');

    try {
      if (await temp.exists()) await temp.delete();
      await temp.writeAsString(data, flush: true);

      if (preservePrevious && await meta.exists()) {
        try {
          final previous = await _readMetadata(meta);
          if (previous.invalidEntries == 0) {
            if (await backupTemp.exists()) await backupTemp.delete();
            await backupTemp.writeAsBytes(
              await meta.readAsBytes(),
              flush: true,
            );
            await _replaceFile(backupTemp, backup);
          }
        } on Object {
          // 当前主文件不可完整校验时保留旧备份，避免扩大损坏范围。
        }
      }
      await _replaceFile(temp, meta);
    } finally {
      if (await temp.exists()) await temp.delete();
      if (await backupTemp.exists()) await backupTemp.delete();
    }
  }

  /// Windows 不保证 rename 覆盖已有文件；失败时利用现有备份执行替换。
  Future<void> _replaceFile(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      if (!Platform.isWindows || !await target.exists()) rethrow;
      await target.delete();
      await source.rename(target.path);
    }
  }
}

/// 一次元数据读取的结果，包含有效书籍及被清理的记录数。
class _MetadataReadResult {
  const _MetadataReadResult(this.books, this.invalidEntries);

  final List<WifiBook> books;
  final int invalidEntries;
}
