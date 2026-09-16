import 'dart:convert';

import 'package:epub_gadget/core/secure_prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final storage = <String, String>{};
  var unavailable = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage.clear();
    unavailable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (unavailable) throw PlatformException(code: 'unavailable');
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return storage[key];
            case 'write':
              storage[key] = args['value'] as String;
              return null;
            case 'delete':
              storage.remove(key);
              return null;
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'failed migration keeps the legacy credential across repeated reads',
    () async {
      final encoded = base64Encode(
        'password'.codeUnits.map((c) => c ^ 0x5a).toList(),
      );
      SharedPreferences.setMockInitialValues({'password': encoded});
      unavailable = true;
      expect(
        await SecurePrefs.readSecure('password', legacyXor: true),
        'password',
      );
      expect(
        await SecurePrefs.readSecure('password', legacyXor: true),
        'password',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('password'), encoded);
      unavailable = false;
      expect(
        await SecurePrefs.readSecure('password', legacyXor: true),
        'password',
      );
      expect(storage['secure:password'], 'password');
      expect(prefs.getString('password'), isNull);
    },
  );

  test('plain tokens and Unicode are preserved exactly', () async {
    SharedPreferences.setMockInitialValues({'token': 'YWJj'});
    expect(await SecurePrefs.readSecure('token'), 'YWJj');
    await SecurePrefs.writeSecure('token', '\u5bc6\u7801');
    expect(await SecurePrefs.readSecure('token'), '\u5bc6\u7801');
    expect((await SharedPreferences.getInstance()).getString('token'), isNull);
  });

  test('new writes fail visibly instead of storing XOR or plaintext', () async {
    unavailable = true;
    await expectLater(
      SecurePrefs.writeSecure('token', 'secret'),
      throwsA(isA<PlatformException>()),
    );
    expect((await SharedPreferences.getInstance()).getString('token'), isNull);
  });

  test(
    'secure value takes precedence and removes a stale legacy copy',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'old'});
      storage['secure:token'] = 'new';
      expect(await SecurePrefs.readSecure('token'), 'new');
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
    },
  );

  test('delete removes both copies and reports keychain failure', () async {
    SharedPreferences.setMockInitialValues({'token': 'legacy'});
    storage['secure:token'] = 'secret';
    await SecurePrefs.deleteSecure('token');
    expect(storage, isEmpty);
    expect(await SecurePrefs.readSecure('token'), isNull);
    unavailable = true;
    await expectLater(
      SecurePrefs.deleteSecure('token'),
      throwsA(isA<PlatformException>()),
    );
  });
}
