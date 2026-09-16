import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef AddressLookup = Future<List<InternetAddress>> Function(String host);

class DownloadRejected implements Exception {
  const DownloadRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Validates DNS answers and connects to the checked IP, not a second lookup.
class PublicNetworkPolicy {
  PublicNetworkPolicy({AddressLookup? lookup})
    : _lookup = lookup ?? InternetAddress.lookup;

  final AddressLookup _lookup;

  Future<List<InternetAddress>> resolve(Uri uri) async {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const DownloadRejected('Invalid image URL');
    }
    final host = uri.host.replaceAll(RegExp(r'^\[|\]$'), '');
    final literal = InternetAddress.tryParse(host);
    final addresses = literal == null ? await _lookup(host) : [literal];
    if (addresses.isEmpty || addresses.any((a) => !isPublicAddress(a))) {
      throw const DownloadRejected('Non-public image address is blocked');
    }
    return addresses;
  }

  static bool isPublicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 192 && b[1] == 0 && (b[2] == 0 || b[2] == 2)) ||
          (b[0] == 192 && b[1] == 88 && b[2] == 99) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19)) ||
          (b[0] == 198 && b[1] == 51 && b[2] == 100) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113));
    }
    // Only global unicast. Exclude mapped/translation/tunnel and special ranges.
    return address.type == InternetAddressType.IPv6 &&
        (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] < 2) &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x3f && b[1] == 0xff && (b[2] & 0xf0) == 0);
  }

  http.Client createClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final addresses = await resolve(uri);
      return Socket.startConnect(addresses.first, uri.port);
    };
    return IOClient(client);
  }
}

/// One instance per operation. All concurrent requests share a byte budget.
class SafeImageDownloader {
  SafeImageDownloader({
    PublicNetworkPolicy? policy,
    this.clientFactory,
    this.maxImageBytes = 10 * 1024 * 1024,
    this.maxTotalBytes = 100 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
  }) : policy = policy ?? PublicNetworkPolicy();

  final PublicNetworkPolicy policy;
  final http.Client Function()? clientFactory;
  final int maxImageBytes;
  final int maxTotalBytes;
  final Duration timeout;
  int _receivedBytes = 0;

  int get receivedBytes => _receivedBytes;

  Future<http.Response> get(String url) async {
    for (var attempt = 0; ; attempt++) {
      final client = clientFactory?.call() ?? policy.createClient();
      try {
        final response = await _get(client, Uri.parse(url)).timeout(timeout);
        if ((response.statusCode == 429 || response.statusCode >= 500) &&
            attempt < 2) {
          throw HttpException(
            'Temporary image HTTP error: ${response.statusCode}',
          );
        }
        return response;
      } on DownloadRejected {
        rethrow;
      } on FormatException {
        rethrow;
      } catch (_) {
        if (attempt >= 2) rethrow;
      } finally {
        // Also aborts the underlying IO request when the deadline expires.
        client.close();
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }

  Future<http.Response> _get(http.Client client, Uri uri) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (_receivedBytes >= maxTotalBytes) {
        throw const DownloadRejected('Total image download limit exceeded');
      }
      await policy.resolve(uri);
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        });
      final response = await client.send(request);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.listen(null).cancel();
        final location = response.headers['location'];
        if (location == null) {
          throw const DownloadRejected('Image redirect has no location');
        }
        uri = uri.resolve(location);
        continue;
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null &&
          (declaredLength > maxImageBytes ||
              declaredLength > maxTotalBytes - _receivedBytes)) {
        // The caller closes the client without subscribing to an oversized body.
        throw const DownloadRejected('Image download size limit exceeded');
      }
      final data = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (chunk.length > maxImageBytes - data.length ||
            chunk.length > maxTotalBytes - _receivedBytes) {
          throw const DownloadRejected('Image download size limit exceeded');
        }
        // No await between checking and reserving shared capacity.
        // Failed downloads and retries still count against this operation.
        _receivedBytes += chunk.length;
        data.add(chunk);
      }
      return http.Response.bytes(
        data.takeBytes(),
        response.statusCode,
        headers: response.headers,
      );
    }
    throw const DownloadRejected('Too many image redirects');
  }
}
