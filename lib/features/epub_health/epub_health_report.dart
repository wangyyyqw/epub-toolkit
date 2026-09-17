import 'dart:convert';

enum EpubHealthSeverity { error, warning, suggestion }

extension EpubHealthSeverityLabel on EpubHealthSeverity {
  String get label => switch (this) {
    EpubHealthSeverity.error => '错误',
    EpubHealthSeverity.warning => '警告',
    EpubHealthSeverity.suggestion => '建议',
  };
}

class EpubHealthFix {
  final String id;
  final String kind;
  final String label;
  final String description;
  final Map<String, Object?> data;
  final bool selectedByDefault;

  const EpubHealthFix({
    required this.id,
    required this.kind,
    required this.label,
    required this.description,
    this.data = const {},
    this.selectedByDefault = true,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'label': label,
    'description': description,
    'data': data,
    'selectedByDefault': selectedByDefault,
  };

  factory EpubHealthFix.fromJson(Map<String, Object?> json) {
    return EpubHealthFix(
      id: json['id'] as String,
      kind: json['kind'] as String,
      label: json['label'] as String,
      description: json['description'] as String,
      data: (json['data'] as Map?)?.cast<String, Object?>() ?? const {},
      selectedByDefault: json['selectedByDefault'] as bool? ?? true,
    );
  }
}

class EpubHealthIssue {
  final String id;
  final String code;
  final EpubHealthSeverity severity;
  final String title;
  final String message;
  final String? location;
  final EpubHealthFix? fix;

