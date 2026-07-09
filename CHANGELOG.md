# 更新日志

## 1.0.0 - 2026-07-09

### 新增

- 将项目初始发布版本设置为 `1.0.0+1`。
- 新增 GitHub Actions 自动构建流程。
- 支持在 GitHub 上自动构建 Android APK、macOS 应用、Windows 应用和 iOS 无签名应用包。
- 构建版本号从 `1.0.0` 开始，后续每次 GitHub Actions 构建按 `1.0.1`、`1.0.2` 递增。

### 调整

- 调整 Android 忽略规则，允许提交 CI 构建必需的 Gradle Wrapper 文件。
- 保持签名文件和本地配置文件被忽略，避免上传 keystore、`local.properties` 等敏感或本机专用文件。

### 清理

- 新增根目录 `.gitignore`，忽略 Flutter/Dart 构建产物、本地缓存和发布包目录。
- 清理本地编译产物、发布包、平台缓存和不可达 Git 大对象。
