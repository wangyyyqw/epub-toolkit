import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 读书书目信息
class WereadBook {
  final String bookId;
  final String title;
  final String author;
  final String cover;

  WereadBook({
    required this.bookId,
    required this.title,
    required this.author,
    this.cover = '',
  });

  factory WereadBook.fromJson(Map<String, dynamic> json) {
    return WereadBook(
      bookId: json['bookId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
    );
  }

  @override
  String toString() => title.isNotEmpty ? '$title · $author' : bookId;
}

/// 读书章节信息
class WereadChapter {
  final String chapterUid;
  final String title;

  WereadChapter({required this.chapterUid, required this.title});
}

/// 划线数据
class WereadUnderline {
  final String range;
  final String markText;
  final String chapterUid;

  WereadUnderline({
    required this.range,
    required this.markText,
    this.chapterUid = '',
  });

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'range': range,
        'markText': markText,
        'chapterUid': chapterUid,
      };

  /// 从 JSON 反序列化
  factory WereadUnderline.fromJson(Map<String, dynamic> json) {
    return WereadUnderline(
      range: json['range']?.toString() ?? '',
      markText: json['markText']?.toString() ?? '',
      chapterUid: json['chapterUid']?.toString() ?? '',
    );
  }
}

/// 想法数据
///
/// [type] 区分数据来源: paragraph(段评)/chapter(章评)/book(书评)。
/// 章评/书评没有 range,范围为空字符串。
class WereadReview {
  final String range;
  final String content;
  final String abstract;
  final String author;
  final int likes;
  final String chapterUid;
  final int createTime;
  final String type;

  WereadReview({
    this.range = '',
    required this.content,
    this.abstract = '',
    this.author = '',
    this.likes = 0,
    this.chapterUid = '',
    this.createTime = 0,
    this.type = 'paragraph',
  });

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'range': range,
        'content': content,
        'abstract': abstract,
        'author': author,
        'likes': likes,
        'chapterUid': chapterUid,
        'createTime': createTime,
        'type': type,
      };

  /// 从 JSON 反序列化
  factory WereadReview.fromJson(Map<String, dynamic> json) {
    return WereadReview(
      range: json['range']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      abstract: json['abstract']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      likes: json['likes'] as int? ?? 0,
      chapterUid: json['chapterUid']?.toString() ?? '',
      createTime: json['createTime'] as int? ?? 0,
      type: json['type']?.toString() ?? 'paragraph',
    );
  }
}

/// 章节合并数据(划线 + 想法)
class ChapterData {
  final String chapterUid;
  final String title;
  final List<WereadUnderline> underlines;
  final Map<String, List<WereadReview>> reviewMap;

  /// 章评(挂在整章上,没有 range)
  final List<WereadReview> chapterReviews;

  ChapterData({
    required this.chapterUid,
    required this.title,
    required this.underlines,
    required this.reviewMap,
    this.chapterReviews = const [],
  });

