// EPUB 操作的稳定 API 契约
//
// 所有具体功能模块（reformat、s2t、img_compress 等）必须实现 EpubOperation 抽象类。
// 设计目标：模块间完全解耦——任何模块被修改后，理论上其他模块的 import 列表不会断裂，
// 只要模块仍实现 EpubOperation 接口，UI 就能继续工作。
//
// 解耦原则：
// 1. 模块目录独立（lib/features/<feature>/），模块间不互相 import
// 2. 工具副本内化（epub_image_helper 等共享代码按需复制到各模块内）
// 3. 唯一的"框架代码"放 lib/core/，本文件属于这一层

/// EPUB 操作抽象基类
///
/// 每个具体功能（reformat、s2t、img_compress 等）都必须继承此抽象类。
/// 这种"反插件"设计保证：所有功能都通过同一个入口被 UI 调用，
/// 模块间没有直接的类型依赖（除本接口）。
abstract class EpubOperation {
  /// 全局唯一 ID（用于日志、注册表、用户偏好等）
  /// 建议格式：`<category>.<action>`，如 `text.reformat`
  String get id;

  /// 用户可见的名称（中文）
  String get displayName;

  /// 用户可见的描述（中文，一句话）
  String get description;

  /// 输出文件扩展名（如 'epub'、'txt'、'cover.jpg'）
  /// 多个用 '|' 分隔（如 'jpg|png|webp'）
  String get outputExtension;

  /// 入口：执行操作
  ///
  /// [epubPath] 输入 EPUB 路径（可为空，对 view_opf 等只读操作）
  /// [outputPath] 输出路径（UI 端保证非空）
  /// [onProgress] 进度回调（0-100）
  /// 返回用户可见的日志字符串（含操作过程、错误提示）
  Future<String> execute({
    required String epubPath,
    required String outputPath,
    void Function(int progress)? onProgress,
  });
}
