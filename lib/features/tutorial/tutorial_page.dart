import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/page_header.dart';

/// 使用教程页面
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              icon: Icons.school_outlined,
              iconColor: Color(0xFF14B8A6),
              title: 'Kindle 传书教程',
              description: '邮箱推送与网页推送的完整使用指南',
            ),
            const SizedBox(height: 20),
            _SectionCard(
              icon: Icons.info_outline,
              title: '推送概述',
              children: [
                const _BodyText(
                  'Kindle 推送（Send to Kindle）可以将 EPUB、PDF、TXT、DOC/DOCX、HTML、RTF、JPEG、PNG、GIF 等文件发送到 Kindle 设备或 App。MOBI 已停止支持，AZW3/KFX 等 Kindle 原生格式不能通过推送上传。',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _InfoPill(title: '邮箱推送', text: '适合 50MB 以内文件'),
                    _InfoPill(title: '网页推送', text: '支持最大 200MB 文件'),
                    _InfoPill(title: '账号要求', text: '建议使用 amazon.com 美亚账号'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.mail_outline,
              title: '邮箱推送教程',
              actionLabel: '打开邮箱推送',
              onAction: (context) => context.go('/send-email'),
              children: const [
                _StepText(
                  '1',
                  '获取 Kindle 接收邮箱：在 Kindle 设备设置或 amazon.com/myk 的设备详情中查看 xxx@kindle.com 地址。',
                ),
                _StepText(
                  '2',
                  '添加发件人白名单：进入 amazon.com/myk 的个人文档设置，把发件邮箱加入“已认可的发件人电子邮箱列表”。',
                ),
                _StepText(
                  '3',
                  '获取 SMTP 授权码：QQ、163、Gmail 等邮箱通常需要开启 SMTP 并生成授权码，不能直接使用登录密码。',
                ),
                _StepText('4', '在应用中选择文件、邮箱服务商，填写 SMTP 账号、授权码和 Kindle 邮箱后发送。'),
                _StepText(
                  '5',
                  '如果亚马逊发送验证邮件，可使用一键验证或手动点击邮件中的 Verify Request 链接完成确认。',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.language,
              title: '网页推送教程',
              actionLabel: '打开网页推送',
              onAction: (context) => context.go('/send-web'),
              children: const [
                _StepText('1', '点击“网页推送”打开 Send to Kindle 页面。'),
                _StepText('2', '登录与 Kindle 绑定的 Amazon 账号。'),
                _StepText('3', '上传 EPUB、PDF 或其他支持格式的文件，确认目标设备后提交。'),
                _StepText('4', '等待亚马逊转换并同步到 Kindle 图书馆，通常需要 1 到 5 分钟。'),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionCard(
              icon: Icons.help_outline,
              title: '常见问题',
              children: [
                _QaText(
                  question: '为什么收不到书？',
                  answer: '检查 Kindle 邮箱是否正确、发件邮箱是否已加入白名单，以及亚马逊验证邮件是否已经确认。',
                ),
                _QaText(
                  question: '为什么 SMTP 发送失败？',
                  answer: '确认 SMTP 服务已开启，端口和 SSL 设置匹配邮箱服务商，密码字段填写的是授权码。',
                ),
                _QaText(
                  question: '大文件怎么推送？',
                  answer: '超过邮箱附件限制时使用网页推送，Send to Kindle 网页方式支持更大的文件。',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? actionLabel;
  final void Function(BuildContext context)? onAction;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF14B8A6), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    onPressed: () => onAction!(context),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String title;
  final String text;
  const _InfoPill({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  final String number;
  final String text;
  const _StepText(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF14B8A6),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(height: 1.45, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _QaText extends StatelessWidget {
  final String question;
  final String answer;
  const _QaText({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            answer,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}
