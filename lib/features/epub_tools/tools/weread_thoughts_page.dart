import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/file_service.dart';
import '../../../core/theme.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/base_button.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';
import '../../weread_thoughts/weread_api.dart';
import '../../weread_thoughts/weread_cache.dart';
import '../../weread_thoughts/weread_thought_operation.dart';

/// 读书想法注入页面
///
/// 从读书平台拉取热门划线和个人想法，注入到本地 EPUB 文件中。
/// 流程：输入 API Key → 选择 EPUB → 根据书名自动搜索 → 绑定书目 → 注入想法。
class WereadThoughtsPage extends StatefulWidget {
  const WereadThoughtsPage({super.key});

  @override
  State<WereadThoughtsPage> createState() => _WereadThoughtsPageState();
}

class _WereadThoughtsPageState extends State<WereadThoughtsPage> {
  /// 读书平台 API 客户端
  final WereadApi _api = WereadApi();

  /// 搜索关键词控制器
  final TextEditingController _searchController = TextEditingController();

  /// 日志控制器
  final OutputLogController _logController = OutputLogController();

  /// 是否已登录
  bool _isLoggedIn = false;

  /// 是否正在获取二维码
  bool _qrLoading = false;

  /// QR 码 URL(扫码确认链接)
  String? _qrUrl;

  /// 从 QR URL 提取的 uid
  String? _loginUid;

  /// 是否正在轮询登录状态
  bool _polling = false;

  /// 当前绑定的书目
  WereadBook? _boundBook;

  /// 搜索结果列表
  List<WereadBook> _searchResults = [];

  /// 是否正在搜索
  bool _searching = false;

  /// 输入 EPUB 文件路径
  String _epubPath = '';

  /// 输出 EPUB 文件路径
  String _outputPath = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 当前进度文本
  String _progressText = '';

  /// 缓存的书目列表(用于离线重注)
  List<CacheData> _cachedBooks = [];

  /// 当前绑定书目的缓存数据
  CacheData? _cacheData;

  /// 是否离线模式(使用缓存数据,不走网络)
  bool _offlineMode = false;

  /// note.png 图标字节(用于弹窗标记)
  Uint8List? _notePngBytes;

  @override
  void initState() {
    super.initState();
    _loadApiState();
    _loadCachedBooks();
    _loadNotePng();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _logController.dispose();
    super.dispose();
  }

  /// 加载 note.png 图标资源
  Future<void> _loadNotePng() async {
    try {
      final bytes = await rootBundle.load('assets/note.png');
      if (mounted) {
        setState(() {
          _notePngBytes = bytes.buffer.asUint8List();
        });
      }
    } catch (e) {
      debugPrint('加载 note.png 失败: $e');
    }
  }

  /// 从本地存储加载 API 状态(Cookie 和绑定的书目)
  Future<void> _loadApiState() async {
    await _api.load();
    if (mounted) {
      setState(() {
        _isLoggedIn = _api.isLoggedIn;
      });
    }
  }

  /// 加载所有缓存书目列表
  ///
  /// 扫描缓存目录,列出所有已缓存的书目供离线重注使用。
  Future<void> _loadCachedBooks() async {
    try {
      final dir = await _getCacheDir();
      final directory = Directory(dir);
      if (!await directory.exists()) return;

      final books = <CacheData>[];
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final bookId = p.basenameWithoutExtension(entity.path);
          final cache = await WereadCache.load(bookId);
          if (cache != null && cache.chapters.isNotEmpty) {
            books.add(cache);
          }
        }
      }

