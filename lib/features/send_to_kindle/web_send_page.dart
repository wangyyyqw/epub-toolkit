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
  });

  /// 测试场景下可关闭外部浏览器自动唤起。
  final bool openExternalBrowserOnStart;

  /// 仅用于测试平台回退界面。
  final bool? forceExternalBrowser;

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
  double _progress = 0;
  bool _isLoading = true;
  bool _windowsReady = false;
  bool _windowsCanGoBack = false;
  bool _windowsCanGoForward = false;
  String? _windowsError;
  bool _browserOpened = false;
  bool _browserLaunchFailed = false;
  double _webViewportWidth = 0;
  Timer? _webFitTimer;
  Timer? _lateWebFitTimer;

  bool get _usesExternalBrowser =>
      widget.forceExternalBrowser ?? Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (_usesExternalBrowser) {
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
      var runtimeVersion =
          await windows_webview.WebviewController.getWebViewVersion();
      if (runtimeVersion == null) {
        await _installWindowsWebViewRuntime();
        runtimeVersion =
            await windows_webview.WebviewController.getWebViewVersion();
      }
      if (runtimeVersion == null) {
        throw StateError('Microsoft Edge WebView2 Runtime 未能完成安装');
      }

      controller = windows_webview.WebviewController();
      _windowsLoadingSubscription = controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == windows_webview.LoadingState.loading;
          if (!_isLoading) _progress = 1;
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
      });
      _scheduleWebContentFit();
    } catch (error) {
      if (controller != null && controller != _windowsController) {
        unawaited(controller.dispose());
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _windowsError = error.toString();
        });
      }
    }
  }

  /// 正常安装会先静默安装 WebView2。此处覆盖旧版升级后的首次进入，
  /// 让用户点击网页推送后直接完成环境准备并进入网页。
  Future<void> _installWindowsWebViewRuntime() async {
    final executable = File(Platform.resolvedExecutable);
    final installer = File(
      '${executable.parent.path}${Platform.pathSeparator}'
      'MicrosoftEdgeWebView2Setup.exe',
    );
    if (!await installer.exists()) return;

    if (mounted) setState(() => _isLoading = true);
    try {
      await Process.run(installer.path, const ['/silent', '/install']);
    } catch (error) {
      debugPrint('WebView2 Runtime 安装失败: $error');
    }
  }

  void _initializeWebView() {
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
            if (mounted) setState(() => _isLoading = false);
            _scheduleWebContentFit();
          },
          onWebResourceError: (error) {
            debugPrint('WebView 错误: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_sendToKindleUrl));
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
    _windowsLoadingSubscription?.cancel();
    _windowsHistorySubscription?.cancel();
    final controller = _windowsController;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width <= 800;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isMobile || _usesExternalBrowser ? null : _buildDesktopAppBar(),
      body: _usesExternalBrowser
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
    if (controller == null) return const SizedBox.shrink();

    return Column(
      children: [
        if (isMobile) _buildMobileBrowserBar(context),
        Expanded(
          child: LayoutBuilder(
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
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _onWebViewportChanged(constraints.maxWidth);
                return windows_webview.Webview(controller);
              },
            ),
          ),
          _buildLoginHint(context, compact: false),
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
          Text(
            _windowsError == null ? '正在打开网页推送…' : '正在准备内置浏览器…',
            style: TextStyle(fontSize: 13, color: context.themeTextSecondary),
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
          color: context.themeCard,
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
                  _browserOpened ? '已在浏览器中打开网页推送' : '使用浏览器完成网页推送',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.themeTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$platformName 暂不支持内嵌网页推送。默认浏览器可正常登录、上传文件并保留亚马逊登录状态。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.themeTextSecondary,
                  ),
                ),
                if (_browserLaunchFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    '未能打开默认浏览器，请检查系统默认浏览器设置后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.themeError),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _openInBrowser,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(_browserOpened ? '再次打开浏览器' : '在默认浏览器中打开'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
