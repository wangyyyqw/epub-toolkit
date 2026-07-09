// 阶段 2 修复：递归补齐内部副本
// 扫描每个 module 的所有文件，凡是 import 了一个 helper 但目标文件不在 module 里，
// 就从 srcDir 复制过去。重复扫描直到稳定（不变量 fixed point）。

import 'dart:io';

final srcDir = Directory('lib/features/epub_tools/operations');
final featuresDir = Directory('lib/features');

void main() {
  // 内化清单：所有 .dart 在 features/<module>/ 里的文件，被 import 时需要存在于本模块内
  final helpers = <String>{
    'epub_image_helper.dart',
    'epub_packer.dart',
    'encrypt_decrypt_base.dart',
    'chinese_convert_base.dart',
    'comment.dart',
    'list_split_targets.dart',
    'duokan_base.dart',
    'ttf_font_encryptor.dart',
    'ttf_subsetter.dart',
    'epub_reformatter.dart',
    'chinese_converter.dart', // lib/core/ 的也算 helper
  };

  bool changed = true;
  var iter = 0;
  while (changed && iter < 10) {
    changed = false;
    iter++;
    print('--- 迭代 $iter ---');
    for (final module in featuresDir.listSync().whereType<Directory>()) {
      if (module.path.contains('epub_tools')) continue;
      final moduleName = module.path.split(Platform.pathSeparator).last;
      // 收集本模块所有 .dart 文件名
      final existing = module.listSync().whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last).toSet();

      // 扫描所有 .dart 的 import
      for (final f in module.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final content = f.readAsStringSync();
        final reg = RegExp(r"^import '([^']+)';", multiLine: true);
        for (final m in reg.allMatches(content)) {
          final imp = m.group(1)!;
          if (helpers.contains(imp) && !existing.contains(imp)) {
            // 尝试从 srcDir 或 featuresDir 复制
            File? src = File('${srcDir.path}/$imp');
            if (!src.existsSync()) {
              src = File('lib/core/$imp');
            }
            if (!src.existsSync()) {
              // 可能在其他 features 模块中
              for (final other in featuresDir.listSync().whereType<Directory>()) {
                final cand = File('${other.path}/$imp');
                if (cand.existsSync()) {
                  src = cand;
                  break;
                }
              }
            }
            if (src != null && src.existsSync()) {
              File('${module.path}/$imp').writeAsStringSync(src.readAsStringSync());
              print('  ✓ $moduleName/$imp ← ${src.path}');
              existing.add(imp);
              changed = true;
            } else {
              print('  ✗ $moduleName/$imp 找不到源');
            }
          }
        }
      }
    }
  }
  print('=== 完成 ===');
}
