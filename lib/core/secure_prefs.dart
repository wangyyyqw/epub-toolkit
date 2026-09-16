import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 安全存储封装：敏感字段走 Keychain/EncryptedSharedPreferences，
/// 非敏感字段仍走 SharedPreferences。自动迁移旧的明文/XOR 数据。
class SecurePrefs {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // macOS releases are ad-hoc signed; use the login Keychain.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static const _xorKey = 0x5A;

  /// 敏感键在 secure_storage 中的前缀，避免与普通键冲突
  static String _secureKey(String key) => 'secure:$key';

  /// 只有历史 Kindle 密码使用 XOR；普通明文凭据不能猜测解码。
  static Future<String?> readSecure(
    String key, {
    bool legacyXor = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final v = await _secure.read(key: _secureKey(key));
      if (v != null) {
        await prefs.remove(key);
        return v;
      }
    } catch (_) {}

    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    var value = raw;
    if (legacyXor) {
      try {
        final bytes = base64Decode(raw);
        value = String.fromCharCodes(bytes.map((b) => b ^ _xorKey));
      } catch (_) {}
    }
    try {
      await writeSecure(key, value);
    } catch (_) {
      // Keychain 暂不可用时保留唯一的旧副本，下次读取再尝试迁移。
    }
    return value;
  }

  static Future<void> writeSecure(String key, String value) async {
    if (value.isEmpty) {
      await deleteSecure(key);
      return;
    }
    // 写入失败必须告知调用方，不能静默降级到明文或 XOR。
    await _secure.write(key: _secureKey(key), value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> deleteSecure(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await _secure.delete(key: _secureKey(key));
  }

  /// 批量读取敏感 Map（存为 json）
  static Future<Map<String, String>> readSecureMap(String key) async {
    final raw = await readSecure(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> writeSecureMap(
    String key,
    Map<String, String> map,
  ) async {
    if (map.isEmpty) {
      await deleteSecure(key);
    } else {
      await writeSecure(key, json.encode(map));
    }
  }
}
