import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/file_service.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../../shared/widgets/base_input.dart';
import '../../shared/widgets/base_select.dart';
import '../../shared/widgets/page_header.dart';
import '../view_opf/view_opf.dart';
import 'metadata_service.dart';

/// 元数据编辑页面
///
/// 提供完整的 EPUB 元数据读取、编辑和保存功能。
/// 用户选择 EPUB 文件后自动加载元数据，可编辑书名、作者、语言等字段，
/// 并支持封面图片的替换与移除。保存时将修改后的元数据写回 EPUB 文件。
class MetadataPage extends StatefulWidget {
  const MetadataPage({super.key});

  @override
  State<MetadataPage> createState() => _MetadataPageState();
}

class _MetadataPageState extends State<MetadataPage> {
  /// 选择的 EPUB 文件路径
  String? _epubPath;

  /// 输出 EPUB 文件路径（自动生成：原文件名_metadata.epub）
  String? _outputPath;

  /// 是否正在加载元数据或保存中
  bool _loading = false;

  /// 读取到的元数据，未加载时为 null
  MetadataData? _metadata;

  /// 格式化后的 OPF XML，按需读取
  String? _opfContent;

  /// 是否正在读取 OPF XML
  bool _opfLoading = false;

  /// 用户选择的新封面图片路径（替换封面时使用）
  String? _coverPath;

  /// 是否标记移除封面
  bool _coverRemoved = false;

