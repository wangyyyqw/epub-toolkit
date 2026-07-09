# EPUB 工具箱

一站式 EPUB 电子书处理工具，基于 Flutter 重写，目标是把常用 EPUB 清理、转换、修复、批注和字体处理功能集中到一个跨平台应用里。

本项目由 [wangyyyqw/epub-gadget](https://github.com/wangyyyqw/epub-gadget) 重写而来。

## 致谢

感谢以下项目和作者提供的思路、实现参考或相关工具：

- [遥遥心航](https://tieba.baidu.com/home/main?id=tb.1.7f262ae1.5_dXQ2Jp0F0MH9YJtgM2Ew)
- [lgernier](https://github.com/lgernier)
- [fontObfuscator](https://github.com/solarhell/fontObfuscator)
- [未响应](https://github.com/cnwxi)

## 注意

Kindle 邮件发送功能可能还没有完全写好，我手头没有 Kindle 设备做完整实机测试。如果这个功能无法发送、发送后 Kindle 没收到，或其它功能没有生效、输出文件错误，请发邮件到 `wanmei8672873@outlook.com`，或提交 issue 说明问题、输入文件特征、操作步骤和输出结果，我会按反馈修复。

## 功能

### 文件转换

- TXT 转 EPUB
- EPUB 转 TXT
- EPUB 2.0 与 3.0 互转
- 简体转繁体
- 繁体转简体

### EPUB 结构处理

- 查看 OPF 元数据
- 编辑元数据
- 替换封面图片
- 重新格式化 EPUB 内部结构
- 合并多个 EPUB
- 按章节拆分 EPUB
- 列出可拆分章节目标

### 图片处理

- 压缩 EPUB 内图片
- 图片转 WebP
- WebP 转 JPEG/PNG
- 下载 EPUB 中引用的网络图片

macOS 打包版会内置 `cwebp`，图片转 WebP 不需要用户额外安装命令行工具。Windows 端支持随程序放置 `bin/cwebp.exe`。

### 字体处理

- 字体子集化
- 字体加密
- 列出字体加密目标
- EPUB 名称混淆加密
- EPUB 名称混淆解密

### 批注和脚注

- 弹窗批注提取
- 标准脚注转弹窗注释
- 弹窗注释转脚注
- 阅微转多看
- 得到/掌阅转多看

### 阅读和推送辅助

- Kindle 邮箱推送
- 应用内打开 Send to Kindle 网页
- Kindle 传书教程

## 支持平台

项目使用 Flutter 构建，当前主要在 macOS 和 Android 上开发测试。Windows、iOS、Linux 保留工程配置，但部分功能可能还需要实际平台测试。

## 开发

```bash
flutter pub get
flutter run
```

## 测试

```bash
flutter analyze lib
flutter test
```

真实书籍全功能测试需要本地测试 EPUB 文件，不随仓库提交。

## 打包

Android:

```bash
flutter build apk --release
```

macOS:

```bash
flutter build macos --release
tool/bundle_cwebp_macos.sh "build/macos/Build/Products/Release/EPUB 工具箱.app"
```

## Android 签名

不要提交真实签名文件。复制示例文件后填入本地配置：

```bash
cp android/key.properties.example android/key.properties
```

`android/key.properties` 和 `android/app/*.jks` 已加入忽略列表。
