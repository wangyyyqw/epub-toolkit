import 'package:flutter/material.dart';

/// 应用主题配置 —「书桌工坊」（Bookdesk Workshop）
///
/// 设计理念：
/// - 松青绿主色 — 与阅读/书籍/图书馆天然关联，有性格但不撞微信读书/Kindle
/// - 暖纸色背景 — 呼应 EPUB 纸质属性，替代冷蓝灰
/// - 工具 UI 使用系统无衬线字体（清晰现代），EPUB 内容预览保留思源宋体
/// - 纯白卡片 + 柔和主色投影 + 弱描边，层次分明

/// 内置思源宋体字体名（仅供 EPUB 内容预览使用）
const String appFontFamily = 'SourceHanSerifApp';

/// 衬线字体回退链（EPUB 内容预览用）
const List<String> _serifFallback = [
  'Source Han Serif SC',
  'Source Han Serif CN',
  'Noto Serif CJK SC',
  'Noto Serif SC',
  'Songti SC',
  'STSong',
  'SimSun',
  'PingFang SC',
  'serif',
];

/// UI 无衬线字体回退链（工具界面用）
const List<String> _sansFallback = [
  'PingFang SC',
  'Noto Sans SC',
  'Microsoft YaHei',
  'Source Han Sans SC',
  'Source Han Sans CN',
  'Heiti SC',
  'sans-serif',
];

/// 为 TextStyle 注入衬线字体（EPUB 内容预览用）
TextStyle withSerifFont(TextStyle style) => style.copyWith(
      fontFamily: appFontFamily,
      fontFamilyFallback: _serifFallback,
    );

class AppTheme {
  AppTheme._();

  // ==================== 亮色色板 ====================

  /// 主色：松青绿（按钮、激活态、品牌色）
  static const Color accent = Color(0xFF3D7A6C);
  static const Color accentDark = Color(0xFF2A5A50);
  static const Color accentLight = Color(0xFFE8F2EF);
  static const Color accentSoft = Color(0xFFF0F7F4);

  /// 强调色：暖陶橙（次操作、进度条、通知标签）
  static const Color warm = Color(0xFFD4845C);
  static const Color warmLight = Color(0xFFFDF2EA);

  /// 背景：暖纸色（替代冷蓝灰）
  static const Color bgBase = Color(0xFFF5F1EB);
  static const Color bgWarm = Color(0xFFEFE9E0);
  static const Color bgPaper = Color(0xFFF5F1EB);

