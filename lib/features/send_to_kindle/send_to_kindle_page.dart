import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_service.dart';
import '../../shared/providers/toast_provider.dart';
import '../../shared/widgets/base_button.dart';
import '../../shared/widgets/base_card.dart';
import '../../shared/widgets/base_input.dart';
import '../../shared/widgets/base_select.dart';
import '../../shared/widgets/output_log.dart';
import '../../shared/widgets/page_header.dart';

enum KindleTab { email, web }

class _SmtpPreset {
  final String key;
  final String label;
  final String host;
  final int port;
  final bool ssl;

  const _SmtpPreset(this.key, this.label, this.host, this.port, this.ssl);
}

const _presets = <_SmtpPreset>[
  _SmtpPreset('qq', 'QQ 邮箱', 'smtp.qq.com', 465, true),
  _SmtpPreset('163', '网易 163', 'smtp.163.com', 465, true),
  _SmtpPreset('126', '网易 126', 'smtp.126.com', 465, true),
  _SmtpPreset('gmail', 'Gmail', 'smtp.gmail.com', 587, false),
  _SmtpPreset('outlook', 'Outlook', 'smtp.office365.com', 587, false),
  _SmtpPreset('sina', '新浪邮箱', 'smtp.sina.com', 465, true),
  _SmtpPreset('custom', '自定义', '', 465, true),
];

class SendToKindlePage extends StatefulWidget {
  final KindleTab tab;

  const SendToKindlePage({super.key, required this.tab});

  @override
  State<SendToKindlePage> createState() => _SendToKindlePageState();
}

class _SendToKindlePageState extends State<SendToKindlePage> {
  static const _settingsKey = 'kindle_smtp_settings';
  static const _amazonKey = 'amazon_account';
  static const _maxAttachmentSize = 50 * 1024 * 1024;

  final _logController = OutputLogController();

  String _inputPath = '';
  String _smtpPreset = 'qq';
  String _smtpHost = 'smtp.qq.com';
  String _smtpPort = '465';
  String _smtpUser = '';
  String _smtpPassword = '';
  bool _useSsl = true;
  bool _rememberLogin = true;
  String _fromEmail = '';
  String _kindleEmail = '';
  String _subject = '';
  String _amazonAccount = '';
  String _amazonPassword = '';
  bool _loading = false;
  bool _showPassword = false;
  bool _showAmazonPassword = false;

