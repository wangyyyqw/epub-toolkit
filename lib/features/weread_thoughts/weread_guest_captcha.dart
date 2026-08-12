import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// 腾讯验证码结果。
class WereadCaptchaResult {
  final String ticket;
  final String randstr;

  const WereadCaptchaResult({required this.ticket, required this.randstr});
}

/// 游客登录的腾讯验证码回调(本机回环 + 默认浏览器)。
///
/// 流程:
/// 1. 在 127.0.0.1 随机端口起一个一次性 HTTP 服务器,提供验证码页面
/// 2. 用系统默认浏览器打开该页面(TCaptcha.js 从 captcha.gtimg.com 加载)
/// 3. 用户在浏览器中完成滑块/点选验证
/// 4. 页面 JS 把 ticket/randstr 上报到 /wr-captcha-result
/// 5. 服务器捕获结果后自动关闭,等待方拿到 ticket/randstr
///
/// 选择外部浏览器而非应用内 WebView:全平台一致(含 Linux),
/// 且无需为移动端/桌面端多种 WebView 分别实现 JS 桥。
class WereadGuestCaptcha {
  WereadGuestCaptcha._();

  /// 等待用户完成验证码。
  ///
  /// [appId] 腾讯验证码 AppId
  /// [timeout] 等待超时(默认 3 分钟,与微信扫码登录等待时长一致)
  /// 返回验证码结果;超时或用户取消时返回 null。
  static Future<WereadCaptchaResult?> run({
    required String appId,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final completer = Completer<WereadCaptchaResult?>();
    var captured = false;

    server.listen((request) {
      final path = request.uri.path;
      if (path == '/') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..headers.set('Cache-Control', 'no-store')
          ..write(_captchaPageHtml(appId, port))
          ..close();
        return;
      }
      if (path == '/wr-captcha-result') {
        final ticket = request.uri.queryParameters['ticket'] ?? '';
        final randstr = request.uri.queryParameters['randstr'] ?? '';
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('ok')
          ..close();
        if (!captured && ticket.isNotEmpty && randstr.isNotEmpty) {
          captured = true;
          if (!completer.isCompleted) {
            completer.complete(
              WereadCaptchaResult(ticket: ticket, randstr: randstr),
            );
          }
        }
        return;
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });

    final pageUrl = 'http://127.0.0.1:$port/';
    final opened = await launchUrl(
      Uri.parse(pageUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await server.close(force: true);
      return null;
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await server.close(force: true);
    }
  }

  /// 验证码页面:加载腾讯 TCaptcha,成功后把 ticket/randstr 上报回环服务器。
  static String _captchaPageHtml(String appId, int port) {
    final safeAppId = json.encode(appId);
    return '''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>微信读书安全验证</title>
<style>
body{margin:0;background:#f4f6f5;color:#17211e;font-family:-apple-system,"Microsoft YaHei",sans-serif}
.wrap{max-width:520px;margin:auto;padding:28px 20px}
.panel{background:#fff;border:1px solid #d9dfdc;border-radius:6px;padding:22px}
h1{font-size:20px;margin:0 0 10px}
p{font-size:15px;line-height:1.7;color:#52615c;margin:8px 0}
#status{margin-top:18px;color:#28785f;font-weight:bold}
</style>
<script src="https://captcha.gtimg.com/TCaptcha.js"></script>
</head><body>
<div class="wrap"><div class="panel">
<h1>微信读书安全验证</h1>
<p>请完成腾讯验证码,验证成功后本页面会自动关闭并继续游客登录。</p>
<div id="status">正在载入验证码...</div>
</div></div>
<script>
var APP_ID = $safeAppId;
var RESULT_URL = 'http://127.0.0.1:$port/wr-captcha-result';
var done = false;
function report(ticket, randstr) {
  if (done) return;
  done = true;
  document.getElementById('status').textContent = '验证成功,正在继续游客登录...';
  try {
    var img = new Image();
    img.src = RESULT_URL + '?ticket=' + encodeURIComponent(ticket) +
        '&randstr=' + encodeURIComponent(randstr);
    img.onload = img.onerror = function() { setTimeout(function() {
      try { window.close(); } catch (e) {}
    }, 500); };
  } catch (e) {
    var link = document.createElement('a');
    link.href = RESULT_URL + '?ticket=' + encodeURIComponent(ticket) +
        '&randstr=' + encodeURIComponent(randstr);
    link.textContent = '验证成功,点击这里返回应用';
    document.body.appendChild(link);
  }
}
window.onload = function() {
  try {
    window.wrCaptcha = new TencentCaptcha(APP_ID, function(result) {
      if (result && result.ret === 0 && result.ticket && result.randstr) {
        report(result.ticket, result.randstr);
      } else {
        document.getElementById('status').textContent =
            '验证未完成,请重试(可关闭本页面返回应用)';
      }
    }, { enableDarkMode: true }).show();
  } catch (e) {
    document.getElementById('status').textContent = '验证码载入失败,请关闭本页面返回应用重试';
  }
};
</script>
</body></html>''';
  }
}
