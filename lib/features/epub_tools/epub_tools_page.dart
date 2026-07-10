import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'epub_background_operation.dart';
import '../../core/file_service.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../../shared/widgets/base_input.dart';
import '../../shared/widgets/base_select.dart';
import '../../shared/widgets/output_log.dart';
import '../../shared/widgets/page_header.dart';
import '../encrypt_decrypt_base/encrypt_decrypt_base.dart';
import '../img_to_webp/img_to_webp.dart';
import '../s2t/s2t.dart';
import '../t2s/t2s.dart';

/// EPUB 工具箱操作类型枚举
///
/// 每个枚举值对应一个具体的 EPUB 操作，包含显示名称和功能描述。
enum EpubToolOp {
  viewOpf('查看 OPF 元数据', '读取并格式化显示 EPUB 的 OPF 文件内容'),
  replaceCover('替换封面图片', '将 EPUB 的封面图片替换为新图片'),
  reformat('重新格式化', '规范化 EPUB 内部结构，清理冗余文件'),
  convertVersion('版本转换', 'EPUB 2.0 与 3.0 互转'),
  epubToTxt('EPUB 转 TXT', '将 EPUB 电子书转换为纯文本'),
  adClean('广告清理', '按正则规则批量清理 EPUB 中的广告内容'),
  imgCompress('图片压缩', '压缩 EPUB 中的图片以减小体积'),
  imgToWebp('图片转 WebP', '将 EPUB 中的图片转换为 WebP 格式'),
  webpToImg('WebP 转图片', '将 EPUB 中的 WebP 图片转回 JPEG/PNG'),
  downloadImages('下载网络图片', '下载 EPUB 中引用的网络图片到本地'),
  s2t('简体转繁体', '将 EPUB 中的简体中文转换为繁体中文'),
  t2s('繁体转简体', '将 EPUB 中的繁体中文转换为简体中文'),
  phonetic('拼音标注', '为 EPUB 中的中文文本添加拼音标注'),
  fontSubset('字体子集化', '子集化 EPUB 中的字体文件以减小体积'),
  encrypt('名称混淆加密', '混淆 EPUB 文件名使编辑器无法打开修改'),
  decrypt('名称混淆解密', '还原被混淆的 EPUB 文件名'),
  encryptFont('字体加密', '字形混淆加密实现防复制保护'),
  listFontTargets('列出字体目标', '扫描 EPUB 中的字体族和 HTML 文件列表'),
  merge('合并 EPUB', '将多个 EPUB 合并为一个'),
  split('拆分 EPUB', '按章节拆分点将 EPUB 拆分为多个'),
  listSplitTargets('列出拆分目标', '扫描 EPUB 目录结构供选择拆分点'),
  comment('批注提取', '用正则从正文中提取批注转为悬浮脚注'),
  footnoteToComment('脚注转弹窗', '将 EPUB 内部脚注链接转换为阅微弹窗注释'),
  spanToFootnote('弹窗转脚注', '将阅微弹窗注释转换为 EPUB3 末尾脚注'),
  yuewei('阅微转多看', '将阅微格式脚注转为多看标准格式'),
  zhangyue('得到转多看', '将得到格式脚注转为多看标准格式');

  /// 操作显示名称
  final String label;

  /// 操作功能描述
  final String desc;

  const EpubToolOp(this.label, this.desc);
}

/// EPUB 工具箱页面
///
/// 提供 24 种 EPUB 操作的可视化界面：查看 OPF、替换封面、重新格式化、
/// 版本转换、EPUB 转 TXT、广告清理、图片处理、简繁转换、拼音标注、
/// 字体子集化、加密/解密、字体加密、合并/拆分 EPUB、批注提取、
/// 阅微/掌阅转多看等。用户选择操作类型后，页面动态展示对应的参数输入
/// 控件，执行后在日志面板中显示结果。
class EpubToolsPage extends StatefulWidget {
  /// 从侧边栏导航传入的初始操作类型（null 时默认 viewOpf）
  final EpubToolOp? initialOp;
  const EpubToolsPage({super.key, this.initialOp});

  @override
  State<EpubToolsPage> createState() => _EpubToolsPageState();
}

class _EpubToolsPageState extends State<EpubToolsPage> {
  /// 当前选中的操作类型
  EpubToolOp _selectedOp = EpubToolOp.viewOpf;

  /// EPUB 输入文件路径
  String _epubPath = '';

  /// 输出文件路径
  String _outputPath = '';

  /// 用户是否通过"选择输出路径"按钮主动选过位置。
  ///
  /// 用于 _pickEpub 时区分"自动填充的 outputPath"与"用户主动选的"，
  /// 防止连续处理多本 EPUB 时用上一本的文件名写新内容。
  bool userPickedOutput = false;

  /// 新封面图片路径（仅 replace_cover 操作使用）
  String _coverPath = '';

  /// 目标版本（仅 convert_version 操作使用）
  String _targetVersion = '3.0';

