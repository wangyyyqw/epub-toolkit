import 'dart:async';
import 'dart:io';

import 'package:epub_gadget/features/download_images/safe_image_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PublicNetworkPolicy publicPolicy() => PublicNetworkPolicy(
  lookup: (_) async => [InternetAddress('93.184.216.34')],
);

void main() {
  test('rejects private, local, mapped and special addresses', () {
    for (final ip in [
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '192.0.0.1',
      '198.18.0.1',
      '224.0.0.1',
      '255.255.255.255',
      '::',
      '::1',
      'fc00::1',
      'fe80::1',
      'ff02::1',
      '::ffff:127.0.0.1',
      '64:ff9b::7f00:1',
      '2002:7f00:1::',
      '2001:db8::1',
    ]) {
      expect(
        PublicNetworkPolicy.isPublicAddress(InternetAddress(ip)),
        isFalse,
        reason: ip,
      );
    }
    for (final ip in ['93.184.216.34', '8.8.8.8', '2606:4700:4700::1111']) {
      expect(PublicNetworkPolicy.isPublicAddress(InternetAddress(ip)), isTrue);
    }
  });

  test('rejects any private DNS answer and credential-bearing URLs', () async {
    final policy = PublicNetworkPolicy(
      lookup: (_) async => [
        InternetAddress('93.184.216.34'),
        InternetAddress('127.0.0.1'),
      ],
    );
    await expectLater(
      policy.resolve(Uri.parse('https://images.example/a')),
      throwsA(isA<DownloadRejected>()),
    );
    for (final url in ['file:///a', 'http://user:pass@images.example/a']) {
      await expectLater(
        publicPolicy().resolve(Uri.parse(url)),
        throwsA(isA<DownloadRejected>()),
      );
    }
  });

  test('blocks a private redirect before issuing the second request', () async {
    var requests = 0;
    final downloader = SafeImageDownloader(
      policy: publicPolicy(),
      clientFactory: () => MockClient((request) async {
        requests++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://127.0.0.1/private'},
        );
      }),
    );
    await expectLater(
      downloader.get('https://images.example/start'),
      throwsA(isA<DownloadRejected>()),
    );
    expect(requests, 1);
  });

  test('checks DNS again at connection time to prevent rebinding', () async {
    var resolutions = 0;
    final policy = PublicNetworkPolicy(
      lookup: (_) async {
        resolutions++;
        return [
          InternetAddress(resolutions == 1 ? '93.184.216.34' : '127.0.0.1'),
        ];
      },
    );
    final downloader = SafeImageDownloader(policy: policy);
    await expectLater(
      downloader.get('http://images.example/a'),
      throwsA(isA<DownloadRejected>()),
    );
    expect(resolutions, 2);
  });

  test('rejects Content-Length before consuming the body', () async {
    var chunksRead = 0;
    Stream<List<int>> body() async* {
      chunksRead++;
      yield List.filled(20, 0);
    }

    final downloader = SafeImageDownloader(
      policy: publicPolicy(),
      maxImageBytes: 10,
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(body(), 200, contentLength: 20),
      ),
    );
    await expectLater(
      downloader.get('https://images.example/a'),
      throwsA(isA<DownloadRejected>()),
    );
    expect(chunksRead, 0);
    expect(downloader.receivedBytes, 0);
  });

  test('cancels a chunked oversized response at the limit', () async {
    var cancelled = false;
    var chunksRead = 0;
    Stream<List<int>> body() async* {
      try {
        for (var i = 0; i < 10; i++) {
          chunksRead++;
          yield List.filled(6, 0);
        }
      } finally {
        cancelled = true;
      }
    }

    final downloader = SafeImageDownloader(
      policy: publicPolicy(),
      maxImageBytes: 10,
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(body(), 200),
      ),
    );
    await expectLater(
      downloader.get('https://images.example/a'),
      throwsA(isA<DownloadRejected>()),
    );
    expect(cancelled, isTrue);
    expect(chunksRead, 2);
    expect(downloader.receivedBytes, 6);
  });

  test('concurrent requests cannot exceed the shared budget', () async {
    final downloader = SafeImageDownloader(
      policy: publicPolicy(),
      maxImageBytes: 10,
      maxTotalBytes: 10,
      clientFactory: () => MockClient.streaming(
        (_, _) async =>
            http.StreamedResponse(Stream.value(List.filled(6, 0)), 200),
      ),
    );
    final results = await Future.wait(
      List.generate(6, (i) async {
        try {
          await downloader.get('https://images.example/$i');
          return true;
        } on DownloadRejected {
          return false;
        }
      }),
    );
    expect(results.where((ok) => ok), hasLength(1));
    expect(downloader.receivedBytes, 6);
  });

  test('valid relative redirects and exact-limit downloads succeed', () async {
    final downloader = SafeImageDownloader(
      policy: publicPolicy(),
      maxImageBytes: 6,
      maxTotalBytes: 6,
      clientFactory: () => MockClient(
        (request) async => request.url.path == '/start'
            ? http.Response('', 302, headers: {'location': '/image'})
            : http.Response.bytes(List.filled(6, 0), 200),
      ),
    );
    expect(
      (await downloader.get('https://images.example/start')).bodyBytes,
      hasLength(6),
    );
    expect(downloader.receivedBytes, 6);
  });
}
