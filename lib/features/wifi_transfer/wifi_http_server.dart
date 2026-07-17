import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'wifi_book.dart';
import 'wifi_book_library.dart';

/// WiFi 传书 HTTP 服务器状态。
enum WifiServerStatus { stopped, starting, running, error }

/// 局域网 HTTP 服务器：在本机起一个端口，供 Kindle 浏览器下载书库中的书。
///
/// 参考 Kindred / kaf-wifi 的实现思路：
/// - 绑定 0.0.0.0，Kindle 与本机需在同一局域网
/// - 首页列出书库并提供搜索
/// - 下载链接使用 ASCII 短名，规避 Kindle Experimental Browser 的中文名与 MIME 限制
class WifiHttpServer extends ChangeNotifier {
  WifiHttpServer(this._library);

  final WifiBookLibrary _library;

  HttpServer? _server;
  WifiServerStatus _status = WifiServerStatus.stopped;
  String? _address;
  String? _errorMessage;
  int _port = 8765;

  /// 当前状态。
  WifiServerStatus get status => _status;

  /// 是否正在运行。
  bool get isRunning => _status == WifiServerStatus.running;

  /// 对外访问地址（http://本机IP:端口/）。
  String? get address => _address;

  /// 当前错误信息。
  String? get errorMessage => _errorMessage;

  /// 监听端口。
  int get port => _port;

  /// 设置监听端口（仅在停止时生效）。
  set port(int value) {
    if (_status != WifiServerStatus.stopped) return;
    if (value <= 0 || value > 65535) return;
    _port = value;
  }

  /// 启动服务器。
  Future<void> start() async {
    if (_status == WifiServerStatus.running || _status == WifiServerStatus.starting) {
      return;
    }
    _status = WifiServerStatus.starting;
    _errorMessage = null;
    notifyListeners();
    try {
      // 绑定任意地址，端口占用时自动 +1 重试，最多尝试 20 次
      var boundPort = _port;
      HttpServer? server;
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          server = await HttpServer.bind(
            InternetAddress.anyIPv4,
            boundPort,
          );
          break;
        } on SocketException {
          boundPort++;
        }
      }
      if (server == null) {
        throw StateError('无法绑定端口 $_port~${_port + 20}，请检查端口占用');
      }
      _server = server;
      _port = boundPort;
      final ip = await _detectWifiIPv4();
      _address = ip == null
          ? 'http://localhost:$_port/'
          : 'http://$ip:$_port/';
      _status = WifiServerStatus.running;
      notifyListeners();
      _serveLoop(server);
    } catch (e) {
      _status = WifiServerStatus.error;
      _errorMessage = '启动失败：$e';
      notifyListeners();
    }
  }

  /// 停止服务器。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // 忽略关闭异常
      }
    }
    _status = WifiServerStatus.stopped;
    _address = null;
    notifyListeners();
  }

  /// 主循环：逐个处理 HTTP 连接。
  void _serveLoop(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handleRequest(request);
      } catch (e) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('内部错误：$e');
          await request.response.close();
        } catch (_) {
          // 连接可能已断开
        }
      }
    }
  }

  /// 处理单个请求。
  Future<void> _handleRequest(HttpRequest request) async {
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      await _sendError(request, HttpStatus.methodNotAllowed, '仅支持 GET / HEAD');
      return;
    }
    final path = request.uri.path;
    final isHead = method == 'HEAD';

    if (path == '/' || path == '/index.html') {
      final query = request.uri.queryParameters['q'] ?? '';
      await _sendIndex(request, query, isHead);
      return;
    }
    if (path == '/favicon.ico') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (path.startsWith('/books/')) {
      await _sendBook(request, path, isHead);
      return;
    }
    await _sendError(request, HttpStatus.notFound, '未找到资源');
  }

  /// 首页 HTML（含搜索框与书籍列表）。
  Future<void> _sendIndex(HttpRequest request, String query, bool isHead) async {
    final books = _library.filter(query);
    final html = _indexHtml(books, query);
    final bytes = html.codeUnits;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.contentLength = bytes.length;
    request.response.headers.set('Cache-Control', 'no-cache');
    if (isHead) {
      await request.response.close();
      return;
    }
    request.response.add(utf8.encode(html));
    await request.response.close();
  }

  /// 下载书籍文件。
  Future<void> _sendBook(HttpRequest request, String path, bool isHead) async {
    // 路径格式：/books/{id} 或 /books/{id}/{filename}
    final rest = path.substring('/books/'.length);
    final idPart = rest.split('/').first.split('.').first;
    final book = _library.books.firstWhere(
      (b) => b.id == idPart,
      orElse: () => throw StateError('not_found'),
    );
    File file;
    try {
      file = _library.fileFor(book);
    } catch (_) {
      await _sendError(request, HttpStatus.notFound, '书库尚未就绪');
      return;
    }
    if (!await file.exists()) {
      await _sendError(request, HttpStatus.notFound, '文件不存在');
      return;
    }
    final downloadName = KindleDownloadCompat.filename(book);
    final mime = KindleDownloadCompat.contentType(book.format);
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', mime);
    request.response.headers.set('Content-Length', '${await file.length()}');
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="$downloadName"',
    );
    request.response.headers.set('Cache-Control', 'no-cache');
    if (isHead) {
      await request.response.close();
      return;
    }
    // 流式发送文件，避免大文件一次性读入内存
    await file.openRead().pipe(request.response);
  }

  /// 错误响应。
  Future<void> _sendError(HttpRequest request, int status, String message) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.html;
    final body = '<html><body><h1>$message</h1></body></html>';
    request.response.write(body);
    await request.response.close();
  }

  /// 生成首页 HTML。
  String _indexHtml(List<WifiBook> books, String query) {
    final rows = books.map((b) {
      final title = _escapeHtml(b.title);
      final details = _escapeHtml('${b.format} · ${b.formattedSize}');
      final downloadName = KindleDownloadCompat.filename(b);
      final href = '/books/${b.id}/$downloadName';
      return '<tr><td><a href="$href">$title</a>'
          '<small>$details</small></td>'
          '<td><a href="$href" download="$downloadName">下载</a></td></tr>';
    }).join('\n');
    final emptyMsg = query.isEmpty ? '书库为空，请先导入书籍。' : '未找到匹配的书籍。';
    final content = rows.isEmpty
        ? '<p>${_escapeHtml(emptyMsg)}</p>'
        : '<table><tr><th>书名</th><th>操作</th></tr>$rows</table>';
    final q = _escapeHtml(query);
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EPUB 工具箱 · 局域网传书</title>
<style>
body{font-family:Arial,sans-serif;margin:18px;color:#222;max-width:720px;margin:auto}
h1{font-size:22px}
form{margin:16px 0}
input{font-size:16px;padding:6px}
input[type=text]{width:60%}
table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:10px 6px;border-bottom:1px solid #aaa}
a{color:#0645ad}
small{color:#666;display:block;margin-top:2px}
</style>
</head><body>
<h1>EPUB 工具箱 · 局域网传书</h1>
<p>点击书名在 Kindle 浏览器中下载。</p>
<form action="/" method="get">
<input type="text" name="q" value="$q">
<input type="submit" value="搜索">
</form>
$content
</body></html>
''';
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 探测本机 Wi-Fi IPv4 地址。
  Future<String?> _detectWifiIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // 优先返回常见 Wi-Fi / 以太网地址
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // 忽略探测失败
    }
    return null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
