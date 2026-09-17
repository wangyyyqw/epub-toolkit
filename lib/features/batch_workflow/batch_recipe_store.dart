import 'package:shared_preferences/shared_preferences.dart';

import 'batch_recipe.dart';

class BatchRecipeStore {
  static const _key = 'batch_workflow_recipes_v1';

  Future<List<BatchRecipe>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_key) ?? const [];
    final custom = <BatchRecipe>[];
    for (final value in values) {
      try {
        custom.add(BatchRecipe.decode(value));
      } catch (_) {
        // Ignore one damaged preset without hiding the remaining presets.
      }
    }
    return [...BatchRecipe.builtIns, ...custom];
  }

  Future<void> saveCustom(List<BatchRecipe> recipes) async {
    final preferences = await SharedPreferences.getInstance();
    final values = recipes
        .where((recipe) => !recipe.builtIn)
        .map((recipe) => recipe.encode())
        .toList();
    await preferences.setStringList(_key, values);
  }
}
