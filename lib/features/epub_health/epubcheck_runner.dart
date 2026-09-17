import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class EpubCheckRunner {
  EpubCheckRunner._();

  static bool get supportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static Future<Map<String, Object?>> probe({
    Map<String, String>? environment,
  }) async {
    if (!supportedPlatform) {
      return {'available': false, 'message': 'EPUBCheck 完整检查仅在桌面平台提供。'};
    }
    final command = await _resolveCommand(environment: environment);
    if (command == null) {
      return {
        'available': false,
        'message': '未找到 EPUBCheck。可安装 epubcheck 命令，或设置 EPUBCHECK_JAR 环境变量。',
      };
    }
    final result = await Process.run(command.executable, [
      ...command.prefixArguments,
      '--version',
    ]);
    return {
      'available': result.exitCode == 0,
      'command': command.displayName,
      'version': '${result.stdout}${result.stderr}'.trim(),
      'exitCode': result.exitCode,
    };
  }

  static Future<Map<String, Object?>> run(
    String epubPath, {
    String? reportPath,
    Map<String, String>? environment,
  }) async {
    if (!supportedPlatform) {
      throw UnsupportedError('EPUBCheck 完整检查仅支持桌面平台');
    }
    final command = await _resolveCommand(environment: environment);
    if (command == null) {
      throw StateError('未找到 EPUBCheck。请安装 epubcheck，或设置 EPUBCHECK_JAR。');
    }
    final requestedReport = reportPath == null || reportPath.trim().isEmpty
        ? p.join(
            p.dirname(epubPath),
            '${p.basenameWithoutExtension(epubPath)}_epubcheck.json',
          )
        : reportPath;
    final report = File(requestedReport).absolute;
    await report.parent.create(recursive: true);
    final result = await Process.run(command.executable, [
      ...command.prefixArguments,
      epubPath,
      '--json',
      report.path,
    ]);

    Object? structured;
    if (await report.exists()) {
      try {
        structured = jsonDecode(await report.readAsString());
      } catch (_) {
        structured = null;
      }
    }
    return {
      'available': true,
      'command': command.displayName,
      'exitCode': result.exitCode,
      'stdout': result.stdout.toString(),
      'stderr': result.stderr.toString(),
      'reportPath': report.path,
      'report': structured,
    };
  }

  static Future<_EpubCheckCommand?> _resolveCommand({
    Map<String, String>? environment,
  }) async {
    final variables = environment ?? Platform.environment;
    final jar = variables['EPUBCHECK_JAR'];
    if (jar != null && jar.trim().isNotEmpty && await File(jar).exists()) {
      return _EpubCheckCommand('java', ['-jar', jar], 'java -jar $jar');
    }
    final executable = variables['EPUBCHECK_COMMAND'];
    if (executable != null && executable.trim().isNotEmpty) {
      return _EpubCheckCommand(executable.trim(), const [], executable.trim());
    }

    final locator = Platform.isWindows ? 'where' : 'which';
    try {
      final located = await Process.run(locator, ['epubcheck']);
      if (located.exitCode == 0) {
        final path = located.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .firstWhere((line) => line.trim().isNotEmpty)
            .trim();
        if (path.isNotEmpty) return _EpubCheckCommand(path, const [], path);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _EpubCheckCommand {
  final String executable;
  final List<String> prefixArguments;
  final String displayName;

  const _EpubCheckCommand(
    this.executable,
    this.prefixArguments,
    this.displayName,
  );
}
