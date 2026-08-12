import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'weread_api.dart';

/// 读书想法缓存数据
///
/// 存储某本书已拉取的章节数据,支持增量同步和离线重注。
/// 缓存文件为 JSON 格式,存储在应用文档目录下。
class WereadCache {
  WereadCache._();

  /// 获取缓存目录路径
  static Future<String> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = p.join(dir.path, 'weread_cache');
    if (!await Directory(cachePath).exists()) {
      await Directory(cachePath).create(recursive: true);
    }
    return cachePath;
  }

  /// 获取某本书的缓存文件路径
  static Future<String> _cacheFile(String bookId) async {
    final dir = await _cacheDir();
    return p.join(dir, '$bookId.json');
  }

  /// 保存章节数据到缓存
  ///
  /// [bookId] 书 ID
  /// [bookTitle] 书名
  /// [bookAuthor] 作者
  /// [totalChapters] 远端总章节数
  /// [chapters] 已拉取的章节数据(全量,包含之前的缓存)
  /// [bookReviews] 整本书评
  static Future<void> save({
    required String bookId,
    required String bookTitle,
    required String bookAuthor,
    required int totalChapters,
    required List<ChapterData> chapters,
    List<WereadReview> bookReviews = const [],
  }) async {
    final filePath = await _cacheFile(bookId);
    final json = {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'bookAuthor': bookAuthor,
      'totalChapters': totalChapters,
      'syncedChapterUids': chapters.map((c) => c.chapterUid).toList(),
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'bookReviews': bookReviews.map((r) => r.toJson()).toList(),
      'syncedAt': DateTime.now().toIso8601String(),
    };
    final file = File(filePath);
    await file.writeAsString(jsonEncode(json));
  }

  /// 加载某本书的缓存数据
  ///
  /// 返回 null 表示无缓存。
  static Future<CacheData?> load(String bookId) async {
    final filePath = await _cacheFile(bookId);
    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final chapters = (json['chapters'] as List? ?? [])
          .map((e) => ChapterData.fromJson(e as Map<String, dynamic>))
          .toList();
      return CacheData(
        bookId: json['bookId']?.toString() ?? '',
        bookTitle: json['bookTitle']?.toString() ?? '',
        bookAuthor: json['bookAuthor']?.toString() ?? '',
        totalChapters: json['totalChapters'] as int? ?? 0,
        syncedChapterUids:
            (json['syncedChapterUids'] as List? ?? []).map((e) => e.toString()).toSet(),
        chapters: chapters,
        bookReviews: (json['bookReviews'] as List? ?? [])
            .map((e) => WereadReview.fromJson(e as Map<String, dynamic>))
            .toList(),
        syncedAt: DateTime.tryParse(json['syncedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// 是否存在缓存
  static Future<bool> hasCache(String bookId) async {
    final filePath = await _cacheFile(bookId);
    return File(filePath).exists();
  }

  /// 清除某本书的缓存
  static Future<void> clear(String bookId) async {
    final filePath = await _cacheFile(bookId);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 合并旧缓存和新拉取的数据
  ///
  /// 以 chapterUid 为键去重,新数据覆盖旧数据(同 chapterUid)。
  /// 保持章节顺序:先旧缓存中未被覆盖的,再新数据。
  static List<ChapterData> merge(
    List<ChapterData> cached,
    List<ChapterData> newChapters,
  ) {
    final newUids = newChapters.map((c) => c.chapterUid).toSet();
    final kept = cached.where((c) => !newUids.contains(c.chapterUid)).toList();
    return [...kept, ...newChapters];
  }
}

/// 缓存数据
class CacheData {
  final String bookId;
  final String bookTitle;
  final String bookAuthor;
  final int totalChapters;
  final Set<String> syncedChapterUids;
  final List<ChapterData> chapters;
  final List<WereadReview> bookReviews;
  final DateTime? syncedAt;

  CacheData({
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.totalChapters,
    required this.syncedChapterUids,
    required this.chapters,
    this.bookReviews = const [],
    this.syncedAt,
  });

  /// 已同步章节数
  int get syncedCount => syncedChapterUids.length;

  /// 剩余未同步章节数
  int get remainingCount => totalChapters - syncedCount;

  /// 是否全部同步完成
  bool get isComplete => syncedCount >= totalChapters && totalChapters > 0;
}
