# EPUB ZIP 密码使用与 KMP 阅读器接入

## 用户怎么添加密码

1. 打开“安全加密 → EPUB ZIP 密码”。
2. 选择“添加密码”。
3. 选择原始 EPUB。
4. 输入并确认密码。密码必须为 8–64 位可打印 ASCII 字符。
5. 选择输出位置，点击“添加密码”。

工具不是把整个 EPUB 文件作为一个条目再套进另一层 ZIP。实际流程是：

```text
原始 EPUB ZIP
  → 读取并解压 mimetype、META-INF、OPF、正文、图片、字体等条目
  → 保持所有条目的原始相对路径
  → 使用密码把这些条目重新打包
  → 输出 encrypted.epub
```

输出文件继续使用 `.epub` 扩展名。文件内容已加密，ZIP 内的文件名和文件大小仍然
可见。普通阅读器不能直接打开，支持该功能的阅读器可以输入密码后直接把内部条目
解压到私有临时目录，然后交给 EPUB 解析器，不必先生成另一份无密码 EPUB 文件。

不要覆盖或删除未加密的原文件，除非已经确认目标阅读器能够正确解密。

## 用户怎么解除密码

1. 打开“安全加密 → EPUB ZIP 密码”。
2. 选择“解除密码”。
3. 选择带密码的 EPUB，输入原密码。
4. 选择输出位置，点击“解除密码”。

工具会验证密码和每个条目的认证码，并重新打包为标准 EPUB。恢复后的
`mimetype` 位于 ZIP 第一项，使用 STORE 模式且不包含额外字段，可以交给普通 EPUB
阅读器使用。密码错误、认证失败或文件损坏时，不会留下半成品输出。

## 文件格式

重新打包阶段使用标准 WinZip AES，而不是传统 ZipCrypto，也不是 EPUB DRM：

| 参数 | 当前值 |
| --- | --- |
| ZIP 通用标志 | bit 0，条目已加密；bit 11，UTF-8 文件名 |
| ZIP 方法号 | `99`（WinZip AES） |
| AES extra field | Header ID `0x9901`，vendor `AE` |
| 格式版本 | AE-1 |
| 强度 | `3`，AES-256 |
| 实际压缩方法 | extra field 中的 STORE 或 DEFLATE |
| 盐 | 每个条目独立的 16 字节随机盐 |
| 密钥派生 | PBKDF2-HMAC-SHA1，1000 次 |
| 派生结果 | 32 字节 AES key + 32 字节 HMAC key + 2 字节密码校验值 |
| 数据加密 | AES-CTR，计数器从 1 开始 |
| 完整性认证 | HMAC-SHA1 的前 10 字节 |
| 文件名 | 不加密 |

