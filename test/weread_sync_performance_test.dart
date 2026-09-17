import 'dart:convert';

import 'package:epub_gadget/features/weread_thoughts/weread_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedApi extends WereadApi {
  final bool rejectLargeBatch;
  final batchLengths = <int>[];
  final activeChapters = <String>{};
  int peakChapters = 0;

  _DelayedApi({this.rejectLargeBatch = false})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<List<WereadChapter>> chapters(String bookId) async => List.generate(
    9,
    (i) => WereadChapter(chapterUid: '$i', title: 'chapter $i'),
  );

  @override
  Future<List<WereadUnderline>> chapterUnderlines(
    String bookId,
    String uid,
  ) async {
    activeChapters.add(uid);
    if (activeChapters.length > peakChapters) {
      peakChapters = activeChapters.length;
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return List.generate(
      12,
      (i) => WereadUnderline(range: '$i-${i + 1}', markText: 'quote $uid $i'),
    );
  }

  @override
  Future<List<WereadReview>> readreviews(
    String bookId,
    String chapterUid,
    List<Map<String, dynamic>> batch, {
    void Function(String)? onDebug,
    void Function(String)? onWarning,
  }) async {
    batchLengths.add(batch.length);
    if (rejectLargeBatch && batch.length > 5) {
      throw Exception('params error(node)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return [
      for (final row in batch)
        WereadReview(
          range: row['range'],
          content: 'thought $chapterUid ${row['range']}',
          chapterUid: chapterUid,
        ),
    ];
  }

  @override
  Future<List<WereadReview>> chapterReviews(
    String bookId,
    String uid, {
    int pages = 2,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    activeChapters.remove(uid);
    return [WereadReview(content: 'chapter review $uid', type: 'chapter')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final reject in [false, true]) {
    test(
      'bounded chapter workers preserve all ranges (small batches=$reject)',
      () async {
        final api = _DelayedApi(rejectLargeBatch: reject);
        addTearDown(api.dispose);
        final progress = <int>[];
        final clock = Stopwatch()..start();
        final result = await api.fetchBookData(
          'book',
          includeBookReviews: false,
          onProgress: (phase, current, total, text) {
            if (phase == 'underlines') progress.add(current);
          },
        );
        clock.stop();
        expect(api.peakChapters, 3);
        expect(api.activeChapters, isEmpty);
        expect(
          result.chapters.map((c) => c.chapterUid),
          List.generate(9, (i) => '$i'),
        );
        expect(result.incompleteCount, 0);
        expect(
          result.chapters.fold<int>(
            0,
            (n, c) =>
                n +
                c.reviewMap.values.fold<int>(0, (m, rows) => m + rows.length),
          ),
          108,
        );
        expect(
          result.chapters.every((c) => c.chapterReviews.length == 1),
          isTrue,
        );
        expect(progress, orderedEquals([...progress]..sort()));
        if (!reject) {
          expect(api.batchLengths, List.filled(9, 12));
        } else {
          expect(api.batchLengths, contains(5));
        }
        // A deterministic workload records elapsed time without brittle speed assertions.
        // ignore: avoid_print
        print(
          'SYNC BENCH: smallBatch=$reject chapters=9 ranges=108 '
          'requests=${api.batchLengths.length} elapsedMs=${clock.elapsedMilliseconds}; '
          'old sequential artificial delays alone=6300ms',
        );
      },
    );
  }

  test(
    'HTTP synchronization processes multiple chapters without mixing reviews',
    () async {
      SharedPreferences.setMockInitialValues({
        'weread_login_mode': 'guest',
        'weread_guest_vid': '123',
        'weread_guest_access_token': 'test-token',
      });
      var active = 0;
      var peak = 0;
      final requests = <String>[];
      final api = WereadApi(
        client: MockClient((request) async {
          requests.add(request.url.path);
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          active--;
          Map<String, dynamic> data;
          switch (request.url.path) {
            case '/book/chapterInfos':
              data = {
                'data': [
                  {
                    'updated': [
                      for (var i = 0; i < 6; i++)
                        {'chapterUid': '$i', 'title': 'chapter $i'},
                    ],
                  },
                ],
              };
            case '/book/bestbookmarks':
              data = {'updated': []};
            case '/book/underlines':
              data = {
                'underlines': [
                  for (var i = 0; i < 12; i++) {'range': '$i-${i + 1}'},
                ],
              };
            case '/book/readreviews':
              final body = json.decode(request.body);
              expect((body['reviews'] as List).length, 12);
              data = {
                'reviews': [
                  for (final row in body['reviews'])
                    {
                      'range': row['range'],
                      'totalCount': 1,
                      'pageReviews': [
                        {
                          'review': {
                            'content':
                                'chapter ${body['chapterUid']} range ${row['range']}',
                          },
                        },
                      ],
                    },
                ],
              };
            default:
              fail('Unexpected request ${request.url}');
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
      final clock = Stopwatch()..start();
      final result = await api.fetchBookData(
        'book',
        includeChapterReviews: false,
        includeBookReviews: false,
      );
      clock.stop();
      expect(peak, inInclusiveRange(2, 3));
      expect(result.chapters, hasLength(6));
      expect(result.incompleteCount, 0);
      for (final chapter in result.chapters) {
        expect(chapter.reviewMap, hasLength(12));
        for (final entry in chapter.reviewMap.entries) {
          expect(
            entry.value.single.content,
            'chapter ${chapter.chapterUid} range ${entry.key}',
          );
        }
      }
      expect(requests.where((p) => p == '/book/readreviews'), hasLength(6));
      // ignore: avoid_print
      print(
        'HTTP BENCH: chapters=6 paragraphs=72 networkDelayMs=300 '
        'requests=${requests.length} peak=$peak elapsedMs=${clock.elapsedMilliseconds}',
      );
    },
  );
}
