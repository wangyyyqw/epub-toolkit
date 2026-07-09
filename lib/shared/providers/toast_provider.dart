import 'package:flutter/foundation.dart';

/// Toast 类型枚举
enum ToastType {
  /// 成功（绿色）
  success,

  /// 警告（橙色）
  warning,

  /// 错误（红色）
  error,

  /// 信息（蓝色）
  info,
}

/// Toast 数据模型
///
/// [id] 使用时间戳生成，保证唯一；[message] 为展示文案；[type] 决定配色与图标。
class ToastMessage {
  /// 唯一标识，使用时间戳生成
  final int id;

  /// 消息内容
  final String message;

  /// Toast 类型
  final ToastType type;

  ToastMessage({
    required this.id,
    required this.message,
    required this.type,
  });
}

/// Toast 状态管理
///
/// 使用 [ChangeNotifier] 管理 Toast 队列。提供 success / warning / error / info
/// 四种类型的快捷方法，每个 Toast 显示 [displayDuration]（默认 3 秒）后自动移除。
/// 另可通过 [dismiss] 手动关闭指定 Toast。
class ToastProvider extends ChangeNotifier {
  /// Toast 显示时长
  static const Duration displayDuration = Duration(seconds: 3);

  final List<ToastMessage> _toasts = [];

  /// 标记是否已 dispose，避免延时回调在销毁后触发通知
  bool _disposed = false;

  /// 当前 Toast 列表（只读副本）
  List<ToastMessage> get toasts => List.unmodifiable(_toasts);

  /// 显示成功 Toast
  void showSuccess(String message) => _show(message, ToastType.success);

  /// 显示警告 Toast
  void showWarning(String message) => _show(message, ToastType.warning);

  /// 显示错误 Toast
  void showError(String message) => _show(message, ToastType.error);

  /// 显示信息 Toast
  void showInfo(String message) => _show(message, ToastType.info);

  /// 内部方法：添加 Toast 并设定自动移除定时器
  ///
  /// [id] 使用微秒级时间戳，避免短时间内连续添加产生重复 id。
  void _show(String message, ToastType type) {
    final toast = ToastMessage(
      id: DateTime.now().microsecondsSinceEpoch,
      message: message,
      type: type,
    );
    _toasts.add(toast);
    _safeNotify();

    // 3 秒后自动移除
    Future<void>.delayed(displayDuration, () {
      if (!_disposed) dismiss(toast.id);
    });
  }

  /// 手动关闭指定 Toast
  void dismiss(int id) {
    final existed = _toasts.any((t) => t.id == id);
    if (!existed) return;
    _toasts.removeWhere((t) => t.id == id);
    _safeNotify();
  }

  /// 仅在未销毁时通知监听者
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _toasts.clear();
    super.dispose();
  }
}
