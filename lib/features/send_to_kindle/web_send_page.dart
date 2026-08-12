import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows_webview;

import '../../core/theme.dart';

/// 打开亚马逊 Send to Kindle 网页。
///
/// Android、iOS 与 macOS 使用应用内 WebView；Windows 使用 Edge WebView2；
/// Linux 暂无受支持的内嵌实现，会显示说明页。
class WebSendPage extends StatefulWidget {
  const WebSendPage({
    super.key,
    this.openExternalBrowserOnStart = true,
    this.forceExternalBrowser,
    this.simulateWindowsInitFailed,
  });

  /// 测试场景下可关闭外部浏览器自动唤起。
  final bool openExternalBrowserOnStart;

  /// 仅用于测试平台回退界面。
  final bool? forceExternalBrowser;

  /// 仅用于测试：模拟 Windows 内置浏览器初始化失败的回退页。
  final String? simulateWindowsInitFailed;

  @override
  State<WebSendPage> createState() => _WebSendPageState();
}

class _WebSendPageState extends State<WebSendPage> {
  static const _sendToKindleUrl = 'https://www.amazon.com/sendtokindle';

  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  StreamSubscription<windows_webview.LoadingState>? _windowsLoadingSubscription;
  StreamSubscription<windows_webview.HistoryChanged>?
  _windowsHistorySubscription;
  StreamSubscription<windows_webview.WebErrorStatus>?
  _windowsLoadErrorSubscription;
  double _progress = 0;
  bool _isLoading = true;
  bool _windowsReady = false;
  bool _windowsCanGoBack = false;
  bool _windowsCanGoForward = false;
  bool _windowsFailed = false;
  String? _windowsError;
  String? _installHint;
  String? _webLoadError;
  Timer? _loadTimeout;
  bool _browserOpened = false;
  bool _browserLaunchFailed = false;
  double _webViewportWidth = 0;
  Timer? _webFitTimer;
  Timer? _lateWebFitTimer;

  /// 页面加载超时（秒）：超过后提示用户检查网络
  static const _pageLoadTimeout = Duration(seconds: 60);

  /// WebView2 Runtime 安装超时（秒）
  static const _installTimeout = Duration(seconds: 180);

  bool get _usesExternalBrowser =>
      widget.forceExternalBrowser ?? Platform.isLinux;

