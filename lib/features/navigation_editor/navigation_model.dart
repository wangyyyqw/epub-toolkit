enum NavigationSection { toc, landmarks, pageList }

extension NavigationSectionLabel on NavigationSection {
  String get label => switch (this) {
    NavigationSection.toc => '目录',
    NavigationSection.landmarks => '地标',
    NavigationSection.pageList => '页码',
  };

  String get epubType => switch (this) {
    NavigationSection.toc => 'toc',
    NavigationSection.landmarks => 'landmarks',
    NavigationSection.pageList => 'page-list',
  };
}

class NavigationEntry {
  final String title;
  final String href;
  final int level;
  final String semanticType;
  final int? sourceHeadingIndex;

  const NavigationEntry({
    required this.title,
    required this.href,
    required this.level,
    this.semanticType = '',
    this.sourceHeadingIndex,
  });

  NavigationEntry copyWith({
    String? title,
    String? href,
    int? level,
    String? semanticType,
    int? sourceHeadingIndex,
    bool clearSourceHeadingIndex = false,
  }) {
    return NavigationEntry(
      title: title ?? this.title,
      href: href ?? this.href,
      level: level ?? this.level,
      semanticType: semanticType ?? this.semanticType,
      sourceHeadingIndex: clearSourceHeadingIndex
          ? null
          : (sourceHeadingIndex ?? this.sourceHeadingIndex),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'href': href,
    'level': level,
    if (semanticType.isNotEmpty) 'semanticType': semanticType,
    if (sourceHeadingIndex != null) 'sourceHeadingIndex': sourceHeadingIndex,
  };

  factory NavigationEntry.fromJson(Map<String, Object?> json) {
    return NavigationEntry(
      title: json['title'] as String? ?? '',
      href: json['href'] as String? ?? '',
      level: json['level'] as int? ?? 1,
      semanticType: json['semanticType'] as String? ?? '',
      sourceHeadingIndex: json['sourceHeadingIndex'] as int?,
    );
  }
}

enum NavigationValidationSeverity { error, warning }

class NavigationValidationIssue {
  final NavigationValidationSeverity severity;
  final NavigationSection section;
  final int? entryIndex;
  final String code;
  final String message;

  const NavigationValidationIssue({
    required this.severity,
    required this.section,
    required this.code,
    required this.message,
    this.entryIndex,
  });

  Map<String, Object?> toJson() => {
    'severity': severity.name,
    'section': section.name,
    'entryIndex': entryIndex,
    'code': code,
    'message': message,
  };

  factory NavigationValidationIssue.fromJson(Map<String, Object?> json) {
    return NavigationValidationIssue(
      severity: NavigationValidationSeverity.values.byName(
        json['severity'] as String,
      ),
      section: NavigationSection.values.byName(json['section'] as String),
      entryIndex: json['entryIndex'] as int?,
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class EpubNavigationDocument {
  final String sourcePath;
  final String opfPath;
  final String epubVersion;
  final String? navPath;
  final String? ncxPath;
  final Map<NavigationSection, List<NavigationEntry>> sections;
  final List<NavigationValidationIssue> issues;

  const EpubNavigationDocument({
    required this.sourcePath,
    required this.opfPath,
    required this.epubVersion,
    required this.sections,
    this.navPath,
    this.ncxPath,
    this.issues = const [],
  });

  List<NavigationEntry> entries(NavigationSection section) =>
      sections[section] ?? const [];

  EpubNavigationDocument copyWith({
    Map<NavigationSection, List<NavigationEntry>>? sections,
    List<NavigationValidationIssue>? issues,
  }) {
    return EpubNavigationDocument(
      sourcePath: sourcePath,
      opfPath: opfPath,
      epubVersion: epubVersion,
      navPath: navPath,
      ncxPath: ncxPath,
      sections: sections ?? this.sections,
      issues: issues ?? this.issues,
    );
  }

  Map<String, Object?> toJson() => {
    'sourcePath': sourcePath,
    'opfPath': opfPath,
    'epubVersion': epubVersion,
    'navPath': navPath,
    'ncxPath': ncxPath,
    'sections': {
      for (final section in NavigationSection.values)
        section.name: entries(section).map((entry) => entry.toJson()).toList(),
    },
    'issues': issues.map((issue) => issue.toJson()).toList(),
  };

  factory EpubNavigationDocument.fromJson(Map<String, Object?> json) {
    final rawSections = (json['sections'] as Map).cast<String, Object?>();
    return EpubNavigationDocument(
      sourcePath: json['sourcePath'] as String,
      opfPath: json['opfPath'] as String,
      epubVersion: json['epubVersion'] as String? ?? '',
      navPath: json['navPath'] as String?,
      ncxPath: json['ncxPath'] as String?,
      sections: {
        for (final section in NavigationSection.values)
          section: (rawSections[section.name] as List? ?? const [])
              .map(
                (item) => NavigationEntry.fromJson(
                  (item as Map).cast<String, Object?>(),
                ),
              )
              .toList(),
      },
      issues: (json['issues'] as List? ?? const [])
          .map(
            (item) => NavigationValidationIssue.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }
}