  /// 卡片：纯白
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFFAF8F4);

  /// 文字
  static const Color textPrimary = Color(0xFF1C2B27);
  static const Color textSecondary = Color(0xFF4A5A55);
  static const Color textTertiary = Color(0xFF8A958F);

  /// 分隔线
  static const Color divider = Color(0xFFD9D2C8);
  static const Color dividerLight = Color(0xFFE3DDD3);

  /// 标签/芯片背景
  static const Color chipBg = Color(0xFFEDE8E0);

  /// 功能色
  static const Color success = Color(0xFF5B9C6B);
  static const Color warning = Color(0xFFD49241);
  static const Color error = Color(0xFFC25E5E);
  static const Color info = Color(0xFF3D7A6C);

  // ==================== 暗色色板 ====================

  static const Color darkAccent = Color(0xFF5DAA97);
  static const Color darkAccentDark = Color(0xFF4A8F7E);
  static const Color darkAccentLight = Color(0xFF1A3330);
  static const Color darkAccentSoft = Color(0xFF122624);
  static const Color darkWarm = Color(0xFFE2A17C);
  static const Color darkWarmLight = Color(0xFF2C211C);
  static const Color darkBgBase = Color(0xFF161B19);
  static const Color darkBgWarm = Color(0xFF1A211E);
  static const Color darkBgPaper = Color(0xFF161B19);
  static const Color darkCard = Color(0xFF1F2724);
  static const Color darkCardSoft = Color(0xFF252E2A);
  static const Color darkTextPrimary = Color(0xFFE8EDE9);
  static const Color darkTextSecondary = Color(0xFFB0BAB4);
  static const Color darkTextTertiary = Color(0xFF6E7D75);
  static const Color darkDivider = Color(0xFF2D3631);
  static const Color darkDividerLight = Color(0xFF242C28);
  static const Color darkChipBg = Color(0xFF1A2320);
  static const Color darkSuccess = Color(0xFF7BC98A);
  static const Color darkWarning = Color(0xFFE7B867);
  static const Color darkError = Color(0xFFE08484);
  static const Color darkInfo = Color(0xFF5DAA97);

  // ==================== 阴影 ====================

  /// 卡片浮起阴影（带主色调的柔和投影）
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF3D7A6C).withValues(alpha: 0.06),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: const Color(0xFF3D7A6C).withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// 轻浮起（用于内嵌卡片）
  static List<BoxShadow> get cardShadowLight => [
        BoxShadow(
          color: const Color(0xFF3D7A6C).withValues(alpha: 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: const Color(0xFF3D7A6C).withValues(alpha: 0.025),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 强调阴影（强调色发光）
  static List<BoxShadow> glow(Color color, {double alpha = 0.25}) => [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  // ==================== 圆角 ====================

  static const double radiusXL = 18;
  static const double radiusL = 16;
  static const double radiusM = 14;
  static const double radiusS = 12;
  static const double radiusXS = 10;
  static const double radiusFull = 999;

  // ==================== 间距 ====================

  static const double spaceXL = 28;
  static const double spaceL = 22;
  static const double spaceM = 16;
  static const double spaceS = 12;
  static const double spaceXS = 8;

  // ==================== 动效时长 ====================

  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durBase = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 320);

  // ==================== 响应式断点 ====================

  /// 桌面端最小宽度
  static const double desktopBreakpoint = 1024;

  /// 平板端最小宽度
  static const double tabletBreakpoint = 800;

  // ==================== 亮色主题 ====================

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamilyFallback: _sansFallback,
        brightness: Brightness.light,
        scaffoldBackgroundColor: bgBase,
        colorScheme: const ColorScheme.light(
          primary: accent,
          onPrimary: Colors.white,
          secondary: warm,
          onSecondary: Colors.white,
          surface: card,
          onSurface: textPrimary,
          surfaceContainerHighest: bgWarm,
          outline: divider,
          outlineVariant: dividerLight,
          error: error,
        ),
        splashFactory: InkSparkle.splashFactory,
        cardTheme: CardThemeData(
          elevation: 0,
          color: card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusL),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: textPrimary,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.3,
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: dividerLight, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: dividerLight, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: error, width: 1.5),
          ),
          hintStyle: const TextStyle(fontSize: 14, color: textTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXS),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: chipBg,
          selectedColor: accentLight,
          labelStyle: const TextStyle(fontSize: 13, color: textSecondary),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXS),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          dividerColor: Colors.transparent,
          labelColor: accent,
          unselectedLabelColor: textTertiary,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          indicatorSize: TabBarIndicatorSize.label,
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 0.5,
          space: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.1,
            height: 1.3,
          ),
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.2,
          ),
          titleMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.2,
          ),
          titleSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.3,
          ),
          bodyLarge: TextStyle(
              fontSize: 16, color: textSecondary, height: 1.5),
          bodyMedium: TextStyle(
              fontSize: 14, color: textSecondary, height: 1.5),
          bodySmall: TextStyle(
              fontSize: 12, color: textTertiary, letterSpacing: 0.2),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      );

  // ==================== 暗色主题 ====================

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamilyFallback: _sansFallback,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBgBase,
        colorScheme: const ColorScheme.dark(
          primary: darkAccent,
          onPrimary: Color(0xFF0D1513),
          secondary: darkWarm,
          onSecondary: Color(0xFF2C1808),
          surface: darkCard,
          onSurface: darkTextPrimary,
          surfaceContainerHighest: darkBgWarm,
          outline: darkDivider,
          outlineVariant: darkDividerLight,
          error: darkError,
        ),
        splashFactory: InkSparkle.splashFactory,
        cardTheme: CardThemeData(
          elevation: 0,
          color: darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusL),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: darkTextPrimary,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.3,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkCard,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkDividerLight, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkDividerLight, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkAccent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkError, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkError, width: 1.5),
          ),
          hintStyle: const TextStyle(fontSize: 14, color: darkTextTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkAccent,
            foregroundColor: const Color(0xFF0D1513),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: darkAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXS),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: darkChipBg,
          selectedColor: darkAccentLight,
          labelStyle: const TextStyle(fontSize: 13, color: darkTextSecondary),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXS),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          dividerColor: Colors.transparent,
          labelColor: darkAccent,
          unselectedLabelColor: darkTextTertiary,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          indicatorSize: TabBarIndicatorSize.label,
        ),
        dividerTheme: const DividerThemeData(
          color: darkDivider,
          thickness: 0.5,
          space: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: darkTextPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: darkTextPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: darkTextPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.1,
            height: 1.3,
          ),
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.2,
          ),
          titleMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.2,
          ),
          titleSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.3,
          ),
          bodyLarge: TextStyle(
              fontSize: 16, color: darkTextSecondary, height: 1.5),
          bodyMedium: TextStyle(
              fontSize: 14, color: darkTextSecondary, height: 1.5),
          bodySmall: TextStyle(
              fontSize: 12, color: darkTextTertiary, letterSpacing: 0.2),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: darkTextSecondary,
            letterSpacing: 0.3,
          ),
        ),
      );
}