  /// 广告清理正则规则（仅 ad_clean 操作使用）
  /// 格式：pattern1|||replacement1|||pattern2|||replacement2
  String _patterns = '';

  /// JPEG 压缩质量（仅 img_compress 操作使用，默认 85）
  int _jpegQuality = 85;

  /// 是否将无透明 PNG 转为 JPG（仅 img_compress 操作使用）
  bool _pngToJpg = true;

  /// 拼音声调模式（仅 phonetic 操作使用）
  String _toneMode = 'mark';

  /// 是否全文注音（仅 phonetic 操作使用）
  bool _annotateAll = false;

  /// 字体加密目标字体族（逗号分隔，仅 encrypt_font 操作使用）
  String _targetFontFamilies = '';

  /// 字体加密目标 XHTML 文件（逗号分隔，仅 encrypt_font 操作使用）
  String _targetXhtmlFiles = '';

  /// 合并 EPUB 输入文件路径列表（仅 merge 操作使用）
  List<String> _mergeInputPaths = [];

  /// 拆分点索引列表（逗号分隔，仅 split 操作使用）
  String _splitPoints = '';

  /// 拆分输出目录（仅 split 操作使用）
  String _splitOutputDir = '';

  /// 批注提取正则表达式（仅 comment 操作使用，默认匹配 [内容] 格式）
  String _regexPattern = r'\[(.*?)\]';

  /// 脚注文字颜色（仅 span_to_footnote 操作使用）
  String _footnoteColor = '';

  /// 脚注引用颜色（仅 span_to_footnote 操作使用）
  String _noterefColor = '';

  /// note.png 二进制数据（用于 yuewei/zhangyue 操作，从 assets 加载）
  Uint8List? _notePngBytes;

  /// 文本类操作的结果内容（view_opf / epub_to_txt 的输出）
  String _resultText = '';

  /// 是否正在执行操作
  bool _loading = false;

  /// 日志输出控制器
  final OutputLogController _logController = OutputLogController();

  @override
  void initState() {
    super.initState();
    // 支持从侧边栏导航预设操作类型
    if (widget.initialOp != null) {
      _selectedOp = widget.initialOp!;
    }
    // 异步加载 note.png 资源（用于阅微/掌阅转多看操作）
    _loadNotePng();
  }

