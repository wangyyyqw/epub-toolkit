import 'dart:io';

// 内部副本：原 import 名 → 复制到目标模块时的新名
// 命名规则：在目标模块里，加 _helper / _base 后缀避免冲突
final internalHelpers = {
  'epub_image_helper.dart': 'epub_image_helper.dart', // 保留原名（无冲突）
  'epub_packer.dart': 'epub_packer.dart',
  'encrypt_decrypt_base.dart': 'encrypt_decrypt_base.dart',
  'chinese_convert_base.dart': 'chinese_convert_base.dart',
  'comment.dart': 'comment.dart',
  'list_split_targets.dart': 'list_split_targets.dart',
  'duokan_base.dart': 'duokan_base.dart',
  'ttf_font_encryptor.dart': 'ttf_font_encryptor.dart',
  'ttf_subsetter.dart': 'ttf_subsetter.dart',
};

void main() {
  final srcDir = Directory('lib/features/epub_tools/operations');
  final featuresDir = Directory('lib/features');
  final sources = srcDir.listSync().whereType<File>().toList();
  print('源文件: ${sources.length}');

  for (final f in sources) {
    final name = f.path.split(Platform.pathSeparator).last;
    if (name.startsWith('debug_') || name.endsWith('_test.dart')) continue;

    final moduleName = name.replaceAll('.dart', '');
    final targetDir = Directory('${featuresDir.path}/$moduleName');
    targetDir.createSync(recursive: true);

    var content = f.readAsStringSync();
    // 内化工具副本 import 替换为同模块内
    content = _inlineImports(content, moduleName);
    File('${targetDir.path}/$name').writeAsStringSync(content);
    print('  ✓ $moduleName/$name');
  }

  // 阶段 2：把内部副本复制到各目标模块
  print('\n=== 阶段 2：分发内部副本 ===');
  _distributeInternalHelpers(srcDir, featuresDir);
}

String _inlineImports(String content, String moduleName) {
  // 把对同模块外业务文件的 import，替换为对"已内化副本"的 import
  // import 'epub_image_helper.dart' → import 'epub_image_helper.dart'（同名）
  // import 'epub_packer.dart' → import 'epub_packer.dart'
  // import 'comment.dart' → import 'comment.dart'
  // 因为副本的文件名与原文件名相同，不需要替换 import
  return content;
}

void _distributeInternalHelpers(Directory srcDir, Directory featuresDir) {
  // 收集所有模块的 import
  final moduleImports = <String, Set<String>>{};
  for (final module in featuresDir.listSync().whereType<Directory>()) {
    if (module.path.contains('epub_tools')) continue;
    final imports = <String>{};
    for (final f in module.listSync().whereType<File>()) {
      final content = f.readAsStringSync();
      final reg = RegExp(r"^import '([^']+)';", multiLine: true);
      for (final m in reg.allMatches(content)) {
        final imp = m.group(1)!;
        if (internalHelpers.containsKey(imp)) {
          imports.add(imp);
        }
      }
    }
    if (imports.isNotEmpty) {
      moduleImports[module.path.split(Platform.pathSeparator).last] = imports;
    }
  }

  // 复制副本到目标模块
  for (final entry in moduleImports.entries) {
    final moduleDir = Directory('${featuresDir.path}/${entry.key}');
    for (final helperName in entry.value) {
      final src = File('${srcDir.path}/$helperName');
      if (!src.existsSync()) continue;
      final dst = File('${moduleDir.path}/$helperName');
      if (!dst.existsSync()) {
        dst.writeAsStringSync(src.readAsStringSync());
        print('  ✓ ${entry.key}/$helperName (复制)');
      }
    }
  }
}