  /// 是否有数据(划线或想法)
  bool get hasData =>
      underlines.isNotEmpty || reviewMap.isNotEmpty || chapterReviews.isNotEmpty;

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'chapterUid': chapterUid,
        'title': title,
        'underlines': underlines.map((u) => u.toJson()).toList(),
        'reviewMap': reviewMap.map(
          (k, v) => MapEntry(k, v.map((r) => r.toJson()).toList()),
        ),
        'chapterReviews': chapterReviews.map((r) => r.toJson()).toList(),
      };

  /// 从 JSON 反序列化
  factory ChapterData.fromJson(Map<String, dynamic> json) {
    final reviewMap = <String, List<WereadReview>>{};
    final rawMap = json['reviewMap'] as Map<String, dynamic>? ?? {};
    for (final entry in rawMap.entries) {
      final list = (entry.value as List? ?? [])
          .map((e) => WereadReview.fromJson(e as Map<String, dynamic>))
          .toList();
      reviewMap[entry.key] = list;
    }
    return ChapterData(
      chapterUid: json['chapterUid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      underlines: (json['underlines'] as List? ?? [])
          .map((e) => WereadUnderline.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviewMap: reviewMap,
      chapterReviews: (json['chapterReviews'] as List? ?? [])
          .map((e) => WereadReview.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 同步统计结果
class SyncStats {
  final int chaptersTotal;
  final int chaptersWithData;
  final int chaptersMatched;
  final int totalUnderlines;
  final int totalThoughts;
  final int injected;
  final int unmatched;
  final int dropped;
  final List<String> errors;

  SyncStats({
    this.chaptersTotal = 0,
    this.chaptersWithData = 0,
    this.chaptersMatched = 0,
    this.totalUnderlines = 0,
    this.totalThoughts = 0,
    this.injected = 0,
    this.unmatched = 0,
    this.dropped = 0,
    this.errors = const [],
  });

  @override
  String toString() =>
      '章节 $chaptersTotal | 有数据 $chaptersWithData | 匹配 $chaptersMatched | '
      '划线 $totalUnderlines | 想法 $totalThoughts | 注入 $injected | '
      '未匹配 $unmatched | 丢弃 $dropped';
}

/// 拉取结果
///
/// 包含本次拉取的全部章节数据、整本书评和远端总章节数。
class FetchResult {
  /// 有数据的章节数据
  final List<ChapterData> chapters;

  /// 远端总章节数
  final int totalChapters;

  /// 整本书评(挂在书上,没有 range)
  final List<WereadReview> bookReviews;

  FetchResult({
    required this.chapters,
    required this.totalChapters,
    this.bookReviews = const [],
  });
}

/// 读书 SKILL API 客户端
///
/// 使用 API Key 通过统一网关调用官方接口:
/// - 网关入口: POST https://i.weread.qq.com/api/agent/gateway
/// - 鉴权方式: Authorization: Bearer {API Key}
/// - 请求体: { api_name, skill_version, ...业务参数 }
///
/// 主要接口:
/// - /_list: 验证 API Key
/// - /store/search: 搜索书目
/// - /book/info: 图书详情
/// - /book/chapterinfo: 章节信息
/// - /book/bestbookmarks: 热门划线(公开)
/// - /book/bookmarklist: 个人划线
/// - /review/list/mine: 个人想法
class WereadApi {
  /// 统一网关地址
  static const _gatewayUrl = 'https://i.weread.qq.com/api/agent/gateway';

  /// API Key 申请入口
  static const apiKeyApplyUrl = 'https://weread.qq.com/r/weread-skills';

  /// 当前接口协议版本(参考 pickthought protocol.lua SKILL_VERSION)
  static const _skillVersion = '1.0.5';

  /// 最大分页拉取次数(安全阀,防止无限循环)
  static const _maxFetchPages = 50;

  /// 请求超时时间(毫秒)
  static const _timeoutMs = 30000;

  /// 最大重试次数(临时错误:408/429/500/502/503/504/网络超时)
  static const _maxRetries = 3;

  /// 本地存储键名
  static const _apiKeyPref = 'weread_api_key';
  static const _cookiesPref = 'weread_cookies';
  static const _userNamePref = 'weread_user_name';
  static const _bookIdPref = 'weread_book_id';
  static const _bookTitlePref = 'weread_book_title';

  String _apiKey = '';
  String _bookId = '';
  String _bookTitle = '';
  String _userName = '';

  /// Cookie 存储(key=cookie名, value=cookie值)
  ///
  /// 只保存持久 cookie(以 wr_ 开头的 + ptcz/RK/pgv_pvid),
  /// 参考 pickthought cookies.lua 的 is_persistent_name。
  Map<String, String> _cookies = {};

  WereadApi();

  /// 从本地存储加载 API Key、Cookie 和绑定的 bookId
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPref) ?? '';
    _bookId = prefs.getString(_bookIdPref) ?? '';
    _bookTitle = prefs.getString(_bookTitlePref) ?? '';
    _userName = prefs.getString(_userNamePref) ?? '';
    final cookiesJson = prefs.getString(_cookiesPref);
    if (cookiesJson != null && cookiesJson.isNotEmpty) {
      try {
        final decoded = json.decode(cookiesJson);
        if (decoded is Map<String, dynamic>) {
          _cookies = decoded.map((k, v) => MapEntry(k, v.toString()));
        }
      } catch (_) {}
    }
  }

  /// 保存 API Key
  Future<void> saveApiKey(String apiKey) async {
    _apiKey = apiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, _apiKey);
  }

  /// 保存 Cookie 到本地存储
  Future<void> _saveCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiesPref, json.encode(_cookies));
  }

  /// 保存登录信息(API Key + Cookie + 用户名)
  Future<void> _saveAuth({
    required String apiKey,
    required Map<String, String> cookies,
    required String userName,
  }) async {
    _apiKey = apiKey;
    _cookies = cookies;
    _userName = userName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, _apiKey);
    await prefs.setString(_cookiesPref, json.encode(_cookies));
    await prefs.setString(_userNamePref, _userName);
  }

  /// 保存绑定的书目
  Future<void> saveBook(WereadBook book) async {
    _bookId = book.bookId;
    _bookTitle = book.title;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookIdPref, _bookId);
    await prefs.setString(_bookTitlePref, _bookTitle);
  }

  /// 清除所有数据(API Key + Cookie + 绑定)
  Future<void> clear() async {
    _apiKey = '';
    _bookId = '';
    _bookTitle = '';
    _userName = '';
    _cookies = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyPref);
    await prefs.remove(_cookiesPref);
    await prefs.remove(_userNamePref);
    await prefs.remove(_bookIdPref);
    await prefs.remove(_bookTitlePref);
  }

  /// 是否已登录(Cookie 非空,有 wr_skey)
  bool get isLoggedIn => _cookies.containsKey('wr_skey');

  /// 当前绑定的 bookId
  String get bookId => _bookId;

  /// 当前绑定的书名
  String get bookTitle => _bookTitle;

  /// 当前 API Key
  String get apiKey => _apiKey;

  /// 当前用户名
  String get userName => _userName;

  /// 当前 Cookie 是否有效(有 wr_skey 和 wr_vid)
  bool get hasValidCookies =>
      _cookies.containsKey('wr_skey') && _cookies.containsKey('wr_vid');

  /// 构建 Cookie 请求头字符串
  ///
  /// 参考 pickthought cookies.lua 的 header 函数,
  /// 只输出持久 cookie(wr_ 前缀 + ptcz/RK/pgv_pvid)。
  String _cookieHeader() {
    if (_cookies.isEmpty) return '';
    final keys = _cookies.keys.where(_isPersistentCookie).toList()..sort();
    return keys.map((k) => '$k=${_cookies[k]}').join('; ');
  }

  /// 判断 cookie 名是否为持久 cookie(参考 pickthought cookies.lua is_persistent_name)
  static bool _isPersistentCookie(String name) {
    return name.startsWith('wr_') ||
        name == 'ptcz' ||
        name == 'RK' ||
        name == 'pgv_pvid';
  }

  /// 从 HTTP 响应的 set-cookie 头解析并吸收 cookie
  ///
  /// 参考 pickthought cookies.lua 的 absorb 函数。
  /// 只保存持久 cookie,忽略 session cookie。
  void _absorbCookies(http.Response response) {
    // http 包可能将多个 Set-Cookie 合并为一行,也可能保留为列表
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;

    // 按逗号分割(但要注意 expires 日期中的逗号)
    // 简化处理:按 ", " 分割,但跳过 expires= 后面的逗号
    final cookies = _parseSetCookieHeader(setCookie);
    for (final cookie in cookies) {
      final eqIdx = cookie.indexOf('=');
      if (eqIdx < 0) continue;
      final name = cookie.substring(0, eqIdx).trim();
      final value = cookie.substring(eqIdx + 1).trim();
      if (_isPersistentCookie(name) && value.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }

  /// 解析 Set-Cookie 头(简化版,处理常见的 weread cookie 格式)
  static List<String> _parseSetCookieHeader(String header) {
    // weread 的 Set-Cookie 通常以分号分隔属性,多个 cookie 以逗号分隔
    // 但 expires 字段也含逗号,需要特殊处理
    final result = <String>[];
    final parts = header.split(', ');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      // 如果以非 cookie 属性开头(expires= 除外),合并到上一个
      if (i > 0 && !part.contains('=') && result.isNotEmpty) {
        result[result.length - 1] += ', $part';
      } else if (part.contains('=')) {
        // 取等号前的部分作为 cookie 名
        final name = part.split('=')[0].trim();
        if (_isPersistentCookie(name)) {
          // 只取 cookie 的第一段(name=value),忽略后面的 path/domain 等
          final firstSemicolon = part.indexOf(';');
          result.add(firstSemicolon >= 0
              ? part.substring(0, firstSemicolon)
              : part);
        }
      }
    }
    return result;
  }

  /// 统一网关调用(含重试、超时)
  ///
  /// [apiName] 接口名称,如 /book/info
  /// [params] 业务参数(直接放在请求体顶层,与 api_name、skill_version 同级)
  ///
  /// 重试策略(参考 pickthought http.lua):
  /// - 临时状态码(408/429/500/502/503/504): 最多重试 3 次,指数退避
  /// - HTTP 499(上游超时): 最多重试 3 次
  /// - 网络异常(timeout/connection): 最多重试 3 次
  /// - HTTP 403: 不重试(鉴权错误或端点不可用,直接报错)
  /// - 其他 HTTP 错误: 不重试,直接抛出
  Future<Map<String, dynamic>> _gateway(
    String apiName, {
    Map<String, dynamic>? params,
  }) async {
    // API Key 为空时,如果有 Cookie 也可以尝试(网关可能接受 Cookie 鉴权)
    final cookie = _cookieHeader();
    if (_apiKey.isEmpty && cookie.isEmpty) {
      throw Exception('未登录:请先扫码登录');
    }

    final body = <String, dynamic>{
      'api_name': apiName,
      'skill_version': _skillVersion,
      ...?params,
    };

    final bodyJson = json.encode(body);
    Object? lastError;

    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        // 优先 Bearer Key,同时携带 Cookie(双保险)
        if (_apiKey.isNotEmpty) {
          headers['Authorization'] = 'Bearer $_apiKey';
        }
        if (cookie.isNotEmpty) {
          headers['Cookie'] = cookie;
        }

        final response = await http.post(
          Uri.parse(_gatewayUrl),
          headers: headers,
          body: bodyJson,
        ).timeout(Duration(milliseconds: _timeoutMs));

        // 临时状态码:可重试(参考 pickthought transient_status)
        if (_isTransientStatus(response.statusCode) && attempt < _maxRetries) {
          final backoff = (350 * (1 << (attempt - 1))).clamp(350, 2500);
          debugPrint('[WereadApi] HTTP ${response.statusCode} 临时错误,'
              '第 $attempt 次重试,等待 ${backoff}ms...');
          await _delay(backoff);
          continue;
        }

        // HTTP 499: 上游超时,可重试
        if (response.statusCode == 499 && attempt < _maxRetries) {
          debugPrint('[WereadApi] HTTP 499 上游超时,第 $attempt 次重试...');
          await _delay(150 * attempt);
          continue;
        }

        // HTTP 403: 鉴权错误或端点不可用,不重试
        if (response.statusCode == 403) {
          if (response.body.isEmpty) {
            throw Exception('HTTP 403: 鉴权失败或端点不可用,请检查 API Key 是否有效');
          }
          // 有 body 的 403 交给 _parseResponse 处理 errcode
        }

        return _parseResponse(response);
      } catch (e) {
        lastError = e;
        // 网络异常或超时:可重试
        if (attempt < _maxRetries && _isRetryableError(e)) {
          debugPrint('[WereadApi] 网络异常,第 $attempt 次重试: $e');
          await _delay(150 * attempt);
          continue;
        }
        rethrow;
      }
    }

    throw Exception('请求失败(已重试 $_maxRetries 次): $lastError');
  }

  /// 判断状态码是否为临时错误(参考 pickthought transient_status)
  static bool _isTransientStatus(int code) {
    return code == 408 || code == 425 || code == 429 ||
        code == 500 || code == 502 || code == 503 || code == 504;
  }

  /// 判断错误是否可重试(网络异常、超时)
  static bool _isRetryableError(Object e) {
    if (e is Exception) {
      final msg = e.toString().toLowerCase();
      // 超时、网络中断、连接重置等可重试
      return msg.contains('timeout') ||
          msg.contains('network') ||
          msg.contains('connection') ||
          msg.contains('socket') ||
          msg.contains('handshake') ||
          msg.contains('failed host lookup');
    }
    return false;
  }

  /// 延迟工具方法
  static Future<void> _delay(int ms) async {
    await Future.delayed(Duration(milliseconds: ms));
  }

  /// 解析网关响应
  ///
  /// 正常响应不一定有 errcode,只要返回业务字段即按成功处理。
  /// 错误类型(参考 weread-cli):
  /// - -2013: API Key 鉴权失败
  /// - -2014: 请求频率超限
  /// - upgrade_info: 接口需要升级
  /// - HTTP 499: 上游超时
  Map<String, dynamic> _parseResponse(http.Response response) {
    // 空响应体处理:服务端可能因速率限制或临时异常返回空 body
    if (response.body.isEmpty) {
      if (response.statusCode == 200) {
        // 200 但空响应,视为无数据,返回空 Map
        debugPrint('[WereadApi] 收到空响应(statusCode=200),返回空 Map');
        return {};
      }
      // 非 200 且空响应,给出明确的错误信息
      throw Exception('HTTP ${response.statusCode}: 服务端返回空响应');
    }

    if (response.statusCode != 200) {
      // HTTP 499: 上游超时
      if (response.statusCode == 499) {
        throw Exception('上游请求超时(HTTP 499),请稍后重试');
      }

      // 尝试解析错误体中的 errmsg,给出更友好的提示
      try {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final errcode = body['errcode'] ?? body['errCode'] ?? body['code'];
          final errmsg = body['errmsg'] ?? body['errMsg'] ?? body['message'];
          // -2014 表示请求频率超限
          if (errcode == -2014 || errcode == '-2014') {
            throw Exception('请求频率超限,请等待几秒后重试');
          }
          if (errmsg != null) {
            throw Exception('HTTP ${response.statusCode}: $errmsg');
          }
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw Exception('HTTP ${response.statusCode}: $preview');
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic>) {
      final preview = response.body.length > 100
          ? response.body.substring(0, 100)
          : response.body;
      throw Exception('接口返回格式异常: $preview');
    }

    // 检查 upgrade_info(接口需要升级)
    final upgradeInfo = data['upgrade_info'];
    if (upgradeInfo is Map<String, dynamic>) {
      final msg = upgradeInfo['message']?.toString() ??
          '接口需要升级,请更新应用后重试';
      throw Exception(msg);
    }

    // 检查错误码(网关使用 errcode 小写,兼容旧格式 errCode/code)
    final errcode = data['errcode'] ?? data['errCode'] ?? data['code'];
    if (errcode != null && errcode != 0 && errcode != '0') {
      // -2013 表示 API Key 鉴权失败
      if (errcode == -2013 || errcode == '-2013') {
        throw Exception('API Key 无效或已过期,请重新获取');
      }
      // -2014 表示请求频率超限
      if (errcode == -2014 || errcode == '-2014') {
        throw Exception('请求频率超限,请等待几秒后重试');
      }
      final msg = data['errmsg'] ?? data['errMsg'] ?? data['message'] ?? errcode;
      throw Exception('接口错误: $msg');
    }

    return data;
  }

  /// 验证 API Key 是否可用
  ///
  /// 调用 /_list 接口,成功返回空字符串,失败返回错误信息。
  Future<String> validateApiKey() async {
    try {
      await _gateway('/_list');
      return '';
    } catch (e) {
      return e.toString();
    }
  }

  // ============== QR 扫码登录流程(参考 pickthought auth.lua) ==============

  /// 获取登录 UID(第一步)
  ///
  /// 参考 pickthought auth.lua _uid 方法:
  /// 1. GET /r/weread-skills 获取初始 session cookie
  /// 2. GET /api/auth/getLoginUid 获取登录 UID
  /// 返回 QR 码确认链接: https://weread.qq.com/web/confirm?uid={uid}
  Future<String> getLoginQrUrl() async {
    final client = http.Client();
    try {
      // 1. 获取初始 session cookie
      final pageResp = await client.get(
        Uri.parse('$_webBaseUrl/r/weread-skills'),
        headers: {
          'User-Agent': _webUserAgent,
          'Accept': 'text/html,application/xhtml+xml',
          'Referer': '$_webBaseUrl/',
        },
      ).timeout(Duration(milliseconds: _timeoutMs));
      _absorbCookies(pageResp);

      // 2. 获取登录 UID
      final uidResp = await client.get(
        Uri.parse('$_webBaseUrl/api/auth/getLoginUid'),
        headers: {
          'User-Agent': _webUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Referer': '$_webBaseUrl/r/weread-skills',
          'Cookie': _cookieHeader(),
        },
      ).timeout(Duration(milliseconds: _timeoutMs));
      _absorbCookies(uidResp);

      if (uidResp.body.isEmpty) {
        throw Exception('获取登录 UID 返回空响应');
      }

      final data = json.decode(uidResp.body);
      if (data is! Map<String, dynamic>) {
        throw Exception('获取登录 UID 返回格式异常');
      }

      final uid = data['uid']?.toString();
      if (uid == null || uid.isEmpty) {
        throw Exception('登录 UID 缺失');
      }

      return '$_webBaseUrl/web/confirm?uid=$uid';
    } finally {
      client.close();
    }
  }

  /// 轮询登录状态(第二步)
  ///
  /// 参考 pickthought auth.lua _poll 方法:
  /// GET /api/auth/getLoginInfo?uid={uid}&otp
  ///
  /// 返回登录结果:
  /// - succeed == true: 登录成功,调用 finishLogin 完成登录
  /// - logicCode == "NEED_OTP": 需要验证码(暂不支持)
  /// - logicCode == "LOGIN_TIMEOUT": 二维码过期
  /// - 其他: 继续轮询
  Future<Map<String, dynamic>> pollLoginStatus(String uid) async {
    final url = Uri.parse('$_webBaseUrl/api/auth/getLoginInfo').replace(
      queryParameters: {'uid': uid, 'otp': ''},
    );

    final resp = await http.get(
      url,
      headers: {
        'User-Agent': _webUserAgent,
        'Accept': 'application/json, text/plain, */*',
        'Referer': '$_webBaseUrl/r/weread-skills',
        'Cookie': _cookieHeader(),
      },
    ).timeout(Duration(seconds: 10));
    _absorbCookies(resp);

    if (resp.body.isEmpty) {
      throw Exception('轮询登录状态返回空响应');
    }

    final data = json.decode(resp.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('轮询登录状态返回格式异常');
    }

    return data;
  }

  /// 完成登录(第三步)
  ///
  /// 参考 pickthought auth.lua _finish 方法:
  /// 1. 从登录结果提取 webLoginVid / accessToken / refreshToken
  /// 2. 设置核心 cookie: wr_vid, wr_skey, wr_rt, wr_ql
  /// 3. GET /api/userInfo 获取用户名
  /// 4. GET /api/skills/apikeyGet 获取 API Key
  /// 5. 保存到本地存储
  Future<String> finishLogin(Map<String, dynamic> loginInfo) async {
    final vid = loginInfo['webLoginVid']?.toString() ?? '';
    final skey = loginInfo['accessToken']?.toString() ?? '';
    final refresh = loginInfo['refreshToken']?.toString() ?? '';

    if (vid.isEmpty || skey.isEmpty) {
      throw Exception('登录凭据缺失(webLoginVid 或 accessToken 为空)');
    }

    // 设置核心 cookie
    _cookies['wr_vid'] = vid;
    _cookies['wr_skey'] = skey;
    _cookies['wr_ql'] = '0';
    if (refresh.isNotEmpty) {
      _cookies['wr_rt'] = Uri.encodeComponent(refresh);
    }

    final cookieStr = _cookieHeader();
    final authHeaders = {
      'User-Agent': _webUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': '$_webBaseUrl/r/weread-skills',
      'Cookie': cookieStr,
      'X-Vid': vid,
      'X-Skey': skey,
    };

    // 获取用户信息
    String userName = vid;
    try {
      final userResp = await http.get(
        Uri.parse('$_webBaseUrl/api/userInfo?userVid=$vid'),
        headers: authHeaders,
      ).timeout(Duration(milliseconds: _timeoutMs));
      _absorbCookies(userResp);
      if (userResp.body.isNotEmpty) {
        final userData = json.decode(userResp.body);
        if (userData is Map<String, dynamic>) {
          final name = userData['name']?.toString();
          if (name != null && name.isNotEmpty) userName = name;
        }
      }
    } catch (e) {
      debugPrint('[WereadApi] 获取用户信息失败: $e');
    }

    // 获取 API Key(用于网关调用)
    String apiKey = '';
    try {
      final skillResp = await http.get(
        Uri.parse('$_webBaseUrl/api/skills/apikeyGet?only_show=1'),
        headers: authHeaders,
      ).timeout(Duration(milliseconds: _timeoutMs));
      _absorbCookies(skillResp);
      if (skillResp.body.isNotEmpty) {
        final skillData = json.decode(skillResp.body);
        if (skillData is Map<String, dynamic>) {
          apiKey = skillData['apikey']?.toString() ?? '';
        }
      }
      // 如果 only_show=1 没返回 key,尝试不带参数(会创建 key)
      if (apiKey.isEmpty) {
        final skillResp2 = await http.get(
          Uri.parse('$_webBaseUrl/api/skills/apikeyGet'),
          headers: authHeaders,
        ).timeout(Duration(milliseconds: _timeoutMs));
        _absorbCookies(skillResp2);
        if (skillResp2.body.isNotEmpty) {
          final skillData2 = json.decode(skillResp2.body);
          if (skillData2 is Map<String, dynamic>) {
            apiKey = skillData2['apikey']?.toString() ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint('[WereadApi] 获取 API Key 失败: $e');
    }

    // 保存登录信息
    await _saveAuth(
      apiKey: apiKey,
      cookies: Map<String, String>.from(_cookies),
      userName: userName,
    );

    debugPrint('[WereadApi] 登录完成: 用户=$userName, '
        'apiKey=${apiKey.isNotEmpty ? "已获取" : "未获取"}, '
        'cookies=${_cookies.keys.toList()}');

    return userName;
  }

  /// 从 QR 码 URL 中提取 uid
  static String? extractUidFromQrUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['uid'];
  }

  /// 微信读书 Web 端基准 URL
  static const _webBaseUrl = 'https://weread.qq.com';

  /// Web 端 User-Agent(与 pickthought protocol.lua 一致,模拟 Edge 浏览器)
  static const _webUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0';

  /// 混淆 bookId,生成 reader URL 路径(参考 pickthought protocol.lua obfuscate)
  ///
  /// [value] bookId 字符串
  /// 返回混淆后的字符串,用于构造 reader URL 作为 Referer
  static String _obfuscate(String value) {
    final s = value;
    final digest = md5.convert(utf8.encode(s)).toString();
    final chunks = <String>[];
    String kind;

    if (RegExp(r'^\d+$').hasMatch(s)) {
      // 纯数字:每 9 位一组,转 hex
      kind = '3';
      for (var i = 0; i < s.length; i += 9) {
        final end = i + 9 < s.length ? i + 9 : s.length;
        final num = int.parse(s.substring(i, end));
        chunks.add(num.toRadixString(16));
      }
    } else {
      // 非数字:逐字符转 hex
      kind = '4';
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        buf.write(s.codeUnitAt(i).toRadixString(16));
      }
      chunks.add(buf.toString());
    }

    var out =
        '${digest.substring(0, 3)}$kind' + '2${digest.substring(digest.length - 2)}';
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      out += c.length.toRadixString(16).padLeft(2, '0') + c;
      if (i < chunks.length - 1) out += 'g';
    }
    if (out.length < 20) {
      out += digest.substring(0, 20 - out.length);
    }
    final outDigest = md5.convert(utf8.encode(out)).toString();
    return out + outDigest.substring(0, 3);
  }

  /// 生成 reader URL(参考 pickthought protocol.lua reader_url)
  ///
  /// 用于 Web 端请求的 Referer 头,格式: https://weread.qq.com/web/reader/{obfuscated}
  static String _readerUrl(String bookId) {
    return '$_webBaseUrl/web/reader/${_obfuscate(bookId)}';
  }

  /// Web 端搜索(参考 pickthought.koplugin 的 web_search)
  ///
  /// Web 搜索使用 Cookie 鉴权(参考 pickthought _web_call)。
  Future<Map<String, dynamic>> _webSearch(
    String keyword, {
    int maxIdx = 0,
    int count = 30,
  }) async {
    final url = Uri.parse('$_webBaseUrl/web/search/global').replace(
      queryParameters: {
        'keyword': keyword,
        'maxIdx': maxIdx.toString(),
        'count': count.toString(),
        'fragmentSize': '120',
      },
    );

    final headers = {
      'User-Agent': _webUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': '$_webBaseUrl/',
    };
    final cookie = _cookieHeader();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await http.get(
      url,
      headers: headers,
    ).timeout(Duration(milliseconds: _timeoutMs));

    if (response.body.isEmpty) {
      throw Exception('Web 搜索返回空响应');
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Web 搜索返回格式异常');
    }

    // 检查错误码
    final errcode = data['errCode'] ?? data['errcode'] ?? data['code'];
    if (errcode != null && errcode != 0 && errcode != '0') {
      throw Exception('Web 搜索错误: ${data['errMsg'] ?? data['errmsg'] ?? errcode}');
    }

    return data;
  }

  /// Web 端章节列表(参考 pickthought.koplugin 的 web_chapters)
  ///
  /// 网关 /book/chapterinfo 对 Bearer key 返回 403,改用 Web 端点。
  /// Referer 必须使用 reader_url(混淆 bookId),否则可能被拒。
  /// 响应结构: {data: [{bookId, updated: [{chapterUid, title}, ...]}]}
  Future<Map<String, dynamic>> _webChapters(String bookId) async {
    final referer = _readerUrl(bookId);
    final headers = {
      'User-Agent': _webUserAgent,
      'Content-Type': 'application/json;charset=UTF-8',
      'Accept': 'application/json, text/plain, */*',
      'Origin': _webBaseUrl,
      'Referer': referer,
    };
    final cookie = _cookieHeader();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await http.post(
      Uri.parse('$_webBaseUrl/web/book/chapterInfos'),
      headers: headers,
      body: json.encode({'bookIds': [bookId]}),
    ).timeout(Duration(milliseconds: _timeoutMs));

    debugPrint('[WereadApi] _webChapters statusCode=${response.statusCode}, '
        'bodyLength=${response.body.length}, '
        'referer=$referer');

    if (response.body.isEmpty) {
      throw Exception('Web 章节列表返回空响应(statusCode=${response.statusCode})');
    }

    // 检测 HTML 响应(未登录时可能重定向到登录页)
    final bodyTrimmed = response.body.trim();
    if (bodyTrimmed.startsWith('<') || bodyTrimmed.toLowerCase().startsWith('<!doctype')) {
      final preview = bodyTrimmed.length > 200 ? bodyTrimmed.substring(0, 200) : bodyTrimmed;
      throw Exception('Web 章节列表返回 HTML(可能需要登录): $preview');
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw Exception('Web 章节列表 JSON 解析失败: $preview');
    }

    // 检查错误码(Web 端点可能返回登录错误)
    final errcode = data['errCode'] ?? data['errcode'] ?? data['code'];
    if (errcode != null && errcode != 0 && errcode != '0') {
      final errmsg = data['errMsg'] ?? data['errmsg'] ?? data['message'] ?? errcode;
      throw Exception('Web 章节列表错误($errcode): $errmsg');
    }

    return data;
  }

  /// Web 端热门划线(参考 pickthought api.lua web_bestbookmarks)
  ///
  /// 一次拉取整本全部热门划线,按 chapterUid 分组。
  /// Cookie 鉴权,Referer 必须使用 reader_url。
  /// 响应结构: {data: {items: [{chapterUid, range, markText, ...}]}} 或类似。
  Future<Map<String, dynamic>> _webBestbookmarks(String bookId) async {
    final referer = _readerUrl(bookId);
    final url = Uri.parse('$_webBaseUrl/web/book/bestbookmarks').replace(
      queryParameters: {
        'bookId': bookId,
        'count': '2000',
        'synckey': '0',
      },
    );

    final headers = {
      'User-Agent': _webUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': referer,
    };
    final cookie = _cookieHeader();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await http.get(
      url,
      headers: headers,
    ).timeout(Duration(milliseconds: _timeoutMs));

    debugPrint('[WereadApi] _webBestbookmarks statusCode=${response.statusCode}, '
        'bodyLength=${response.body.length}');

    if (response.body.isEmpty) {
      throw Exception('Web 热门划线返回空响应(statusCode=${response.statusCode})');
    }

    // 检测 HTML 响应(未登录时可能重定向到登录页)
    final bodyTrimmed = response.body.trim();
    if (bodyTrimmed.startsWith('<') ||
        bodyTrimmed.toLowerCase().startsWith('<!doctype')) {
      throw Exception('Web 热门划线返回 HTML(可能需要登录)');
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw Exception('Web 热门划线 JSON 解析失败: $preview');
    }

    // 检查错误码
    final errcode = data['errCode'] ?? data['errcode'] ?? data['code'];
    if (errcode != null && errcode != 0 && errcode != '0') {
      final errmsg =
          data['errMsg'] ?? data['errmsg'] ?? data['message'] ?? errcode;
      throw Exception('Web 热门划线错误($errcode): $errmsg');
    }

    return data;
  }

  /// Web 端章节想法(参考 pickthought api.lua web_chapter_reviews)
  ///
  /// 获取指定章节的公开想法,Cookie 鉴权。
  /// 响应结构: {reviews: [{range, review: {content, abstract, author, ...}, ...}]}
  Future<Map<String, dynamic>> _webChapterReviews(
    String bookId,
    String chapterUid,
  ) async {
    final referer = _readerUrl(bookId);
    final url = Uri.parse('$_webBaseUrl/web/review/list').replace(
      queryParameters: {
        'bookId': bookId,
        'chapterUid': chapterUid,
        'listType': '8',
        'maxIdx': '0',
        'count': '100',
        'listMode': '3',
        'synckey': '0',
      },
    );

    final headers = {
      'User-Agent': _webUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': referer,
    };
    final cookie = _cookieHeader();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    final response = await http.get(
      url,
      headers: headers,
    ).timeout(Duration(milliseconds: _timeoutMs));

    debugPrint('[WereadApi] _webChapterReviews statusCode=${response.statusCode}, '
        'bodyLength=${response.body.length}, chapter=$chapterUid');

    if (response.body.isEmpty) {
      throw Exception('Web 章节想法返回空响应(statusCode=${response.statusCode})');
    }

    // 检测 HTML 响应
    final bodyTrimmed = response.body.trim();
    if (bodyTrimmed.startsWith('<') ||
        bodyTrimmed.toLowerCase().startsWith('<!doctype')) {
      throw Exception('Web 章节想法返回 HTML(可能需要登录)');
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw Exception('Web 章节想法 JSON 解析失败: $preview');
    }

    // 检查错误码
    final errcode = data['errCode'] ?? data['errcode'] ?? data['code'];
    if (errcode != null && errcode != 0 && errcode != '0') {
      final errmsg =
          data['errMsg'] ?? data['errmsg'] ?? data['message'] ?? errcode;
      throw Exception('Web 章节想法错误($errcode): $errmsg');
    }

    return data;
  }

  /// 搜索书目
  ///
  /// [keyword] 搜索关键词
  /// [scope] 搜索范围(参考 weread-cli): all|book|fiction|audio|author|fulltext
  ///         默认 book(仅电子书)
  /// [count] 每页数量,默认不传(由服务端决定)
  /// [maxIdx] 分页偏移量(从上次结果的 searchIdx 继续)
  /// [onDebug] 调试回调,接收原始响应 JSON 字符串
  /// 返回匹配的书目列表
  ///
  /// 策略(参考 pickthought.koplugin):
  /// 1. 优先用 Web 端点(weread.qq.com/web/search/global),避免网关 403
  /// 2. Web 失败时回退到网关 /store/search
  Future<List<WereadBook>> search(
    String keyword, {
    String scope = 'book',
    int? count,
    int? maxIdx,
    void Function(String)? onDebug,
  }) async {
    Map<String, dynamic> data;

    // 1. 优先 Web 端点(避免网关 403)
    try {
      data = await _webSearch(
        keyword,
        maxIdx: maxIdx ?? 0,
        count: count ?? 30,
      );
      debugPrint('[WereadApi] search via web endpoint succeeded');
    } catch (webErr) {
      debugPrint('[WereadApi] web search failed: $webErr, falling back to gateway');
      // 2. 回退到网关
      final params = <String, dynamic>{
        'keyword': keyword,
        'scope': _scopeValue(scope),
      };
      if (count != null) params['count'] = count;
      if (maxIdx != null) params['maxIdx'] = maxIdx;
      data = await _gateway('/store/search', params: params);
    }

    // 调试:输出原始响应
    final rawJson = json.encode(data);
    debugPrint('[WereadApi] search("$keyword", scope=$scope) response keys: ${data.keys.toList()}');
    debugPrint('[WereadApi] search response: ${rawJson.length > 800 ? rawJson.substring(0, 800) : rawJson}');
    if (onDebug != null) {
      onDebug(rawJson.length > 800 ? '${rawJson.substring(0, 800)}...' : rawJson);
    }

    final books = <WereadBook>[];

    // 响应结构兼容多种格式:
    // 1. results[].books[].bookInfo  (实际搜索接口返回的格式)
    // 2. books[] 直接在顶层
    // 3. data.books[] 在 data 下
    // 4. data 本身是列表
    final results = data['results'];
    if (results is List) {
      // 格式: {results: [{title: "电子书", books: [{bookInfo: {...}}]}]}
      for (final group in results) {
        if (group is Map<String, dynamic>) {
          final groupBooks = group['books'];
          if (groupBooks is List) {
            for (final item in groupBooks) {
              if (item is Map<String, dynamic>) {
                final bookInfo = item['bookInfo'] ?? item;
                if (bookInfo is Map<String, dynamic>) {
                  final book = WereadBook.fromJson(bookInfo);
                  if (book.bookId.isNotEmpty) books.add(book);
                }
              }
            }
          }
        }
      }
    }

    if (books.isEmpty) {
      // 降级:尝试其他可能的结构
      dynamic booksData = data['books'];
      if (booksData == null) {
        final d = data['data'];
        if (d is Map) {
          booksData = d['books'];
        } else if (d is List) {
          booksData = d;
        }
      }

      if (booksData is List) {
        for (final item in booksData) {
          if (item is Map<String, dynamic>) {
            final bookInfo = item['bookInfo'] ?? item;
            if (bookInfo is Map<String, dynamic>) {
              final book = WereadBook.fromJson(bookInfo);
              if (book.bookId.isNotEmpty) books.add(book);
            }
          }
        }
      }
    }

    debugPrint('[WereadApi] search found ${books.length} books');
    return books;
  }

  /// 将 scope 字符串映射为数字值(参考 weread-cli 的 scopeValue)
  ///
  /// 支持: all(0), book(10), fiction(1), audio(2), author(3),
  ///       fulltext(4), list(5), mp(6), article(7)
  static int _scopeValue(String scope) {
    const map = <String, int>{
      'all': 0,
      'book': 10,
      'fiction': 1,
      'audio': 2,
      'author': 3,
      'fulltext': 4,
      'list': 5,
      'mp': 6,
      'article': 7,
    };
    // 如果传入的是数字字符串,直接解析
    final num = int.tryParse(scope);
    if (num != null) return num;
    return map[scope.toLowerCase()] ?? 10; // 默认 book
  }

  /// 获取章节列表
  ///
  /// [bookId] 读书书 ID
  /// 返回章节列表(按顺序)
  ///
  /// 策略(参考 pickthought.koplugin):
  /// 1. 优先用 Web 端点(weread.qq.com/web/book/chapterInfos),避免网关 403
  /// 2. Web 失败时回退到网关 /book/chapterinfo
  /// 3. 两者均失败时,输出合并的错误信息(便于排查)
  Future<List<WereadChapter>> chapters(String bookId) async {
    Map<String, dynamic> data;
    bool usedWeb = false;
    String? webError;

    // 1. 优先 Web 端点(避免网关 403)
    try {
      data = await _webChapters(bookId);
      usedWeb = true;
      final rawJson = json.encode(data);
      debugPrint('[WereadApi] chapters via web endpoint succeeded, '
          'keys=${data.keys.toList()}, '
          'body=${rawJson.length > 500 ? rawJson.substring(0, 500) : rawJson}');
    } catch (webErr) {
      webError = webErr.toString();
      debugPrint('[WereadApi] web chapters failed: $webErr, falling back to gateway');
      // 2. 回退到网关
      try {
        data = await _gateway('/book/chapterinfo', params: {
          'bookId': bookId,
        });
        final rawJson = json.encode(data);
        debugPrint('[WereadApi] chapters via gateway, '
            'keys=${data.keys.toList()}, '
            'body=${rawJson.length > 500 ? rawJson.substring(0, 500) : rawJson}');
      } catch (gwErr) {
        // 3. 两者均失败:输出合并错误
        debugPrint('[WereadApi] gateway chapters also failed: $gwErr');
        throw Exception(
          '获取章节列表失败(Web: $webError | 网关: $gwErr)'
        );
      }
    }

    final chapters = <WereadChapter>[];

    // 兼容多种响应结构:
    // Web 端点: {data: [{bookId, updated: [{chapterUid, title}, ...]}]}
    // 网关: {chapters: [...]} 或 {data: {chapters: [...]}}
    dynamic chapterList = data['chapters'];
    if (chapterList == null) {
      final d = data['data'];
      if (d is List) {
        // Web 端点: data 是数组,每个元素含 updated 字段
        for (final item in d) {
          if (item is Map<String, dynamic>) {
            final updated = item['updated'];
            if (updated is List) {
              chapterList = updated;
              break;
            }
          }
        }
        if (chapterList == null) chapterList = d;
      } else if (d is Map) {
        chapterList = d['chapters'] ?? d['updated'];
      }
    }

    if (chapterList is List) {
      for (final ch in chapterList) {
        if (ch is Map<String, dynamic>) {
          chapters.add(WereadChapter(
            chapterUid: ch['chapterUid']?.toString() ?? '',
            title: ch['title']?.toString() ?? '',
          ));
        }
      }
    }

    if (chapters.isEmpty) {
      // 解析后为空:输出原始数据摘要,帮助排查
      final rawJson = json.encode(data);
      final preview = rawJson.length > 300 ? rawJson.substring(0, 300) : rawJson;
      throw Exception('章节列表解析为空(来源=${usedWeb ? "Web" : "网关"}, '
          'keys=${data.keys.toList()}, data=$preview)');
    }

    return chapters;
  }

  /// 获取单章全部划线(不限热度)
  ///
  /// [bookId] 读书书 ID
  /// [chapterUid] 章节 UID
  ///
  /// 与 bestBookmarks(整本热门 top N)不同,此接口按章返回该章**全部**划线,
  /// 是 pickthought.koplugin 使用的核心数据源,覆盖范围远大于 bestBookmarks。
  ///
  /// 注意:chapterUid 必须传整数,网关对类型敏感(参考 pickthought 的 unique_candidates)。
  Future<List<WereadUnderline>> underlines(
    String bookId,
    String chapterUid,
  ) async {
    final chapterUidInt = int.tryParse(chapterUid);
    final params = <String, dynamic>{
      'bookId': bookId,
      'chapterUid': chapterUidInt ?? chapterUid,
    };

    final data = await _gateway('/book/underlines', params: params);

    final result = <WereadUnderline>[];

    // 兼容多种响应结构:underlines / updated / bookmarks / 直接数组
    dynamic items = data['underlines'];
    items ??= data['updated'];
    items ??= data['bookmarks'];
    if (items == null) {
      final d = data['data'];
      if (d is Map) {
        items = d['underlines'] ?? d['updated'] ?? d['bookmarks'];
      } else if (d is List) {
        items = d;
      }
    }

    if (items is List) {
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final range = item['range']?.toString() ??
              item['markRange']?.toString() ??
              '';
          if (range.isNotEmpty) {
            result.add(WereadUnderline(
              range: range,
              // /book/underlines 不返回 markText,用空字符串占位
              // 后续由 readreviews 返回的 abstract 填充
              markText: item['markText']?.toString() ??
                  item['mark_text']?.toString() ??
                  '',
              chapterUid: chapterUid,
            ));
          }
        }
      }
    }

    debugPrint('[WereadApi] underlines: chapter=$chapterUid, ${result.length} items');
    return result;
  }

  /// 获取指定 range 的全部公开想法
  ///
  /// [bookId] 读书书 ID
  /// [chapterUid] 章节 UID
  /// [batch] range 批次,格式为 [{range, maxIdx, count, synckey}, ...]
  ///
  /// 此接口按 range 返回该段的**全部公开想法**(每 range 最多 count 条),
  /// 远比 /review/list/mine(仅个人想法)和 /review/list(章级热门前几条)完整。
  ///
  /// 注意:chapterUid 必须传整数,网关对类型敏感(参考 pickthought 的 unique_candidates)。
  Future<List<WereadReview>> readreviews(
    String bookId,
    String chapterUid,
    List<Map<String, dynamic>> batch, {
    void Function(String)? onDebug,
  }) async {
    final chapterUidInt = int.tryParse(chapterUid);
    final data = await _gateway('/book/readreviews', params: {
      'bookId': bookId,
      'chapterUid': chapterUidInt ?? chapterUid,
      'reviews': batch,
    });

    // 调试:输出原始响应(仅第一次调用)
    if (onDebug != null) {
      final rawJson = json.encode(data);
      onDebug(rawJson.length > 800 ? '${rawJson.substring(0, 800)}...' : rawJson);
    }

    final result = <WereadReview>[];

    // 响应结构: {reviews: [{review: {...}, pageReviews: [{review: {...}}], ...}]}
    // 兼容扁平结构: {reviews: [{range, content, ...}]}
    dynamic reviewList = data['reviews'];
    if (reviewList == null) {
      final d = data['data'];
      if (d is Map) {
        reviewList = d['reviews'];
      } else if (d is List) {
        reviewList = d;
      }
    }

    debugPrint('[WereadApi] readreviews: chapter=$chapterUid, '
        'batch=${batch.length} ranges, '
        'response reviews=${reviewList is List ? reviewList.length : 0}');

    if (reviewList is List) {
      for (final item in reviewList) {
        if (item is! Map<String, dynamic>) continue;

        // 提取 range
        final range = item['range']?.toString() ??
            (item['review'] is Map
                ? item['review']['range']?.toString() ?? ''
                : '');

        // pageReviews 结构:一个 range 对应多条想法
        final pageReviews = item['pageReviews'];
        if (pageReviews is List) {
          for (final pr in pageReviews) {
            if (pr is! Map<String, dynamic>) continue;
            final thought = pr['review'] is Map ? pr['review'] as Map<String, dynamic> : pr;
            final content = thought['content']?.toString() ?? '';
            if (content.isNotEmpty && range.isNotEmpty) {
              final author = thought['author'];
              result.add(WereadReview(
                range: range,
                content: content,
                abstract: _cleanQuote(thought['abstract']?.toString() ??
                    thought['contextAbstract']?.toString() ?? ''),
                author: author is Map
                    ? (author['name']?.toString() ?? author['nick']?.toString() ?? '')
                    : '',
                // likesCount 可能是 int 或 double,安全转换
                likes: _safeInt(pr['likesCount'] ?? thought['likesCount'] ?? 0),
                chapterUid: chapterUid,
              ));
            }
          }
        } else {
          // 扁平结构:直接在 item 上
          final review = item['review'] is Map ? item['review'] as Map<String, dynamic> : item;
          final content = review['content']?.toString() ?? '';
          if (content.isNotEmpty && range.isNotEmpty) {
            result.add(WereadReview(
              range: range,
              content: content,
              abstract: _cleanQuote(review['abstract']?.toString() ??
                  review['contextAbstract']?.toString() ?? ''),
              chapterUid: chapterUid,
            ));
          }
        }
      }
    }

    return result;
  }

  /// 安全转换为 int(兼容 int / double / String)
  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 清理想法引文中的排版占位符
  ///
  /// [插图] 等占位符不在正文中出现,保留会破坏引文对齐。
  static String _cleanQuote(String text) {
    return text.replaceAll('[插图]', '');
  }

  /// 将 range 列表分批,供 readreviews 使用
  ///
  /// [ranges] range 列表
  /// [batchSize] 每批数量,默认 5(参考 pickthought)
  static List<List<Map<String, dynamic>>> reviewBatches(
    List<String> ranges, {
    int batchSize = 5,
  }) {
    final batches = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < ranges.length; i += batchSize) {
      final batch = <Map<String, dynamic>>[];
      for (var j = i; j < i + batchSize && j < ranges.length; j++) {
        batch.add({
          'range': ranges[j],
          'maxIdx': 0,
          'count': 30,
          'synckey': 0,
        });
      }
      batches.add(batch);
    }
    return batches;
  }

  /// 解析章评/书评接口响应,提取想法列表
  ///
  /// 响应结构兼容:
  /// - {reviews: [{review: {content, abstract, author, ...}, likesCount, ...}]}
  /// - {reviews: [{content, abstract, ...}]} (扁平)
  /// - {data: {reviews: [...]}}
  List<WereadReview> _parseReviewList(
    Map<String, dynamic> data,
    String chapterUid,
    String type,
  ) {
    dynamic reviewList = data['reviews'];
    if (reviewList == null) {
      final d = data['data'];
      if (d is Map) {
        reviewList = d['reviews'];
      } else if (d is List) {
        reviewList = d;
      }
    }

    final result = <WereadReview>[];
    if (reviewList is List) {
      for (final item in reviewList) {
        if (item is! Map<String, dynamic>) continue;
        final wrapper = item;
        final review = item['review'] is Map
            ? item['review'] as Map<String, dynamic>
            : item;
        final content = review['content']?.toString() ?? '';
        if (content.isEmpty) continue;
        final author = review['author'];
        result.add(WereadReview(
          range: '',
          content: content,
          abstract: _cleanQuote(review['abstract']?.toString() ??
              review['contextAbstract']?.toString() ?? ''),
          author: author is Map
              ? (author['name']?.toString() ??
                  author['nick']?.toString() ??
                  '')
              : '',
          likes: _safeInt(wrapper['likesCount'] ?? review['likesCount'] ?? 0),
          chapterUid: chapterUid,
          createTime: _safeInt(review['createTime'] ?? 0),
          type: type,
        ));
      }
    }

    debugPrint('[WereadApi] _parseReviewList($type): ${result.length} reviews');
    return result;
  }

  /// 获取单章章评(整章范围,不针对特定段落)
  ///
  /// [bookId] 读书书 ID
  /// [chapterUid] 章节 UID
  /// [pages] 最多拉取页数(每页 20 条)
  ///
  /// 注意:chapterUid 必须传整数,网关对类型敏感。
  /// 接口失败时抛出异常(由调用方决定是否降级)。
  Future<List<WereadReview>> chapterReviews(
    String bookId,
    String chapterUid, {
    int pages = 2,
  }) async {
    final chapterUidInt = int.tryParse(chapterUid);
    final result = <WereadReview>[];
    var cursor = 0;
    var fetched = 0;
    var hasMore = true;

    while (hasMore && fetched < pages) {
      final data = await _gateway('/book/chapterreviewlist', params: {
        'bookId': bookId,
        'chapterUid': chapterUidInt ?? chapterUid,
        'count': 20,
        'maxIdx': cursor,
      });
      final reviews = _parseReviewList(data, chapterUid, 'chapter');
      result.addAll(reviews);
      fetched++;

      final next = _safeInt(data['maxIdx'] ?? 0);
      hasMore = (data['hasMore'] == true) && next > cursor && next > 0;
      cursor = next;
      if (hasMore) await _delay(150);
    }

    debugPrint('[WereadApi] chapterReviews: chapter=$chapterUid, '
        '${result.length} reviews');
    return result;
  }

  /// 获取整本书评(挂在书上的公开评论)
  ///
  /// [bookId] 读书书 ID
  /// [category] 书评分类: 0=热门, 1=推荐, 3=最新, 4=一般, 2=不推荐, 8=资深读者
  /// [pages] 最多拉取页数(每页 100 条)
  ///
  /// 接口失败时抛出异常(由调用方决定是否降级)。
  Future<List<WereadReview>> bookReviews(
    String bookId, {
    int category = 0,
    int pages = 2,
  }) async {
    final result = <WereadReview>[];
    var cursor = 0;
    var fetched = 0;
    var hasMore = true;

    while (hasMore && fetched < pages) {
      final data = await _gateway('/book/podcasts', params: {
        'bookId': bookId,
        'count': 100,
        'listType': 2,
        'reviewListType': category,
        'synckey': cursor,
      });
      final reviews = _parseReviewList(data, '', 'book');
      result.addAll(reviews);
      fetched++;

      final next = _safeInt(data['synckey'] ?? 0);
      hasMore = (data['reviewsHasMore'] == true) && next > cursor && next > 0;
      cursor = next;
      if (hasMore) await _delay(200);
    }

    debugPrint('[WereadApi] bookReviews: category=$category, '
        '${result.length} reviews');
    return result;
  }

  /// 解析 Web bestbookmarks 响应,提取划线列表
  ///
  /// 响应结构兼容多种格式:
  /// - {data: {items: [{chapterUid, range, markText, ...}]}}
  /// - {items: [...]}
  /// - {data: [...]}
  /// - {bookmarks: [...]}
  List<WereadUnderline> _parseBestbookmarks(
    Map<String, dynamic> data,
    String defaultChapterUid,
  ) {
    dynamic items = data['items'];
    if (items == null) {
      final d = data['data'];
      if (d is Map) {
        items = d['items'] ?? d['bookmarks'] ?? d['underlines'];
      } else if (d is List) {
        items = d;
      }
    }
    items ??= data['bookmarks'] ?? data['underlines'];

    final result = <WereadUnderline>[];
    if (items is List) {
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final range = item['range']?.toString() ??
            item['markRange']?.toString() ??
            '';
        if (range.isEmpty) continue;
        final chapterUid = item['chapterUid']?.toString() ?? defaultChapterUid;
        final markText = item['markText']?.toString() ??
            item['bookmarkText']?.toString() ??
            '';
        result.add(WereadUnderline(
          range: range,
          markText: markText,
          chapterUid: chapterUid,
        ));
      }
    }

    debugPrint('[WereadApi] _parseBestbookmarks: ${result.length} items');
    return result;
  }

  /// 解析 Web chapter reviews 响应,提取想法列表
  ///
  /// 响应结构兼容:
  /// - {reviews: [{range, review: {content, abstract, author, ...}, ...}]}
  /// - {data: {reviews: [...]}}
  List<WereadReview> _parseWebReviews(
    Map<String, dynamic> data,
    String chapterUid,
  ) {
    dynamic reviewList = data['reviews'];
    if (reviewList == null) {
      final d = data['data'];
      if (d is Map) {
        reviewList = d['reviews'];
      } else if (d is List) {
        reviewList = d;
      }
    }

    final result = <WereadReview>[];
    if (reviewList is List) {
      for (final item in reviewList) {
        if (item is! Map<String, dynamic>) continue;

        // 提取 range
        final range = item['range']?.toString() ??
            (item['review'] is Map
                ? item['review']['range']?.toString() ?? ''
                : '');

        // pageReviews 结构:一个 range 对应多条想法
        final pageReviews = item['pageReviews'];
        if (pageReviews is List) {
          for (final pr in pageReviews) {
            if (pr is! Map<String, dynamic>) continue;
            final thought = pr['review'] is Map
                ? pr['review'] as Map<String, dynamic>
                : pr;
            final content = thought['content']?.toString() ?? '';
            if (content.isNotEmpty && range.isNotEmpty) {
              final author = thought['author'];
              result.add(WereadReview(
                range: range,
                content: content,
                abstract: _cleanQuote(thought['abstract']?.toString() ??
                    thought['contextAbstract']?.toString() ?? ''),
                author: author is Map
                    ? (author['name']?.toString() ??
                        author['nick']?.toString() ??
                        '')
                    : '',
                likes: _safeInt(pr['likesCount'] ?? thought['likesCount'] ?? 0),
                chapterUid: chapterUid,
              ));
            }
          }
        } else {
          // 扁平结构:直接在 item 上
          final review = item['review'] is Map
              ? item['review'] as Map<String, dynamic>
              : item;
          final content = review['content']?.toString() ?? '';
          if (content.isNotEmpty && range.isNotEmpty) {
            final author = review['author'];
            result.add(WereadReview(
              range: range,
              content: content,
              abstract: _cleanQuote(review['abstract']?.toString() ??
                  review['contextAbstract']?.toString() ?? ''),
              author: author is Map
                  ? (author['name']?.toString() ??
                      author['nick']?.toString() ??
                      '')
                  : '',
              chapterUid: chapterUid,
            ));
          }
        }
      }
    }

    debugPrint('[WereadApi] _parseWebReviews: ${result.length} reviews');
    return result;
  }

  /// 拉取整本书的划线与公开想法数据
  ///
  /// 策略(参考 pickthought.koplugin,Web 端点优先 + 网关回退):
  /// a. 获取章节列表(Web 优先,网关回退)
  /// b. 划线:先尝试 Web bestbookmarks(整本一次拉取),失败则逐章网关 underlines
  /// c. 想法:先尝试 Web review/list(按章),失败则网关 readreviews(按 range 批量)
  /// d. 章评/书评:逐章网关 chapterreviewlist + 整本一次网关 podcasts(失败不影响主线)
  /// e. 用想法的 abstract 填充划线的 markText
  /// f. 想法有自己的 range:没有对应划线时补一条划线
  /// g. 合并到章节
  ///
  /// [onProgress] 进度回调 (phase, current, total, text)
  /// [includeChapterReviews] 是否拉取章评(默认拉取)
  /// [includeBookReviews] 是否拉取书评(默认拉取)
  Future<FetchResult> fetchBookData(
    String bookId, {
    void Function(String phase, int current, int total, String text)?
        onProgress,
    bool includeChapterReviews = true,
    bool includeBookReviews = true,
  }) async {
    onProgress ??= (_, _, _, _) {};

    // 1. 获取章节列表
    onProgress('chapters', 0, 1, '获取章节列表');
    final chapterList = await chapters(bookId);
    if (chapterList.isEmpty) {
      throw Exception('返回的章节列表为空');
    }
    onProgress('chapters', 1, 1, '共 ${chapterList.length} 章');

    final allUnderlines = <WereadUnderline>[];
    final hotReviews = <WereadReview>[];

    // 2. 划线数据源
    //
    // a. 整本 Web bestbookmarks:热门划线(带原文 markText)。
    //    /book/underlines 不返回 markText(划线原文),bestbookmarks 的 markText
    //    作为引文词典填充,同时作为逐章拉取失败时的兜底数据。
    onProgress('underlines', 0, chapterList.length, '拉取划线');
    final bestmarksByChapter = <String, List<WereadUnderline>>{};
    final markTextByRange = <String, String>{};
    try {
      final bmData = await _webBestbookmarks(bookId);
      final bmUnderlines = _parseBestbookmarks(bmData, '');
      for (final u in bmUnderlines) {
        if (u.markText.isNotEmpty && !markTextByRange.containsKey(u.range)) {
          markTextByRange[u.range] = u.markText;
        }
        bestmarksByChapter.putIfAbsent(u.chapterUid, () => []).add(u);
      }
      debugPrint('[WereadApi] Web bestbookmarks 成功: ${bmUnderlines.length} 条热门划线');
    } catch (e) {
      debugPrint('[WereadApi] Web bestbookmarks 失败(可选数据源,不影响主线): $e');
    }

    // b. 逐章网关 /book/underlines(该章全部划线,不限热度)。
    //    这是 pickthought 的成熟方案:bestbookmarks 只给热门划线 range,
    //    非热门段(却有想法)的 range 会丢失,readreviews 按缺不全的 range 拉就漏大量想法;
    //    underlines 覆盖全章 range,后续 readreviews 才能按 range 拉全该段全部想法。
    final underlinesByChapter = <String, List<WereadUnderline>>{};
    for (var i = 0; i < chapterList.length; i++) {
      final ch = chapterList[i];
      onProgress('underlines', i, chapterList.length,
          '${i + 1}/${chapterList.length} ${ch.title}');

      try {
        final chapterUnderlines = await underlines(bookId, ch.chapterUid);
        if (chapterUnderlines.isNotEmpty) {
          underlinesByChapter.putIfAbsent(ch.chapterUid, () => []).addAll(chapterUnderlines);
        }
      } catch (e) {
        debugPrint('[WereadApi] 网关 underlines 失败,用 bestbookmarks 兜底: '
            'chapter=${ch.chapterUid}, error=$e');
        final fallback = bestmarksByChapter[ch.chapterUid];
        if (fallback != null && fallback.isNotEmpty) {
          underlinesByChapter.putIfAbsent(ch.chapterUid, () => []).addAll(fallback);
        }
      }

      // 章节间停顿(防风控)
      if (chapterList.length > 50) {
        await _delay(300 + (i % 3) * 100);
      } else {
        await _delay(150);
      }
    }

    // c. 合并 bestbookmarks 中未被 underlines 覆盖的热门 range(兜底补全)
    bestmarksByChapter.forEach((chapterUid, marks) {
      if (marks.isEmpty) return;
      final list = underlinesByChapter.putIfAbsent(chapterUid, () => []);
      final seen = <String>{for (final u in list) u.range};
      for (final u in marks) {
        if (!seen.contains(u.range)) {
          seen.add(u.range);
          list.add(u);
        }
      }
    });

    // d. 汇总全部划线
    for (final list in underlinesByChapter.values) {
      allUnderlines.addAll(list);
    }

    // 5. 逐章拉取想法
    //    主路径:网关 /book/readreviews 按 range 拉该段【全部】公开想法
    //    (每 range 最多 count=30 条),远比 /web/review/list 的章级热门前几条完整。
    //    Web review/list 仅在 readreviews 无结果时兜底。
    final totalToFetch = chapterList.length;
    final chapterReviewsByChapter = <String, List<WereadReview>>{};

    for (var i = 0; i < chapterList.length; i++) {
      final ch = chapterList[i];
      final progressText = '${i + 1}/${chapterList.length} ${ch.title}';
      onProgress('underlines', i, totalToFetch, progressText);

      final chapterUnderlines = underlinesByChapter[ch.chapterUid] ?? [];
      final ranges = <String>[];
      final seenRanges = <String>{};
      for (final u in chapterUnderlines) {
        if (!seenRanges.contains(u.range)) {
          seenRanges.add(u.range);
          ranges.add(u.range);
        }
      }

      final paraReviews = <WereadReview>[];

      // 5a. 主路径:网关 readreviews 按 range 批量拉该段全部想法
      bool reviewsFetched = false;
      if (ranges.isNotEmpty) {
        final batches = reviewBatches(ranges, batchSize: 5);
        for (var bi = 0; bi < batches.length; bi++) {
          try {
            final batchReviews = await readreviews(
              bookId,
              ch.chapterUid,
              batches[bi],
            );
            if (batchReviews.isNotEmpty) reviewsFetched = true;
            paraReviews.addAll(batchReviews);
            hotReviews.addAll(batchReviews);
          } catch (e) {
            debugPrint('[WereadApi] 网关 readreviews 失败: '
                'chapter=${ch.chapterUid}, batch=$bi, error=$e');
          }
          if (batches.length > 1) await _delay(200);
        }
      }

      // 5b. readreviews 无结果时,用 Web review/list(章级热门想法)兜底
      if (!reviewsFetched) {
        try {
          final rvData = await _webChapterReviews(bookId, ch.chapterUid);
          final webReviews = _parseWebReviews(rvData, ch.chapterUid);
          if (webReviews.isNotEmpty) {
            paraReviews.addAll(webReviews);
            hotReviews.addAll(webReviews);
          }
        } catch (e) {
          debugPrint('[WereadApi] Web chapterReviews 兜底失败: '
              'chapter=${ch.chapterUid}, error=$e');
        }
      }

      // 5c. 用想法的 abstract 填充划线的 markText(bestbookmarks 原文优先)
      final reviewMap = <String, List<WereadReview>>{};
      for (final r in paraReviews) {
        reviewMap.putIfAbsent(r.range, () => []).add(r);
      }

      // 5c2. 章评(挂在整章上,范围为空):失败不影响主线
      final chapterReviewList = <WereadReview>[];
      if (includeChapterReviews) {
        try {
          chapterReviewList.addAll(
            await chapterReviews(bookId, ch.chapterUid),
          );
          if (chapterReviewList.isNotEmpty) {
            chapterReviewsByChapter[ch.chapterUid] = chapterReviewList;
          }
        } catch (e) {
          debugPrint('[WereadApi] 章评拉取失败(可选数据源,不影响主线): '
              'chapter=${ch.chapterUid}, error=$e');
        }
      }

      for (final u in chapterUnderlines) {
        String markText = u.markText;
        if (markText.isEmpty) {
          markText = markTextByRange[u.range] ?? '';
        }
        if (markText.isEmpty) {
          final texts = reviewMap[u.range];
          if (texts != null && texts.isNotEmpty) {
            markText = texts.first.abstract;
          }
        }
        // 替换为填充后的 markText
        final idx = allUnderlines.indexOf(u);
        if (idx >= 0 && markText.isNotEmpty) {
          allUnderlines[idx] = WereadUnderline(
            range: u.range,
            markText: markText,
            chapterUid: u.chapterUid,
          );
        }
      }

      // 5d. 想法有自己的 range:没有对应划线时补一条划线
      for (final entry in reviewMap.entries) {
        if (!seenRanges.contains(entry.key)) {
          seenRanges.add(entry.key);
          final abstract = entry.value.isNotEmpty
              ? entry.value.first.abstract
              : '';
          allUnderlines.add(WereadUnderline(
            range: entry.key,
            markText: abstract,
            chapterUid: ch.chapterUid,
          ));
          underlinesByChapter.putIfAbsent(ch.chapterUid, () => []).add(
            WereadUnderline(
              range: entry.key,
              markText: abstract,
              chapterUid: ch.chapterUid,
            ),
          );
        }
      }

      // 章节间停顿
      if (chapterList.length > 50) {
        await _delay(200 + (i % 3) * 80);
      } else {
        await _delay(100);
      }
    }

    // 统计
    final withMarkText =
        allUnderlines.where((u) => u.markText.isNotEmpty).length;
    onProgress('underlines', chapterList.length, chapterList.length,
        '划线 ${allUnderlines.length} 条(有引文 $withMarkText),公开想法 ${hotReviews.length} 条');

    // 5e. 整本书评(挂在书上):失败不影响主线
    var bookReviewList = <WereadReview>[];
    if (includeBookReviews) {
      try {
        bookReviewList = await bookReviews(bookId);
      } catch (e) {
        debugPrint('[WereadApi] 书评拉取失败(可选数据源,不影响主线): $e');
      }
    }
    if (bookReviewList.isNotEmpty) {
      onProgress('reviews', 1, 1, '书评 ${bookReviewList.length} 条');
    }

    // 6. 合并到章节
    final reviewsByChapter = <String, List<WereadReview>>{};
    for (final r in hotReviews) {
      reviewsByChapter.putIfAbsent(r.chapterUid, () => []).add(r);
    }

    final result = _mergeChapters(
      chapterList,
      underlinesByChapter,
      reviewsByChapter,
      chapterReviewsByChapter,
    );

    return FetchResult(
      chapters: result,
      totalChapters: chapterList.length,
      bookReviews: bookReviewList,
    );
  }

  /// 将划线和想法按 chapterUid 合并到章节列表
  ///
  /// [chapterList] 章节列表
  /// [underlinesByChapter] 按 chapterUid 分组的划线
  /// [reviewsByChapter] 按 chapterUid 分组的想法
  /// [chapterReviewsByChapter] 按 chapterUid 分组的章评
  static List<ChapterData> _mergeChapters(
    List<WereadChapter> chapterList,
    Map<String, List<WereadUnderline>> underlinesByChapter,
    Map<String, List<WereadReview>> reviewsByChapter,
    Map<String, List<WereadReview>> chapterReviewsByChapter,
  ) {
    final result = <ChapterData>[];

    for (final ch in chapterList) {
      final underlines = underlinesByChapter[ch.chapterUid] ?? [];
      final reviews = reviewsByChapter[ch.chapterUid] ?? [];
      final chapterReviews = chapterReviewsByChapter[ch.chapterUid] ?? [];

      // 跳过没有数据的章节
      if (underlines.isEmpty && reviews.isEmpty && chapterReviews.isEmpty) {
        continue;
      }

      // 划线去重保序
      final seenRanges = <String>{};
      final cleanUnderlines = <WereadUnderline>[];
      for (final u in underlines) {
        if (!seenRanges.contains(u.range)) {
          seenRanges.add(u.range);
          cleanUnderlines.add(u);
        }
      }

      // 合并:想法的 range 如果没有对应划线,补一条划线(用 abstract 做引文)
      final reviewMap = <String, List<WereadReview>>{};
      for (final r in reviews) {
        reviewMap.putIfAbsent(r.range, () => []).add(r);
        if (!seenRanges.contains(r.range)) {
          seenRanges.add(r.range);
          cleanUnderlines.add(WereadUnderline(
            range: r.range,
            markText: r.abstract,
            chapterUid: ch.chapterUid,
          ));
        }
      }

      // 如果划线的 markText 为空,用同 range 想法的 abstract 填充
      for (var j = 0; j < cleanUnderlines.length; j++) {
        final u = cleanUnderlines[j];
        if (u.markText.isEmpty) {
          final texts = reviewMap[u.range];
          if (texts != null && texts.isNotEmpty) {
            cleanUnderlines[j] = WereadUnderline(
              range: u.range,
              markText: texts.first.abstract,
              chapterUid: u.chapterUid,
            );
          }
        }
      }

      result.add(ChapterData(
        chapterUid: ch.chapterUid,
        title: ch.title,
        underlines: cleanUnderlines,
        reviewMap: reviewMap,
        chapterReviews: chapterReviews,
      ));
    }

    return result;
  }
}
