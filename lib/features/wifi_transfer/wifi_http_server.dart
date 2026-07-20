import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'wifi_book.dart';
import 'wifi_book_library.dart';

/// WiFi 传书 HTTP 服务器状态。
enum WifiServerStatus { stopped, starting, running, error }

/// 局域网 HTTP 服务器：在本机起一个端口，供 Kindle 浏览器下载书库中的书。
///
/// 稳定性策略：
/// - 绑定 0.0.0.0，Kindle 与本机需在同一局域网；
/// - 每个请求独立处理，避免大文件下载阻塞其他请求；
/// - 使用 UTF-8 字节数计算响应长度，避免中文页面被截断；
/// - 下载链接使用 ASCII 短名，兼容 Kindle Experimental Browser。
class WifiHttpServer extends ChangeNotifier {
  WifiHttpServer(this._library, {String? accessCode})
    : _accessCode = _resolveAccessCode(accessCode);

  static const _accessCodeAlphabet = '23456789abcdefghjkmnpqrstuvwxyz';

  final WifiBookLibrary _library;
  final String _accessCode;

  HttpServer? _server;
  WifiServerStatus _status = WifiServerStatus.stopped;
  String? _address;
  List<String> _addresses = const <String>[];
  String? _errorMessage;
  int _port = 8765;
  bool _disposed = false;
  int _lifecycleToken = 0;
  final Set<Future<void>> _activeRequests = <Future<void>>{};

  /// 当前状态。
  WifiServerStatus get status => _status;

  /// 是否正在运行。
  bool get isRunning => _status == WifiServerStatus.running;

  /// 对外访问地址（http://本机IP:端口/）。
  String? get address => _address;

  /// 所有可用访问地址，首项为优先推荐地址。
  List<String> get addresses => List.unmodifiable(_addresses);

  /// 当前服务的会话访问路径。
  String get accessPath => '/$_accessCode/';

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
    if (_disposed ||
        _status == WifiServerStatus.running ||
        _status == WifiServerStatus.starting) {
      return;
    }
    final token = ++_lifecycleToken;
    _status = WifiServerStatus.starting;
    _errorMessage = null;
    _notifySafely();