  @override
  void didUpdateWidget(covariant EpubToolsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 侧边栏切换操作时同步选中状态
    if (widget.initialOp != null &&
        widget.initialOp != oldWidget.initialOp &&
        widget.initialOp != _selectedOp) {
      setState(() {
        _selectedOp = widget.initialOp!;
        _resultText = '';
        _outputPath = ''; // 重置，执行时自动填充安全路径
        userPickedOutput = false; // 切换操作时重置用户主动选择标志
        if (_selectedOp == EpubToolOp.comment) {
          _regexPattern = r'\[(.*?)\]';
        }
      });
      // 异步填充输出路径到应用安全目录
      if (_epubPath.isNotEmpty) {
        _autoFillOutputPath().then((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  /// 从 assets 加载 note.png
  Future<void> _loadNotePng() async {
    try {
      final data = await rootBundle.load('assets/note.png');
      _notePngBytes = data.buffer.asUint8List();
    } catch (_) {
      // 加载失败时静默处理，操作时会提示
    }
  }

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  /// 判断当前操作是否返回文本（需要显示结果区域）
  bool get _returnsText =>
      _selectedOp == EpubToolOp.viewOpf || _selectedOp == EpubToolOp.epubToTxt;

  /// 选择 EPUB 文件
  ///
  /// 重新选择输入文件时，根据 [userPickedOutput] 决定是否重置 _outputPath：
  /// - 用户没主动选过输出位置（默认）：重置 _outputPath 并重新计算默认文件名，
  ///   避免连续处理多本 EPUB 时用上一本的文件名写新内容（修复之前的 bug）。
  /// - 用户主动选过输出位置（通过"选择输出路径"按钮）：保留用户选择。
  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path != null) {
      _epubPath = path;
      // 仅当用户未主动选过输出位置时才重置
      if (!userPickedOutput) {
        _outputPath = '';
        await _autoFillOutputPath();
      }
      if (mounted) setState(() {});
    }
  }

  /// 选择封面图片
  Future<void> _pickCover() async {
    final path = await FileService.pickImage();
    if (path != null) {
      setState(() => _coverPath = path);
    }
  }

  /// 选择输出文件路径
  ///
  /// 用户通过 SAF 主动选过位置时记录 [userPickedOutput] 标志，
  /// 防止 [pickEpub] 重新选择输入时错误重置。
  Future<void> _pickOutput() async {
    final defaultName = _epubPath.isNotEmpty
        ? _defaultOutputFilename(_epubPath, _selectedOp)
        : (_selectedOp == EpubToolOp.epubToTxt ? 'output.txt' : 'output.epub');
    final path = await FileService.saveFile(
      defaultFileName: defaultName,
      initialDirectory: _epubPath.isNotEmpty
          ? p.dirname(_epubPath)
          : (_mergeInputPaths.isNotEmpty
                ? p.dirname(_mergeInputPaths.first)
                : null),
    );
    if (path != null) {
      userPickedOutput = true;
      setState(() => _outputPath = path);
    }
  }

  /// 生成默认输出文件名（不含目录路径）
  String _defaultOutputFilename(String inputPath, EpubToolOp op) {
    final rawBase = p.basenameWithoutExtension(inputPath);
    final base = op == EpubToolOp.convertVersion
        ? rawBase.replaceFirst(RegExp(r'_v[23](?:\.0)?$'), '')
        : rawBase;
    switch (op) {
      case EpubToolOp.convertVersion:
        return '${base}_v$_targetVersion.epub';
      case EpubToolOp.epubToTxt:
        return '$base.txt';
      case EpubToolOp.replaceCover:
        return '${base}_cover.epub';
      case EpubToolOp.footnoteToComment:
        return '${base}_ftc.epub';
      case EpubToolOp.spanToFootnote:
        return '${base}_converted.epub';
      default:
        return '${base}_output.epub';
    }
  }

  /// 自动填充输出路径。
  ///
  /// 桌面端默认输出到输入 EPUB 同目录，移动端默认输出到应用安全目录。
  Future<void> _autoFillOutputPath() async {
    if (_epubPath.isEmpty || _selectedOp == EpubToolOp.merge) return;
    final filename = _defaultOutputFilename(_epubPath, _selectedOp);
    _outputPath = await FileService.getDefaultOutputPathForInput(
      inputPath: _epubPath,
      filename: filename,
    );
  }

  Future<void> _ensureOutputPath() async {
    if (_outputPath.isEmpty &&
        _epubPath.isNotEmpty &&
        _selectedOp != EpubToolOp.merge) {
      await _autoFillOutputPath();
    }
  }

  /// 选择多个 EPUB 文件用于合并
  Future<void> _pickMergeFiles() async {
    final paths = await FileService.pickMultipleEpubs();
    if (paths != null && paths.isNotEmpty) {
      _mergeInputPaths = paths;
      // 自动生成默认输出路径；桌面端使用首个输入文件目录。
      if (_outputPath.isEmpty) {
        _outputPath = await FileService.getDefaultOutputPathInDirectory(
          directoryPath: p.dirname(_mergeInputPaths.first),
          filename: 'merged.epub',
        );
      }
      if (mounted) setState(() {});
    }
  }

  /// 选择拆分输出目录
  Future<void> _pickSplitOutputDir() async {
    final dir = await FileService.pickDirectory(title: '选择拆分输出目录');
    if (dir != null) {
      setState(() => _splitOutputDir = dir);
    }
  }

  /// 执行当前选中的操作
  ///
  /// 根据操作类型分发到对应的 Operation 类，执行过程中更新日志面板，
  /// 成功后显示 Toast 提示。文本类操作的结果显示在结果区域。
  Future<void> _execute() async {
    // 校验输入（merge 使用 _mergeInputPaths，其他操作使用 _epubPath）
    if (_selectedOp == EpubToolOp.merge) {
      if (_mergeInputPaths.length < 2) {
        context.read<ToastProvider>().showWarning('合并至少需要 2 个 EPUB 文件');
        return;
      }
    } else if (_epubPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择 EPUB 文件');
      return;
    }

    setState(() {
      _loading = true;
      _resultText = '';
    });
    await _ensureOutputPath();
    _logController.clear();
    _logController.append('PROGRESS: 开始执行「${_selectedOp.label}」操作...');
    // merge 操作使用多文件列表，其他操作使用单个 EPUB 路径
    if (_selectedOp == EpubToolOp.merge) {
      _logController.append('输入文件：${_mergeInputPaths.length} 个 EPUB');
    } else {
      _logController.append('输入文件：$_epubPath');
    }

    try {
      switch (_selectedOp) {
        case EpubToolOp.viewOpf:
          _logController.append('正在读取 OPF 元数据...');
          final result = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.viewOpf,
            {'epubPath': _epubPath},
          );
          _logController.append('OPF 元数据读取完成');
          setState(() => _resultText = result);
          if (mounted) {
            context.read<ToastProvider>().showSuccess('OPF 元数据读取成功');
          }
          break;

        case EpubToolOp.replaceCover:
          if (_coverPath.isEmpty) {
            if (mounted) {
              context.read<ToastProvider>().showWarning('请选择新封面图片');
            }
            setState(() => _loading = false);
            return;
          }
          _logController.append('新封面图片：$_coverPath');
          _logController.append('输出文件：$_outputPath');
          await runEpubBackgroundOperation<void>(
            EpubBackgroundOperation.replaceCover,
            {
              'epubPath': _epubPath,
              'coverPath': _coverPath,
              'outputPath': _outputPath,
            },
          );
          _logController.append('封面替换完成');
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '封面替换成功，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.reformat:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在规范化 EPUB 结构...');
          await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.reformat,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          _logController.append('重新格式化完成');
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '格式化完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.convertVersion:
          _logController.append('目标版本：EPUB $_targetVersion');
          _logController.append('输出文件：$_outputPath');
          await runEpubBackgroundOperation<void>(
            EpubBackgroundOperation.convertVersion,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'targetVersion': _targetVersion,
            },
          );
          _logController.append('版本转换完成：已转换为 EPUB $_targetVersion');
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '版本转换成功，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.epubToTxt:
          _logController.append('正在提取文本内容...');
          _logController.append('输出文件：$_outputPath');
          final result = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.epubToTxt,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          _logController.append('文本提取完成，共 ${result.length} 字符');
          _logController.append('TXT 已保存到 $_outputPath');
          setState(() => _resultText = result);
          if (mounted) {
            context.read<ToastProvider>().showSuccess('EPUB 转 TXT 成功');
          }
          break;

        case EpubToolOp.adClean:
          if (_patterns.trim().isEmpty) {
            if (mounted) {
              context.read<ToastProvider>().showWarning('请输入清理规则');
            }
            setState(() => _loading = false);
            return;
          }
          _logController.append('清理规则：$_patterns');
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在清理广告内容...');
          await runEpubBackgroundOperation<void>(
            EpubBackgroundOperation.adClean,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'patterns': _patterns,
            },
          );
          _logController.append('广告清理完成');
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '广告清理完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.imgCompress:
          _logController.append('JPEG 质量：$_jpegQuality, PNG→JPG: $_pngToJpg');
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在压缩图片...');
          final result = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.imgCompress,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'jpegQuality': _jpegQuality,
              'pngToJpg': _pngToJpg,
            },
          );
          // 将结果按行输出到日志面板
          for (final line in result.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '图片压缩完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.imgToWebp:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在将图片转换为 WebP...');
          final result = await ImgToWebpOperation.execute(
            epubPath: _epubPath,
            outputPath: _outputPath,
          );
          // 将结果按行输出到日志面板
          for (final line in result.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            if (result.contains('未能转换') || result.contains('跳过')) {
              context.read<ToastProvider>().showWarning(
                result.contains('未能转换') ? '未能转换任何图片' : '图片转 WebP 已完成（部分跳过）',
              );
            } else {
              context.read<ToastProvider>().showSuccess(
                '图片转 WebP 完成，已保存到 $_outputPath',
              );
            }
          }
          break;