  const EpubHealthIssue({
    required this.id,
    required this.code,
    required this.severity,
    required this.title,
    required this.message,
    this.location,
    this.fix,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'severity': severity.name,
    'title': title,
    'message': message,
    if (location != null) 'location': location,
    if (fix != null) 'fix': fix!.toJson(),
  };

  factory EpubHealthIssue.fromJson(Map<String, Object?> json) {
    return EpubHealthIssue(
      id: json['id'] as String,
      code: json['code'] as String,
      severity: EpubHealthSeverity.values.byName(json['severity'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      location: json['location'] as String?,
      fix: json['fix'] is Map
          ? EpubHealthFix.fromJson((json['fix'] as Map).cast<String, Object?>())
          : null,
    );
  }
}

class EpubHealthReport {
  final String sourcePath;
  final String scannedAt;
  final String? epubVersion;
  final String? opfPath;
  final int fileCount;
  final int manifestItemCount;
  final int spineItemCount;
  final List<EpubHealthIssue> issues;
  final Map<String, Object?>? epubCheck;

  const EpubHealthReport({
    required this.sourcePath,
    required this.scannedAt,
    required this.fileCount,
    required this.manifestItemCount,
    required this.spineItemCount,
    required this.issues,
    this.epubVersion,
    this.opfPath,
    this.epubCheck,
  });

  int count(EpubHealthSeverity severity) =>
      issues.where((issue) => issue.severity == severity).length;

  int get errorCount => count(EpubHealthSeverity.error);
  int get warningCount => count(EpubHealthSeverity.warning);
  int get suggestionCount => count(EpubHealthSeverity.suggestion);
  int get safeFixCount => fixes.length;
  bool get hasErrors => errorCount > 0;

  List<EpubHealthFix> get fixes {
    final unique = <String, EpubHealthFix>{};
    for (final issue in issues) {
      final fix = issue.fix;
      if (fix != null) unique.putIfAbsent(fix.id, () => fix);
    }
    return unique.values.toList(growable: false);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sourcePath': sourcePath,
    'scannedAt': scannedAt,
    'epubVersion': epubVersion,
    'opfPath': opfPath,
    'fileCount': fileCount,
    'manifestItemCount': manifestItemCount,
    'spineItemCount': spineItemCount,
    'summary': {
      'errors': errorCount,
      'warnings': warningCount,
      'suggestions': suggestionCount,
      'safeFixes': safeFixCount,
    },
    'issues': issues.map((issue) => issue.toJson()).toList(),
    if (epubCheck != null) 'epubCheck': epubCheck,
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory EpubHealthReport.fromJson(Map<String, Object?> json) {
    final rawIssues = json['issues'] as List? ?? const [];
    return EpubHealthReport(
      sourcePath: json['sourcePath'] as String? ?? '',
      scannedAt: json['scannedAt'] as String? ?? '',
      epubVersion: json['epubVersion'] as String?,
      opfPath: json['opfPath'] as String?,
      fileCount: json['fileCount'] as int? ?? 0,
      manifestItemCount: json['manifestItemCount'] as int? ?? 0,
      spineItemCount: json['spineItemCount'] as int? ?? 0,
      issues: rawIssues
          .map(
            (item) =>
                EpubHealthIssue.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList(),
      epubCheck: (json['epubCheck'] as Map?)?.cast<String, Object?>(),
    );
  }

  String toHtml() {
    final rows = issues
        .map((issue) {
          final location = issue.location == null
              ? ''
              : '<div class="location">${_escape(issue.location!)}</div>';
          final fix = issue.fix == null
              ? ''
              : '<div class="fix">可安全修复：${_escape(issue.fix!.label)}</div>';
          return '''
      <article class="issue ${issue.severity.name}">
        <div class="badge">${issue.severity.label}</div>
        <div class="detail">
          <h2>${_escape(issue.title)}</h2>
          <p>${_escape(issue.message)}</p>
          $location
          $fix
          <code>${_escape(issue.code)}</code>
        </div>
      </article>''';
        })
        .join('\n');

    final empty = issues.isEmpty ? '<div class="empty">未发现错误、警告或建议。</div>' : '';
    return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EPUB 体检报告</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background: #f5f5f4; color: #18181b; }
    main { max-width: 980px; margin: 0 auto; padding: 32px 20px 64px; }
    h1 { font-size: 28px; margin: 0 0 8px; }
    .meta { color: #71717a; overflow-wrap: anywhere; }
    .summary { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; margin: 24px 0; }
    .metric { border: 1px solid #d4d4d8; background: #fff; padding: 14px; border-radius: 6px; }
    .metric strong { display: block; font-size: 24px; }
    .issue { display: flex; gap: 14px; border-top: 1px solid #d4d4d8; padding: 18px 0; }
    .badge { flex: 0 0 52px; font-weight: 700; }
    .error .badge { color: #b91c1c; } .warning .badge { color: #a16207; } .suggestion .badge { color: #0369a1; }
    .detail { min-width: 0; } h2 { font-size: 16px; margin: 0 0 6px; } p { margin: 0 0 6px; line-height: 1.6; }
    .location, .fix { font-size: 13px; margin-top: 5px; overflow-wrap: anywhere; }
    .location { color: #71717a; } .fix { color: #166534; } code { font-size: 11px; color: #71717a; }
    .empty { border: 1px solid #d4d4d8; background: #fff; padding: 24px; border-radius: 6px; }
    @media (max-width: 640px) { .summary { grid-template-columns: repeat(2, 1fr); } main { padding: 20px 14px 48px; } }
    @media (prefers-color-scheme: dark) {
      body { background: #18181b; color: #f4f4f5; } .meta, .location, code { color: #a1a1aa; }
      .metric, .empty { background: #27272a; border-color: #3f3f46; } .issue { border-color: #3f3f46; }
      .error .badge { color: #fca5a5; } .warning .badge { color: #fde68a; } .suggestion .badge { color: #7dd3fc; } .fix { color: #86efac; }
    }
  </style>
</head>
<body>
<main>
  <h1>EPUB 体检报告</h1>
  <div class="meta">${_escape(sourcePath)}</div>
  <div class="meta">扫描时间：${_escape(scannedAt)} · EPUB ${_escape(epubVersion ?? '未知')} · $fileCount 个文件</div>
  <section class="summary">
    <div class="metric"><strong>$errorCount</strong>错误</div>
    <div class="metric"><strong>$warningCount</strong>警告</div>
    <div class="metric"><strong>$suggestionCount</strong>建议</div>
    <div class="metric"><strong>$safeFixCount</strong>可安全修复</div>
  </section>
  $empty
  $rows
</main>
</body>
</html>''';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
