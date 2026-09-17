import '../../core/background_task.dart';
import 'epub_operation_registry.dart';

enum EpubBackgroundOperation {
  healthScan,
  healthRepair,
  viewOpf,
  replaceCover,
  reformat,
  convertVersion,
  epubToTxt,
  adClean,
  imgCompress,
  embedImageWatermark,
  inspectImageWatermark,
  webpToImg,
  downloadImages,
  phonetic,
  fontSubset,
  encrypt,
  decrypt,
  encryptFont,
  addZipPassword,
  removeZipPassword,
  scanFontTargets,
  listFontTargets,
  merge,
  split,
  listSplitTargets,
  comment,
  footnoteToComment,
  spanToFootnote,
  yuewei,
  zhangyue,
}

Future<T> runEpubBackgroundOperation<T>(
  EpubBackgroundOperation operation,
  Map<String, Object?> args,
) async {
  final result = await runBackgroundTask(_runEpubOperation, {
    'operation': operation.name,
    'args': args,
  });
  return result as T;
}

Future<T> runRegisteredEpubOperation<T>(
  String operationId,
  Map<String, Object?> args,
) async {
  final result = await runBackgroundTask(_runEpubOperation, {
    'operation': operationId,
    'args': args,
  });
  return result as T;
}

List<Map<String, Object?>> describeRegisteredEpubOperations({
  bool batchOnly = false,
}) => epubOperationRegistry.describe(batchOnly: batchOnly);

Future<Object?> _runEpubOperation(Map<String, Object?> message) async {
  final operation = message['operation'] as String;
  final args = message['args'] as Map<String, Object?>;
  return epubOperationRegistry.execute(operation, args);
}
