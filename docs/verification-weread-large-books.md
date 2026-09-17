# 读书想法大书稳定性验证

日期：2026-09-17

## 问题与范围

用户反馈《修真聊天群》有三千多章、十万条想法，获取完成后应用闪退。
本次未获得该书原始 EPUB、真实想法响应或故障设备崩溃日志，因此不能确认操作系统是否因 OOM 或无响应终止进程。
代码检查确认原流程在界面 isolate 内执行重型匹配、注入和压缩，并同时保留全书 HTML、多个 Archive 与完整 ZIP 字节，存在明显的内存和响应风险。

本次修复覆盖获取完成后的交接、章节匹配、逐章注入、流式输出及进度日志。
网络请求协议、限速规则、段评内容和既有章评/书评展示数量上限不变。
没有用截断十万条想法的方式通过压力测试。

## 实现

- 独立 isolate 执行重型处理。请求只携带数据及 SendPort，回调仍在调用方执行，不将页面 State 或 native 资源闭包发送到 worker。
- ZIP 由 InputFileStream 支撑。每次读取使用新的压缩数据切片，避免 archive 3.6.1 的惰性解压缓存长期持有所有章节。
- 逐文件注入并写入 OutputFileStream，未改动图片、字体等资源直接传递原压缩数据。
- 保留 mimetype 首条、STORED、无 extra field 和规范内容要求，以及既有 XHTML 标准化。
- 同目录临时输出在完成后替换目标；失败清理临时文件，不覆盖输入书籍或损坏已有输出。
- 前缀索引替代每个文件对所有章节的反复全文扫描；投票最多保留四个目标，标题保留足以判断歧义的四个命中。
- worker 进度约每 200ms 发送一次，页面约每 500ms 接收一次常规更新，阶段切换和完成不丢弃；页面进度文本和最终日志均有界。

仍需保存获取到的想法数据，且单个特别巨大的 XHTML 仍需按文件载入、分词和注入；本次不是任意输入下的恒定内存保证。

## 自动测试

### 压力场景

`test/operations/weread_large_book_test.dart`

- 原创 3,200 个章节，每章 8 段划线，每段 4 条不同想法，共 102,400 条。
- 每章附带约两千字正文，另含压缩、未压缩和空资源。
- 检查 25,600 个想法锚点以及全部 102,400 条段评，书评页和额外资源存在且内容正确。
- 检查输入文件 SHA256 未变化；输出首条为规范 mimetype。
- 在处理期间以 20ms 定时器观测调用方事件循环，回调还持有不可发送的 ReceivePort，以验证隔离边界。
- 验证错误传回调用方、拒绝覆盖输入、失败不损坏已有输出、临时目录清理。

一次独立本机运行记录：

```text
chapters=3200 thoughts=102400
elapsedMs=11729 heartbeat=586
rssStartMiB=200 rssPeakMiB=273
```

RSS 是 macOS Flutter 测试进程总驻留内存，包括运行时、夹具和测试框架，并非手机安装包峰值。
耗时和内存只记录为诊断数据，不用易波动的绝对数值作跨平台测试门槛。

### 匹配一致性

`test/chapter_mapper_test.dart` 使用固定随机种子生成 35 组文件与章节。
以独立全文扫描参考实现核对全部映射目标和 quoteOnly 标志，覆盖重复引文、共享前缀、中文标题、补充平面字符、单引文多目标、拆分章、标题兜底和目录页。

### 检查命令

```sh
flutter analyze --no-pub lib test/chapter_mapper_test.dart test/operations/weread_large_book_test.dart
flutter test --no-pub test/chapter_mapper_test.dart test/operations/weread_large_book_test.dart
flutter test --no-pub test/operations/weread_reviews_injection_test.dart test/weread_thoughts_layout_test.dart test/weread_api_guest_test.dart
flutter test --no-pub --concurrency=1
```

应用源码及新增测试静态分析无问题，两组针对性回归共 21 项通过。
最终串行全量回归 272 项通过、20 项因夹具或显式输入要求跳过、0 失败，耗时约 94 秒。
全仓 `flutter analyze --no-pub` 仍有旧测试、第三方源码及历史工具中的 508 条诊断，本次未修改无关代码。

## 真实 EPUB

使用用户此前提供的 `C43-王立群读史记套装-王立群-手机.epub`，
对真实正文进行受控离线段评、章评和书评注入，检查三种标记均出现在正确输出中。
这不代表使用《修真聊天群》真实数据。

输出位于忽略目录 `build/weread-large-verification/33_offline_weread/out.epub`，
独立 `tool/audit_epub_outputs.py` 检查源书和产物的 ZIP CRC、mimetype、XML、manifest/spine 和资源/锚点引用：
两份文件结构错误 0、引用警告 0。审计 JSON 留在本地输出目录，不上传书籍。

## 尚未验证

- 未使用《修真聊天群》的真实平台账号、完整返回数据及该书原始 EPUB 复现用户设备上的崩溃。
- 未取得 Android/iOS 设备 OOM、watchdog 或原生崩溃日志。
- 未在低内存手机上测量峰值；后续实机复测需要用户原书与设备信息。
