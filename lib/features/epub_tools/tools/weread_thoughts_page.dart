import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/file_service.dart';
import '../../../core/theme.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/base_button.dart';
import '../../../shared/widgets/output_log.dart';
import '../epub_tool_widgets.dart';
import '../../weread_thoughts/weread_api.dart';
import '../../weread_thoughts/weread_guest_captcha.dart';
import '../../weread_thoughts/weread_guest_signature.dart';
import '../../weread_thoughts/weread_thought_operation.dart';

/// 读书想法注入页面
///
/// 从读书平台拉取热门划线、公开想法(段评/章评/书评),注入到本地 EPUB 文件中。
/// 支持两种登录:扫码登录(Web Cookie + API Key)或游客登录(APP 直连,
/// 无需微信账号;可能触发腾讯验证码,由系统浏览器完成)。
/// 流程:登录 → 选择 EPUB → 根据书名自动搜索 → 绑定书目 → 注入想法。
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

  /// 是否正在轮询登录状态
  bool _polling = false;

  /// 是否正在执行游客登录
  bool _guestLoading = false;

  /// 是否正在等待浏览器完成安全验证(游客登录)
  bool _guestCaptchaWaiting = false;

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

  /// note.png 图标字节(用于弹窗标记)
  Uint8List? _notePngBytes;

  @override
  void initState() {
    super.initState();
    _loadApiState();
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

  /// 清除登录状态
  Future<void> _clearLogin() async {
    await _api.clear();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _boundBook = null;
      _searchResults = [];
      _searchController.clear();
      _qrUrl = null;
    });
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
    });
    context.read<ToastProvider>().showWarning('登录超时,请重试');
  }

  /// 取消二维码登录
  void _cancelQrLogin() {
    setState(() {
      _polling = false;
      _qrUrl = null;
    });
  }

  /// 开始游客登录。
  ///
  /// 无需微信账号:APP 直连 + 签名登录。预登录被安全验证拦截时,
  /// 打开系统浏览器完成腾讯验证码(本机回环服务器接收结果),再继续登录。
  Future<void> _startGuestLogin() async {
    if (_guestLoading || _loading) return;
    setState(() {
      _guestLoading = true;
      _guestCaptchaWaiting = false;
    });

    try {
      final message = await _api.startGuestLogin();
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _polling = false;
        _qrUrl = null;
      });
      context.read<ToastProvider>().showSuccess(message);
    } on GuestCaptchaRequiredException catch (e) {
      // 需要安全验证:在系统浏览器中打开验证码页
      if (!mounted) return;
      setState(() => _guestCaptchaWaiting = true);
      context.read<ToastProvider>().showInfo('请在浏览器中完成微信读书安全验证');
      final captcha = await WereadGuestCaptcha.run(
        appId: wereadCaptchaAppId,
      );
      if (!mounted) return;
      if (captcha == null) {
        setState(() => _guestCaptchaWaiting = false);
        context.read<ToastProvider>().showWarning('安全验证等待超时或已取消,请重试');
        return;
      }
      setState(() {
        _guestCaptchaWaiting = false;
        _guestLoading = true;
      });
      try {
        final message = await _api.completeGuestLogin(
          e.session,
          captcha.ticket,
          captcha.randstr,
        );
        if (!mounted) return;
        setState(() {
          _isLoggedIn = true;
          _polling = false;
          _qrUrl = null;
        });
        context.read<ToastProvider>().showSuccess(message);
      } catch (err) {
        if (mounted) {
          context.read<ToastProvider>().showError('游客登录失败: $err');
        }
      }
    } catch (e) {
      if (mounted) {
        context.read<ToastProvider>().showError('游客登录失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _guestLoading = false;
          _guestCaptchaWaiting = false;
        });
      }
    }
  }

  /// 取消等待安全验证(浏览器页面仍会等待,超时后自动关闭)
  void _cancelGuestCaptcha() {
    setState(() {
      _guestCaptchaWaiting = false;
      _guestLoading = false;
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

    if (!_isLoggedIn) {
      if (mounted) setState(() {});
      return;
    }

    // 提取书名并自动搜索
    final title = await _extractEpubTitle(_epubPath);
    if (!mounted) return;
    // 清理标题:去掉括号内的副标题/宣传语,只用核心书名搜索
    final cleanTitle = _cleanSearchKeyword(title);
    _searchController.text = cleanTitle;
    setState(() {});
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
    if (!mounted) return;
    setState(() => _outputPath = path);
  }

  /// 搜索书目
  Future<void> _search() async {
    if (_searching) return; // 防重入：避免并发搜索结果乱序覆盖
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
        if (!mounted) return;
        _logController.append('API 原始响应：$raw');
      });
      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });
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
    try {
      await _api.saveBook(book);
    } catch (e) {
      _logController.append('ERROR: 绑定书目失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('绑定书目失败：$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _boundBook = book;
      _searchResults = [];
    });
    context.read<ToastProvider>().showSuccess('已绑定：${book.title}');
  }

  /// 解绑当前书目(保留登录状态)
  Future<void> _unbindBook() async {
    setState(() {
      _boundBook = null;
    });
  }

  /// 将进度回调写入日志
  void _logProgress(String phase, int current, int total, String text) {
    if (!mounted) return;
    final progress = total > 0 ? '($current/$total)' : '';
    _logController.append('PROGRESS: [$phase] $text $progress');
  }

  /// 执行完整同步流程
  ///
  /// 通过 SKILL API / APP 直连拉取热门划线和公开想法,注入到 EPUB 中。
  /// 完成后自动保存缓存,方便离线重注。
  Future<void> _execute() async {
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
      _logController.append('PROGRESS: 拉取章节列表、热门划线与公开想法...');

      final fetchResult = await _api.fetchBookData(
        _boundBook!.bookId,
        onProgress: _logProgress,
      );
      if (!mounted) return;

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
      if (!mounted) return;

      // 注入想法到 EPUB
      if (!mounted) return;
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
      if (!mounted) return;

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
        if (!mounted) return;
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
      if (mounted) {
        _logController.append('ERROR: 同步失败：$e');
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

  /// 把生成的 EPUB 复制到公共 Download/books/ 目录
  ///
  /// 仅 Android 生效。统一走流式复制(原生端 FileInputStream 分块写入
  /// MediaStore),避免 Dart 堆持有完整文件字节 + MethodChannel 序列化副本
  /// 导致移动端大书 OOM 闪退。
  Future<void> _copyToPublicDownload() async {
    if (!mounted) return;
    if (_outputPath.isEmpty) return;
    if (!Platform.isAndroid) return;
    if (!await File(_outputPath).exists()) return;
    try {
      final filename = p.basename(_outputPath);
      _logController.append('PROGRESS: 复制到公共 Download...');
      final publicPath = await FileService.copyFileToPublicDownload(
        sourcePath: _outputPath,
        filename: filename,
      );
      if (mounted) {
        _logController.append('PROGRESS: 已复制到公共 Download: $publicPath');
        try {
          await File(_outputPath).delete();
        } catch (_) {}
        _outputPath = publicPath;
      }
    } catch (e) {
      if (mounted) {
        _logController.append('WARN: 复制到公共 Download 失败：$e');
      }
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
              '1. 扫码登录或游客登录(无需微信账号;游客登录可能需在浏览器中完成安全验证)\n'
              '2. 选择本地 EPUB 文件\n'
              '3. 程序自动根据书名搜索书目\n'
              '4. 在搜索结果中选择对应书目\n'
              '5. 点击执行，等待拉取和注入完成\n'
              '6. 完成后自动清除搜索结果，方便处理下一本',
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
    // 桌面(≥720)双列并排输出路径;窄屏保持纵向原顺序
    final isWide = MediaQuery.sizeOf(context).width >= 720;
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

                // === 已登录后才显示以下区域 ===
                if (_isLoggedIn) ...[
                  const SizedBox(height: 10),

                  // === EPUB 文件区 + 输出路径(桌面双列并排,窄屏保持原顺序)===
                  if (isWide) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInputSection()),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _boundBook != null
                              ? _buildOutputSection()
                              : _buildOutputPlaceholder(),
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildInputSection(),
                  ],

                  // === 搜索绑定区(选完 EPUB 后自动出现)===
                  if (_isLoggedIn && _epubPath.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildSearchSection(),
                  ],

                  // === 输出路径(窄屏:绑定书目后显示,保持原顺序)===
                  if (!isWide && _boundBook != null) ...[
                    const SizedBox(height: 10),
                    _buildOutputSection(),
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
            label: '同步想法到 EPUB',
            icon: Icons.cloud_download_outlined,
          ),
        ],
      ),
    );
  }

  /// 输入区：EPUB 文件选择
  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
      ],
    );
  }

  /// 输出区：输出路径选择 + 帮助条
  Widget _buildOutputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
          text: '程序会自动根据 EPUB 书名搜索书目。选择对应书目后点击执行,完成后自动清除搜索结果。',
          onTap: _showFeatureHelp,
        ),
      ],
    );
  }

  /// 输出区占位：桌面双列下尚未绑定书目时的提示
  Widget _buildOutputPlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        buildSectionLabel(context, Icons.save_outlined, '输出路径'),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: context.themeCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.themeDividerLight),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: context.themeTextTertiary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '搜索并绑定书目后，在此选择输出路径',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.themeTextTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
          ] else if (_guestLoading || _guestCaptchaWaiting) ...[
            // 游客登录进行中
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: context.themeDividerLight),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _guestCaptchaWaiting
                              ? '请在浏览器中完成微信读书安全验证(3 分钟内)...'
                              : '正在游客登录...',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.themeTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_guestCaptchaWaiting) ...[
                    const SizedBox(height: 8),
                    Text(
                      '若浏览器未自动打开,请检查默认浏览器设置后重试。'
                      '验证完成后本页面会自动继续。',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeTextTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BaseButton(
                      label: '取消等待',
                      size: BaseButtonSize.sm,
                      variant: BaseButtonVariant.secondary,
                      onPressed: _cancelGuestCaptcha,
                    ),
                  ],
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
                Expanded(
                  child: BaseButton(
                    label: '游客登录',
                    icon: Icons.person_outline,
                    size: BaseButtonSize.sm,
                    variant: BaseButtonVariant.secondary,
                    onPressed: _loading ? null : _startGuestLogin,
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
                          errorBuilder: (_, _, _) => _buildCoverPlaceholder(),
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