    HttpServer? createdServer;
    try {
      var boundPort = _port;
      final lastPort = min(_port + 19, 65535);
      while (boundPort <= lastPort) {
        try {
          createdServer = await HttpServer.bind(
            InternetAddress.anyIPv4,
            boundPort,
            shared: false,
          );
          break;
        } on SocketException {
          boundPort++;
        }
      }
      if (createdServer == null) {
        throw StateError('无法绑定端口 $_port~$lastPort，请检查端口占用或防火墙设置');
      }

      // 启动过程中若页面已销毁或服务已被停止，立即释放刚绑定的端口。
      if (_disposed || token != _lifecycleToken) {
        await createdServer.close(force: true);
        return;
      }

      createdServer.idleTimeout = const Duration(minutes: 2);
      _server = createdServer;
      _port = boundPort;
      final localAddresses = await _detectLocalIPv4Addresses();

      if (_disposed || token != _lifecycleToken) {
        _server = null;
        await createdServer.close(force: true);
        return;
      }

      _addresses = localAddresses.isEmpty
          ? <String>[_buildAddress('localhost')]
          : localAddresses.map(_buildAddress).toList(growable: false);
      _address = _addresses.first;
      _errorMessage = localAddresses.isEmpty
          ? '未检测到局域网 IPv4 地址；请检查 WiFi 或网络权限'
          : null;
      _status = WifiServerStatus.running;
      _notifySafely();
      unawaited(_serveLoop(createdServer));
    } catch (e) {
      if (createdServer != null) {
        if (identical(createdServer, _server)) _server = null;
        await createdServer.close(force: true);
      }
      if (_disposed || token != _lifecycleToken) return;
      _server = null;
      _address = null;
      _addresses = const <String>[];
      _status = WifiServerStatus.error;
      _errorMessage = '启动失败：$e';
      _notifySafely();
    }
  }

  /// 停止服务器并释放端口。
  Future<void> stop() async {
    ++_lifecycleToken;
    final server = _server;
    _server = null;
    _address = null;
    _addresses = const <String>[];
    if (server != null) {
      try {
        await server.close(force: true);
      } on SocketException {
        // 端口可能已经被系统回收，停止操作仍视为成功。
      }
    }
    if (_disposed) return;
    _status = WifiServerStatus.stopped;
    _errorMessage = null;
    _notifySafely();
  }

  /// 接收请求并并发处理，避免一个大文件下载阻塞整个书库。
  Future<void> _serveLoop(HttpServer server) async {
    try {
      await for (final request in server) {
        final task = _handleRequestSafely(request);
        _activeRequests.add(task);
        unawaited(task.whenComplete(() => _activeRequests.remove(task)));
      }
    } on SocketException catch (e) {
      if (!_disposed && identical(server, _server)) {
        _server = null;
        _address = null;
        _addresses = const <String>[];
        _status = WifiServerStatus.error;
        _errorMessage = '服务异常中断：$e';
        _notifySafely();
      }
    } catch (e) {
      if (!_disposed && identical(server, _server)) {
        _server = null;
        _address = null;
        _addresses = const <String>[];
        _status = WifiServerStatus.error;
        _errorMessage = '服务异常中断：$e';
        _notifySafely();
      }
    }
  }

  /// 安全处理单个请求，客户端中途断开不会影响服务器主循环。
  Future<void> _handleRequestSafely(HttpRequest request) async {
    try {
      await _handleRequest(request);
    } on SocketException {
      // Kindle 或浏览器取消下载时连接会断开，无需将服务标记为失败。
      await _closeResponseQuietly(request.response);
    } catch (_) {
      try {
        await _sendError(request, HttpStatus.internalServerError, '内部错误');
      } catch (_) {
        // 响应可能已经发送或连接已经断开，此时仅确保连接被关闭。
        await _closeResponseQuietly(request.response);
      }
    }
  }

  /// 处理单个 HTTP 请求。
  Future<void> _handleRequest(HttpRequest request) async {
    // Kindred 对旧版 Kindle 浏览器使用短连接，避免浏览器复用半关闭连接。
    request.response.persistentConnection = false;
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      request.response.headers.set('Allow', 'GET, HEAD');
      await _sendError(request, HttpStatus.methodNotAllowed, '仅支持 GET / HEAD');
      return;
    }
    final isHead = method == 'HEAD';
    final path = request.uri.path;

    if (path == '/health') {
      await _sendHealth(request, isHead);
      return;
    }
    if (path == '/favicon.ico') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.isEmpty || segments.first != _accessCode) {
      await _sendError(request, HttpStatus.notFound, '未找到资源');
      return;
    }
    final resource = segments.skip(1).toList();
    if (resource.isNotEmpty && resource.last.isEmpty) {
      resource.removeLast();
    }

    if (resource.isEmpty ||
        (resource.length == 1 && resource.first == 'index.html')) {
      final query = request.uri.queryParameters['q'] ?? '';
      await _sendIndex(request, query, isHead);
      return;
    }
    if (resource.length >= 2 && resource.first == 'books') {
      await _sendBook(request, resource.skip(1).toList(), isHead);
      return;
    }
    await _sendError(request, HttpStatus.notFound, '未找到资源');
  }

  /// 返回轻量健康检查，便于测试服务是否可用。
  Future<void> _sendHealth(HttpRequest request, bool isHead) async {
    final bytes = utf8.encode('ok');
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.text;
    request.response.headers.contentLength = bytes.length;
    request.response.headers.set('Cache-Control', 'no-store');
    if (!isHead) request.response.add(bytes);
    await request.response.close();
  }

  /// 返回书库首页（含搜索框与书籍列表）。
  Future<void> _sendIndex(
    HttpRequest request,
    String query,
    bool isHead,
  ) async {
    final bytes = utf8.encode(_indexHtml(_library.filter(query), query));
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.contentLength = bytes.length;
    request.response.headers.set('Cache-Control', 'no-cache');
    if (!isHead) request.response.add(bytes);
    await request.response.close();
  }

  /// 下载书籍文件。
  Future<void> _sendBook(
    HttpRequest request,
    List<String> pathSegments,
    bool isHead,
  ) async {
    if (pathSegments.isEmpty || pathSegments.first.isEmpty) {
      await _sendError(request, HttpStatus.notFound, '未找到书籍');
      return;
    }

    final requestedId = pathSegments.first;
    var book = _findBook(requestedId);
    // 兼容 Kindred/kaf-wifi 曾使用的 /books/{id}.{ext} 形式。
    if (book == null && pathSegments.length == 1) {
      final dot = requestedId.lastIndexOf('.');
      if (dot > 0) book = _findBook(requestedId.substring(0, dot));
    }
    if (book == null) {
      await _sendError(request, HttpStatus.notFound, '未找到书籍');
      return;
    }

    File file;
    try {
      file = _library.fileFor(book);
    } on StateError {
      await _sendError(request, HttpStatus.serviceUnavailable, '书库尚未就绪');
      return;
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      await _sendError(request, HttpStatus.notFound, '文件不存在');
      return;
    }

    final fileLength = stat.size;
    final modified = stat.modified.toUtc();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    final downloadName = KindleDownloadCompat.filename(book);
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      KindleDownloadCompat.contentType(book.format),
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(
      HttpHeaders.lastModifiedHeader,
      HttpDate.format(modified),
    );
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="$downloadName"',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    if (rangeHeader == null && _isNotModified(request, modified)) {
      request.response.statusCode = HttpStatus.notModified;
      await request.response.close();
      return;
    }

    final range = _parseSingleRange(rangeHeader, fileLength);
    if (rangeHeader != null && range == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$fileLength',
      );
      request.response.headers.contentLength = 0;
      await request.response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? (fileLength - 1);
    final contentLength = fileLength == 0 ? 0 : end - start + 1;
    request.response.headers.contentLength = contentLength;
    if (range != null) {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$fileLength',
      );
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    if (isHead || fileLength == 0) {
      await request.response.close();
      return;
    }
    await file.openRead(start, end + 1).pipe(request.response);
  }

  WifiBook? _findBook(String id) {
    for (final candidate in _library.books) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  /// 支持 kual-wifi-transfer 使用的 If-Modified-Since 条件请求。
  bool _isNotModified(HttpRequest request, DateTime modified) {
    final value = request.headers.value(HttpHeaders.ifModifiedSinceHeader);
    if (value == null ||
        request.headers.value(HttpHeaders.ifNoneMatchHeader) != null) {
      return false;
    }
    try {
      final since = HttpDate.parse(value).toUtc();
      final modifiedSeconds = modified.millisecondsSinceEpoch ~/ 1000;
      final sinceSeconds = since.millisecondsSinceEpoch ~/ 1000;
      return modifiedSeconds <= sinceSeconds;
    } on FormatException {
      return false;
    }
  }

  /// 解析单段 HTTP Range；多段 Range 为降低复杂度明确拒绝。
  _ByteRange? _parseSingleRange(String? value, int fileLength) {
    if (value == null) return null;
    if (!value.startsWith('bytes=') || value.contains(',')) return null;
    final parts = value.substring(6).split('-');
    if (parts.length != 2 || fileLength <= 0) return null;

    final startText = parts[0].trim();
    final endText = parts[1].trim();
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      final start = suffixLength >= fileLength ? 0 : fileLength - suffixLength;
      return _ByteRange(start, fileLength - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= fileLength) return null;
    final requestedEnd = endText.isEmpty
        ? fileLength - 1
        : int.tryParse(endText);
    if (requestedEnd == null || requestedEnd < start) return null;
    final end = requestedEnd >= fileLength ? fileLength - 1 : requestedEnd;
    return _ByteRange(start, end);
  }

  /// 返回 HTML 错误响应。
  Future<void> _sendError(
    HttpRequest request,
    int status,
    String message,
  ) async {
    final body =
        '<!doctype html><html><head><meta charset="utf-8"></head>'
        '<body><h1>${_escapeHtml(message)}</h1></body></html>';
    final bytes = utf8.encode(body);
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.contentLength = bytes.length;
    request.response.headers.set('Cache-Control', 'no-store');
    if (request.method.toUpperCase() != 'HEAD') request.response.add(bytes);
    await request.response.close();
  }

  /// 生成兼容 Kindle 浏览器的轻量首页 HTML。
  String _indexHtml(List<WifiBook> books, String query) {
    final rows = books
        .map((b) {
          final title = _escapeHtml(b.title);
          final details = _escapeHtml('${b.format} · ${b.formattedSize}');
          final downloadName = KindleDownloadCompat.filename(b);
          final href = Uri(
            pathSegments: <String>[
              '',
              _accessCode,
              'books',
              b.id,
              downloadName,
            ],
          ).toString();
          return '<tr><td><a href="$href">$title</a>'
              '<small>$details</small></td>'
              '<td><a href="$href" download="$downloadName">下载</a></td></tr>';
        })
        .join('\n');
    final emptyMsg = query.isEmpty ? '书库为空，请先导入书籍。' : '未找到匹配的书籍。';
    final content = rows.isEmpty
        ? '<p>${_escapeHtml(emptyMsg)}</p>'
        : '<table><tr><th>书名</th><th>操作</th></tr>$rows</table>';
    final q = _escapeHtml(query);
    final formAction = _escapeHtml(accessPath);
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>EPUB 工具箱 · 局域网传书</title>
<style>
body{font-family:Arial,sans-serif;margin:18px;color:#222;max-width:720px;margin-left:auto;margin-right:auto}
h1{font-size:22px}form{margin:16px 0}input{font-size:16px;padding:6px}
input[type=text]{width:60%}table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:10px 6px;border-bottom:1px solid #aaa}a{color:#0645ad}
small{color:#666;display:block;margin-top:2px}td:last-child{text-align:right}
</style></head><body>
<h1>EPUB 工具箱 · 局域网传书</h1>
<p>点击书名在 Kindle 浏览器中下载。</p>
<form action="$formAction" method="get">
<input type="text" name="q" value="$q"><input type="submit" value="搜索">
</form>$content
</body></html>
''';
  }

  /// 转义用户可编辑文本，防止书名破坏页面结构。
  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _resolveAccessCode(String? supplied) {
    if (supplied != null) {
      final normalized = supplied.trim().toLowerCase();
      if (!RegExp(r'^[a-z0-9]{4,32}$').hasMatch(normalized)) {
        throw ArgumentError.value(supplied, 'accessCode', '必须为 4~32 位字母或数字');
      }
      return normalized;
    }
    final random = Random.secure();
    return List<String>.generate(
      6,
      (_) => _accessCodeAlphabet[random.nextInt(_accessCodeAlphabet.length)],
      growable: false,
    ).join();
  }

  String _buildAddress(String host) {
    return Uri(
      scheme: 'http',
      host: host,
      port: _port,
      path: accessPath,
    ).toString();
  }

  /// 参考 kaf-wifi 返回全部地址，并优先 Kindred 使用的 WiFi 接口。
  Future<List<String>> _detectLocalIPv4Addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final candidates = <_AddressCandidate>[];
      final seen = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || !seen.add(addr.address)) continue;
          candidates.add(
            _AddressCandidate(
              addr.address,
              _addressRank(iface.name, addr.address),
            ),
          );
        }
      }
      candidates.sort((a, b) {
        final rank = a.rank.compareTo(b.rank);
        return rank != 0 ? rank : a.address.compareTo(b.address);
      });
      return candidates.map((candidate) => candidate.address).toList();
    } catch (_) {
      // 网络接口可能在权限弹窗或网络切换期间暂不可用，启动服务仍可继续。
      return const <String>[];
    }
  }

  int _addressRank(String interfaceName, String address) {
    final name = interfaceName.toLowerCase();
    final isWifi =
        name == 'en0' ||
        name.startsWith('wl') ||
        name.contains('wifi') ||
        name.contains('wi-fi') ||
        name.contains('wlan');
    final isWired =
        name.startsWith('eth') ||
        name.startsWith('en') ||
        name.contains('ethernet');
    final isVirtual = <String>[
      'bridge',
      'docker',
      'hamachi',
      'tap',
      'tailscale',
      'tun',
      'utun',
      'vbox',
      'veth',
      'virtual',
      'vmnet',
      'zerotier',
    ].any(name.contains);

    var rank = _isLanIPv4(address) ? 0 : 40;
    rank += isWifi ? 0 : (isWired ? 10 : 20);
    if (isVirtual) rank += 100;
    return rank;
  }

  /// 判断地址是否属于 RFC 1918 或运营商级 NAT 局域网段。
  bool _isLanIPv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  /// 仅在对象仍有效时通知 UI。
  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  /// 忽略客户端断开后重复关闭响应的异常。
  Future<void> _closeResponseQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // 响应已经关闭时无需额外处理。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_lifecycleToken;
    final server = _server;
    _server = null;
    _address = null;
    _addresses = const <String>[];
    if (server != null) unawaited(server.close(force: true));
    super.dispose();
  }
}

/// 已校验的单段字节范围（包含起止位置）。
class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}

class _AddressCandidate {
  const _AddressCandidate(this.address, this.rank);

  final String address;
  final int rank;
}
