import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Runs CPU-heavy work away from Flutter's UI isolate when possible.
///
/// EPUB operations do a lot of ZIP, XML and image byte processing. Running them
/// directly from button handlers can freeze Android for minutes on large books.
Future<R> runBackgroundTask<M, R>(
  FutureOr<R> Function(M message) task,
  M message,
) async {
  if (kIsWeb) {
    return Future<R>.value(task(message));
  }
  return Isolate.run(() async => await task(message));
}
