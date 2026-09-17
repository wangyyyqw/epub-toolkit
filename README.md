# EPUB 工具箱

一站式 EPUB 电子书处理工具，基于 Flutter 重写，目标是把常用 EPUB 清理、转换、修复、批注和字体处理功能集中到一个跨平台应用里。

本项目由 [wangyyyqw/epub-gadget](https://github.com/wangyyyqw/epub-gadget) 重写而来。

## 致谢

感谢以下项目和作者提供的思路、实现参考或相关工具：

- [遥遥心航](https://tieba.baidu.com/home/main?id=tb.1.7f262ae1.5_dXQ2Jp0F0MH9YJtgM2Ew)
- [lgernier](https://github.com/lgernier)
- [fontObfuscator](https://github.com/solarhell/fontObfuscator)
- [epub_tool](https://github.com/cnwxi)
- [pickthought.koplugin](https://github.com/Mr54233/pickthought.koplugin)

## 注意

Kindle 邮件发送功能可能还没有完全写好，我手头没有 Kindle 设备做完整实机测试。如果这个功能无法发送、发送后 Kindle 没收到，或其它功能没有生效、输出文件错误，请发邮件到 `wanmei8672873@outlook.com`，或提交 issue 说明问题、输入文件特征、操作步骤和输出结果，我会按反馈修复。

## 功能

### 文件转换

- TXT 转 EPUB（导入后自动识别多级章节，支持可编辑正则、预览排除误识别、阅微/Kindle 章节头图和全屏首页）
- EPUB 转 TXT
- EPUB 2.0 与 3.0 互转
- 简体转繁体
- 繁体转简体

### EPUB 结构处理

- 编辑元数据并查看完整 OPF 源码
- 替换封面图片
- 重新格式化 EPUB 内部结构
- EPUB 体检与选择性修复：检查 ZIP、`mimetype`、OPF、manifest、spine、NAV/NCX、资源与锚点、重复 ID、媒体类型、封面和字体引用，按错误/警告/建议分类展示并导出 HTML/JSON 报告
- 可视化目录与导航编辑：树状调整标题、链接、层级和顺序，可从正文 H1-H6 重建目录，并同步维护 EPUB 3 NAV、EPUB 2 NCX、landmarks 与 `page-list`
- 合并多个 EPUB
- 按章节拆分 EPUB
- 列出可拆分章节目标

### 批量工作流

- 一次导入多个 EPUB 或递归扫描整个目录
- 组合、排序、启停处理步骤，并保存可复用的自定义配方
- 内置“标准优化”“批量体检”“兼容性整理”配方
- 支持 1-4 个任务并发、暂停、完成当前步骤后取消、失败重试和跳过已有输出
- 每本书可导出体检报告，整个批次导出 JSON/HTML 汇总

### 图片处理

- 压缩 EPUB 内图片
- 图片转 WebP
- WebP 转 JPEG/PNG
- 下载 EPUB 中引用的网络图片

GitHub Release 的 macOS 应用和 Windows 安装程序都会内置 `cwebp`，图片转
WebP 不需要用户额外安装组件，也不需要配置环境变量；安装后可以离线使用。

### 字体处理

- 字体子集化
- 字体加密
- 导入 EPUB 后自动扫描字体加密目标
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

字体子集化使用项目内固定版本的 HarfBuzz 14.2.1，通过 Dart native assets
随应用编译、打包，支持 CFF/OTF 和包含 GSUB 的 TTF。运行时不需要安装
Python、HarfBuzz 命令行或 Homebrew。构建机需要对应平台的 C++ 工具链。
`third_party/epubx` 保存中文、百分号编码和嵌套目录的路径兼容修复；
两个本地依赖的来源、许可证和改动均记录在各自的 `LOCAL_CHANGES.md`。

EPUB 体检的内置快速检查可在所有支持平台运行。macOS、Windows、Linux
还可以在“EPUB 体检与修复”页面运行可选的 EPUBCheck 完整检查，本项目不捆绑
EPUBCheck。应用按以下顺序寻找可执行入口：

1. `EPUBCHECK_JAR` 指向 EPUBCheck JAR，并确保 `java` 在 `PATH` 中。
2. `EPUBCHECK_COMMAND` 指向可直接执行的 EPUBCheck 命令。
3. 在 `PATH` 中寻找名为 `epubcheck` 的命令。

未安装 EPUBCheck 不影响内置体检、选择性修复或其它功能。

## 测试

```bash
flutter analyze lib
flutter test
```

完整真实书籍回归需按“生成产物、补充流程、阅读器导入”的顺序执行：

```bash
bash tool/verify_real_epub.sh /absolute/path/book.epub build/real-book-check
```

输出目录必须尚不存在。使用 `FLUTTER_BIN` 可指定 Flutter 可执行文件。
不要给整个 `flutter test` 设置 `REAL_EPUB_OUTPUT`，否则不同测试文件会并行
读写尚未完成的产物。测试会保留结果和报告，不修改输入 EPUB。
WiFi 传输通过本机 HTTP 验证；微信读书注入和远程图片使用受控离线响应，
不等同于真实账号登录、SMTP 邮件发送或外部阅读器人工验收。

真实书籍全功能测试需要本地测试 EPUB 文件，不随仓库提交。

```bash
REAL_EPUB_INPUT=/absolute/path/book.epub \
REAL_EPUB_OUTPUT=/absolute/path/existing-output-directory \
flutter test test/real_book_reader_test.dart

# 只验证字体缩减，输出路径必须尚不存在。
REAL_EPUB_INPUT=/absolute/path/book.epub \
FONT_EPUB_OUTPUT=build/font-check/subset.epub \
flutter test test/operations/harfbuzz_subsetter_test.dart
```

独立字体检查工具 `tool/audit_epub_fonts.py` 使用 fontTools；
`tool/audit_epub_font_shaping.py` 额外使用 uharfbuzz，比较全书横排/竖排的字形、
字距与位置。这些 Python 依赖仅用于开发审计，不属于应用运行依赖。

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

Windows（需在 Windows 主机执行）：

```powershell
flutter build windows --release
& "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe" windows\installer.iss
```

GitHub Actions 在推送 `main` 后自动执行检查和四平台打包，全部通过后，
为尚未发布的 `pubspec.yaml` 版本创建 tag（如 `v1.6.3`）并发布。
也支持推送匹配版本的 tag，或在 `main`/该 tag 上手动运行。PR 只运行检查。
已有版本/tag 不移动、不覆盖发布附件；再次发布须提升版本。
CI 构建号使用工作流运行编号；工具链统一固定为 Flutter 3.44.0 并严格使用锁文件。

检查与四平台编译并行，但发布仍要求全部成功。Gradle 启用构建缓存和受限并行，
检查跳过重复 `pub get`，已压缩产物上传不再二次压缩。
原生 release 构建保留 Flutter 默认准备流程，不传 `--no-pub`；
Flutter 3.44 需要这一步重新生成不含测试插件的 release 注册文件。
Actions 摘要提供构建耗时；`build-logs-*` 附件保留诊断日志 14 天。
发布正文自动提取本版 CHANGELOG，附带源码提交、运行链接、各平台文件大小；
`SHA256SUMS.txt` 与 `build-metadata.json` 提供校验和、构建环境与任务时间记录。

工作流会自动生成 `epub-toolkit-windows-*-setup.exe` 安装程序，并作为
GitHub Release 附件发布。Flutter 的原始程序目录包含 DLL 和资源文件，不能只复制
其中的 `epub_gadget.exe` 单独运行。

## Android 签名

签名密钥库与 `android/key.properties` 已被 Git 忽略，不应提交。
本地 release 构建按 `android/key.properties.example` 配置；
CI 需要配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 四项 GitHub Secrets。
工作流将密钥库解码为临时文件并设置 `ANDROID_KEYSTORE_FILE`。

缺少签名配置或密钥库时，release 构建会失败，不再降级为 debug 签名。
调试构建仍使用调试签名。已有用户升级需要继续使用原正式签名密钥。
