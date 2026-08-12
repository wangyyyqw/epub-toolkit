// 游客登录签名算法测试
//
// 测试向量由书源(微信读书二合一本地源)中的 JS 原样实现
// (node + crypto sha256)生成,验证 Dart 移植逐字节一致:
//   {"token":"guest_token_abc123","random":123456789,"ts":1786457291,
//    "dev":"1111111111111111111111111111",
//    "sig":"dd202e63c9610788660595167b586620effd414f9e3517904a404e93d3e82fe4"}
// 等共 4 组。

import 'package:epub_gadget/features/weread_thoughts/weread_guest_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wereadGuestSignature(与书源 JS 向量交叉验证)', () {
    const vectors = [
      (
        token: 'guest_token_abc123',
        random: 123456789,
        ts: 1786457291,
        dev: '1111111111111111111111111111',
        sig: 'dd202e63c9610788660595167b586620effd414f9e3517904a404e93d3e82fe4',
      ),
      (
        token: 'hello世界',
        random: 42,
        ts: 1700000000,
        dev: '2222222222222222222222222222',
        sig: '269c8c297543a17abed0469fbee8f56aa2c4139f596238adb09aed9ecb448bc6',
      ),
      (
        token: '',
        random: 0,
        ts: 0,
        dev: '3333333333333333333333333333',
        sig: 'e04aa660ae5de1433ca5477439679023feafdf787ec5ddc063ea67a3415a3160',
      ),
      (
        token: 'a',
        random: 2147483647,
        ts: 9999999999,
        dev: '4444444444444444444444444444',
        sig: 'f08fd0ff4d27b32ef138ec03a1f55d816bd8e6a25f4f66638cdbdf3a58878cd1',
      ),
    ];

    for (final v in vectors) {
      test('token=${v.token == "" ? "(空)" : v.token} random=${v.random}', () {
        expect(
          wereadGuestSignature(v.token, v.random, v.ts, v.dev),
          v.sig,
        );
      });
    }
  });

  group('wereadRotateByXor(与书源 JS 向量交叉验证)', () {
    test('移位示例', () {
      // JS: wrRotateByXor([1,2,3,4,5]) -> 5,1,2,3,4 (xor=1, shift=1)
      expect(wereadRotateByXor([1, 2, 3, 4, 5]), [5, 1, 2, 3, 4]);
    });

    test('全 0 输入保持全 0', () {
      expect(wereadRotateByXor([0, 0, 0]), [0, 0, 0]);
    });

    test('空输入返回空', () {
      expect(wereadRotateByXor([]), isEmpty);
    });
  });

  group('WereadGuestDeviceState', () {
    test('合法设备 ID 被复用', () {
      final state = WereadGuestDeviceState.create(
        oldDeviceId: '1234567890123456789012345678', // 28 位
        installId: '1234567890123456789012345678',
        newDeviceId: '12345678901234567890123456789012345678', // 38 位
      );
      expect(state.oldDeviceId, '1234567890123456789012345678');
      expect(state.installId, '1234567890123456789012345678');
      expect(state.newDeviceId, '12345678901234567890123456789012345678');
    });

    test('非法设备 ID 重新生成且位数正确', () {
      final state = WereadGuestDeviceState.create(
        oldDeviceId: 'short',
        installId: 'abcdefghijklmnopqrstuvwxyz12',
        newDeviceId: '',
      );
      expect(state.oldDeviceId.length, 28);
      expect(state.installId.length, 28);
      expect(state.newDeviceId.length, 38);
      expect(RegExp(r'^\d+$').hasMatch(state.oldDeviceId), isTrue);
      expect(RegExp(r'^\d+$').hasMatch(state.installId), isTrue);
      expect(RegExp(r'^\d+$').hasMatch(state.newDeviceId), isTrue);
    });
  });

  group('wereadRemapTable', () {
    test('REMAP 表长度为 256', () {
      expect(wereadRemapTable().length, 256);
    });

    test('REMAP 表所有值在 0~255 且唯一(为置换表)', () {
      final table = wereadRemapTable();
      expect(table.toSet().length, 256, reason: 'REMAP 应为 256 字节置换表');
      for (final v in table) {
        expect(v, inInclusiveRange(0, 255));
      }
    });
  });
}
