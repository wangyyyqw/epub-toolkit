import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/file_service.dart';
import '../../../core/theme.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/base_button.dart';
import '../../../shared/widgets/base_card.dart';
import '../../../shared/widgets/output_log.dart';
import '../../epub_health/epub_health_repair.dart';
import '../../epub_health/epub_health_report.dart';
import '../../epub_health/epubcheck_runner.dart';
import '../epub_background_operation.dart';
import '../epub_tool_widgets.dart';

enum _IssueFilter { all, error, warning, suggestion }

class EpubHealthPage extends StatefulWidget {
  const EpubHealthPage({super.key});

  @override
  State<EpubHealthPage> createState() => _EpubHealthPageState();
}

class _EpubHealthPageState extends State<EpubHealthPage> {
  String _epubPath = '';
  String _outputPath = '';
  bool _userPickedOutput = false;
  bool _loading = false;
  bool _epubCheckLoading = false;
  EpubHealthReport? _report;
  _IssueFilter _filter = _IssueFilter.all;
  final Set<String> _selectedFixIds = {};
  final OutputLogController _logController = OutputLogController();

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  Future<void> _pickEpub() async {
    final path = await FileService.pickEpub();
    if (path == null) return;
    _epubPath = path;
    _report = null;
    _selectedFixIds.clear();
    if (!_userPickedOutput) {
      _outputPath = await FileService.getDefaultOutputPathForInput(
        inputPath: path,
        filename: '${p.basenameWithoutExtension(path)}_repaired.epub',
      );
    }
    if (mounted) setState(() {});
    await _scan();
  }

  Future<void> _pickOutput() async {
    final path = await FileService.saveFile(
      defaultFileName: _epubPath.isEmpty
          ? 'repaired.epub'
          : '${p.basenameWithoutExtension(_epubPath)}_repaired.epub',
      initialDirectory: _epubPath.isEmpty ? null : p.dirname(_epubPath),
    );
    if (path == null) return;
    _userPickedOutput = true;
    if (mounted) setState(() => _outputPath = path);
  }