        case EpubToolOp.webpToImg:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在将 WebP 图片转换为 JPEG/PNG...');
          final webpResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.webpToImg,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          for (final line in webpResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              'WebP 转图片完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.downloadImages:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在下载网络图片...');
          final dlResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.downloadImages,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          for (final line in dlResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '网络图片下载完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.s2t:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行简体转繁体...');
          final s2tResult = await S2tOperation.execute(
            epubPath: _epubPath,
            outputPath: _outputPath,
          );
          for (final line in s2tResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '简转繁完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.t2s:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行繁体转简体...');
          final t2sResult = await T2sOperation.execute(
            epubPath: _epubPath,
            outputPath: _outputPath,
          );
          for (final line in t2sResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '繁转简完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.phonetic:
          _logController.append('声调模式: $_toneMode, 全文注音: $_annotateAll');
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行拼音标注...');
          final phoneticResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.phonetic,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'toneMode': _toneMode,
              'annotateAll': _annotateAll,
            },
          );
          for (final line in phoneticResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '拼音标注完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.fontSubset:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行字体子集化...');
          final subsetResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.fontSubset,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          for (final line in subsetResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '字体子集化完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.encrypt:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行名称混淆加密...');
          final encResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.encrypt,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          if (encResult == EncryptDecryptBase.encrypted) {
            _logController.append('该 EPUB 已被加密，跳过');
            if (mounted) {
              context.read<ToastProvider>().showWarning('该 EPUB 已被加密，无需重复加密');
            }
          } else {
            for (final line in encResult.split('\n')) {
              if (line.trim().isNotEmpty) {
                _logController.append(line.trim());
              }
            }
            if (mounted) {
              context.read<ToastProvider>().showSuccess(
                '加密完成，已保存到 $_outputPath',
              );
            }
          }
          break;

        case EpubToolOp.decrypt:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行名称混淆解密...');
          final decResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.decrypt,
            {'epubPath': _epubPath, 'outputPath': _outputPath},
          );
          if (decResult == EncryptDecryptBase.zhangyueDrm) {
            _logController.append('检测到掌阅 DRM，不支持解密');
            if (mounted) {
              context.read<ToastProvider>().showError('检测到掌阅 DRM，不支持解密');
            }
          } else if (decResult == EncryptDecryptBase.notEncrypted) {
            _logController.append('该 EPUB 未被加密，无需解密');
            if (mounted) {
              context.read<ToastProvider>().showWarning('该 EPUB 未被加密，无需解密');
            }
          } else {
            for (final line in decResult.split('\n')) {
              if (line.trim().isNotEmpty) {
                _logController.append(line.trim());
              }
            }
            if (mounted) {
              context.read<ToastProvider>().showSuccess(
                '解密完成，已保存到 $_outputPath',
              );
            }
          }
          break;

        case EpubToolOp.encryptFont:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在进行字体加密...');
          final fontFamilies = _targetFontFamilies.trim().isEmpty
              ? null
              : _targetFontFamilies
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
          final xhtmlFiles = _targetXhtmlFiles.trim().isEmpty
              ? null
              : _targetXhtmlFiles
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
          final efResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.encryptFont,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'targetFontFamilies': fontFamilies,
              'targetXhtmlFiles': xhtmlFiles,
            },
          );
          for (final line in efResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '字体加密完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.listFontTargets:
          _logController.append('正在扫描字体目标...');
          final ltResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.listFontTargets,
            {'epubPath': _epubPath},
          );
          for (final line in ltResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess('字体目标扫描完成');
          }
          break;

        case EpubToolOp.merge:
          if (_mergeInputPaths.length < 2) {
            if (mounted) {
              context.read<ToastProvider>().showWarning('合并至少需要 2 个 EPUB 文件');
            }
            setState(() => _loading = false);
            return;
          }
          _logController.append('合并 ${_mergeInputPaths.length} 个 EPUB');
          _logController.append('输出文件：$_outputPath');
          final mergeResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.merge,
            {'inputPaths': _mergeInputPaths, 'outputPath': _outputPath},
          );
          for (final line in mergeResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess('合并完成，已保存到 $_outputPath');
          }
          break;

        case EpubToolOp.split:
          if (_splitPoints.trim().isEmpty) {
            if (mounted) {
              context.read<ToastProvider>().showWarning('请输入拆分点索引');
            }
            setState(() => _loading = false);
            return;
          }
          final outputDir = _splitOutputDir.isEmpty
              ? p.dirname(_outputPath)
              : _splitOutputDir;
          final points = _splitPoints
              .split(',')
              .map((s) => int.tryParse(s.trim()) ?? -1)
              .where((i) => i >= 0)
              .toList();
          _logController.append('拆分点: $points');
          _logController.append('输出目录: $outputDir');
          final splitResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.split,
            {
              'epubPath': _epubPath,
              'outputDir': outputDir,
              'splitPoints': points,
            },
          );
          for (final line in splitResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess('拆分完成，已保存到 $outputDir');
          }
          break;

        case EpubToolOp.listSplitTargets:
          _logController.append('正在扫描拆分目标...');
          final targets = await runEpubBackgroundOperation<Map>(
            EpubBackgroundOperation.listSplitTargets,
            {'epubPath': _epubPath},
          );
          final formatted = targets['formatted'] as String;
          for (final line in formatted.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '拆分目标扫描完成 (${targets['length']} 个)',
            );
          }
          break;

        case EpubToolOp.comment:
          if (_regexPattern.trim().isEmpty) {
            if (mounted) {
              context.read<ToastProvider>().showWarning('请输入正则表达式');
            }
            setState(() => _loading = false);
            return;
          }
          _logController.append('正则表达式：$_regexPattern');
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在提取批注...');
          final commentResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.comment,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'regexPattern': _regexPattern,
            },
          );
          for (final line in commentResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            if (commentResult.contains('错误')) {
              context.read<ToastProvider>().showError('批注提取失败');
            } else {
              context.read<ToastProvider>().showSuccess(
                '批注提取完成，已保存到 $_outputPath',
              );
            }
          }
          break;

        case EpubToolOp.footnoteToComment:
          _logController.append('输出文件：$_outputPath');
          final ftcResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.footnoteToComment,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'regexPattern': r'^#+',
              'notePngBytes': _notePngBytes,
            },
          );
          for (final line in ftcResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '脚注转弹窗完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.spanToFootnote:
          _logController.append(
            '脚注文字颜色：${_footnoteColor.isEmpty ? '默认' : _footnoteColor}',
          );
          _logController.append(
            '引用颜色：${_noterefColor.isEmpty ? '默认' : _noterefColor}',
          );
          _logController.append('输出文件：$_outputPath');
          final stfResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.spanToFootnote,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'footnoteColor': _footnoteColor,
              'noterefColor': _noterefColor,
            },
          );
          for (final line in stfResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            context.read<ToastProvider>().showSuccess(
              '弹窗转脚注完成，已保存到 $_outputPath',
            );
          }
          break;

        case EpubToolOp.yuewei:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在转换阅微脚注为多看格式...');
          final yueweiResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.yuewei,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'notePngBytes': _notePngBytes,
            },
          );
          for (final line in yueweiResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            if (yueweiResult.contains('错误')) {
              context.read<ToastProvider>().showError('阅微转多看失败');
            } else {
              context.read<ToastProvider>().showSuccess(
                '阅微转多看完成，已保存到 $_outputPath',
              );
            }
          }
          break;

        case EpubToolOp.zhangyue:
          _logController.append('输出文件：$_outputPath');
          _logController.append('正在转换得到脚注为多看格式...');
          final zhangyueResult = await runEpubBackgroundOperation<String>(
            EpubBackgroundOperation.zhangyue,
            {
              'epubPath': _epubPath,
              'outputPath': _outputPath,
              'notePngBytes': _notePngBytes,
            },
          );
          for (final line in zhangyueResult.split('\n')) {
            if (line.trim().isNotEmpty) {
              _logController.append(line.trim());
            }
          }
          if (mounted) {
            if (zhangyueResult.contains('错误')) {
              context.read<ToastProvider>().showError('得到转多看失败');
            } else {
              context.read<ToastProvider>().showSuccess(
                '得到转多看完成，已保存到 $_outputPath',
              );
            }
          }
          break;
      }
      // 操作成功后，尝试把输出 EPUB 复制到公共 Download/books/ 目录
      // （仅 Android 生效，Mac/Windows/iOS 跳过）
      await _copyToPublicDownload();
    } catch (e) {
      _logController.append('ERROR: 操作失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('操作失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 把生成的 EPUB 复制到公共 Download/books/ 目录
  ///
  /// Android 11+ Scoped Storage 禁止应用直接写入公共 Download，
  /// 通过 MediaStore.Downloads API 复制可解决这个问题，
  /// 让用户在文件管理器 / Download 目录看到输出文件。
  ///
  /// **大文件优化**：对 >10MB 文件，改用 [FileService.copyFileToPublicDownload]，
  /// 让原生端通过 FileInputStream 流式读写，避免 Dart 堆持有整个文件副本
  /// 导致 OOM 闪退（之前 47MB EPUB 在某些 Android 设备上必闪退）。
  ///
  /// 仅 Android 平台生效，其他平台直接保留原 _outputPath。
  /// 操作成功后更新 _outputPath 为公共路径，Toast 和日志都展示新路径。
  Future<void> _copyToPublicDownload() async {
    if (_outputPath.isEmpty) return;
    if (!Platform.isAndroid) return;
    // 文件不存在（拆分等操作可能输出到其他目录）则跳过
    if (!await File(_outputPath).exists()) {
      _logController.append('WARN: 输出文件不存在，跳过复制到公共 Download：$_outputPath');
      return;
    }

    // 阈值：超过 10MB 改用流式复制（避免 OOM）
    const streamThreshold = 10 * 1024 * 1024;
    final fileSize = await File(_outputPath).length();
    final useStream = fileSize > streamThreshold;

    try {
      final filename = p.basename(_outputPath);
      String publicPath;

      if (useStream) {
        _logController.append(
          'PROGRESS: 大文件（${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB），使用流式复制...',
        );
        publicPath = await FileService.copyFileToPublicDownload(
          sourcePath: _outputPath,
          filename: filename,
        );
      } else {
        // 小文件（≤10MB）：直接读 bytes 走原方法，简单可靠
        final bytes = await File(_outputPath).readAsBytes();
        publicPath = await FileService.writeToPublicDownload(
          filename: filename,
          bytes: bytes,
        );
      }

      _logController.append('PROGRESS: 已复制到公共 Download: $publicPath');

      // 复制成功后删除原文件（应用专属目录的临时副本），
      // 避免 /Android/data/.../files/books/ 堆满重复文件。
      try {
        final tempFile = File(_outputPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
          _logController.append('PROGRESS: 已清理临时文件: $_outputPath');
        }
      } catch (e) {
        _logController.append('WARN: 清理临时文件失败：$e');
      }

      _outputPath = publicPath;
    } catch (e) {
      _logController.append('WARN: 复制到公共 Download 失败：$e（文件保留在 $_outputPath）');
    }
  }

  /// 构建质量滑块控件
  Widget _buildQualitySlider({
    required String label,
    required int value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value.toDouble(),
          min: 10,
          max: 100,
          divisions: 18,
          label: value.toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// 获取声调模式显示名称
  String _toneModeName(String mode) {
    switch (mode) {
      case 'mark':
        return '带音标';
      case 'number':
        return '数字声调';
      default:
        return '不带声调';
    }
  }

  /// 从显示名称获取声调模式值
  String _toneModeFromName(String name) {
    switch (name) {
      case '带音标':
        return 'mark';
      case '数字声调':
        return 'number';
      default:
        return 'none';
    }
  }

  /// 构建操作特定的参数输入区域
  ///
  /// 根据当前选中的操作类型，返回对应的参数输入控件列表。
  List<Widget> _buildOperationParams() {
    switch (_selectedOp) {
      case EpubToolOp.viewOpf:
        return const [];
      case EpubToolOp.replaceCover:
        return [
          // 新封面图片选择
          BaseInput(
            label: '新封面图片',
            value: _coverPath,
            hint: '请选择新封面图片文件',
            prefixIcon: Icons.image_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickCover,
            ),
          ),
          const SizedBox(height: 16),
          // 输出路径
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.reformat:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.convertVersion:
        return [
          BaseSelect(
            label: '目标版本',
            value: _targetVersion,
            items: const ['2.0', '3.0'],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _targetVersion = v);
              if (!userPickedOutput && _epubPath.isNotEmpty) {
                await _autoFillOutputPath();
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.epubToTxt:
        return [
          BaseInput(
            label: '输出 TXT 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.adClean:
        return [
          BaseInput(
            label: '清理规则',
            value: _patterns,
            hint: '格式：正则1|||替换1|||正则2|||替换2',
            prefixIcon: Icons.cleaning_services_outlined,
            onChanged: (v) => setState(() => _patterns = v),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.imgCompress:
        return [
          // JPEG 质量滑块
          _buildQualitySlider(
            label: 'JPEG 压缩质量',
            value: _jpegQuality,
            onChanged: (v) => setState(() => _jpegQuality = v.round()),
          ),
          const SizedBox(height: 12),
          // PNG 转 JPG 开关
          SwitchListTile(
            title: const Text('无透明 PNG 转 JPG'),
            subtitle: const Text('将不含透明通道的 PNG 转为 JPG 以减小体积'),
            value: _pngToJpg,
            onChanged: (v) => setState(() => _pngToJpg = v),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.imgToWebp:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'WebP 质量固定为 80。macOS 打包版已内置 cwebp；Windows 打包时可随程序放入 bin/cwebp.exe。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.webpToImg:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.downloadImages:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.s2t:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.t2s:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.phonetic:
        return [
          BaseSelect(
            label: '声调模式',
            value: _toneModeName(_toneMode),
            items: const ['带音标', '不带声调', '数字声调'],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _toneMode = _toneModeFromName(v);
              });
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('全文注音'),
            subtitle: const Text('关闭则仅标注生僻字'),
            value: _annotateAll,
            onChanged: (v) => setState(() => _annotateAll = v),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.fontSubset:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '仅支持 TTF/OTF 格式字体子集化，WOFF/WOFF2 将跳过',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.encrypt:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '通过 MD5 哈希混淆文件名，使编辑器无法打开修改',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.decrypt:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '用 manifest id 还原被混淆的文件名',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.encryptFont:
        return [
          BaseInput(
            label: '目标字体族（逗号分隔，留空则全部）',
            value: _targetFontFamilies,
            hint: '如：SongTi,HeiTi',
            prefixIcon: Icons.font_download_outlined,
            onChanged: (v) => setState(() => _targetFontFamilies = v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '目标 XHTML 文件（逗号分隔，留空则全部）',
            value: _targetXhtmlFiles,
            hint: '如：chapter1.xhtml,chapter2.xhtml',
            prefixIcon: Icons.article_outlined,
            onChanged: (v) => setState(() => _targetXhtmlFiles = v),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '仅支持 TTF 字体，通过字形混淆实现防复制',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.listFontTargets:
        return const [];
      case EpubToolOp.merge:
        return [
          // 合并输入文件列表
          Text(
            '待合并 EPUB 文件 (${_mergeInputPaths.length} 个)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          // 文件列表显示
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: _mergeInputPaths.isEmpty
                ? Center(
                    child: Text(
                      '请选择要合并的 EPUB 文件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _mergeInputPaths.length,
                    itemBuilder: (ctx, idx) {
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text('${idx + 1}'),
                        ),
                        title: Text(
                          p.basename(_mergeInputPaths[idx]),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        subtitle: Text(
                          _mergeInputPaths[idx],
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              BaseButton(
                label: '选择文件',
                icon: Icons.library_add_outlined,
                variant: BaseButtonVariant.secondary,
                onPressed: _pickMergeFiles,
              ),
              const SizedBox(width: 8),
              if (_mergeInputPaths.isNotEmpty)
                BaseButton(
                  label: '清空',
                  icon: Icons.clear,
                  variant: BaseButtonVariant.secondary,
                  onPressed: () => setState(() => _mergeInputPaths = []),
                ),
            ],
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.split:
        return [
          BaseInput(
            label: '拆分点索引（逗号分隔）',
            value: _splitPoints,
            hint: '如：2,5,8（先执行「列出拆分目标」获取索引）',
            prefixIcon: Icons.call_split,
            onChanged: (v) => setState(() => _splitPoints = v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '输出目录',
            value: _splitOutputDir,
            hint: '选择拆分后 EPUB 的保存目录',
            prefixIcon: Icons.folder_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickSplitOutputDir,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '先执行「列出拆分目标」获取章节列表和索引，再输入拆分点',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case EpubToolOp.listSplitTargets:
        return const [];
      case EpubToolOp.comment:
        return [
          BaseInput(
            label: '正则表达式',
            value: _regexPattern,
            hint: r'默认 \[(.*?)\] 匹配 [内容] 格式批注',
            prefixIcon: Icons.code,
            onChanged: (v) => setState(() => _regexPattern = v),
          ),
          const SizedBox(height: 8),
          Text(
            '正则中第一个捕获组将被作为批注内容提取。'
            '程序会自动将 (.*) 优化为 (.*?) 非贪婪匹配。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.footnoteToComment:
        return [
          Text(
            '会把内部脚注链接替换为阅微弹窗注释，并尝试删除原脚注正文。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.spanToFootnote:
        return [
          BaseInput(
            label: '脚注文字颜色',
            value: _footnoteColor,
            hint: '默认 #004e1c',
            prefixIcon: Icons.format_color_text,
            onChanged: (v) => setState(() => _footnoteColor = v),
          ),
          const SizedBox(height: 12),
          BaseInput(
            label: '脚注引用颜色',
            value: _noterefColor,
            hint: '默认 #b00020',
            prefixIcon: Icons.format_color_fill,
            onChanged: (v) => setState(() => _noterefColor = v),
          ),
          const SizedBox(height: 16),
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
        ];
      case EpubToolOp.yuewei:
      case EpubToolOp.zhangyue:
        return [
          BaseInput(
            label: '输出 EPUB 路径',
            value: _outputPath,
            hint: '选择输出文件位置',
            prefixIcon: Icons.save_outlined,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _pickOutput,
            ),
          ),
          if (_selectedOp == EpubToolOp.yuewei) const SizedBox(height: 8),
          if (_selectedOp == EpubToolOp.yuewei)
            Text(
              '将阅微格式的弹窗脚注 span 转为多看标准脚注格式，'
              '自动注入 note.png 图标和 epub 命名空间。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (_selectedOp == EpubToolOp.zhangyue) const SizedBox(height: 8),
          if (_selectedOp == EpubToolOp.zhangyue)
            Text(
              '将得到格式散落的 aside 脚注转为多看标准格式，'
              '集中生成脚注区域并添加返回链接。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 页头
            const PageHeader(
              icon: Icons.build_outlined,
              iconColor: Color(0xFF0EA5E9),
              title: 'EPUB 工具箱',
              description:
                  '查看元数据、替换封面、格式化、版本转换、转TXT、广告清理、图片压缩/转WebP/WebP转图片、下载网络图片、简繁转换、拼音标注、字体子集化、加密/解密、字体加密、合并/拆分EPUB、批注/脚注转换、阅微转多看、得到转多看',
            ),
            const SizedBox(height: 12),

            // 操作选择卡片
            BaseCard(
              title: '选择操作',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BaseSelect(
                    label: '操作类型',
                    value: _selectedOp.label,
                    items: EpubToolOp.values.map((e) => e.label).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final op = EpubToolOp.values.firstWhere(
                        (e) => e.label == v,
                      );
                      setState(() {
                        _selectedOp = op;
                        _resultText = '';
                        _outputPath = ''; // 重置，执行时自动填充安全路径
                        if (op == EpubToolOp.comment) {
                          _regexPattern = r'\[(.*?)\]';
                        }
                      });
                      // 异步填充输出路径到应用安全目录
                      if (_epubPath.isNotEmpty) {
                        _autoFillOutputPath().then((_) {
                          if (mounted) setState(() {});
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedOp.desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 文件选择卡片
            BaseCard(
              title: '文件选择',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // merge 操作使用独立的多文件选择器，不显示单个 EPUB 输入
                  if (_selectedOp != EpubToolOp.merge) ...[
                    BaseInput(
                      label: 'EPUB 文件',
                      value: _epubPath,
                      hint: '请选择 EPUB 文件',
                      prefixIcon: Icons.book_outlined,
                      suffix: BaseButton(
                        label: '选择',
                        variant: BaseButtonVariant.secondary,
                        onPressed: _pickEpub,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 操作特定参数
                  ..._buildOperationParams(),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 执行按钮
            Row(
              children: [
                BaseButton(
                  label: '执行操作',
                  icon: Icons.play_arrow,
                  loading: _loading,
                  onPressed: _loading ? null : _execute,
                ),
                const SizedBox(width: 12),
                if (_loading)
                  Text(
                    '正在处理，请稍候...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 文本结果区域（仅文本类操作显示）
            if (_returnsText && _resultText.isNotEmpty) ...[
              BaseCard(
                title: _selectedOp == EpubToolOp.viewOpf ? 'OPF 元数据' : '提取的文本',
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _resultText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 输出日志面板
            OutputLog(controller: _logController),
          ],
        ),
      ),
    );
  }
}
