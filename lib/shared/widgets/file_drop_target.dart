import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

typedef FilesDroppedCallback = FutureOr<void> Function(List<String> paths);

class FileDropTarget extends StatefulWidget {
  const FileDropTarget({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.enabled = true,
  });

  final Widget child;
  final FilesDroppedCallback? onFilesDropped;
  final bool enabled;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool _dragging = false;

  bool get _supportedDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  Widget build(BuildContext context) {
    if (!_supportedDesktop || widget.onFilesDropped == null) {
      return widget.child;
    }

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList();
        if (paths.isNotEmpty) {
          widget.onFilesDropped?.call(paths);
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.themeAccentLight.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(AppTheme.radiusS),
                    border: Border.all(color: context.themeAccent, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