/// 便捷扩展：从 BuildContext 快速获取主题值
extension AppThemeExt on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get themeAccent => isDarkMode ? AppTheme.darkAccent : AppTheme.accent;
  Color get themeAccentDark =>
      isDarkMode ? AppTheme.darkAccentDark : AppTheme.accentDark;
  Color get themeAccentLight =>
      isDarkMode ? AppTheme.darkAccentLight : AppTheme.accentLight;
  Color get themeAccentSoft =>
      isDarkMode ? AppTheme.darkAccentSoft : AppTheme.accentSoft;
  Color get themeWarm => isDarkMode ? AppTheme.darkWarm : AppTheme.warm;
  Color get themeWarmLight =>
      isDarkMode ? AppTheme.darkWarmLight : AppTheme.warmLight;
  Color get themeBg => isDarkMode ? AppTheme.darkBgBase : AppTheme.bgBase;
  Color get themeBgWarm => isDarkMode ? AppTheme.darkBgWarm : AppTheme.bgWarm;
  Color get themeBgPaper =>
      isDarkMode ? AppTheme.darkBgPaper : AppTheme.bgPaper;
  Color get themeCard => isDarkMode ? AppTheme.darkCard : AppTheme.card;
  Color get themeCardSoft =>
      isDarkMode ? AppTheme.darkCardSoft : AppTheme.cardSoft;
  Color get themeTextPrimary =>
      isDarkMode ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
  Color get themeTextSecondary =>
      isDarkMode ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
  Color get themeTextTertiary =>
      isDarkMode ? AppTheme.darkTextTertiary : AppTheme.textTertiary;
  Color get themeDivider =>
      isDarkMode ? AppTheme.darkDivider : AppTheme.divider;
  Color get themeDividerLight =>
      isDarkMode ? AppTheme.darkDividerLight : AppTheme.dividerLight;
  Color get themeChipBg => isDarkMode ? AppTheme.darkChipBg : AppTheme.chipBg;
  Color get themeSuccess =>
      isDarkMode ? AppTheme.darkSuccess : AppTheme.success;
  Color get themeWarning =>
      isDarkMode ? AppTheme.darkWarning : AppTheme.warning;
  Color get themeError => isDarkMode ? AppTheme.darkError : AppTheme.error;
  Color get themeInfo => isDarkMode ? AppTheme.darkInfo : AppTheme.info;
  List<BoxShadow> get themeCardShadow =>
      isDarkMode ? const [] : AppTheme.cardShadow;
  List<BoxShadow> get themeCardShadowLight =>
      isDarkMode ? const [] : AppTheme.cardShadowLight;

  /// 响应式断点
  bool get isDesktop =>
      MediaQuery.of(this).size.width >= AppTheme.desktopBreakpoint;
  bool get isTablet =>
      MediaQuery.of(this).size.width >= AppTheme.tabletBreakpoint;
  bool get isMobile =>
      MediaQuery.of(this).size.width < AppTheme.tabletBreakpoint;
}

/// 高质感白卡（柔和投影 + 弱描边）
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? color;
  final bool selected;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius,
    this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusL),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusL),
        splashColor: context.themeAccent.withValues(alpha: 0.08),
        highlightColor: context.themeAccent.withValues(alpha: 0.05),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? context.themeCard,
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppTheme.radiusL),
            boxShadow: context.themeCardShadow,
            border: Border.all(
              color: selected
                  ? context.themeAccent.withValues(alpha: 0.4)
                  : context.themeDividerLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 应用背景 — 暖纸色渐变（亮色）/ 深墨绿黑渐变（暗色）
///
/// 用法：
/// - 作为整页背景：`PaperBackground(child: ...)` 直接包裹
/// - 作为独立底层：`Positioned.fill(child: PaperBackground(child: SizedBox.shrink()))`
///   这样在 Stack 中它只绘制渐变，不影响上层布局
class PaperBackground extends StatelessWidget {
  final Widget child;

  const PaperBackground({super.key, this.child = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) {
    final colors = context.isDarkMode
        ? const [
            Color(0xFF161B19),
            Color(0xFF161B19),
            Color(0xFF1A211E),
          ]
        : const [
            Color(0xFFF5F1EB),
            Color(0xFFF5F1EB),
            Color(0xFFEFE9E0),
          ];
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        if (child is! SizedBox) child,
      ],
    );
  }
}