  bool get _isEmail => widget.tab == KindleTab.email;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberLogin = prefs.getBool('$_settingsKey.remember') ?? true;
      if (_rememberLogin) {
        _smtpPreset = prefs.getString('$_settingsKey.preset') ?? 'qq';
        _smtpHost = prefs.getString('$_settingsKey.host') ?? 'smtp.qq.com';
        _smtpPort = prefs.getInt('$_settingsKey.port')?.toString() ?? '465';
        _smtpUser = prefs.getString('$_settingsKey.user') ?? '';
        // 密码用 Base64 轻量混淆存储（不是真正的加密，仅防止被明文扫描到）
        _smtpPassword = _decodePassword(
          prefs.getString('$_settingsKey.password') ?? '',
        );
        _useSsl = prefs.getBool('$_settingsKey.ssl') ?? true;
        _fromEmail = prefs.getString('$_settingsKey.from') ?? '';
        _kindleEmail = prefs.getString('$_settingsKey.kindle') ?? '';
      }
      _amazonAccount = prefs.getString('$_amazonKey.account') ?? '';
      _amazonPassword = _decodePassword(
        prefs.getString('$_amazonKey.password') ?? '',
      );
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_settingsKey.remember', _rememberLogin);
    if (_rememberLogin) {
      await prefs.setString('$_settingsKey.preset', _smtpPreset);
      await prefs.setString('$_settingsKey.host', _smtpHost);
      await prefs.setInt('$_settingsKey.port', int.tryParse(_smtpPort) ?? 465);
      await prefs.setString('$_settingsKey.user', _smtpUser);
      await prefs.setString(
        '$_settingsKey.password',
        _encodePassword(_smtpPassword),
      );
      await prefs.setBool('$_settingsKey.ssl', _useSsl);
      await prefs.setString('$_settingsKey.from', _fromEmail);
      await prefs.setString('$_settingsKey.kindle', _kindleEmail);
    } else {
      for (final suffix in [
        'preset',
        'host',
        'port',
        'user',
        'password',
        'ssl',
        'from',
        'kindle',
      ]) {
        await prefs.remove('$_settingsKey.$suffix');
      }
    }
    await prefs.setString('$_amazonKey.account', _amazonAccount);
    await prefs.setString(
      '$_amazonKey.password',
      _encodePassword(_amazonPassword),
    );
  }

  // 仅作混淆用：明文密码 → Base64
  // 注：这不是真正的加密，仅防止密码以原文形式在 SharedPreferences 中可见。
  // 真正安全做法是使用 flutter_secure_storage（Keychain/DPAPI），但会增加依赖。
  static const _xorKey = 0x5A; // 单字节 XOR 混淆 + Base64
  static String _encodePassword(String raw) {
    if (raw.isEmpty) return '';
    final xorred = raw.codeUnits.map((c) => c ^ _xorKey).toList();
    return base64Encode(xorred);
  }

  static String _decodePassword(String encoded) {
    if (encoded.isEmpty) return '';
    try {
      final bytes = base64Decode(encoded);
      return String.fromCharCodes(bytes.map((b) => b ^ _xorKey));
    } catch (_) {
      // 兼容旧的明文格式（升级时旧数据可能不是 Base64）
      return encoded;
    }
  }

  void _applyPreset(String label) {
    final preset = _presets.firstWhere((p) => p.label == label);
    setState(() {
      _smtpPreset = preset.key;
      if (preset.key != 'custom') {
        _smtpHost = preset.host;
        _smtpPort = preset.port.toString();
        _useSsl = preset.ssl;
      }
    });
  }

  /// 协议自动协商：常见端口与 SSL 设置的对应关系
  ///
  /// - 465/993/995 等：SSL 直连（隐式 TLS）
  /// - 587/25/2525 等：STARTTLS（明文连接后升级为 TLS）
  /// - 25/2500/8025 等自定义：信任用户选择
  static bool _normalizeSslSetting(int port, bool userChoice) {
    // 已知 SSL 直连端口
    const sslPorts = {465, 993, 995, 2525};
    // 已知 STARTTLS 端口
    const startTlsPorts = {25, 587, 2526, 8025};
    if (sslPorts.contains(port)) return true;
    if (startTlsPorts.contains(port)) return false;
    // 未知端口信任用户选择
    return userChoice;
  }

  Future<void> _pickFile() async {
    try {
      final path = await FileService.pickFileByExtensions([
        'epub',
        'pdf',
        'txt',
        'doc',
        'docx',
        'html',
        'htm',
        'rtf',
        'jpg',
        'jpeg',
        'png',
        'gif',
      ], title: '选择要推送的文件');
      if (path == null) return;
      setState(() => _inputPath = path);
      _logController.append('已选择文件: ${p.basename(path)}');
    } catch (e) {
      if (!mounted) return;
      _logController.append('ERROR: 选择文件失败：$e');
      context.read<ToastProvider>().showError('选择文件失败：$e');
    }
  }

  Future<void> _sendViaEmail() async {
    if (_inputPath.isEmpty) {
      context.read<ToastProvider>().showWarning('请先选择文件');
      return;
    }
    if (_smtpHost.trim().isEmpty ||
        _smtpUser.trim().isEmpty ||
        _smtpPassword.isEmpty) {
      context.read<ToastProvider>().showWarning('请填写 SMTP 服务器、用户名和密码');
      return;
    }
    if (_kindleEmail.trim().isEmpty) {
      context.read<ToastProvider>().showWarning('请填写 Kindle 接收邮箱');
      return;
    }

    final file = File(_inputPath);
    if (!await file.exists()) {
      if (!mounted) return;
      context.read<ToastProvider>().showError('文件不存在');
      return;
    }
    final size = await file.length();
    if (size > _maxAttachmentSize) {
      if (!mounted) return;
      context.read<ToastProvider>().showError('文件超过 50MB，请使用网页版推送');
      return;
    }

    setState(() => _loading = true);
    _logController.clear();
    _logController.append('PROGRESS: 准备发送 ${p.basename(_inputPath)}');

    // 协议自动协商：587/25 通常是 STARTTLS，465/993/995 通常是 SSL 直连
    final port = int.tryParse(_smtpPort) ?? 465;
    final useSsl = _normalizeSslSetting(port, _useSsl);
    if (useSsl != _useSsl && mounted) {
      _logController.append(
        'INFO: 端口 $port 与 SSL 设置不匹配，自动调整为 ${useSsl ? 'SSL 直连' : 'STARTTLS'}',
      );
    }

    _logController.append(
      'SMTP: $_smtpHost:$port (${useSsl ? 'SSL' : 'STARTTLS'})',
    );
    _logController.append(
      '发件人: ${_fromEmail.trim().isEmpty ? _smtpUser.trim() : _fromEmail.trim()}',
    );
    _logController.append('收件人: ${_kindleEmail.trim()}');

    try {
      await _saveSettings();
      final server = SmtpServer(
        _smtpHost.trim(),
        port: port,
        username: _smtpUser.trim(),
        password: _smtpPassword,
        ssl: useSsl,
        allowInsecure: false,
      );

      final message = Message()
        ..from = Address(
          _fromEmail.trim().isEmpty ? _smtpUser.trim() : _fromEmail.trim(),
        )
        ..recipients.add(_kindleEmail.trim())
        ..subject = _subject
        ..text = ''
        ..attachments = [FileAttachment(file)];

      _logController.append('PROGRESS: 正在连接 SMTP 并发送邮件...');
      await send(message, server);
      _logController.append('PROGRESS: 发送成功');
      _logController.append('请检查发件邮箱收件箱；亚马逊可能会发送验证请求邮件，需要确认后推送才会生效。');
      if (mounted) {
        context.read<ToastProvider>().showSuccess('邮件已发送，请检查验证邮件');
      }
    } catch (e) {
      _logController.append('ERROR: 发送失败：$e');
      if (mounted) {
        context.read<ToastProvider>().showError('发送失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 打开应用内网页版 Send to Kindle
  ///
  /// 使用 WebView 在应用内加载 https://www.amazon.com/sendtokindle
  /// 而不是跳转到外部浏览器。
  void _openWebSend() {
    context.go('/send-web');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              icon: Icons.send_outlined,
              iconColor: const Color(0xFFF59E0B),
              title: 'Kindle 推送 · ${_isEmail ? '邮箱推送' : '网页推送'}',
              description: _isEmail
                  ? '通过 SMTP 邮箱发送文件到 Kindle 设备（支持最大 50MB）'
                  : '打开亚马逊 Send to Kindle 网页上传文件（支持最大 200MB）',
            ),
            const SizedBox(height: 12),
            if (_isEmail) _buildEmailForm() else _buildWebForm(),
            const SizedBox(height: 12),
            OutputLog(controller: _logController),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailForm() {
    return Column(
      children: [
        BaseCard(
          title: '文件',
          child: BaseInput(
            label: '待推送文件',
            value: _inputPath.isEmpty ? '' : p.basename(_inputPath),
            hint: '选择 EPUB、PDF、TXT、DOCX 等个人文档',
            prefixIcon: Icons.attach_file,
            readOnly: true,
            suffix: BaseButton(
              label: '选择',
              variant: BaseButtonVariant.secondary,
              onPressed: _loading ? null : _pickFile,
            ),
          ),
        ),
        const SizedBox(height: 16),
        BaseCard(
          title: '邮箱配置',
          child: Column(
            children: [
              BaseSelect(
                label: '邮箱服务商',
                value: _presets.firstWhere((p) => p.key == _smtpPreset).label,
                items: _presets.map((p) => p.label).toList(),
                onChanged: (v) {
                  if (v != null) _applyPreset(v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: BaseInput(
                      label: 'SMTP 主机',
                      value: _smtpHost,
                      hint: 'smtp.qq.com',
                      prefixIcon: Icons.dns_outlined,
                      onChanged: (v) => setState(() => _smtpHost = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BaseInput(
                      label: '端口',
                      value: _smtpPort,
                      hint: '465',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => _smtpPort = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('SSL 直连'),
                subtitle: const Text('465 端口通常开启；587 端口通常关闭并使用 STARTTLS'),
                value: _useSsl,
                onChanged: (v) => setState(() => _useSsl = v),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: 'SMTP 用户名',
                value: _smtpUser,
                hint: '通常是发件邮箱地址',
                prefixIcon: Icons.alternate_email,
                onChanged: (v) => setState(() => _smtpUser = v),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: 'SMTP 密码/授权码',
                value: _smtpPassword,
                obscureText: !_showPassword,
                prefixIcon: Icons.key_outlined,
                onChanged: (v) => setState(() => _smtpPassword = v),
                suffix: IconButton(
                  tooltip: _showPassword ? '隐藏' : '显示',
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: '发件人邮箱',
                value: _fromEmail,
                hint: '留空则使用 SMTP 用户名',
                prefixIcon: Icons.mail_outline,
                onChanged: (v) => setState(() => _fromEmail = v),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: 'Kindle 接收邮箱',
                value: _kindleEmail,
                hint: 'name@kindle.com',
                prefixIcon: Icons.mark_email_read_outlined,
                onChanged: (v) => setState(() => _kindleEmail = v),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: '邮件主题',
                value: _subject,
                hint: '可留空',
                prefixIcon: Icons.subject,
                onChanged: (v) => setState(() => _subject = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('记住登录信息'),
                value: _rememberLogin,
                onChanged: (v) => setState(() => _rememberLogin = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: BaseButton(
            label: '发送到 Kindle',
            icon: Icons.send_outlined,
            loading: _loading,
            onPressed: _loading ? null : _sendViaEmail,
          ),
        ),
      ],
    );
  }

  Widget _buildWebForm() {
    return Column(
      children: [
        BaseCard(
          title: '亚马逊账号辅助',
          child: Column(
            children: [
              BaseInput(
                label: '亚马逊账号',
                value: _amazonAccount,
                hint: '可选，仅保存在本机',
                prefixIcon: Icons.person_outline,
                onChanged: (v) => setState(() => _amazonAccount = v),
              ),
              const SizedBox(height: 12),
              BaseInput(
                label: '亚马逊密码',
                value: _amazonPassword,
                obscureText: !_showAmazonPassword,
                hint: '可选，仅保存在本机',
                prefixIcon: Icons.lock_outline,
                onChanged: (v) => setState(() => _amazonPassword = v),
                suffix: IconButton(
                  tooltip: _showAmazonPassword ? '隐藏' : '显示',
                  icon: Icon(
                    _showAmazonPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () => setState(
                    () => _showAmazonPassword = !_showAmazonPassword,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: BaseButton(
            label: '打开 Send to Kindle',
            icon: Icons.open_in_new,
            onPressed: _openWebSend,
          ),
        ),
      ],
    );
  }
}