      // 按同步时间倒序排列
      books.sort((a, b) {
        final aTime = a.syncedAt ?? DateTime(2000);
        final bTime = b.syncedAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() => _cachedBooks = books);
      }
    } catch (_) {}
  }

  /// 获取缓存目录路径
  Future<String> _getCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'weread_cache');
  }

  /// 加载绑定书目的缓存数据
  Future<void> _loadCacheForBook(String bookId) async {
    final cache = await WereadCache.load(bookId);
    if (mounted) {
      setState(() => _cacheData = cache);
    }
  }

  /// 选择缓存书目进行离线重注
  ///
  /// 设置绑定书目为缓存数据,用户只需选择 EPUB 文件即可重注。
  Future<void> _selectCachedBook(CacheData cache) async {
    setState(() {
      _boundBook = WereadBook(
        bookId: cache.bookId,
        title: cache.bookTitle,
        author: cache.bookAuthor,
      );
      _cacheData = cache;
      _offlineMode = true;
      _searchResults = [];
      _searchController.text = cache.bookTitle;
    });
    if (!mounted) return;
    context.read<ToastProvider>().showSuccess(
      '已选择缓存书目：${cache.bookTitle}（${cache.syncedCount}/${cache.totalChapters} 章）',
    );
  }

  /// 清除某本书的缓存
  Future<void> _clearCache(String bookId) async {
    await WereadCache.clear(bookId);
    await _loadCachedBooks();
    if (_cacheData?.bookId == bookId) {
      setState(() => _cacheData = null);
    }
    if (!mounted) return;
    context.read<ToastProvider>().showSuccess('已清除缓存');
  }

  /// 清除登录状态
  Future<void> _clearLogin() async {
    await _api.clear();
    setState(() {
      _isLoggedIn = false;
      _boundBook = null;
      _searchResults = [];
      _searchController.clear();
      _qrUrl = null;
      _loginUid = null;
    });
    if (!mounted) return;
    context.read<ToastProvider>().showSuccess('已退出登录');
  }

  /// 开始 QR 扫码登录流程
  ///
  /// 参考 pickthought auth.lua:
  /// 1. 获取登录 UID 和 QR 码 URL
  /// 2. 显示 QR 码供用户扫码
  /// 3. 轮询登录状态直到成功或超时
  Future<void> _startQrLogin() async {
    if (_qrLoading || _polling) return;

    setState(() {
      _qrLoading = true;
      _qrUrl = null;
      _loginUid = null;
    });

    try {
      final url = await _api.getLoginQrUrl();
      final uid = WereadApi.extractUidFromQrUrl(url);
      if (uid == null || uid.isEmpty) {
        throw Exception('QR URL 中缺少 uid');
      }
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _loginUid = uid;
        _qrLoading = false;
        _polling = true;
      });
      // 开始轮询
      _pollLoginLoop(uid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrLoading = false;
        _polling = false;
      });
      context.read<ToastProvider>().showError('获取二维码失败: $e');
    }
  }

  /// 轮询登录状态(参考 pickthought auth.lua _schedule)
  ///
  /// 每 1.5 秒轮询一次,最长 5 分钟超时。
  Future<void> _pollLoginLoop(String uid) async {
    final maxAttempts = 200; // ~5 分钟
    for (var i = 0; i < maxAttempts; i++) {
      if (!_polling || !mounted) return;

      await Future.delayed(const Duration(milliseconds: 1500));
      if (!_polling || !mounted) return;

      try {
        final result = await _api.pollLoginStatus(uid);

        // 登录成功
        if (result['succeed'] == true) {
          if (!mounted) return;
          setState(() => _polling = false);
          // 完成登录:获取 Cookie + API Key + 用户名
          try {
            final userName = await _api.finishLogin(result);
            if (!mounted) return;
            setState(() {
              _isLoggedIn = true;
              _qrUrl = null;
              _loginUid = null;
            });
            context.read<ToastProvider>().showSuccess('登录成功: $userName');
          } catch (e) {
            if (!mounted) return;
            context.read<ToastProvider>().showError('登录完成失败: $e');
          }
          return;
        }

        // 检查状态码
        final code = result['logicCode']?.toString() ?? '';
        if (code == 'LOGIN_TIMEOUT' || code == 'OTP_EXPIRED') {
          if (!mounted) return;
          setState(() {
            _polling = false;
            _qrUrl = null;
            _loginUid = null;
          });
          context.read<ToastProvider>().showWarning('二维码已过期,请重新获取');
          return;
        }
        // NEED_OTP / OTP_NOT_MATCH 暂不支持,继续轮询
        // 其他状态:继续轮询
      } catch (e) {
        // 网络异常:继续重试
        debugPrint('[QR Login] poll error: $e');
      }
    }

    // 超时
    if (!mounted) return;
    setState(() {
      _polling = false;
      _qrUrl = null;
      _loginUid = null;
    });
    context.read<ToastProvider>().showWarning('登录超时,请重试');
  }

  /// 取消二维码登录
  void _cancelQrLogin() {
    setState(() {
      _polling = false;
      _qrUrl = null;
      _loginUid = null;
    });
  }

  /// 从 EPUB 文件中提取书名
  ///
  /// 读取 EPUB 的 OPF 元数据，提取 dc:title 作为搜索关键词。
  /// 若提取失败则降级使用文件名（不含扩展名）。
  /// 清理搜索关键词
  ///
  /// 去掉括号内的副标题/宣传语,只保留核心书名。
  /// 例如: "低智商犯罪（王骁、田曦薇主演同名电视剧原著）" → "低智商犯罪"
  String _cleanSearchKeyword(String title) {
    var result = title.trim();
    // 去掉中文括号内的内容
    result = result.replaceAll(RegExp(r'（[^）]*）'), '');
    // 去掉英文括号内的内容
    result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
    // 去掉方括号内的内容
    result = result.replaceAll(RegExp(r'【[^】]*】'), '');
    result = result.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    // 去掉常见分隔符后的内容
    result = result.split(RegExp(r'[:：_-—]')).first.trim();
    // 如果清理后为空,回退到原标题
    if (result.isEmpty) result = title.trim();
    return result;
  }

  Future<String> _extractEpubTitle(String epubPath) async {
    try {
      final bytes = await File(epubPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 找到 container.xml 获取 OPF 路径
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) return p.basenameWithoutExtension(epubPath);
      final containerXml =
          utf8.decode(containerFile.content as List<int>, allowMalformed: true);
      final opfPathMatch =
          RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
      if (opfPathMatch == null) return p.basenameWithoutExtension(epubPath);
      final opfPath = opfPathMatch.group(1)!;

      // 读取 OPF
      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) return p.basenameWithoutExtension(epubPath);
      final opfContent =
          utf8.decode(opfFile.content as List<int>, allowMalformed: true);

      // 提取 dc:title（优先带 title-type=main 的，否则取第一个）
      final titlePattern = RegExp(
        r'<(?:dc:)?title[^>]*>(.*?)</(?:dc:)?title>',
        dotAll: true,
      );
      final matches = titlePattern.allMatches(opfContent);
      if (matches.isEmpty) {
        // 降级：EPUB2 风格 <meta name="title" content="...">
        final metaPattern = RegExp(
          r'<meta\s+name="title"\s+content="([^"]*)"',
        );
        final metaMatch = metaPattern.firstMatch(opfContent);
        if (metaMatch != null) return metaMatch.group(1)!.trim();
        return p.basenameWithoutExtension(epubPath);
      }

      // 取第一个非空 title
      for (final match in matches) {
        final title = match.group(1)!.trim();
        if (title.isNotEmpty) return title;
      }
      return p.basenameWithoutExtension(epubPath);
    } catch (_) {
      return p.basenameWithoutExtension(epubPath);
    }
  }

  /// 选择 EPUB 输入文件后自动搜索
  ///
  /// 提取 EPUB 元数据中的书名，自动调用搜索 API。
  /// 离线模式下跳过自动搜索。
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _outputPath = '';
    _boundBook = null;
    _searchResults = [];
    _searchController.clear();
    await _autoFillOutputPath();

    // 离线模式下不需要搜索
    if (_offlineMode) {
      // 恢复绑定信息
      if (_cacheData != null) {
        setState(() {
          _boundBook = WereadBook(
            bookId: _cacheData!.bookId,
            title: _cacheData!.bookTitle,
            author: _cacheData!.bookAuthor,
          );
        });
      }
      if (mounted) setState(() {});
      return;
    }

    if (!_isLoggedIn) {
      if (mounted) setState(() {});
      return;
    }

    // 提取书名并自动搜索
    final title = await _extractEpubTitle(_epubPath);
    // 清理标题:去掉括号内的副标题/宣传语,只用核心书名搜索
    final cleanTitle = _cleanSearchKeyword(title);
    _searchController.text = cleanTitle;
    if (mounted) setState(() {});
    await _search();
  }

  /// 自动填充输出路径
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty) return;
    final base = p.basenameWithoutExtension(_epubPath);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: '${base}_weread.epub',
    );
  }

  /// 手动选择输出文件路径
  Future<void> _pickOutput() async {
    final base = _epubPath.isNotEmpty
        ? p.basenameWithoutExtension(_epubPath)
        : 'output';
    final path = await FileService.saveFile(
      defaultFileName: '${base}_weread.epub',
      initialDirectory: _epubPath.isNotEmpty ? p.dirname(_epubPath) : null,
    );
    if (path == null) return;
    setState(() => _outputPath = path);
  }

  /// 搜索书目
  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      context.read<ToastProvider>().showWarning('请输入书名或关键词');
      return;
    }
    if (!_isLoggedIn) {
      context.read<ToastProvider>().showWarning('请先登录');
      return;
    }

    setState(() => _searching = true);
    _logController.append('搜索关键词：「$keyword」');
    try {
      final results = await _api.search(keyword, onDebug: (raw) {
        _logController.append('API 原始响应：$raw');
      });
      setState(() {
        _searchResults = results;
      });
      if (!mounted) return;
      if (results.isEmpty) {
        _logController.append('搜索结果：未找到匹配书目');
        context.read<ToastProvider>().showInfo('未找到匹配书目');
      } else {
        _logController.append('搜索结果：找到 ${results.length} 本');
        for (final book in results) {
          _logController.append('  - ${book.title} · ${book.author} (ID: ${book.bookId})');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _logController.append('搜索失败：$e');
      context.read<ToastProvider>().showError('搜索失败：$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// 绑定选中的书目
  Future<void> _bindBook(WereadBook book) async {
    await _api.saveBook(book);
    setState(() {
      _boundBook = book;
      _searchResults = [];
      _offlineMode = false;
    });
    // 加载该书目的缓存数据
    await _loadCacheForBook(book.bookId);
    if (!mounted) return;
    context.read<ToastProvider>().showSuccess('已绑定：${book.title}');
  }

  /// 解绑当前书目(保留登录状态)
  Future<void> _unbindBook() async {
    setState(() {
      _boundBook = null;
      _cacheData = null;
      _offlineMode = false;
    });
  }

  /// 将进度回调写入日志
  void _logProgress(String phase, int current, int total, String text) {
    final progress = total > 0 ? '($current/$total)' : '';
    _logController.append('PROGRESS: [$phase] $text $progress');
  }

  /// 执行完整同步流程
  ///
  /// 通过 SKILL API 拉取热门划线和个人想法,注入到 EPUB 中。
  /// 完成后自动保存缓存,方便离线重注。
  Future<void> _execute() async {
    if (_offlineMode) {
      await _executeOffline();
      return;
    }

    if (!_isLoggedIn) {
      context.read<ToastProvider>().showWarning('请先登录');
      return;
    }
    if (_boundBook == null) {
      context.read<ToastProvider>().showWarning('请先搜索并绑定书目');
      return;
    }
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() {
      _loading = true;
      _progressText = '准备同步...';
    });
    _logController.clear();
    _logController.append('PROGRESS: 开始同步读书想法...');
    _logController.append('绑定书目：${_boundBook!.title} (${_boundBook!.bookId})');
    _logController.append('输入文件：$_epubPath');
    _logController.append('输出文件：$_outputPath');

    try {
      // 1. 拉取数据
      setState(() => _progressText = '正在拉取数据...');
      _logController.append('PROGRESS: 拉取章节列表、热门划线与个人想法...');

      final fetchResult = await _api.fetchBookData(
        _boundBook!.bookId,
        onProgress: _logProgress,
      );

      final allChapters = fetchResult.chapters;

      final totalUnderlines = allChapters.fold<int>(
        0,
        (sum, ch) => sum + ch.underlines.length,
      );
      final totalThoughts = allChapters.fold<int>(
        0,
        (sum, ch) => sum + ch.reviewMap.values.fold<int>(
          0,
          (s, list) => s + list.length,
        ),
      );

      _logController.append(
        'PROGRESS: 拉取完成 - ${allChapters.length}/${fetchResult.totalChapters} 章有数据, '
        '$totalUnderlines 条划线, $totalThoughts 条想法',
      );

      // 2. 保存缓存
      await WereadCache.save(
        bookId: _boundBook!.bookId,
        bookTitle: _boundBook!.title,
        bookAuthor: _boundBook!.author,
        totalChapters: fetchResult.totalChapters,
        chapters: allChapters,
      );
      await _loadCachedBooks();

      // 3. 注入想法到 EPUB
      setState(() => _progressText = '正在注入想法到 EPUB...');
      _logController.append('PROGRESS: 开始注入想法到 EPUB...');

      if (_notePngBytes == null) {
        throw Exception('note.png 资源加载失败,请重启应用');
      }

      final result = await WereadThoughtOperation.execute(
        epubPath: _epubPath,
        outputPath: _outputPath,
        chapters: allChapters,
        notePngBytes: _notePngBytes!,
        onProgress: _logProgress,
      );

      _logController.appendLines(
        result.split('\n').where((l) => l.trim().isNotEmpty),
      );

      if (result.contains('错误')) {
        if (mounted) {
          context.read<ToastProvider>().showError('同步失败，请查看日志');
        }
      } else {
        if (mounted) {
          context.read<ToastProvider>().showSuccess(
            '想法注入完成，已保存到 $_outputPath',
          );
        }
        await _copyToPublicDownload();

        // 输出完成后清除书目绑定和搜索结果(缓存保留)
        if (mounted) {
          await _unbindBook();
          setState(() {
            _searchResults = [];
            _searchController.clear();
          });
        }
      }
    } catch (e) {
      _logController.append('ERROR: 同步失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('同步失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progressText = '';
        });
      }
    }
  }

  /// 离线重注:使用缓存数据重新注入,零网络请求
  ///
  /// 适用于换了本地书版本、还原后想重打等场景。
  /// 要求已有完整或部分缓存,无需登录。
  Future<void> _executeOffline() async {
    if (_cacheData == null || _cacheData!.chapters.isEmpty) {
      context.read<ToastProvider>().showWarning('无可用缓存数据');
      return;
    }
    if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() {
      _loading = true;
      _progressText = '离线重注中...';
    });
    _logController.clear();
    _logController.append('PROGRESS: 离线重注(使用缓存数据,零网络)...');
    _logController.append('缓存书目：${_cacheData!.bookTitle} (${_cacheData!.bookId})');
    _logController.append(
      '缓存章节：${_cacheData!.syncedCount}/${_cacheData!.totalChapters} 章',
    );
    if (_cacheData!.syncedAt != null) {
      _logController.append('缓存时间：${_cacheData!.syncedAt}');
    }
    _logController.append('输入文件：$_epubPath');
    _logController.append('输出文件：$_outputPath');

    try {
      // 直接使用缓存章节数据
      final filteredChapters = _cacheData!.chapters;

      final totalUnderlines = filteredChapters.fold<int>(
        0,
        (sum, ch) => sum + ch.underlines.length,
      );
      final totalThoughts = filteredChapters.fold<int>(
        0,
        (sum, ch) => sum + ch.reviewMap.values.fold<int>(
          0,
          (s, list) => s + list.length,
        ),
      );
      _logController.append(
        'PROGRESS: 缓存数据 - ${filteredChapters.length} 章, '
        '$totalUnderlines 条划线, $totalThoughts 条想法',
      );

      setState(() => _progressText = '正在注入想法到 EPUB...');
      _logController.append('PROGRESS: 开始注入想法到 EPUB...');

      if (_notePngBytes == null) {
        throw Exception('note.png 资源加载失败,请重启应用');
      }

      final result = await WereadThoughtOperation.execute(
        epubPath: _epubPath,
        outputPath: _outputPath,
        chapters: filteredChapters,
        notePngBytes: _notePngBytes!,
        onProgress: _logProgress,
      );

      _logController.appendLines(
        result.split('\n').where((l) => l.trim().isNotEmpty),
      );

      if (result.contains('错误')) {
        if (mounted) {
          context.read<ToastProvider>().showError('重注失败，请查看日志');
        }
      } else {
        if (mounted) {
          context.read<ToastProvider>().showSuccess(
            '离线重注完成，已保存到 $_outputPath',
          );
        }
        await _copyToPublicDownload();

        // 重注完成后清除书目绑定(缓存保留)
        if (mounted) {
          setState(() {
            _boundBook = null;
            _offlineMode = false;
            _searchController.clear();
          });
        }
      }
    } catch (e) {
      _logController.append('ERROR: 重注失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('重注失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progressText = '';
        });
      }
    }
  }

  /// 把生成的 EPUB 复制到公共 Download/books/ 目录
  ///
  /// 仅 Android 生效；大文件（>10MB）使用流式复制，否则直接写入字节。
  Future<void> _copyToPublicDownload() async {
    if (_outputPath.isEmpty) return;
    if (!Platform.isAndroid) return;
    if (!await File(_outputPath).exists()) return;
    const streamThreshold = 10 * 1024 * 1024;
    final fileSize = await File(_outputPath).length();
    final useStream = fileSize > streamThreshold;
    try {
      final filename = p.basename(_outputPath);
      String publicPath;
      if (useStream) {
        _logController.append('PROGRESS: 大文件，使用流式复制...');
        publicPath = await FileService.copyFileToPublicDownload(
          sourcePath: _outputPath,
          filename: filename,
        );
      } else {
        final bytes = await File(_outputPath).readAsBytes();
        publicPath = await FileService.writeToPublicDownload(
          filename: filename,
          bytes: bytes,
        );
      }
      _logController.append('PROGRESS: 已复制到公共 Download: $publicPath');
      try {
        await File(_outputPath).delete();
      } catch (_) {}
      _outputPath = publicPath;
    } catch (e) {
      _logController.append('WARN: 复制到公共 Download 失败：$e');
    }
  }

  /// 显示功能说明
  void _showFeatureHelp() {
    showToolHelpDialog(
      context,
      title: '读书想法注入说明',
      sections: const [
        ToolHelpSection(
          title: '功能简介',
          content:
              '从读书平台拉取一本书的热门划线和公开想法，'
              '通过引文匹配将想法注入到本地 EPUB 的对应位置。'
              '注入后阅读 EPUB 时，划线位置会显示一个图标，点击/悬停即可查看想法。',
        ),
        ToolHelpSection(
          title: '使用流程',
          content:
              '1. 扫码登录读书账号\n'
              '2. 选择本地 EPUB 文件\n'
              '3. 程序自动根据书名搜索书目\n'
              '4. 在搜索结果中选择对应书目\n'
              '5. 点击执行，等待拉取和注入完成\n'
              '6. 完成后自动清除搜索结果，方便处理下一本',
        ),
        ToolHelpSection(
          title: '离线重注',
          content:
              '同步完成后数据自动缓存到本地。\n'
              '之后换了本地 EPUB 版本或还原后想重新注入时，\n'
              '在页面顶部「缓存书目」中选择对应书目，选择新 EPUB 文件，\n'
              '点击「离线重注」即可零网络重跑映射和注入。',
        ),
        ToolHelpSection(
          title: '匹配原理',
          content:
              '程序使用引文投票算法：取每章的热门划线前缀，在本地 EPUB 的各 HTML 文件中搜索。'
              '命中最多的文件即为该章对应的本地文件。'
              '如果引文因精校修改无法匹配，会降级使用章节标题兜底。',
        ),
        ToolHelpSection(
          title: '关于未匹配章节',
          content:
              '同步结果中出现「未匹配」属于正常现象。\n'
              '封面、版权页、附录等非正文章节不含可定位的划线引文，无法匹配到本地 EPUB 文件。\n'
              '只要正文章节均已成功注入，即可正常使用。',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 页头
          buildToolHeader(
            context,
            icon: Icons.psychology_outlined,
            title: '读书想法',
            subtitle: '拉取热门划线想法注入到本地 EPUB',
          ),

          // 内容区
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 80),
              children: [
                // === 登录区 ===
                _buildLoginSection(),

                // === 已登录/离线模式后才显示以下区域 ===
                if (_isLoggedIn || _offlineMode) ...[
                  const SizedBox(height: 10),

                  // === EPUB 文件区 ===
                  buildSectionLabel(context, Icons.folder_open, 'EPUB 文件'),
                  const SizedBox(height: 6),
                  buildFilePickerRow(
                    context,
                    icon: Icons.book_outlined,
                    label: 'EPUB 文件',
                    value: _epubPath,
                    hint: '点击选择本地 EPUB 文件',
                    onTap: _loading ? () {} : _pickEpub,
                    isComplete: _epubPath.isNotEmpty,
                  ),

                  // === 数据源选择 ===
                  const SizedBox(height: 10),
                  _buildDataSourceSelector(),

                  // === 搜索绑定区(选完 EPUB 后自动出现,离线模式跳过)===
                  if (_isLoggedIn && _epubPath.isNotEmpty && !_offlineMode) ...[
                    const SizedBox(height: 10),
                    _buildSearchSection(),
                  ],

                  // === 缓存状态(离线模式下显示)===
                  if (_offlineMode && _cacheData != null) ...[
                    const SizedBox(height: 10),
                    _buildCacheStatusCard(),
                  ],

                  // === 输出路径 ===
                  if (_boundBook != null) ...[
                    const SizedBox(height: 10),
                    buildSectionLabel(context, Icons.save_outlined, '输出路径'),
                    const SizedBox(height: 6),
                    buildFilePickerRow(
                      context,
                      icon: Icons.save_outlined,
                      label: '输出 EPUB',
                      value: _outputPath,
                      hint: '点击选择输出文件位置',
                      onTap: _loading ? () {} : _pickOutput,
                      isComplete: _outputPath.isNotEmpty,
                    ),

                    const SizedBox(height: 8),
                    buildHelpInfoBar(
                      context,
                      text: _offlineMode
                          ? '离线重注模式:使用缓存数据,无需网络。选择输出路径后点击重注。'
                          : '程序会自动根据 EPUB 书名搜索书目。选择对应书目后点击执行,完成后自动清除搜索结果。',
                      onTap: _showFeatureHelp,
                    ),
                  ],
                ],

                // 进度文本
                if (_loading && _progressText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildProgressIndicator(),
                ],

                // 日志面板
                const SizedBox(height: 10),
                buildLogPanel(
                  context,
                  OutputLog(
                    key: const ValueKey('weread-output-log'),
                    controller: _logController,
                  ),
                ),
              ],
            ),
          ),

          // 底部操作栏
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading ? () {} : _execute,
            label: _offlineMode ? '离线重注' : '同步想法到 EPUB',
            icon: _offlineMode
                ? Icons.cached
                : Icons.cloud_download_outlined,
          ),
        ],
      ),
    );
  }

  /// 构建数据源选择器
  Widget _buildDataSourceSelector() {
    return const SizedBox.shrink();
  }

  /// 构建登录区域(扫码登录)
  Widget _buildLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionLabel(context, Icons.login, '读书登录'),
        const SizedBox(height: 6),

        // 登录状态指示(透明背景,仅边框)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isLoggedIn
                  ? context.themeSuccess.withValues(alpha: 0.3)
                  : context.themeDividerLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isLoggedIn ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: _isLoggedIn
                    ? context.themeSuccess
                    : context.themeTextTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isLoggedIn
                      ? '已登录: ${_api.userName}'
                      : '未登录',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isLoggedIn
                        ? context.themeSuccess
                        : context.themeTextTertiary,
                  ),
                ),
              ),
              if (_isLoggedIn)
                BaseButton(
                  label: '退出',
                  size: BaseButtonSize.sm,
                  variant: BaseButtonVariant.danger,
                  onPressed: _loading ? null : _clearLogin,
                ),
            ],
          ),
        ),

        // 未登录时显示扫码登录
        if (!_isLoggedIn) ...[
          const SizedBox(height: 6),

          // QR 码区域
          if (_qrLoading) ...[
            // 正在获取二维码
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '正在获取二维码...',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (_qrUrl != null && _polling) ...[
            // 显示 QR 码 + 等待扫码
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: context.themeDividerLight),
              ),
              child: Column(
                children: [
                  // QR 码
                  QrImageView(
                    data: _qrUrl!,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '使用读书 App 扫描二维码登录',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '等待扫码确认...',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeTextTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BaseButton(
                    label: '取消',
                    size: BaseButtonSize.sm,
                    variant: BaseButtonVariant.secondary,
                    onPressed: _cancelQrLogin,
                  ),
                ],
              ),
            ),
          ] else ...[
            // 初始状态:显示登录按钮
            Row(
              children: [
                Expanded(
                  child: BaseButton(
                    label: '扫码登录',
                    icon: Icons.qr_code_scanner,
                    size: BaseButtonSize.sm,
                    onPressed: _loading ? null : _startQrLogin,
                  ),
                ),
                const SizedBox(width: 6),
                BaseButton(
                  label: '使用说明',
                  icon: Icons.help_outline,
                  size: BaseButtonSize.sm,
                  variant: BaseButtonVariant.secondary,
                  onPressed: _showFeatureHelp,
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  /// 构建搜索绑定区域
  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionLabel(context, Icons.search, '搜索绑定书目'),
        const SizedBox(height: 6),

        // 已绑定的书目(透明背景,仅边框)
        if (_boundBook != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: context.themeAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bookmark,
                  size: 16,
                  color: context.themeAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _boundBook!.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.themeTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_boundBook!.author.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          _boundBook!.author,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.themeTextTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _loading ? null : _unbindBook,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 24),
                  ),
                  child: Text(
                    '解绑',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // 搜索框
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _search(),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.themeTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入书名或作者搜索',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: context.themeTextTertiary,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: context.themeDividerLight,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: context.themeDividerLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: context.themeDivider,
                          width: 1.5,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 42,
                child: BaseButton(
                  label: '搜索',
                  size: BaseButtonSize.sm,
                  loading: _searching,
                  onPressed: _searching || _loading ? null : _search,
                ),
              ),
            ],
          ),

          // 搜索结果
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '找到 ${_searchResults.length} 个结果',
              style: TextStyle(
                fontSize: 11,
                color: context.themeTextTertiary,
              ),
            ),
            const SizedBox(height: 3),
            ..._searchResults.map((book) => _buildBookResultTile(book)),
          ],
        ],
      ],
    );
  }

  /// 构建搜索结果条目
  Widget _buildBookResultTile(WereadBook book) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        onTap: _loading ? null : () => _bindBook(book),
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: context.themeDividerLight),
          ),
          child: Row(
            children: [
              // 封面缩略图
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: SizedBox(
                  width: 28,
                  height: 40,
                  child: book.cover.isNotEmpty
                      ? Image.network(
                          book.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                        )
                      : _buildCoverPlaceholder(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.themeTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (book.author.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        book.author,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeTextTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.link,
                size: 14,
                color: context.themeAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建封面占位图(无封面或加载失败时使用)
  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.themeDividerLight),
      ),
      child: Icon(
        Icons.book_outlined,
        size: 16,
        color: context.themeTextTertiary,
      ),
    );
  }

  /// 构建缓存书目列表区域
  ///
  /// 显示所有已缓存的书目,用户可选择进行离线重注。
  Widget _buildCacheSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cached, size: 16, color: context.themeTextTertiary),
            const SizedBox(width: 6),
            Text(
              '缓存书目',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.themeTextTertiary,
              ),
            ),
            const Spacer(),
            Text(
              '${_cachedBooks.length} 本',
              style: TextStyle(
                fontSize: 12,
                color: context.themeTextTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._cachedBooks.map((cache) => _buildCacheTile(cache)),
      ],
    );
  }

  /// 构建单个缓存书目条目
  Widget _buildCacheTile(CacheData cache) {
    final isComplete = cache.isComplete;
    final isSelected = _cacheData?.bookId == cache.bookId && _offlineMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: _loading ? null : () => _selectCachedBook(cache),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? context.themeAccent.withValues(alpha: 0.06)
                : context.themeCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? context.themeAccent.withValues(alpha: 0.2)
                  : context.themeDividerLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle : Icons.sync,
                size: 18,
                color: isComplete
                    ? context.themeSuccess
                    : context.themeAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cache.bookTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.themeTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cache.syncedCount}/${cache.totalChapters} 章'
                      '${cache.remainingCount > 0 ? ' · 剩余 ${cache.remainingCount}' : ' · 已完成'}'
                      '${cache.syncedAt != null ? ' · ${_formatDate(cache.syncedAt!)}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // 清除缓存按钮
              IconButton(
                onPressed: _loading
                    ? null
                    : () => _clearCache(cache.bookId),
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: context.themeTextTertiary,
                ),
                tooltip: '清除缓存',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: context.themeTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化日期为简短显示
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }

  /// 构建缓存状态卡片(离线模式下显示)
  Widget _buildCacheStatusCard() {
    final cache = _cacheData!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: context.themeAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cached, size: 16, color: context.themeAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cache.bookTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  '缓存 ${cache.syncedCount}/${cache.totalChapters} 章'
                  '${cache.isComplete ? ' · 完整' : ' · 部分(剩余 ${cache.remainingCount} 章需在线)'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _unbindBook,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 24),
            ),
            child: Text(
              '取消',
              style: TextStyle(
                fontSize: 11,
                color: context.themeTextTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建进度指示器
  Widget _buildProgressIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: context.themeAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.themeAccent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _progressText,
              style: TextStyle(
                fontSize: 12,
                color: context.themeAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
