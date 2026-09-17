import 'dart:async';

enum EpubOperationMode { transform, inspect, multiInput }

typedef EpubOperationExecutor =
    FutureOr<Object?> Function(Map<String, Object?> arguments);

abstract interface class EpubOperation {
  String get id;
  String get displayName;
  String get description;
  String get category;
  String get outputExtension;
  EpubOperationMode get mode;
  bool get supportsBatch;
  Map<String, Object?> get defaultArguments;
  List<String> get passThroughMessages;

  Future<Object?> execute(Map<String, Object?> arguments);
}

class RegisteredEpubOperation implements EpubOperation {
  @override
  final String id;
  @override
  final String displayName;
  @override
  final String description;
  @override
  final String category;
  @override
  final String outputExtension;
  @override
  final EpubOperationMode mode;
  @override
  final bool supportsBatch;
  @override
  final Map<String, Object?> defaultArguments;
  @override
  final List<String> passThroughMessages;
  final EpubOperationExecutor executor;

  const RegisteredEpubOperation({
    required this.id,
    required this.displayName,
    required this.description,
    required this.category,
    required this.outputExtension,
    required this.executor,
    this.mode = EpubOperationMode.transform,
    this.supportsBatch = false,
    this.defaultArguments = const {},
    this.passThroughMessages = const [],
  });

  @override
  Future<Object?> execute(Map<String, Object?> arguments) async {
    return executor({...defaultArguments, ...arguments});
  }
}

class EpubOperationRegistry {
  final Map<String, EpubOperation> _operations;

  EpubOperationRegistry(Iterable<EpubOperation> operations)
    : _operations = {
        for (final operation in operations) operation.id: operation,
      } {
    if (_operations.length != operations.length) {
      throw ArgumentError('EPUB 操作注册表存在重复 ID');
    }
  }

  Iterable<EpubOperation> get operations => _operations.values;

  EpubOperation? find(String id) => _operations[id];

  EpubOperation require(String id) {
    final operation = find(id);
    if (operation == null) {
      throw ArgumentError.value(id, 'id', '未知 EPUB 操作');
    }
    return operation;
  }

  Future<Object?> execute(String id, Map<String, Object?> arguments) {
    return require(id).execute(arguments);
  }

  List<Map<String, Object?>> describe({bool batchOnly = false}) {
    return operations
        .where((operation) => !batchOnly || operation.supportsBatch)
        .map(
          (operation) => {
            'id': operation.id,
            'displayName': operation.displayName,
            'description': operation.description,
            'category': operation.category,
            'outputExtension': operation.outputExtension,
            'mode': operation.mode.name,
            'supportsBatch': operation.supportsBatch,
            'defaultArguments': operation.defaultArguments,
            'passThroughMessages': operation.passThroughMessages,
          },
        )
        .toList(growable: false);
  }
}
