import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

/// 应用内打开亚马逊 Send to Kindle 网页
///
/// 使用 WebView 在应用内加载 https://www.amazon.com/sendtokindle
/// 用户无需跳转到外部浏览器即可完成推送。
class WebSendPage extends StatefulWidget {
  const WebSendPage({super.key});

  @override
  State<WebSendPage> createState() => _WebSendPageState();
}

class _WebSendPageState extends State<WebSendPage> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _isLoading = true;

  static const _sendToKindleUrl = 'https://www.amazon.com/sendtokindle';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('WebView 错误: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_sendToKindleUrl));
  }

  Future<void> _clearCookies() async {
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
    await _controller.reload();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: context.themeBg.withValues(alpha: 0.95),
        foregroundColor: context.themeTextPrimary,
        elevation: 0,
        // 紧凑工具栏：让标题与顶部距离更近
        toolbarHeight: 48,
        titleSpacing: 16,
        centerTitle: false,
        title: Text(
          '网页推送',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.themeTextPrimary,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              if (value == 'clear') _clearCookies();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.logout,
                      size: 18,
                      color: context.themeTextSecondary,
                    ),
                    SizedBox(width: 10),
                    Text('清除登录状态'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: Icon(Icons.arrow_back, size: 20),
            tooltip: '后退',
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward, size: 20),
            tooltip: '前进',
            onPressed: () async {
              if (await _controller.canGoForward()) {
                await _controller.goForward();
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isLoading ? 2 : 0,
            child: LinearProgressIndicator(
              value: _progress > 0 && _progress < 1 ? _progress : null,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(context.themeAccent),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          // 底部提示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: context.themeCard,
              border: Border(top: BorderSide(color: context.themeDividerLight)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: context.themeAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '登录状态会自动保存，下次打开无需重新登录',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