  /// 预设语言选项
  static const _presetLanguages = ['zh-CN', 'zh-TW', 'en', 'ja', 'ko', '其他'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              icon: Icons.edit_note_outlined,
              iconColor: Color(0xFF10B981),
              title: '元数据编辑',
              description: '编辑书名、作者、封面等元数据，并查看完整 OPF 源码',
            ),
            const SizedBox(height: 12),
            // 卡片1：文件选择
            _buildFileSelectionCard(),
            // 加载完成后显示元数据编辑表单
            if (_metadata != null) ...[
              const SizedBox(height: 12),
              _buildMetadataEditCard(),
              const SizedBox(height: 12),
              _buildOpfCard(),
              const SizedBox(height: 16),
              _buildSaveButton(),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建文件选择卡片
  ///
  /// 提供 EPUB 文件选择按钮，选择后自动设置输出路径并加载元数据。
  Widget _buildFileSelectionCard() {
    final theme = Theme.of(context);
    return BaseCard(
      title: '文件选择',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 显示已选择的文件名
          if (_epubPath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.basename(_epubPath!),
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // 文件选择按钮 + 加载指示器
          Row(
            children: [
              BaseButton(
                label: '选择 EPUB 文件',
                icon: Icons.folder_open_outlined,
                onPressed: _loading ? null : _pickEpub,
                variant: BaseButtonVariant.secondary,
              ),
              if (_loading) ...[
                const SizedBox(width: 16),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在加载…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          // 显示输出路径
          if (_outputPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '输出：${p.basename(_outputPath!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建元数据编辑卡片
  ///
  /// 包含封面预览/操作区和 9 个元数据字段的编辑表单。
  Widget _buildMetadataEditCard() {
    return BaseCard(
      title: '元数据编辑',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面预览与操作区
          _buildCoverSection(),
          const SizedBox(height: 20),
          // 表单字段
          BaseInput(
            label: '书名',
            value: _metadata!.title,
            hint: '请输入书名',
            onChanged: (v) => _updateField(title: v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '副标题',
            value: _metadata!.subtitle,
            hint: '可选',
            onChanged: (v) => _updateField(subtitle: v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '作者',
            value: _metadata!.author,
            hint: '请输入作者',
            onChanged: (v) => _updateField(author: v),
          ),
          const SizedBox(height: 12),
          BaseSelect(
            label: '语言',
            value: _metadata!.language,
            items: _languageItems,
            onChanged: _onLanguageChanged,
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '出版者',
            value: _metadata!.publisher,
            hint: '可选',
            onChanged: (v) => _updateField(publisher: v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '描述',
            value: _metadata!.description,
            hint: '可选，书籍简介',
            onChanged: (v) => _updateField(description: v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '标识符',
            value: _metadata!.identifier,
            hint: '如 ISBN、UUID',
            onChanged: (v) => _updateField(identifier: v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '版权',
            value: _metadata!.rights,
            hint: '可选，版权声明',
            onChanged: (v) => _updateField(rights: v),
          ),
        ],
      ),
    );
  }

  /// 构建 OPF 源码卡片。
  ///
  /// XML 按需读取，避免仅编辑常规元数据时额外渲染完整 OPF 文档。
  Widget _buildOpfCard() {
    final theme = Theme.of(context);
    final content = _opfContent;

    return BaseCard(
      title: 'OPF 源码',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (content != null)
            IconButton(
              tooltip: '复制 OPF',
              icon: const Icon(Icons.copy_outlined, size: 20),
              onPressed: _copyOpf,
            ),
          TextButton.icon(
            onPressed: (_loading || _opfLoading) ? null : _loadOpf,
            icon: _opfLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    content == null ? Icons.code_outlined : Icons.refresh,
                    size: 18,
                  ),
            label: Text(content == null ? '查看 OPF' : '刷新'),
          ),
        ],
      ),
      child: content == null
          ? Text(
              '查看 EPUB 包中的完整 OPF XML，包括 metadata、manifest 和 spine。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  content,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ),
    );
  }

  /// 构建封面预览与操作区
  ///
  /// 左侧显示封面图片预览，右侧提供「替换封面」和「移除封面」按钮。
  Widget _buildCoverSection() {
    final theme = Theme.of(context);
    // 判断当前是否有封面可显示
    final hasNewCover = _coverPath != null;
    final hasOriginalCover = _metadata?.coverBytes != null && !_coverRemoved;
    final hasCover = hasNewCover || hasOriginalCover;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面预览区域
        Container(
          width: 120,
          height: 180,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasCover
              ? (hasNewCover
                    ? Image.file(
                        File(_coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _coverPlaceholder(theme),
                      )
                    : Image.memory(
                        _metadata!.coverBytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _coverPlaceholder(theme),
                      ))
              : _coverPlaceholder(theme),
        ),
        const SizedBox(width: 16),
        // 封面操作按钮
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '封面图片',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              BaseButton(
                label: '替换封面',
                icon: Icons.image_outlined,
                onPressed: _loading ? null : _pickCover,
                variant: BaseButtonVariant.secondary,
              ),
              const SizedBox(height: 8),
              BaseButton(
                label: '移除封面',
                icon: Icons.delete_outline,
                onPressed: (hasCover && !_loading) ? _removeCover : null,
                variant: BaseButtonVariant.danger,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建封面占位图标
  Widget _coverPlaceholder(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.menu_book_outlined,
        size: 48,
        color: theme.colorScheme.outline,
      ),
    );
  }

  /// 构建底部保存按钮
  Widget _buildSaveButton() {
    return Center(
      child: BaseButton(
        label: '保存',
        icon: Icons.save_outlined,
        loading: _loading,
        onPressed: _loading ? null : _save,
      ),
    );
  }

  /// 获取语言下拉选项
  ///
  /// 在预设选项基础上，若当前语言值不在预设列表中则动态追加，
  /// 确保 BaseSelect 的 value 始终在可选项中。
  List<String> get _languageItems {
    final items = <String>[..._presetLanguages];
    final current = _metadata?.language ?? 'zh-CN';
    // 当前语言不在预设列表中时，插入到「其他」之前
    if (current.isNotEmpty && !_presetLanguages.contains(current)) {
      items.insert(items.length - 1, current);
    }
    return items;
  }

  /// 选择 EPUB 文件并加载元数据
  ///
  /// 调用 FileService.pickEpub 选择文件，自动生成输出路径，
  /// 然后调用 MetadataService.read 读取元数据。
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;

    // 生成默认输出路径；桌面端与输入文件同目录。
    final filename = '${p.basenameWithoutExtension(path)}_metadata.epub';
    final safePath = await FileService.getDefaultOutputPathForInput(
      inputPath: path,
      filename: filename,
    );

    // 重置状态并开始加载
    setState(() {
      _epubPath = path;
      _outputPath = safePath;
      _metadata = null;
      _opfContent = null;
      _opfLoading = false;
      _coverPath = null;
      _coverRemoved = false;
      _loading = true;
    });

    try {
      final metadata = await MetadataService.read(path);
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      // 读取失败时显示错误提示
      context.read<ToastProvider>().showError('读取元数据失败：$e');
    }
  }

  /// 按需读取并格式化当前 EPUB 的 OPF XML。
  Future<void> _loadOpf() async {
    final path = _epubPath;
    if (path == null || _opfLoading) return;

    setState(() => _opfLoading = true);
    try {
      final content = await ViewOpfOperation.execute(path);
      if (!mounted) return;
      setState(() => _opfContent = content);
    } catch (e) {
      if (!mounted) return;
      context.read<ToastProvider>().showError('读取 OPF 失败：$e');
    } finally {
      if (mounted) setState(() => _opfLoading = false);
    }
  }

  /// 复制已经读取的 OPF XML。
  Future<void> _copyOpf() async {
    final content = _opfContent;
    if (content == null) return;

    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    context.read<ToastProvider>().showSuccess('OPF 源码已复制');
  }

  /// 更新元数据字段
  ///
  /// 通过 copyWith 创建新的 MetadataData，仅更新传入的非 null 字段。
  void _updateField({
    String? title,
    String? subtitle,
    String? author,
    String? language,
    String? publisher,
    String? description,
    String? identifier,
    String? rights,
  }) {
    setState(() {
      _metadata = _metadata!.copyWith(
        title: title,
        subtitle: subtitle,
        author: author,
        language: language,
        publisher: publisher,
        description: description,
        identifier: identifier,
        rights: rights,
      );
    });
  }

  /// 语言下拉选择变化回调
  ///
  /// 选择「其他」时弹出输入对话框让用户输入自定义语言代码，
  /// 选择预设值时直接更新。
  Future<void> _onLanguageChanged(String? value) async {
    if (value == null) return;

    if (value == '其他') {
      // 弹出对话框让用户输入自定义语言代码
      final input = await _showLanguageInputDialog();
      if (input != null && input.isNotEmpty) {
        _updateField(language: input);
      }
    } else {
      _updateField(language: value);
    }
  }

  /// 显示自定义语言代码输入对话框
  ///
  /// 返回用户输入的语言代码，取消则返回 null
  Future<String?> _showLanguageInputDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('输入语言代码'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '如 fr、de、es',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(controller.text.trim());
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  /// 选择新封面图片
  ///
  /// 调用 FileService.pickImage 选择图片，选择后更新预览。
  Future<void> _pickCover() async {
    final path = await FileService.pickImage();
    if (path == null) return;

    setState(() {
      _coverPath = path;
      // 选择新封面时取消移除标记
      _coverRemoved = false;
    });
  }

  /// 移除封面
  ///
  /// 标记封面为移除状态，保存时将删除 EPUB 中的封面图片。
  void _removeCover() {
    setState(() {
      _coverRemoved = true;
      _coverPath = null;
    });
  }

  /// 保存元数据到 EPUB 文件
  ///
  /// 调用 MetadataService.write 将修改后的元数据写入输出路径。
  /// 保存中显示 loading 状态，成功/失败后显示 Toast 提示。
  Future<void> _save() async {
    if (_epubPath == null || _outputPath == null || _metadata == null) return;

    setState(() {
      _loading = true;
    });

    try {
      await MetadataService.write(
        epubPath: _epubPath!,
        outputPath: _outputPath!,
        metadata: _metadata!,
        coverPath: _coverPath,
        removeCover: _coverRemoved,
      );
      if (!mounted) return;
      // 保存成功提示
      context.read<ToastProvider>().showSuccess(
        '元数据已保存：${p.basename(_outputPath!)}',
      );
    } catch (e) {
      if (!mounted) return;
      // 保存失败提示
      context.read<ToastProvider>().showError('保存失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }
}
