import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/file_service.dart';
import '../../core/theme.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../../shared/widgets/base_input.dart';
import '../../shared/widgets/output_log.dart';
import '../../shared/widgets/page_header.dart';
import 'wifi_book.dart';
import 'wifi_book_library.dart';
import 'wifi_http_server.dart';

/// WiFi 局域网传书页面。
///
/// 在本机启动 HTTP 服务，Kindle 浏览器访问局域网地址即可下载书库中的书。
/// 参考 Kindred / kaf-wifi 的思路，适配 iOS / Android / Windows / macOS。
class WifiTransferPage extends StatefulWidget {
  const WifiTransferPage({super.key});

  @override
  State<WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends State<WifiTransferPage> {
  final WifiBookLibrary _library = WifiBookLibrary();
  late final WifiHttpServer _server;
  final OutputLogController _logController = OutputLogController();

  String _searchText = '';
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _server = WifiHttpServer(_library);
    _server.addListener(_onServerChanged);
    _initLibrary();
  }

  /// 初始化书库并记录日志。
  Future<void> _initLibrary() async {
    await _library.init();
    if (!mounted) return;
    setState(() => _initialized = true);
    if (_library.errorMessage != null) {
      _logController.append('ERROR: ${_library.errorMessage}');
    } else {
      _logController.append('书库就绪，当前 ${_library.books.length} 本书');
    }
  }

  void _onServerChanged() {
    if (!mounted) return;
    setState(() {});
    final status = _server.status;
    if (status == WifiServerStatus.running && _server.address != null) {
      _logController.append('服务已启动：${_server.address}');
      _logController.append('在 Kindle 浏览器中打开上述地址即可下载');
    } else if (status == WifiServerStatus.error) {
      _logController.append('ERROR: ${_server.errorMessage}');
    } else if (status == WifiServerStatus.stopped) {
      _logController.append('服务已停止');
    }
  }

  @override
  void dispose() {
    _server.removeListener(_onServerChanged);
    _server.dispose();
    _library.dispose();
    _logController.dispose();
    super.dispose();
  }

  /// 选择并导入书籍文件。
  Future<void> _pickAndImport() async {
    try {
      final paths = await FileService.pickFiles(
        type: FileType.custom,
        allowedExtensions: kWifiBookExtensions.toList(),
        title: '选择要导入的电子书（可多选）',
      );
      if (paths == null || paths.isEmpty) return;
      final count = await _library.importPaths(paths);
      if (!mounted) return;
      if (count > 0) {
        _logController.append('成功导入 $count 本书');
        context.read<ToastProvider>().showSuccess('已导入 $count 本书');
      }
      if (_library.errorMessage != null) {
        _logController.append('WARN: ${_library.errorMessage}');
        context.read<ToastProvider>().showWarning('部分文件导入失败，详见日志');
      }
    } catch (e) {
      if (!mounted) return;
      _logController.append('ERROR: 导入失败：$e');
      context.read<ToastProvider>().showError('导入失败：$e');
    }
  }

  /// 启动或停止服务。
  Future<void> _toggleServer() async {
    if (_server.isRunning) {
      await _server.stop();
    } else {
      await _server.start();
    }
  }