  @override
  void initState() {
    super.initState();
    final simulatedFailure = widget.simulateWindowsInitFailed;
    if (simulatedFailure != null) {
      _windowsFailed = true;
      _windowsError = simulatedFailure;
      _isLoading = false;
    } else if (_usesExternalBrowser) {
      if (widget.openExternalBrowserOnStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openInBrowser());
      } else {
        _isLoading = false;
      }
    } else if (Platform.isWindows) {
      _initializeWindowsWebView();
    } else {
      _initializeWebView();
    }
  }

  Future<void> _initializeWindowsWebView() async {
    windows_webview.WebviewController? controller;
    try {
      if (mounted) {
        setState(() {
          _windowsError = null;
          _installHint = null;
          _webLoadError = null;
        });
      }

      var runtimeVersion =
          await windows_webview.WebviewController.getWebViewVersion();
      if (runtimeVersion == null) {
        final installError = await _installWindowsWebViewRuntime();
        if (installError != null) {
          _handleWindowsInitFailure(installError);
          return;
        }
        runtimeVersion =
            await windows_webview.WebviewController.getWebViewVersion();
      }
      if (runtimeVersion == null) {
        throw StateError(
          'WebView2 Runtime 安装完成后仍无法检测到，请重启应用后重试',
        );
      }

      controller = windows_webview.WebviewController();
      _windowsLoadingSubscription = controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == windows_webview.LoadingState.loading;
          if (!_isLoading) {
            _progress = 1;
            _loadTimeout?.cancel();
            if (state == windows_webview.LoadingState.navigationCompleted) {
              _webLoadError = null;
            }
          }
        });
      });
      _windowsHistorySubscription = controller.historyChanged.listen((history) {
        if (mounted) {
          setState(() {
            _windowsCanGoBack = history.canGoBack;
            _windowsCanGoForward = history.canGoForward;
          });
        }
      });
      _windowsLoadErrorSubscription = controller.onLoadError.listen((status) {
        // 仅首次加载（主导航）期间报错时提示，避免页面内子资源错误误报
        if (!mounted || !_isLoading) return;
        setState(() {
          _webLoadError = '网页加载失败（${status.name}），请检查网络连接后点击刷新';
        });
      });
      await controller.initialize();
      await controller.loadUrl(_sendToKindleUrl);
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _windowsController = controller;
        _windowsReady = true;
        _isLoading = false;
        _installHint = null;
      });
      _scheduleWebContentFit();
      _startLoadTimeout();
    } catch (error) {
      if (controller != null && controller != _windowsController) {
        unawaited(controller.dispose());
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _installHint = null;
        });
      }
      _handleWindowsInitFailure(error.toString());
    }
  }

  /// 安装 WebView2 Runtime。
  ///
  /// 成功返回 null；失败返回用户可读的错误描述。
  /// 安装可能触发系统 UAC 提权提示，且安装过程有 [_installTimeout] 超时。
  Future<String?> _installWindowsWebViewRuntime() async {
    final executable = File(Platform.resolvedExecutable);
    final installer = File(
      '${executable.parent.path}${Platform.pathSeparator}'
      'MicrosoftEdgeWebView2Setup.exe',
    );
    if (!await installer.exists()) {
      return '应用内未找到 WebView2 安装程序（MicrosoftEdgeWebView2Setup.exe）。'
          '请重新安装 EPUB 工具箱后再试，或改用浏览器完成推送。';
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _installHint = '正在安装网页组件（WebView2 Runtime），可能需要几分钟…\n'
            '若弹出「用户账户控制」窗口，请点击「是」以完成安装。';
      });
    }
    try {
      final result = await Process.run(
        installer.path,
        const ['/silent', '/install'],
      ).timeout(_installTimeout);
      if (result.exitCode != 0) {
        return 'WebView2 安装失败（退出码 ${result.exitCode}）。'
            '若 UAC 提示被取消，请重新打开本功能重试，或改用浏览器推送。';
      }
      return null;
    } on TimeoutException {
      return 'WebView2 安装超时（超过 180 秒）。'
          '请改用「在浏览器中打开」完成推送，或手动安装 WebView2 Runtime。';
    } catch (error) {
      return 'WebView2 安装失败：$error';
    }
  }

  /// Windows 内置浏览器初始化失败：切换到外部浏览器回退页，并自动打开默认浏览器。
  void _handleWindowsInitFailure(String error) {
    if (!mounted) return;
    setState(() {
      _windowsFailed = true;
      _windowsError = error;
      _isLoading = false;
      _installHint = null;
    });
    // 自动回退：在默认浏览器中打开 Send to Kindle（与 Linux 行为一致）
    if (widget.openExternalBrowserOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInBrowser());
    }
  }

  /// 从失败回退页重试内置浏览器
  Future<void> _retryWindowsWebView() async {
    _windowsLoadingSubscription?.cancel();
    _windowsHistorySubscription?.cancel();
    _windowsLoadErrorSubscription?.cancel();
    _windowsLoadingSubscription = null;
    _windowsHistorySubscription = null;
    _windowsLoadErrorSubscription = null;
    if (mounted) {
      setState(() {
        _windowsFailed = false;
        _windowsError = null;
        _webLoadError = null;
        _browserOpened = false;
        _browserLaunchFailed = false;
        _isLoading = true;
      });
    }
    await _initializeWindowsWebView();
  }

  void _initializeWebView() {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress / 100);
            },
            onPageStarted: (_) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _webLoadError = null;
                });
              }
              _loadTimeout?.cancel();
              _scheduleWebContentFit();
            },
            onWebResourceError: (error) {
              // 仅主框架加载失败时提示，避免页面内子资源错误误报
              if (error.isForMainFrame != true) return;
              if (!mounted) return;
              setState(() {
                _webLoadError = '网页加载失败：${error.description}，请检查网络连接后点击刷新';
              });
            },
          ),
        )
        ..loadRequest(Uri.parse(_sendToKindleUrl));
      _startLoadTimeout();
    } catch (e) {
      // WebView 内核初始化失败(少见)：给出可恢复的错误提示而非永久转圈
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _webLoadError = '内嵌网页初始化失败：$e，请点击刷新重试';
      });
    }
  }

  /// 页面加载超时检测：加载超过 [_pageLoadTimeout] 仍未完成时提示网络问题
  void _startLoadTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(_pageLoadTimeout, () {
      if (!mounted || !_isLoading) return;
      setState(() {
        _webLoadError = '网页加载超时，请检查网络连接后点击刷新';
      });
    });
  }

  void _reloadPage() {
    setState(() => _webLoadError = null);
    final windowsController = _windowsController;
    if (windowsController != null) {
      windowsController.reload();
      return;
    }
    final controller = _controller;
    if (controller != null) {
      controller.reload();
      return;
    }
    // 初始化失败路径：重新创建 WebView（错误横幅的「刷新」按钮走这里）
    _initializeWebView();
  }

  Future<void> _openInBrowser() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _browserLaunchFailed = false;
      });
    }
    final opened = await launchUrl(
      Uri.parse(_sendToKindleUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _browserOpened = opened;
      _browserLaunchFailed = !opened;
    });
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开默认浏览器，请检查系统浏览器设置')));
    }
  }

  Future<void> _clearCookies() async {
    final windowsController = _windowsController;
    if (windowsController != null) {
      await windowsController.clearCookies();
      await windowsController.clearCache();
      await windowsController.reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清除登录状态，下次需重新登录')));
      }
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    await controller.clearCache();
    await controller.clearLocalStorage();
    await controller.reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已清除登录状态，下次需重新登录'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _webFitTimer?.cancel();
    _lateWebFitTimer?.cancel();
    _loadTimeout?.cancel();
    _windowsLoadingSubscription?.cancel();
    _windowsHistorySubscription?.cancel();
    _windowsLoadErrorSubscription?.cancel();
    final controller = _windowsController;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width <= 800;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isMobile || _usesExternalBrowser || _windowsFailed
          ? null
          : _buildDesktopAppBar(),
      body: _usesExternalBrowser || _windowsFailed
          ? _buildExternalBrowserPage(context)
          : Platform.isWindows
          ? _buildWindowsWebViewPage(context)
          : _buildWebViewPage(context, isMobile),
    );
  }

  PreferredSizeWidget _buildDesktopAppBar() {
    return AppBar(
      backgroundColor: context.themeBg.withValues(alpha: 0.95),
      foregroundColor: context.themeTextPrimary,
      elevation: 0,
      toolbarHeight: 48,
      titleSpacing: 16,
      centerTitle: false,
      title: Text(
        '网页推送',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.themeTextPrimary,
        ),
      ),
      actions: _buildBrowserActions(compact: false),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: _buildProgressLine(),
      ),
    );
  }

  Widget _buildWebViewPage(BuildContext context, bool isMobile) {
    final controller = _controller;

    return Column(
      children: [
        if (isMobile) _buildMobileBrowserBar(context),
        _buildWebErrorBanner(context),
        Expanded(
          child: controller == null
              // 初始化失败：占位空白，错误横幅在上方可点「刷新」重建 WebView
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    _onWebViewportChanged(constraints.maxWidth);
                    return WebViewWidget(controller: controller);
                  },
                ),
        ),
        _buildLoginHint(context, compact: isMobile),
      ],
    );
  }

  Widget _buildWindowsWebViewPage(BuildContext context) {
    final controller = _windowsController;
    if (controller != null && _windowsReady) {
      // 窄窗口下 appBar 为 null，导航控制由移动浏览器栏补齐（与 WebView 分支一致）
      final isNarrow = MediaQuery.sizeOf(context).width <= 800;
      return Column(
        children: [
          if (isNarrow) _buildMobileBrowserBar(context),
          _buildWebErrorBanner(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _onWebViewportChanged(constraints.maxWidth);
                return windows_webview.Webview(controller);
              },
            ),
          ),
          _buildLoginHint(context, compact: isNarrow),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _installHint ?? '正在打开网页推送…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.themeTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 网络加载失败提示条（主框架加载失败或加载超时）
  Widget _buildWebErrorBanner(BuildContext context) {
    final message = _webLoadError;
    if (message == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: context.themeError.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: context.themeError.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 15, color: context.themeError),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.35, color: context.themeError),
            ),
          ),
          TextButton(
            onPressed: _reloadPage,
            style: TextButton.styleFrom(
              foregroundColor: context.themeError,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  void _onWebViewportChanged(double width) {
    if (width <= 0 || (width - _webViewportWidth).abs() < 2) return;
    _webViewportWidth = width;
    _scheduleWebContentFit();
  }

  /// Amazon 的桌面页有最小布局宽度。每次网页加载或 Flutter 窗口改变
  /// 大小时，按可用宽度缩放网页正文，避免产生横向滚动条。
  void _scheduleWebContentFit() {
    if (_webViewportWidth <= 0) return;
    _webFitTimer?.cancel();
    _lateWebFitTimer?.cancel();
    _webFitTimer = Timer(const Duration(milliseconds: 260), () {
      unawaited(_fitWebContentToViewport());
    });
    // Amazon 页面会在初次加载后继续异步插入导航和图片，再校正一次。
    _lateWebFitTimer = Timer(const Duration(milliseconds: 1200), () {
      unawaited(_fitWebContentToViewport());
    });
  }

  Future<void> _fitWebContentToViewport() async {
    if (!mounted || _webViewportWidth <= 0) return;
    final script =
        '''
      (() => {
        const viewportWidth = ${_webViewportWidth.floor()};
        const root = document.documentElement;
        const body = document.body;
        if (!body || viewportWidth <= 0) return;
        root.style.overflowX = 'visible';
        body.style.zoom = '1';
        requestAnimationFrame(() => {
          let contentWidth = Math.max(
            root.scrollWidth || 0,
            body.scrollWidth || 0,
            root.offsetWidth || 0,
            body.offsetWidth || 0,
          );
          // 部分 Amazon 导航元素在普通 scrollWidth 之外溢出；把其实际
          // 右边界也纳入测量，防止右侧登录、购物车等内容被裁掉。
          for (const element of body.querySelectorAll('*')) {
            const rect = element.getBoundingClientRect();
            contentWidth = Math.max(contentWidth, rect.right, rect.width);
          }
          const scale = Math.min(
            1,
            Math.max(0.1, (viewportWidth - 8) / Math.max(contentWidth, 1)),
          );
          body.style.zoom = String(scale);
          root.style.overflowX = 'hidden';
        });
      })();
    ''';
    try {
      final windowsController = _windowsController;
      if (windowsController != null) {
        await windowsController.executeScript(script);
      } else {
        await _controller?.runJavaScript(script);
      }
    } catch (error) {
      debugPrint('网页自适应缩放失败: $error');
    }
  }

  Widget _buildMobileBrowserBar(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.themeBg.withValues(alpha: 0.96),
        border: Border(bottom: BorderSide(color: context.themeDividerLight)),
      ),
      child: Row(
        children: [
          Icon(Icons.language_rounded, size: 18, color: context.themeAccent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Amazon Send to Kindle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.themeTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ..._buildBrowserActions(compact: true),
        ],
      ),
    );
  }

  List<Widget> _buildBrowserActions({required bool compact}) {
    final controller = _controller;
    final windowsController = _windowsController;
    final size = compact ? 19.0 : 20.0;
    final constraints = compact
        ? const BoxConstraints.tightFor(width: 36, height: 36)
        : null;
    return [
      IconButton(
        icon: Icon(Icons.arrow_back_rounded, size: size),
        tooltip: '后退',
        constraints: constraints,
        padding: EdgeInsets.zero,
        onPressed: controller == null && windowsController == null
            ? null
            : () async {
                if (windowsController != null) {
                  if (_windowsCanGoBack) await windowsController.goBack();
                } else if (await controller!.canGoBack()) {
                  await controller.goBack();
                }
              },
      ),
      IconButton(
        icon: Icon(Icons.refresh_rounded, size: size),
        tooltip: '刷新',
        constraints: constraints,
        padding: EdgeInsets.zero,
        onPressed: windowsController?.reload ?? controller?.reload,
      ),
      IconButton(
        icon: Icon(Icons.arrow_forward_rounded, size: size),
        tooltip: '前进',
        constraints: constraints,
        padding: EdgeInsets.zero,
        onPressed: controller == null && windowsController == null
            ? null
            : () async {
                if (windowsController != null) {
                  if (_windowsCanGoForward) await windowsController.goForward();
                } else if (await controller!.canGoForward()) {
                  await controller.goForward();
                }
              },
      ),
      PopupMenuButton<String>(
        tooltip: '更多操作',
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: Icon(Icons.more_horiz_rounded, size: size),
        onSelected: (value) {
          if (value == 'clear') _clearCookies();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'clear', child: Text('清除登录状态')),
        ],
      ),
    ];
  }

  Widget _buildProgressLine() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: _isLoading ? 2 : 0,
      child: LinearProgressIndicator(
        value: _progress > 0 && _progress < 1 ? _progress : null,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(context.themeAccent),
      ),
    );
  }

  Widget _buildLoginHint(BuildContext context, {required bool compact}) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: context.themeBg,
          border: Border(top: BorderSide(color: context.themeDividerLight)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: context.themeAccent),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '登录状态会自动保存，下次打开无需重新登录',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: context.themeTextTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalBrowserPage(BuildContext context) {
    final isWindowsFallback = _windowsFailed;
    final platformName = Platform.isWindows ? 'Windows' : '当前桌面平台';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.themeCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              border: Border.all(color: context.themeDividerLight),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.themeAccentLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.open_in_browser_rounded,
                    color: context.themeAccent,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _browserOpened
                      ? '已在浏览器中打开网页推送'
                      : isWindowsFallback
                      ? '内置浏览器不可用'
                      : '使用浏览器完成网页推送',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isWindowsFallback
                      ? '内置浏览器初始化失败，已改用默认浏览器。可正常登录、上传文件并保留亚马逊登录状态。'
                      : '$platformName 暂不支持内嵌网页推送。默认浏览器可正常登录、上传文件并保留亚马逊登录状态。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.themeTextSecondary,
                  ),
                ),
                if (_windowsError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.themeError.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: context.themeError.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '错误详情：$_windowsError',
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: context.themeError,
                      ),
                    ),
                  ),
                ],
                if (_browserLaunchFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    '未能打开默认浏览器，请检查系统默认浏览器设置后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.themeError),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (isWindowsFallback) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _retryWindowsWebView,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.themeAccent,
                            side: BorderSide(
                              color: context.themeAccent.withValues(alpha: 0.4),
                            ),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusL,
                              ),
                            ),
                          ),
                          child: const Text('重试内置浏览器'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _openInBrowser,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(
                            _browserOpened ? '再次打开浏览器' : '在默认浏览器中打开',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
