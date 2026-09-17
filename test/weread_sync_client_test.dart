import 'dart:async';
import 'dart:convert';

import 'package:epub_gadget/features/weread_thoughts/weread_sync_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'sync requests share spacing and never exceed three in flight',
    () async {
      final starts = <DateTime>[];
      var active = 0;
      var peak = 0;
      final client = WereadSyncClient(
        MockClient((request) async {
          starts.add(DateTime.now());
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 90));
          active--;
          return http.Response('{"ok":true}', 200);
        }),
        interval: const Duration(milliseconds: 20),
      );
      addTearDown(client.close);
      client.begin();
      final responses = await Future.wait(
        List.generate(12, (i) => client.get(Uri.https('example.test', '/$i'))),
      );
      client.end();
      expect(responses.length, 12);
      expect(peak, 3);
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]).inMilliseconds,
          greaterThanOrEqualTo(18),
        );
      }
    },
  );

  test(
    '429 pauses every worker, retries body and reduces concurrency',
    () async {
      final starts = <DateTime>[];
      final bodies = <String>[];
      var calls = 0;
      var active = 0;
      var peakAfterLimit = 0;
      final notices = <String>[];
      final client = WereadSyncClient(
        MockClient((request) async {
          starts.add(DateTime.now());
          bodies.add(request.body);
          if (++calls == 1) {
            return http.Response('{}', 429, headers: {'retry-after': '1'});
          }
          active++;
          if (active > peakAfterLimit) peakAfterLimit = active;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          active--;
          return http.Response('{"ok":true}', 200);
        }),
        interval: const Duration(milliseconds: 5),
      );
      addTearDown(client.close);
      client.begin(onThrottle: notices.add);
      final responses = await Future.wait(
        List.generate(
          3,
          (i) => client.post(
            Uri.https('example.test', '/readreviews'),
            body: 'page=$i',
          ),
        ),
      );
      expect(responses.every((r) => r.statusCode == 200), isTrue);
      expect(calls, 4);
      expect(bodies.where((body) => body == 'page=0').length, 2);
      expect(
        starts[1].difference(starts[0]).inMilliseconds,
        greaterThanOrEqualTo(990),
      );
      expect(peakAfterLimit, 1);
      expect(notices, hasLength(1));
      client.end();
    },
  );

  test('business rate-limit codes use the same shared retry policy', () async {
    var calls = 0;
    final client = WereadSyncClient(
      MockClient((request) async {
        return http.Response(
          json.encode(++calls == 1 ? {'errCode': '-2014'} : {'reviews': []}),
          200,
        );
      }),
      interval: Duration.zero,
      backoff: const Duration(milliseconds: 10),
    );
    addTearDown(client.close);
    client.begin();
    final response = await client.get(Uri.https('example.test', '/reviews'));
    expect(response.statusCode, 200);
    expect(calls, 2);
    client.end();
  });

  test(
    'long Retry-After stops queued requests rather than bypassing the wait',
    () async {
      var calls = 0;
      final client = WereadSyncClient(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '60'});
        }),
        interval: const Duration(milliseconds: 5),
      );
      addTearDown(client.close);
      client.begin();
      final results = await Future.wait(
        List.generate(3, (i) async {
          try {
            await client.get(Uri.https('example.test', '/$i'));
            return false;
          } on WereadSyncStopped {
            return true;
          }
        }),
      );
      expect(results, everyElement(isTrue));
      expect(calls, 1);
      expect(client.stoppedReason, isNotNull);
      client.end();
    },
  );

  test(
    'repeated limiting is bounded and overlapping syncs are rejected',
    () async {
      var calls = 0;
      final client = WereadSyncClient(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '0'});
        }),
        interval: Duration.zero,
      );
      addTearDown(client.close);
      client.begin();
      expect(client.begin, throwsStateError);
      await expectLater(
        client.get(Uri.https('example.test', '/reviews')),
        throwsA(isA<WereadSyncStopped>()),
      );
      expect(calls, 3);
      client.end();
    },
  );

  test('closing a client prevents queued requests from being sent', () async {
    final started = Completer<void>();
    var calls = 0;
    final client = WereadSyncClient(
      MockClient((request) async {
        if (++calls == 1) started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response('{}', 200);
      }),
      interval: const Duration(milliseconds: 60),
    );
    client.begin();
    final requests = Future.wait(
      List.generate(4, (i) async {
        try {
          await client.get(Uri.https('example.test', '/$i'));
          return true;
        } on StateError {
          return false;
        }
      }),
    );
    await started.future;
    client.close();
    final results = await requests;
    expect(results.where((ok) => ok).length, lessThanOrEqualTo(1));
    expect(calls, 1);
    client.end();
  });
}
