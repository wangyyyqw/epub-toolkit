import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A run-scoped limiter for read-only sync requests, shared by all chapters.
class WereadSyncClient extends http.BaseClient {
  final http.Client _inner;
  final Duration interval;
  final Duration backoff;
  final int concurrency;
  final _waiting = Queue<Completer<void>>();
  Future<void> _starts = Future<void>.value();
  DateTime _nextStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _cooldown = DateTime.fromMillisecondsSinceEpoch(0);
  int _active = 0;
  bool _slow = false;
  bool _closed = false;
  bool syncing = false;
  String? stoppedReason;
  void Function(String message)? onThrottle;

  WereadSyncClient(
    this._inner, {
    this.interval = const Duration(milliseconds: 200),
    this.backoff = const Duration(seconds: 2),
    this.concurrency = 3,
  });

  void begin({void Function(String message)? onThrottle}) {
    if (_closed) throw StateError('读书客户端已关闭');
    if (syncing) throw StateError('已有读书同步任务正在运行');
    syncing = true;
    _slow = false;
    stoppedReason = null;
    this.onThrottle = onThrottle;
  }

  void end() {
    syncing = false;
    onThrottle = null;
  }

  void _checkOpen() {
    if (_closed) throw StateError('读书客户端已关闭');
    if (stoppedReason != null) throw WereadSyncStopped(stoppedReason!);
  }

  Future<void> _acquire() async {
    while (true) {
      _checkOpen();
      if (_active < (_slow ? 1 : concurrency)) {
        _active++;
        return;
      }
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    }
  }

  void _wake() {
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    }
  }

  Future<void> _waitToStart() {
    final turn = _starts.then((_) async {
      while (true) {
        _checkOpen();
        final now = DateTime.now();
        final ready = _nextStart.isAfter(_cooldown) ? _nextStart : _cooldown;
        if (!ready.isAfter(now)) {
          await _acquire();
          if (_closed ||
              stoppedReason != null ||
              _cooldown.isAfter(DateTime.now())) {
            _active--;
            _wake();
            _checkOpen();
            continue;
          }
          _nextStart = DateTime.now().add(_slow ? interval * 3 : interval);
          return;
        }
        // Recheck shared cooldown after every wait: another in-flight request
        // may have received a new Retry-After in the meantime.
        await Future<void>.delayed(ready.difference(now));
      }
    });
    _starts = turn.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return turn;
  }

  static bool _limited(http.Response response) {
    if (response.statusCode == 429) return true;
    try {
      final data = json.decode(response.body);
      if (data is Map) {
        final code = data['errcode'] ?? data['errCode'] ?? data['code'];
        return code.toString() == '-2014';
      }
    } catch (_) {
      // Non-JSON errors are handled by the caller's protocol parser.
    }
    return false;
  }

  Duration _retryAfter(http.Response response, int attempt) {
    final value = response.headers['retry-after'];
    if (value != null) {
      final seconds = int.tryParse(value);
      if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
      try {
        final delay = HttpDate.parse(value).difference(DateTime.now());
        if (delay > Duration.zero) return delay;
      } catch (_) {
        // Missing/invalid server advice uses bounded exponential backoff.
      }
    }
    return backoff * (1 << attempt);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw StateError('读书客户端已关闭');
    if (!syncing) return _inner.send(request);
    // Sync only sends small read-only GET/POST requests. Buffer the request
    // once so a rate-limited attempt can be replayed without re-finalizing it.
    final bytes = await request.finalize().toBytes();
    for (var attempt = 0; ; attempt++) {
      await _waitToStart();
      final abort = Completer<void>();
      try {
        final copy =
            http.AbortableRequest(
                request.method,
                request.url,
                abortTrigger: abort.future,
              )
              ..headers.addAll(request.headers)
              ..bodyBytes = bytes
              ..followRedirects = request.followRedirects
              ..maxRedirects = request.maxRedirects
              ..persistentConnection = request.persistentConnection;
        final response = await _inner
            .send(copy)
            .then(http.Response.fromStream)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                abort.complete();
                throw TimeoutException('读书请求超时', const Duration(seconds: 30));
              },
            );
        if (!_limited(response)) {
          return http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
            headers: response.headers,
            contentLength: response.bodyBytes.length,
            request: request,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
            reasonPhrase: response.reasonPhrase,
          );
        }
        _slow = true;
        final wait = _retryAfter(response, attempt);
        final until = DateTime.now().add(wait);
        if (until.isAfter(_cooldown)) _cooldown = until;
        if (attempt >= 2 || wait > const Duration(seconds: 10)) {
          stoppedReason = '平台持续限流或要求较长等待，已停止新请求并保留已获取数据，请稍后重试';
          _wake();
          throw WereadSyncStopped(stoppedReason!);
        }
        onThrottle?.call('平台限流，统一等待 ${wait.inMilliseconds}ms 后降为单请求');
      } finally {
        _active--;
        _wake();
      }
    }
  }

  @override
  void close() {
    _closed = true;
    stoppedReason = '同步已取消，客户端已关闭';
    _wake();
    _inner.close();
  }
}

class WereadSyncStopped implements Exception {
  final String message;
  WereadSyncStopped(this.message);

  @override
  String toString() => message;
}
