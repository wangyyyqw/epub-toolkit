// 游客登录 + 游客模式数据源测试
//
// 用 MockClient 模拟微信读书 APP 接口,验证:
// 1. startGuestLogin 预登录直连成功(无需验证码)
// 2. 预登录 499 → GuestCaptchaRequiredException → completeGuestLogin 验证码重试
// 3. 游客模式搜索/章节列表走 APP 端点(请求头含 vid/accessToken)
// 4. fetchBookData 游客模式全链路:章节 → 热门划线 → 段评 → 章评 → 书评
// 5. 登录态持久化(load/clear)

import 'dart:convert';

import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:epub_gadget/features/weread_thoughts/weread_guest_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 根据请求路径路由的模拟微信读书 APP 服务器。
///
/// [challengeGuestLogin] 为 true 时 /guestLogin 首次返回 499(触发验证码)。
MockClient _mockServer({bool challengeGuestLogin = false}) {
  return MockClient((request) async {
    final path = request.url.path;
    http.Response okJson(Map<String, dynamic> body, [int status = 200]) =>
        http.Response(
          json.encode(body),
          status,
          headers: {'content-type': 'application/json'},
        );

    switch (path) {
      case '/feature':
        return okJson({
          'feature': {'guest_token': 'gt_test_token'},
        });

      case '/guestLogin':
        final headers = request.headers;
        if (challengeGuestLogin &&
            !headers.containsKey('wr_ticket') &&
            !headers.containsKey('wr_randstr')) {
          // 挑战模式:无验证码头一律触发安全验证
          return okJson({'errcode': -2041}, 499);
        }
        return okJson({
          'vid': '8888888888',
          'accessToken': 'guest_access_token_1',
        });

      case '/store/search':
        // 校验游客登录用的关键词是"测试"(URL 编码)
        final keyword = request.url.queryParameters['keyword'] ?? '';
        if (keyword == '测试') {
          return okJson({'errcode': 0, 'books': []});
        }
        return okJson({
          'books': [
            {
              'bookInfo': {
                'bookId': 'b1',
                'title': '书名甲',
                'author': '作者甲',
                'intro': '简介甲',
              },
            },
          ],
        });

      case '/book/chapterInfos':
        return okJson({
          'data': [
            {
              'bookId': 'b1',
              'updated': [
                {'chapterUid': '1', 'title': '第一章'},
              ],
            },
          ],
        });

      case '/book/bestbookmarks':
        return okJson({
          'updated': [
            {'chapterUid': '1', 'range': '1-25', 'markText': '第一段引文原文内容'},
          ],
        });

      case '/book/underlines':
        return okJson({
          'underlines': [
            {'range': '1-25'},
          ],
        });

      case '/book/readreviews':
        return okJson({
          'reviews': [
            {
              'range': '1-25',
              'totalCount': 1,
              'pageReviews': [
                {
                  'review': {
                    'content': '这一段写得真好',
                    'abstract': '第一段引文原文内容',
                    'author': {'name': '读者甲'},
                  },
                  'likesCount': 5,
                },
              ],
            },
          ],
        });

      case '/book/chapterreviewlist':
        return okJson({
          'reviews': [
            {
              'review': {
                'content': '本章剧情紧凑',
                'author': {'name': '读者乙'},
              },
            },
          ],
          'maxIdx': 0,
          'hasMore': false,
        });

      case '/book/podcasts':
        return okJson({
          'reviews': [
            {
              'review': {
                'content': '年度好书,值得一读',
                'author': {'name': '读者丙'},
              },
            },
          ],
          'synckey': 0,
          'reviewsHasMore': false,
        });

      default:
        return http.Response('not found: $path', 404);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<WereadApi> apiWithRoutes(
    Map<String, dynamic>? Function(http.Request request) route,
  ) async {
    final fallback = _mockServer();
    final api = WereadApi(
      client: MockClient((request) async {
        final body = route(request);
        if (body != null) {
          return http.Response(
            json.encode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes;
        return http.Response.fromStream(await fallback.send(copy));
      }),
    );
    addTearDown(api.dispose);
    addTearDown(fallback.close);
    await api.load();
    await api.startGuestLogin();
    return api;
  }

  test(
    'non-popular chapter ranges are fetched and abstracts fill missing quotes',
    () async {
      final requestedRanges = <String>{};
      final api = await apiWithRoutes((request) {
        if (request.url.path == '/book/underlines') {
          return {
            'data': {
              'updated': [
                {'range': '1-25'},
                {'bookmarkRange': '30-60', 'mark_text': ''},
                {'markRange': '70-100', 'markText': '第三段完整引文'},
              ],
            },
          };
        }
        if (request.url.path == '/book/readreviews') {
          final body = json.decode(request.body) as Map;
          final ranges = (body['reviews'] as List).cast<Map>();
          requestedRanges.addAll(ranges.map((r) => r['range'] as String));
          return {
            'reviews': [
              for (final range in ranges)
                {
                  'range': range['range'],
                  'totalCount': 1,
                  'pageReviews': [
                    {
                      'review': {
                        'reviewId': 'id-${range['range']}',
                        'content': '想法-${range['range']}',
                        'abstract': '该段的完整引文[插图]',
                      },
                    },
                  ],
                },
            ],
          };
        }
        return null;
      });
      final result = await api.fetchBookData('b1');
      expect(requestedRanges, {'1-25', '30-60', '70-100'});
      expect(result.chapters.single.reviewMap.length, 3);
      expect(
        result.chapters.single.underlines
            .singleWhere((u) => u.range == '30-60')
            .markText,
        '该段的完整引文',
      );
      expect(result.incompleteCount, 0);
    },
  );

  test(
    'range pagination fetches more than 30 and deduplicates overlapping IDs',
    () async {
      final requests = <List<Map>>[];
      final api = await apiWithRoutes((request) {
        if (request.url.path != '/book/readreviews') return null;
        final ranges = (json.decode(request.body)['reviews'] as List)
            .cast<Map>();
        requests.add(ranges);
        return {
          'data': {
            'reviews': [
              for (final range in ranges)
                {
                  'range': range['range'],
                  'totalCount': range['range'] == '1-25' ? 45 : 1,
                  'hasMore': range['range'] == '1-25' && range['maxIdx'] == 0,
                  'maxIdx': range['maxIdx'] == 0 ? 30 : 45,
                  'pageReviews': [
                    for (
                      var i = range['maxIdx'] == 0 ? 0 : 29;
                      i <
                          (range['range'] == '1-25'
                              ? (range['maxIdx'] == 0 ? 30 : 45)
                              : 1);
                      i++
                    )
                      {
                        'review': {
                          'reviewId': '${range['range']}-$i',
                          'content': '段评$i',
                          'createTime': i,
                          'author': {'name': '读者$i'},
                        },
                      },
                  ],
                },
            ],
          },
        };
      });
      final warnings = <String>[];
      final result = await api.readreviews(
        'b1',
        '1',
        WereadApi.reviewBatches(['1-25', '30-60']).single,
        onWarning: warnings.add,
      );
      expect(result.length, 46);
      expect(requests.length, 2);
      expect(requests.last.map((r) => r['range']), ['1-25']);
      expect(requests.last.single['maxIdx'], 30);
      expect(result.last.author, '读者44');
      expect(warnings, isEmpty);
    },
  );

  test(
    'stalled pagination retains reviews and reports incomplete fetch',
    () async {
      var calls = 0;
      final api = await apiWithRoutes((request) {
        if (request.url.path != '/book/readreviews') return null;
        calls++;
        return {
          'reviews': [
            {
              'range': '1-25',
              'totalCount': 100,
              'hasMore': 1,
              'maxIdx': calls,
              'pageReviews': [
                {
                  'review': {'reviewId': 'same', 'content': '不重复插入'},
                },
              ],
            },
          ],
        };
      });
      final result = await api.fetchBookData('b1');
      expect(calls, 2);
      expect(result.chapters.single.reviewMap['1-25']!.length, 1);
      expect(result.incompleteCount, 1);
      expect(result.warnings.single, contains('游标缺失或停滞'));
    },
  );

  test(
    'chapter range failure is visible while preserving popular fallback',
    () async {
      final api = await apiWithRoutes((request) {
        if (request.url.path == '/book/underlines') {
          return {'errcode': -1, 'errmsg': 'underlines unavailable'};
        }
        return null;
      });
      final result = await api.fetchBookData('b1');
      expect(result.chapters.single.reviewMap['1-25'], isNotEmpty);
      expect(result.incompleteCount, 1);
      expect(result.warnings.single, contains('仅使用热门划线降级'));
    },
  );

  test('later page failure keeps already fetched reviews', () async {
    var calls = 0;
    final api = await apiWithRoutes((request) {
      if (request.url.path != '/book/readreviews') return null;
      if (++calls > 1) return {'errcode': -1, 'errmsg': 'page unavailable'};
      return {
        'reviews': [
          {
            'range': '1-25',
            'hasMore': true,
            'maxIdx': 10,
            'pageReviews': [
              {
                'review': {'content': '保留首批'},
              },
            ],
          },
        ],
      };
    });
    final warnings = <String>[];
    final result = await api.readreviews(
      'b1',
      '1',
      WereadApi.reviewBatches(['1-25']).single,
      onWarning: warnings.add,
    );
    expect(result.single.content, '保留首批');
    expect(warnings.single, contains('后续分页失败'));
  });

  test('full first page without a cursor is explicitly incomplete', () async {
    var calls = 0;
    final api = await apiWithRoutes((request) {
      if (request.url.path != '/book/readreviews') return null;
      calls++;
      return {
        'reviews': [
          {
            'review': {'range': '1-25'},
            'pageReviews': [
              for (var i = 0; i < 30; i++)
                {
                  'review': {'reviewId': '$i', 'content': '第$i条'},
                },
            ],
          },
        ],
      };
    });
    final warnings = <String>[];
    final result = await api.readreviews(
      'b1',
      '1',
      WereadApi.reviewBatches(['1-25']).single,
      onWarning: warnings.add,
    );
    expect(result.length, 30);
    expect(calls, 1, reason: 'Do not invent unsupported pagination offsets');
    expect(warnings.single, contains('不能确认完整'));
  });

  for (final fallback in [false, true]) {
    test(
      'QR chapter underlines use Web with gateway fallback=$fallback',
      () async {
        SharedPreferences.setMockInitialValues({
          'weread_api_key': 'test-key',
          'weread_cookies': '{"wr_skey":"test-session","wr_vid":"123"}',
        });
        var gatewayCalls = 0;
        final api = WereadApi(
          client: MockClient((request) async {
            Map<String, dynamic> data;
            if (request.url.path == '/web/book/underlines') {
              expect(request.url.queryParameters['chapterUid'], '42');
              expect(
                request.headers['cookie'],
                contains('wr_skey=test-session'),
              );
              if (fallback) return http.Response('unavailable', 403);
              data = {
                'underlines': [
                  {'range': '2-20', 'markText': 'Web引文'},
                ],
              };
            } else {
              expect(request.url.path, '/api/agent/gateway');
              final body = json.decode(request.body);
              expect(body['api_name'], '/book/underlines');
              expect(body['chapterUid'], 42);
              gatewayCalls++;
              data = {
                'updated': [
                  {'bookmarkRange': '2-20', 'mark_text': '网关引文'},
                ],
              };
            }
            return http.Response(
              json.encode(data),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(api.dispose);
        await api.load();
        final marks = await api.chapterUnderlines('b1', '42');
        expect(marks.single.range, '2-20');
        expect(marks.single.chapterUid, '42');
        expect(gatewayCalls, fallback ? 1 : 0);
      },
    );
  }

  group('游客登录', () {
    test('预登录直连成功(无需验证码)', () async {
      final api = WereadApi(client: _mockServer());
      await api.load();

      final message = await api.startGuestLogin();

      expect(message, contains('游客登录成功'));
      expect(api.isGuestMode, isTrue);
      expect(api.isLoggedIn, isTrue);
      expect(api.userName, '游客账号');
    });

    test('预登录 499 → 抛验证码异常 → completeGuestLogin 成功', () async {
      final api = WereadApi(client: _mockServer(challengeGuestLogin: true));
      await api.load();

      await expectLater(
        api.startGuestLogin(),
        throwsA(isA<GuestCaptchaRequiredException>()),
      );
      expect(api.isGuestMode, isFalse, reason: '验证码未完成前不应视为已登录');

      // 再次预登录仍被拦截,捕获会话后带验证码重试
      try {
        await api.startGuestLogin();
        fail('应再次抛出验证码异常');
      } on GuestCaptchaRequiredException catch (e) {
        final result = await api.completeGuestLogin(
          e.session,
          'ticket_abc',
          'randstr_xyz',
        );
        expect(result, contains('游客登录成功'));
        expect(api.isGuestMode, isTrue);
        expect(api.isLoggedIn, isTrue);
      }
    });

    test('guestLogin 请求体签名与本地算法一致', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        if (request.url.path == '/guestLogin') {
          captured = request;
          return http.Response(
            json.encode({'vid': '8888888888', 'accessToken': 't1'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          json.encode({
            'feature': {'guest_token': 'gt_sig'},
          }),
          200,
        );
      });
      final api = WereadApi(client: client);
      await api.load();

      await api.startGuestLogin();

      expect(captured, isNotNull);
      final body = json.decode(captured!.body) as Map<String, dynamic>;
      expect(body['virtualChannelId'], '');
      expect(body['appFirstInstall'], 0);
      final deviceId = body['deviceId'] as String;
      final random = body['random'] as int;
      final timestamp = body['timestamp'] as int;
      expect(
        body['signature'],
        wereadGuestSignature('gt_sig', random, timestamp, deviceId),
        reason: '请求体签名应与本地算法一致',
      );
      // 验证码重试头
      expect(captured!.headers['wr_ticket'], isNull);
    });
  });

  group('游客模式数据源', () {
    test('搜索走 APP 端点且携带鉴权头', () async {
      final client = _mockServer();
      final api = WereadApi(client: client);
      await api.load();
      await api.startGuestLogin();

      final books = await api.search('书名');

      expect(books, hasLength(1));
      expect(books.first.bookId, 'b1');
      expect(books.first.title, '书名甲');
    });

    test('章节列表走 APP 端点', () async {
      final api = WereadApi(client: _mockServer());
      await api.load();
      await api.startGuestLogin();

      final chapters = await api.chapters('b1');

      expect(chapters, hasLength(1));
      expect(chapters.first.chapterUid, '1');
      expect(chapters.first.title, '第一章');
    });

    test('fetchBookData 全链路:热门划线 + 公开想法 + 章评 + 书评', () async {
      final api = WereadApi(client: _mockServer());
      await api.load();
      await api.startGuestLogin();

      final result = await api.fetchBookData('b1');

      // 章节
      expect(result.totalChapters, 1);
      expect(result.chapters, hasLength(1));

      final chapter = result.chapters.single;
      // 热门划线(markText 原文)
      expect(chapter.underlines, hasLength(1));
      expect(chapter.underlines.first.range, '1-25');
      expect(chapter.underlines.first.markText, '第一段引文原文内容');
      // 公开段评
      expect(chapter.reviewMap.containsKey('1-25'), isTrue);
      expect(chapter.reviewMap['1-25']!.first.content, '这一段写得真好');
      // 章评
      expect(chapter.chapterReviews, hasLength(1));
      expect(chapter.chapterReviews.first.content, '本章剧情紧凑');
      // 书评
      expect(result.bookReviews, hasLength(1));
      expect(result.bookReviews.first.content, '年度好书,值得一读');
    });
  });

  group('登录态持久化', () {
    test('clear 清除游客状态', () async {
      final api = WereadApi(client: _mockServer());
      await api.load();
      await api.startGuestLogin();
      expect(api.isGuestMode, isTrue);

      await api.clear();

      expect(api.isGuestMode, isFalse);
      expect(api.isLoggedIn, isFalse);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      final restored = WereadApi(client: _mockServer());
      await restored.load();
      expect(restored.isLoggedIn, isFalse);
    });

    test('load 恢复游客登录态', () async {
      SharedPreferences.setMockInitialValues({
        'weread_login_mode': 'guest',
        'weread_guest_vid': '8888888888',
        'weread_guest_access_token': 'tok_restored',
        'weread_guest_user_agent': 'UA-test',
        'weread_guest_old_device': '1234567890123456789012345678',
        'weread_guest_install_id': '1234567890123456789012345678',
        'weread_guest_new_device': '12345678901234567890123456789012345678',
      });
      final api = WereadApi(client: _mockServer());
      await api.load();

      expect(api.isGuestMode, isTrue);
      expect(api.isLoggedIn, isTrue);
      expect(api.userName, '游客账号');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('weread_guest_access_token'), isNull);
      expect(
        await const FlutterSecureStorage().read(
          key: 'secure:weread_guest_access_token',
        ),
        'tok_restored',
      );
    });

    test(
      'API keys and cookies migrate without guessing Base64 encoding',
      () async {
        SharedPreferences.setMockInitialValues({
          'weread_api_key': 'YWJj',
          'weread_cookies': '{"wr_skey":"session","wr_vid":"123"}',
        });
        final api = WereadApi(client: _mockServer());
        await api.load();
        expect(api.isLoggedIn, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('weread_api_key'), isNull);
        expect(prefs.getString('weread_cookies'), isNull);
        const storage = FlutterSecureStorage();
        expect(await storage.read(key: 'secure:weread_api_key'), 'YWJj');
        await api.saveApiKey('updated');
        expect(await storage.read(key: 'secure:weread_api_key'), 'updated');
        expect(prefs.getString('weread_api_key'), isNull);
        await api.clear();
        expect(await storage.readAll(), isEmpty);
      },
    );
  });
}
