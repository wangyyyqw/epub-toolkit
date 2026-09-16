import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:epub_gadget/core/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'loading a saved preference does not overwrite a newer selection',
    () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final controller = ThemeController();
      addTearDown(controller.dispose);
      final pending = controller.load();
      await controller.setMode(ThemeMode.light);
      await pending;
      expect(controller.mode, ThemeMode.light);
      expect(
        (await SharedPreferences.getInstance()).getString('theme_mode'),
        'light',
      );
    },
  );

  test('loading after disposal is harmless', () async {
    final controller = ThemeController();
    final pending = controller.load();
    controller.dispose();
    await pending;
  });

  test('主题模式按系统、日间、夜间顺序循环', () async {
    final controller = ThemeController();

    expect(controller.mode, ThemeMode.system);
    expect(controller.label, '跟随系统');

    await controller.cycle();
    expect(controller.mode, ThemeMode.light);
    expect(controller.label, '日间模式');

    await controller.cycle();
    expect(controller.mode, ThemeMode.dark);
    expect(controller.label, '夜间模式');

    await controller.cycle();
    expect(controller.mode, ThemeMode.system);
  });
}