上述格式遵循 [WinZip AES 规范](https://www.winzip.com/en/support/aes-encryption/#zip-format)。
工具目前只允许 ASCII 密码，是为了避免不同库对非 ASCII 密码字符串编码方式不同。

## KMP 阅读器是否容易接入

可以接入，难度中等。主要问题不是 EPUB 解析，而是 KMP 各目标没有统一支持
WinZip AES 的标准 ZIP API。推荐在 `commonMain` 定义普通接口，通过依赖注入提供平台
实现；Kotlin 官方也推荐用接口封装平台依赖，而不是让公共代码依赖具体平台类型。

推荐组合：

- Android、JVM Desktop：使用 [Zip4j](https://github.com/srikanth-lingala/zip4j)。
  它支持 AES、密码 ZIP、UTF-8 文件名、流和进度信息。
- iOS、macOS Native：使用
  [SSZipArchive](https://github.com/ZipArchive/ZipArchive)。其 Objective-C 接口支持检测
  密码、验证密码和解压 WinZip AES，适合通过 CocoaPods/SPM 或一个很薄的 Swift
  bridge 接入。
- 如果还有 Kotlin/Native Windows 或 Linux 目标：使用
  [minizip-ng](https://github.com/zlib-ng/minizip-ng) 的 C interop。它原生支持 WinZip
  AES，但构建和分发成本高于前两种方案。

不建议为了“全部写在 commonMain”自行实现 ZIP 中央目录、PBKDF2、AES-CTR、HMAC
和 DEFLATE。解析边界、Zip64、CRC、认证码以及路径安全都容易出现问题。

## 推荐的公共接口

平台文件类型通常已经由阅读器自己的文件系统层封装。公共层只需要表达业务结果：

```kotlin
interface EncryptedEpubExtractor {
    suspend fun isEncrypted(input: ReaderFile): Boolean

    /**
     * 使用密码直接解压到阅读器的私有临时目录。
     * 成功后返回可供现有 EPUB 解析器读取的目录。
     */
    suspend fun extract(
        input: ReaderFile,
        password: String,
        destination: ReaderDirectory,
    ): EpubUnlockResult
}

sealed interface EpubUnlockResult {
    data class Success(val directory: ReaderDirectory) : EpubUnlockResult
    data object WrongPassword : EpubUnlockResult
    data object NotEncrypted : EpubUnlockResult
    data class InvalidEpub(val reason: String) : EpubUnlockResult
    data class IoError(val cause: Throwable) : EpubUnlockResult
}
```

如果项目不使用依赖注入，也可以使用 `expect`/`actual` 工厂函数。Kotlin 官方文档说明
了公共声明与平台实现的对应方式：
[Expected and actual declarations](https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html)。

## JVM / Android 实现

依赖：

```kotlin
// jvmMain 或 androidMain
dependencies {
    implementation("net.lingala.zip4j:zip4j:2.11.6")
}
```

核心代码：

```kotlin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.exception.ZipException
import java.io.File

suspend fun extractEncryptedEpub(
    source: File,
    destination: File,
    password: String,
): EpubUnlockResult = withContext(Dispatchers.IO) {
    val chars = password.toCharArray()
    try {
        val zip = ZipFile(source, chars)
        if (!zip.isEncrypted) return@withContext EpubUnlockResult.NotEncrypted

        destination.mkdirs()
        zip.extractAll(destination.absolutePath)
        validateExtractedEpub(destination)
        EpubUnlockResult.Success(destination.asReaderDirectory())
    } catch (error: ZipException) {
        when (error.type) {
            ZipException.Type.WRONG_PASSWORD -> EpubUnlockResult.WrongPassword
            ZipException.Type.CHECKSUM_MISMATCH ->
                EpubUnlockResult.InvalidEpub("AES 认证或 ZIP 校验失败")
            else -> EpubUnlockResult.IoError(error)
        }
    } finally {
        chars.fill('\u0000')
    }
}
```

Android 的 `content://` URI 不能直接当作 `File` 传给 Zip4j。先通过
`ContentResolver.openInputStream()` 复制到应用私有缓存，再执行检测和解压。

本工具已使用 Zip4j 2.11.6 对约 30 MB 的真实加密 EPUB 做过互操作验证，Zip4j 能
识别其为加密 ZIP，并成功解出全部 50 个条目和正确的 `mimetype`。

## iOS / macOS Native 实现

SSZipArchive 提供这些直接可用的 Objective-C API：

- `isFilePasswordProtectedAtPath:`
- `isPasswordValidForArchiveAtPath:password:error:`
- `unzipFileAtPath:toDestination:overwrite:password:error:`

Swift bridge 的核心调用可以保持很薄：

```swift
import SSZipArchive

func extractEncryptedEpub(
    source: URL,
    destination: URL,
    password: String
) throws {
    var error: NSError?
    let ok = SSZipArchive.unzipFile(
        atPath: source.path,
        toDestination: destination.path,
        overwrite: false,
        password: password,
        error: &error
    )
    if !ok {
        throw error ?? ReaderArchiveError.decryptFailed
    }
}
```

可以让 Swift 层实现公共接口的桥接，也可以通过 Kotlin CocoaPods 插件把
SSZipArchive 暴露给 `iosMain`。前者通常更容易调试和处理系统文件 URL；后者能把
更多逻辑留在共享模块。应按项目的当前安装说明选择 CocoaPods 或 SPM，并固定经过
测试的版本，不要直接跟随 `master`；SSZipArchive 的最低系统版本会随版本变化。

## 导入和打开流程

```text
用户选择 EPUB
  → 复制到应用私有缓存
  → 检测 ZIP 是否加密
      → 未加密：进入现有 EPUB 打开流程
      → 已加密：弹出密码框
          → 使用密码直接解压到唯一临时目录
          → 校验 EPUB 必需结构
          → 交给现有解析器打开
          → 关闭书籍或应用退出时清理明文缓存
```

不要在输入密码前尝试读取 `mimetype` 的内容，因为该条目本身也已加密。可以使用
Zip4j/SSZipArchive 的加密检测 API，或检查中央目录中通用标志 bit 0、方法号 99 和
`0x9901` extra field。

解密后至少校验：

1. `mimetype` 内容等于 `application/epub+zip`。
2. 存在 `META-INF/container.xml`。
3. `container.xml` 指向的 OPF 文件存在。
4. 所有解压目标的规范化路径仍位于临时目录内，拒绝 `../`、绝对路径和逃逸符号链接。
5. 解压库已读取所有条目并验证 AES HMAC，不能只验证两字节密码校验值。

## 密码和明文缓存

- 默认不要永久保存密码；确需“记住密码”时使用 Android Keystore 或 Apple Keychain。
- 不要把密码、解密 URL、异常中的密码内容写入日志或崩溃上报。
- 解压目录使用每本书独立的随机名称，并限制为应用私有目录。
- 解密过程中先写临时目录，全部成功并验证 EPUB 后再标记为可用。
- 密码错误时立即清理已解出的部分文件。
- 关闭书籍、退出账户或应用收到存储压力时清理明文缓存。
- 解析器如果能从解压目录工作，没必要再生成一份无密码 EPUB，能减少明文副本和 I/O。

## 接入测试清单

- 正确密码可以打开目录、封面、正文、图片和字体。
- 错误密码不会留下任何可读正文或半成品目录。
- 中文文件名和深层目录正常。
- STORE 与 DEFLATE 条目都能读取。
- 篡改密文或 10 字节认证码后必须失败。
- 大文件不会在 UI 线程解密，并能显示进度或取消。
- 应用重启、关闭书籍和清理缓存后没有遗留明文。
- Android、iOS、JVM Desktop 各使用同一份加密夹具做互操作测试。