  Future<void> _scan() async {
    if (_epubPath.isEmpty) {
      _warning('请先选择 EPUB 文件');
      return;
    }
    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 正在执行内置 EPUB 体检...');
    try {
      final data = await runEpubBackgroundOperation<Map<String, Object?>>(
        EpubBackgroundOperation.healthScan,
        {'epubPath': _epubPath},
      );
      final report = EpubHealthReport.fromJson(data);
      _selectedFixIds
        ..clear()
        ..addAll(
          report.fixes
              .where((fix) => fix.selectedByDefault)
              .map((fix) => fix.id),
        );
      _report = report;
      _appendSummary(report);
      if (report.hasErrors) {
        _warning('体检完成，发现 ${report.errorCount} 个错误');
      } else {
        _success('体检完成');
      }
    } catch (error) {
      _logController.append('ERROR: 体检失败：$error');
      _error('体检失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _repair() async {
    final report = _report;
    if (report == null) {
      await _scan();
      return;
    }
    if (_selectedFixIds.isEmpty) {
      _warning('请至少选择一项安全修复');
      return;
    }
    if (_outputPath.isEmpty) await _pickOutput();
    if (_outputPath.isEmpty) return;

    setState(() => _loading = true);
    _logController.append('PROGRESS: 正在应用 ${_selectedFixIds.length} 项安全修复...');
    try {
      final result = await runEpubBackgroundOperation<Map<String, Object?>>(
        EpubBackgroundOperation.healthRepair,
        {
          'epubPath': _epubPath,
          'outputPath': _outputPath,
          'selectedFixIds': _selectedFixIds.toList(),
          'reportDirectory': p.dirname(_outputPath),
        },
      );
      final after = EpubHealthReport.fromJson(
        (result['after'] as Map).cast<String, Object?>(),
      );
      _outputPath = await FileService.copyGeneratedFileToPublicDownload(
        sourcePath: result['outputPath'] as String,
        log: _logController.append,
      );
      _report = after;
      _selectedFixIds
        ..clear()
        ..addAll(
          after.fixes
              .where((fix) => fix.selectedByDefault)
              .map((fix) => fix.id),
        );
      final applied = (result['appliedFixes'] as List).cast<String>();
      _logController.append('已应用：${applied.join('、')}');
      _logController.append('输出文件：$_outputPath');
      _logController.append('修复前 JSON：${result['beforeJsonReportPath']}');
      _logController.append('修复前 HTML：${result['beforeHtmlReportPath']}');
      _logController.append('修复后 JSON：${result['afterJsonReportPath']}');
      _logController.append('修复后 HTML：${result['afterHtmlReportPath']}');
      _appendSummary(after);
      _success('修复完成并已自动复检');
    } catch (error) {
      _logController.append('ERROR: 修复失败：$error');
      _error('修复失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportReport() async {
    final report = _report;
    if (report == null) return;
    final directory = await FileService.pickDirectory(title: '选择报告保存目录');
    if (directory == null) return;
    try {
      final paths = await EpubHealthRepairOperation.exportReport(
        report: report,
        directory: directory,
        baseName: '${p.basenameWithoutExtension(_epubPath)}_health',
      );
      _logController.append('JSON 报告：${paths['jsonReportPath']}');
      _logController.append('HTML 报告：${paths['htmlReportPath']}');
      _success('报告已导出');
    } catch (error) {
      _error('报告导出失败：$error');
    }
  }

  Future<void> _runEpubCheck() async {
    if (_epubPath.isEmpty) return;
    setState(() => _epubCheckLoading = true);
    _logController.append('PROGRESS: 正在运行 EPUBCheck 完整检查...');
    try {
      final result = await EpubCheckRunner.run(_epubPath);
      final exitCode = result['exitCode'] as int;
      _logController.append('EPUBCheck 退出码：$exitCode');
      _logController.append('EPUBCheck JSON：${result['reportPath']}');
      final output = '${result['stdout']}${result['stderr']}'.trim();
      if (output.isNotEmpty) {
        for (final line in output.split(RegExp(r'[\r\n]+'))) {
          if (line.trim().isNotEmpty) _logController.append(line.trim());
        }
      }
      if (exitCode == 0) {
        _success('EPUBCheck 检查通过');
      } else {
        _warning('EPUBCheck 发现问题，请查看日志和 JSON 报告');
      }
    } catch (error) {
      _logController.append('ERROR: EPUBCheck 无法运行：$error');
      _warning('$error');
    } finally {
      if (mounted) setState(() => _epubCheckLoading = false);
    }
  }

  void _appendSummary(EpubHealthReport report) {
    _logController.append(
      'RESULT: 错误 ${report.errorCount} · 警告 ${report.warningCount} · '
      '建议 ${report.suggestionCount} · 可安全修复 ${report.safeFixCount}',
    );
  }

  void _success(String message) {
    if (mounted) context.read<ToastProvider>().showSuccess(message);
  }

  void _warning(String message) {
    if (mounted) context.read<ToastProvider>().showWarning(message);
  }

  void _error(String message) {
    if (mounted) context.read<ToastProvider>().showError(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          buildToolHeader(
            context,
            icon: Icons.health_and_safety_outlined,
            title: 'EPUB 体检与修复',
            subtitle: '检查包结构、导航、资源引用、封面与字体声明',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                ResponsiveRow(
                  children: [
                    buildFilePickerRow(
                      context,
                      icon: Icons.book_outlined,
                      label: 'EPUB 文件',
                      value: _epubPath,
                      hint: '点击选择 EPUB 文件',
                      onTap: _loading ? () {} : _pickEpub,
                      isComplete: _epubPath.isNotEmpty,
                    ),
                    buildFilePickerRow(
                      context,
                      icon: Icons.save_outlined,
                      label: '修复后 EPUB',
                      value: _outputPath,
                      hint: '点击选择输出位置',
                      onTap: _loading ? () {} : _pickOutput,
                      isComplete: _outputPath.isNotEmpty,
                    ),
                  ],
                ),
                if (_report != null) ...[
                  const SizedBox(height: 12),
                  _buildSummary(context, _report!),
                  const SizedBox(height: 12),
                  _buildIssues(context, _report!),
                ],
                const SizedBox(height: 12),
                OutputLog(controller: _logController),
              ],
            ),
          ),
          buildBottomActionBar(
            context,
            loading: _loading,
            onPressed: _loading
                ? () {}
                : _report == null
                ? _scan
                : _repair,
            label: _report == null
                ? '开始体检'
                : _selectedFixIds.isEmpty
                ? '重新体检'
                : '修复并复检 (${_selectedFixIds.length})',
            icon: _report == null
                ? Icons.fact_check_outlined
                : Icons.build_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, EpubHealthReport report) {
    return BaseCard(
      title: '体检结果',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          BaseButton(
            label: '重新体检',
            icon: Icons.refresh,
            size: BaseButtonSize.sm,
            variant: BaseButtonVariant.secondary,
            onPressed: _loading ? null : _scan,
          ),
          BaseButton(
            label: '导出报告',
            icon: Icons.download_outlined,
            size: BaseButtonSize.sm,
            variant: BaseButtonVariant.secondary,
            onPressed: _loading ? null : _exportReport,
          ),
          if (EpubCheckRunner.supportedPlatform)
            BaseButton(
              label: 'EPUBCheck',
              icon: Icons.verified_outlined,
              size: BaseButtonSize.sm,
              variant: BaseButtonVariant.secondary,
              loading: _epubCheckLoading,
              onPressed: _loading || _epubCheckLoading ? null : _runEpubCheck,
            ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _metric(
                context,
                '错误',
                report.errorCount,
                const Color(0xFFB91C1C),
              ),
              _metric(
                context,
                '警告',
                report.warningCount,
                const Color(0xFFA16207),
              ),
              _metric(
                context,
                '建议',
                report.suggestionCount,
                const Color(0xFF0369A1),
              ),
              _metric(
                context,
                '可修复',
                report.safeFixCount,
                const Color(0xFF166534),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'EPUB ${report.epubVersion ?? '未知'} · ${report.fileCount} 个文件 · '
              '${report.manifestItemCount} 个 manifest 项 · ${report.spineItemCount} 个 spine 项',
              style: TextStyle(fontSize: 12, color: context.themeTextTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value, Color color) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: context.themeDividerLight)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: context.themeTextTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssues(BuildContext context, EpubHealthReport report) {
    final visible = report.issues.where((issue) {
      return switch (_filter) {
        _IssueFilter.all => true,
        _IssueFilter.error => issue.severity == EpubHealthSeverity.error,
        _IssueFilter.warning => issue.severity == EpubHealthSeverity.warning,
        _IssueFilter.suggestion =>
          issue.severity == EpubHealthSeverity.suggestion,
      };
    }).toList();
    return BaseCard(
      title: '检查项目',
      trailing: report.safeFixCount == 0
          ? null
          : Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedFixIds
                      ..clear()
                      ..addAll(report.fixes.map((fix) => fix.id));
                  }),
                  child: const Text('全选可修复项'),
                ),
                TextButton(
                  onPressed: () => setState(_selectedFixIds.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_IssueFilter>(
            segments: const [
              ButtonSegment(value: _IssueFilter.all, label: Text('全部')),
              ButtonSegment(value: _IssueFilter.error, label: Text('错误')),
              ButtonSegment(value: _IssueFilter.warning, label: Text('警告')),
              ButtonSegment(value: _IssueFilter.suggestion, label: Text('建议')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '当前分类没有检查项',
                style: TextStyle(color: context.themeTextTertiary),
              ),
            )
          else
            for (var index = 0; index < visible.length; index++) ...[
              _buildIssueRow(context, visible[index]),
              if (index != visible.length - 1)
                Divider(height: 1, color: context.themeDividerLight),
            ],
        ],
      ),
    );
  }

  Widget _buildIssueRow(BuildContext context, EpubHealthIssue issue) {
    final color = switch (issue.severity) {
      EpubHealthSeverity.error => const Color(0xFFB91C1C),
      EpubHealthSeverity.warning => const Color(0xFFA16207),
      EpubHealthSeverity.suggestion => const Color(0xFF0369A1),
    };
    final fix = issue.fix;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fix == null)
            SizedBox(
              width: 42,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.circle, size: 8, color: color),
              ),
            )
          else
            SizedBox(
              width: 42,
              child: Checkbox(
                value: _selectedFixIds.contains(fix.id),
                onChanged: _loading
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selectedFixIds.add(fix.id);
                        } else {
                          _selectedFixIds.remove(fix.id);
                        }
                      }),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      issue.severity.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      issue.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.themeTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  issue.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.themeTextSecondary,
                  ),
                ),
                if (issue.location != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    issue.location!,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeTextTertiary,
                    ),
                  ),
                ],
                if (fix != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    '安全修复：${fix.label}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