  /// 复制地址到剪贴板。
  void _copyAddress() {
    final addr = _server.address;
    if (addr == null) return;
    // 简单提示，不引入额外依赖
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('地址已显示，请在 Kindle 浏览器输入：$addr')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _library.filter(_searchText);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              icon: Icons.wifi_rounded,
              iconColor: Color(0xFF6FAE5C),
              title: 'WiFi 局域网传书',
              description: '本机启动服务，Kindle 浏览器访问局域网地址下载',
            ),
            const SizedBox(height: 12),
            _buildServerCard(),
            const SizedBox(height: 16),
            _buildLibraryCard(filtered),
            const SizedBox(height: 12),
            OutputLog(controller: _logController),
          ],
        ),
      ),
    );
  }

  /// 服务器状态卡片。
  Widget _buildServerCard() {
    final isRunning = _server.isRunning;
    final isStarting = _server.status == WifiServerStatus.starting;
    final addr = _server.address;
    return BaseCard(
      title: '传书服务',
      trailing: BaseButton(
        label: isRunning ? '停止服务' : (isStarting ? '启动中…' : '启动服务'),
        icon: isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
        loading: isStarting,
        variant: isRunning ? BaseButtonVariant.danger : BaseButtonVariant.primary,
        onPressed: _initialized && !isStarting ? _toggleServer : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: isRunning ? context.themeSuccess : context.themeTextTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                isRunning ? '运行中' : '已停止',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isRunning ? context.themeSuccess : context.themeTextTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '端口 ${_server.port}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeTextTertiary,
                ),
              ),
            ],
          ),
          if (addr != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.themeAccentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      addr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: '复制地址',
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    padding: EdgeInsets.zero,
                    onPressed: _copyAddress,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请确保手机/电脑与 Kindle 连接同一 Wi-Fi，'
              '在 Kindle 的「实验性浏览器」中打开上述地址。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.themeTextSecondary,
              ),
            ),
          ],
          if (_server.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _server.errorMessage!,
              style: TextStyle(fontSize: 12, color: context.themeError),
            ),
          ],
        ],
      ),
    );
  }

  /// 书库管理卡片。
  Widget _buildLibraryCard(List<WifiBook> books) {
    return BaseCard(
      title: '书库（${_library.books.length}）',
      trailing: BaseButton(
        label: '导入书籍',
        icon: Icons.add,
        variant: BaseButtonVariant.secondary,
        onPressed: _initialized ? _pickAndImport : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_library.books.isNotEmpty) ...[
            BaseInput(
              label: '搜索',
              value: _searchText,
              hint: '按书名或格式筛选',
              prefixIcon: Icons.search,
              onChanged: (v) => setState(() => _searchText = v),
            ),
            const SizedBox(height: 8),
          ],
          if (books.isEmpty)
            _buildEmptyHint()
          else
            _buildBookList(books),
          if (_library.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _library.errorMessage!,
              style: TextStyle(fontSize: 12, color: context.themeWarning),
            ),
          ],
        ],
      ),
    );
  }

  /// 空书库提示。
  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 36,
              color: context.themeTextTertiary,
            ),
            const SizedBox(height: 8),
            Text(
              _library.books.isEmpty ? '书库为空，点击「导入书籍」添加' : '未找到匹配的书籍',
              style: TextStyle(
                fontSize: 13,
                color: context.themeTextTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 书籍列表。
  Widget _buildBookList(List<WifiBook> books) {
    return Column(
      children: books.map((book) => _BookRow(
        book: book,
        onDelete: () => _confirmDelete(book),
        onRename: () => _showRenameDialog(book),
      )).toList(),
    );
  }

  /// 确认删除。
  Future<void> _confirmDelete(WifiBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定删除「${book.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: context.themeError),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _library.delete(book);
    if (!mounted) return;
    _logController.append('已删除：${book.title}');
    context.read<ToastProvider>().showSuccess('已删除');
  }

  /// 重命名弹窗。
  Future<void> _showRenameDialog(WifiBook book) async {
    final controller = TextEditingController(text: book.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '书名',
            hintText: '输入新的书名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    await _library.rename(book, result);
    if (!mounted) return;
    _logController.append('已重命名：${book.title} → $result');
  }
}

/// 单本书的行组件。
class _BookRow extends StatelessWidget {
  final WifiBook book;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _BookRow({
    required this.book,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_formatIcon(book.format), size: 20, color: context.themeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.themeTextPrimary,
                  ),
                ),
                Text(
                  '${book.format} · ${book.formattedSize}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeTextTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '重命名',
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onRename,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: context.themeError),
            tooltip: '删除',
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  IconData _formatIcon(String format) {
    switch (format.toUpperCase()) {
      case 'PDF':
        return Icons.picture_as_pdf_outlined;
      case 'TXT':
        return Icons.description_outlined;
      case 'EPUB':
        return Icons.menu_book_outlined;
      default:
        return Icons.book_outlined;
    }
  }
}
