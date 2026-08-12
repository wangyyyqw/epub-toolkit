/// 微信读书游客登录签名算法(纯 Dart 移植)。
///
/// 算法来源于阅读 App 书源(微信读书二合一本地源)对 Android 客户端
/// 逆向还原的 guestLogin 签名流程:
/// 1. token / random / timestamp / deviceId 逐字节经 REMAP 表映射(表长 256)
/// 2. 五段字节按字典序排序后拼接
/// 3. 按 xor 值旋转(shift = xor % 11)
/// 4. SHA-256 → 再对 hex 字符串字节做一次旋转 + SHA-256
///
/// 该实现与书源 JS 逻辑逐字节对齐,测试使用 JS 原样生成的向量交叉验证。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// 微信读书 Android 10.2.1 的 REMAP 字节表(hex)。
///
/// 逆向常量:微信读书升级客户端后可能变更,失效时游客登录签名会被拒绝。
const String wereadRemapHex =
    '34ca55401db693c63130293532a7b811c2b516fa8bb124a4109004e908f83b8a9'
    'c8c44f9bc5c69e2a1dad2d37589f71e2d5056d77253bf22fb200f012e45876e6648'
    'f2e0cdfe67a943f49451cea54aee13268eccaa33145d0e39bbcf912b814dea99ec1'
    'a2c85c5d936744b18e1f13d9d419fb4170dd64cbedcaf972877f062ff71c1c8278f'
    '6c68a89be6591c1b1209984e3f063700ba1f0a192fc9d5d057496ffd25e4610c42c'
    'b96645fdbad60238d9a6dc3c45e3eb9926abd5b077f7695ed4fab847a80e778c7e5'
    'eb73836bfc38467d4765b352633a05d1efa3a6de9e3c02aeb27ba0f6f32ac0ac860'
    '35a540bf582d47ee3dfb0d8dd21e87c88a2795870b715';

/// 游客登录签名中附加的固定盐(逆向常量)。
const String wereadGuestSalt = '5a6f1';

/// 游客登录使用的客户端版本号(与 REMAP 表配套)。
const String wereadAppVersion = '10.2.1.10167607';

/// 游客登录默认 User-Agent(逆向常量,需与签名所用客户端配套)。
const String wereadGuestUserAgent =
    'WeRead/10.2.1 WRBrand/xiaomi Dalvik/2.1.0 '
    '(Linux; U; Android 16; 2509FPN0BC Build/BP2A.250605.031.A3)';

/// 腾讯验证码 AppId(游客登录安全验证用)。
const String wereadCaptchaAppId = '2044038556';

/// 解码 REMAP hex 表。
@visibleForTesting
List<int> wereadRemapTable() {
  final hex = wereadRemapHex;
  final table = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < table.length; i++) {
    table[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return table;
}

/// 字符串经 REMAP 表逐字节映射(索引为原始字节值 0~255)。
@visibleForTesting
List<int> wereadRemapBytes(String value) {
  final table = wereadRemapTable();
  final input = utf8.encode(value);
  final out = List<int>.filled(input.length, 0);
  for (var i = 0; i < input.length; i++) {
    out[i] = table[input[i] & 0xff];
  }
  return out;
}

/// 按字节字典序比较(与书源 wrCompareBytes 一致)。
@visibleForTesting
int wereadCompareBytes(List<int> left, List<int> right) {
  final length = min(left.length, right.length);
  for (var i = 0; i < length; i++) {
    if (left[i] != right[i]) return left[i] - right[i];
  }
  return left.length - right.length;
}

/// 按全体字节 xor 值旋转(shift = xor % 11)。
@visibleForTesting
List<int> wereadRotateByXor(List<int> values) {
  if (values.isEmpty) return const [];
  var xor = 0;
  for (final value in values) {
    xor ^= value;
  }
  final shift = xor % 11;
  final out = List<int>.filled(values.length, 0);
  for (var i = 0; i < values.length; i++) {
    out[(i + shift) % values.length] = values[i];
  }
  return out;
}

/// 计算游客登录签名。
///
/// [token] feature 接口返回的 guest_token
/// [random] 随机数(与请求体 random 一致)
/// [timestamp] Unix 秒(与请求体 timestamp 一致)
/// [oldDeviceId] 设备 ID(与请求体 deviceId 一致)
String wereadGuestSignature(
  String token,
  int random,
  int timestamp,
  String oldDeviceId,
) {
  final parts = <List<int>>[
    wereadRemapBytes(token),
    wereadRemapBytes('$random'),
    wereadRemapBytes('$timestamp'),
    wereadRemapBytes(oldDeviceId),
    utf8.encode(wereadGuestSalt),
  ]..sort(wereadCompareBytes);

  final joined = <int>[];
  for (final part in parts) {
    joined.addAll(part);
  }
  final first = sha256.convert(wereadRotateByXor(joined)).toString();
  return sha256.convert(wereadRotateByXor(utf8.encode(first))).toString();
}

/// 生成指定长度的纯数字随机串(设备 ID)。
String wereadRandomDigits(Random random, int length) {
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write(random.nextInt(10));
  }
  return buffer.toString();
}

/// 游客登录的设备状态(deviceId / installId / newDeviceId)。
///
/// 设备 ID 需在预登录、验证码重试、正式登录之间保持一致,
/// 因此由调用方持久化复用,不要每次重新生成。
class WereadGuestDeviceState {
  final String oldDeviceId;
  final String installId;
  final String newDeviceId;
  final Random random;

  const WereadGuestDeviceState({
    required this.oldDeviceId,
    required this.installId,
    required this.newDeviceId,
    required this.random,
  });

  /// 创建新的设备状态(或复用已持久化的设备 ID)。
  factory WereadGuestDeviceState.create({
    String? oldDeviceId,
    String? installId,
    String? newDeviceId,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    return WereadGuestDeviceState(
      oldDeviceId: _validDigits(oldDeviceId, 28) ?? wereadRandomDigits(rng, 28),
      installId: _validDigits(installId, 28) ?? wereadRandomDigits(rng, 28),
      newDeviceId: _validDigits(newDeviceId, 38) ?? wereadRandomDigits(rng, 38),
      random: rng,
    );
  }

  static String? _validDigits(String? value, int length) {
    if (value != null && value.length == length && RegExp(r'^\d+$').hasMatch(value)) {
      return value;
    }
    return null;
  }
}
