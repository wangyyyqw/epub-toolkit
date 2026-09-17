import 'dart:convert';

class BatchRecipeStep {
  final String operationId;
  final Map<String, Object?> arguments;
  final bool enabled;

  const BatchRecipeStep({
    required this.operationId,
    this.arguments = const {},
    this.enabled = true,
  });

  BatchRecipeStep copyWith({
    String? operationId,
    Map<String, Object?>? arguments,
    bool? enabled,
  }) {
    return BatchRecipeStep(
      operationId: operationId ?? this.operationId,
      arguments: arguments ?? this.arguments,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'arguments': arguments,
    'enabled': enabled,
  };

  factory BatchRecipeStep.fromJson(Map<String, Object?> json) {
    return BatchRecipeStep(
      operationId: json['operationId'] as String,
      arguments:
          (json['arguments'] as Map?)?.cast<String, Object?>() ?? const {},
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class BatchRecipe {
  final String id;
  final String name;
  final List<BatchRecipeStep> steps;
  final bool builtIn;

  const BatchRecipe({
    required this.id,
    required this.name,
    required this.steps,
    this.builtIn = false,
  });

  BatchRecipe copyWith({
    String? id,
    String? name,
    List<BatchRecipeStep>? steps,
    bool? builtIn,
  }) {
    return BatchRecipe(
      id: id ?? this.id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      builtIn: builtIn ?? this.builtIn,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'steps': steps.map((step) => step.toJson()).toList(),
    'builtIn': builtIn,
  };

  factory BatchRecipe.fromJson(Map<String, Object?> json) {
    return BatchRecipe(
      id: json['id'] as String,
      name: json['name'] as String,
      steps: (json['steps'] as List? ?? const [])
          .map(
            (item) =>
                BatchRecipeStep.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList(),
      builtIn: json['builtIn'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  static BatchRecipe decode(String value) =>
      BatchRecipe.fromJson((jsonDecode(value) as Map).cast<String, Object?>());

  static const standardOptimize = BatchRecipe(
    id: 'standard-optimize',
    name: '标准优化',
    builtIn: true,
    steps: [
      BatchRecipeStep(operationId: 'reformat'),
      BatchRecipeStep(operationId: 'downloadImages'),
      BatchRecipeStep(
        operationId: 'imgCompress',
        arguments: {'jpegQuality': 82, 'pngToJpg': false},
      ),
      BatchRecipeStep(operationId: 'fontSubset'),
      BatchRecipeStep(operationId: 'healthScan'),
    ],
  );

  static const quickCheck = BatchRecipe(
    id: 'quick-check',
    name: '批量体检',
    builtIn: true,
    steps: [BatchRecipeStep(operationId: 'healthScan')],
  );

  static const compatibility = BatchRecipe(
    id: 'compatibility',
    name: '兼容性整理',
    builtIn: true,
    steps: [
      BatchRecipeStep(operationId: 'reformat'),
      BatchRecipeStep(operationId: 'webpToImg'),
      BatchRecipeStep(operationId: 'healthScan'),
    ],
  );

  static const builtIns = [standardOptimize, quickCheck, compatibility];
}
