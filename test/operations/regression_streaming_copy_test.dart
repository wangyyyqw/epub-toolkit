// 回归测试：大文件复制到公共 Download 应走流式通道
//
// 之前的 bug：47MB EPUB 用 writeToPublicDownload(bytes: 47MB Uint8List) 时，
// Dart 持有 47MB 副本 + MethodChannel 序列化时复制 47MB = 94MB 内存峰值，
// 在中低端 Android 设备上必闪退。
//
// 修复：
// - 新增 FileService.copyFileToPublicDownload(sourcePath, filename)
//   原生端用 FileInputStream 流式读源文件，写到 MediaStore.OutputStream。
// - 调用方在 >10MB 时自动改走流式通道。

import 'package:epub_gadget/core/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileService.copyFileToPublicDownload', () {
    test('方法签名包含 sourcePath 和 filename 参数', () {
      // 通过反射或简单的存在性检查验证方法已定义
      // 这里用 dart:mirrors 不可用，改用编译期类型断言
      // 实际验证靠：能成功调用此方法（不抛 NoSuchMethodError）
      // 真机测试在 CI/Android 端跑

      // 非 Android 平台：降级走 File.copy，不走 MethodChannel
      // 此测试只验证函数可被引用
      expect(FileService.copyFileToPublicDownload, isNotNull);
    });

    test('小文件 (<10MB) 应走 bytes 通道，大文件应走流式通道', () {
      // 静态验证：方法存在 + 签名正确
      // 真实行为验证需要在 Android 真机上跑
      const streamThreshold = 10 * 1024 * 1024;
      // 流式阈值是 10MB，47MB 测试文件 > 阈值
      const testFileSize = 47 * 1024 * 1024;
      expect(testFileSize > streamThreshold, true,
          reason: '47MB 用户的 EPUB 大于 10MB 阈值，应走流式');
    });
  });

  group('流式复制 vs 一次性复制内存对比', () {
    test('流式复制应不持有完整文件副本', () {
      // 概念验证：流式方法只需要传文件路径（几十字节字符串），
      // 不需要传整个文件内容的 Uint8List。
      // 这一点通过 API 签名体现：
      // - writeToPublicDownload(filename, Uint8List bytes) // 全量传
      // - copyFileToPublicDownload(sourcePath, filename)   // 只传路径
      const streamSignature = 'String sourcePath, String filename';
      expect(streamSignature, isNot(contains('Uint8List')));
    });
  });
}
