import 'package:flutter/material.dart';

/// 应用主题配置（阅微设置页风格）

/// 中文字体方案：思源宋体优先
const List<String> _sansFallback = [
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

TextStyle _withSans(TextStyle s) =>
    s.copyWith(fontFamily: null, fontFamilyFallback: _sansFallback);

///
/// 设计哲学：
/// - 工具类界面优先清晰、紧凑、可扫描
/// - 低饱和背景 + 白色工作卡片 + 明确描边
/// - 主色用于当前状态和主操作，不做大面积装饰
class AppTheme {
  AppTheme._();

  // ==================== 核心色板 ====================

  /// 主色：蓝绿（工具状态）
  static const Color accent = Color(0xFFBDBDBD);
  static const Color accentDark = Color(0xFFA8A8A8);
  static const Color accentLight = Color(0xFFD0D0D0);
  static const Color accentSoft = Color(0xFFE2E2E2);

  /// 强调色：暖橙（活跃状态/通知）
  static const Color warm = Color(0xFFC67B4D);
  static const Color warmLight = Color(0xFFFFF0E7);

  /// 背景：参考设置页的淡蓝灰底
  static const Color bgBase = Color(0xFFEAF2FB);
  static const Color bgWarm = Color(0xFFF3F7FC);
  static const Color bgPaper = Color(0xFFEAF2FB);

  /// 卡片：轻微冷白
  static const Color card = Color(0xFFF9FCFF);
  static const Color cardSoft = Color(0xFFF6FAFE);

  /// 文字
  static const Color textPrimary = Color(0xFF151B24);
  static const Color textSecondary = Color(0xFF4D5A68);
  static const Color textTertiary = Color(0xFF8D99A8);

  /// 分隔线
  static const Color divider = Color(0xFF9C9C9C);
  static const Color dividerLight = Color(0xFFB8B8B8);

  /// 标签/芯片背景
  static const Color chipBg = Color(0xFFE3ECF5);

  /// 功能色
  static const Color success = Color(0xFF6FAE5C);
  static const Color warning = Color(0xFFE0A24F);
  static const Color error = Color(0xFFCB6F6F);
  static const Color info = Color(0xFF6B95B8);

  // ==================== 暗色色板 ====================

  static const Color darkAccent = Color(0xFFBDBDBD);
  static const Color darkAccentDark = Color(0xFFA8A8A8);
  static const Color darkAccentLight = Color(0xFF2B3138);
  static const Color darkAccentSoft = Color(0xFF1D232A);
  static const Color darkWarm = Color(0xFFE2A17C);
  static const Color darkWarmLight = Color(0xFF2C211C);
  static const Color darkBgBase = Color(0xFF020A11);
  static const Color darkBgWarm = Color(0xFF071018);
  static const Color darkBgPaper = Color(0xFF020A11);
  static const Color darkCard = Color(0xFF071018);
  static const Color darkCardSoft = Color(0xFF0A141D);
  static const Color darkTextPrimary = Color(0xFFEAF0F7);
  static const Color darkTextSecondary = Color(0xFFBBC6D2);
  static const Color darkTextTertiary = Color(0xFF687684);
  static const Color darkDivider = Color(0xFF1D2A36);
  static const Color darkDividerLight = Color(0xFF16232E);
  static const Color darkChipBg = Color(0xFF101B25);
  static const Color darkSuccess = Color(0xFF8BCB78);
  static const Color darkWarning = Color(0xFFE7B867);
  static const Color darkError = Color(0xFFE08484);
  static const Color darkInfo = Color(0xFF8AB7DD);

  // ==================== 阴影 ====================

  /// 卡片浮起阴影（双层：近阴影+远阴影）
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF17212B).withValues(alpha: 0.035),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF17212B).withValues(alpha: 0.035),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  /// 轻浮起（用于内嵌卡片）
  static List<BoxShadow> get cardShadowLight => [
    BoxShadow(
      color: const Color(0xFF17212B).withValues(alpha: 0.025),
      blurRadius: 1,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: const Color(0xFF17212B).withValues(alpha: 0.025),
      blurRadius: 6,
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

  // ==================== 主题数据 ====================

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamilyFallback: _sansFallback,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bgBase,
    colorScheme: const ColorScheme.light(
      primary: accent,
      onPrimary: textPrimary,
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
    // 卡片主题
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusL),
      ),
    ),
    // AppBar 主题
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
    // 列表瓦片主题
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusM),
      ),
    ),
    // 输入框主题
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: const BorderSide(color: divider, width: 1.5),
      ),
      hintStyle: const TextStyle(fontSize: 14, color: textTertiary),
    ),
    // 按钮主题
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: textPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
    // 文字按钮主题
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXS),
        ),
      ),
    ),
    // 芯片主题
    chipTheme: ChipThemeData(
      backgroundColor: chipBg,
      selectedColor: accentLight,
      labelStyle: const TextStyle(fontSize: 13, color: textSecondary),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXS),
      ),
    ),
    // TabBar 主题
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: accent,
      unselectedLabelColor: textTertiary,
      labelStyle: TextStyle(fontWeight: FontWeight.w600),
      indicatorSize: TabBarIndicatorSize.label,
    ),
    // 分割线主题
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 0.5,
      space: 1,
    ),
    // 文字主题：工具界面统一使用无衬线，提升扫描效率
    textTheme: TextTheme(
      displayLarge: _withSans(
        const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
          height: 1.2,
        ),
      ),
      headlineLarge: _withSans(
        const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
          height: 1.3,
        ),
      ),
      headlineMedium: _withSans(
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.2,
          height: 1.3,
        ),
      ),
      headlineSmall: _withSans(
        const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.1,
          height: 1.3,
        ),
      ),
      titleLarge: _withSans(
        const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.2,
        ),
      ),
      titleMedium: _withSans(
        const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.2,
        ),
      ),
      titleSmall: _withSans(
        const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.3,
        ),
      ),
      bodyLarge: _withSans(
        const TextStyle(fontSize: 16, color: textSecondary, height: 1.5),
      ),
      bodyMedium: _withSans(
        const TextStyle(fontSize: 14, color: textSecondary, height: 1.5),
      ),
      bodySmall: _withSans(
        const TextStyle(fontSize: 12, color: textTertiary, letterSpacing: 0.2),
      ),
      labelLarge: _withSans(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    fontFamilyFallback: _sansFallback,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBgBase,
    colorScheme: const ColorScheme.dark(
      primary: darkAccent,
      onPrimary: Color(0xFF151B24),
      secondary: darkWarm,
      onSecondary: Color(0xFF2C1808),
      surface: darkCard,
      onSurface: darkTextPrimary,
      surfaceContainerHighest: darkBgWarm,
      outline: darkDivider,
      outlineVariant: darkDividerLight,
      error: darkError,
    ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusS),
        borderSide: const BorderSide(color: darkDivider, width: 1.5),
      ),
      hintStyle: const TextStyle(fontSize: 14, color: darkTextTertiary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkAccent,
        foregroundColor: const Color(0xFF151B24),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    textTheme: TextTheme(
      displayLarge: _withSans(
        const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
          height: 1.2,
        ),
      ),
      headlineLarge: _withSans(
        const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
          height: 1.3,
        ),
      ),
      headlineMedium: _withSans(
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
          height: 1.3,
        ),
      ),
      headlineSmall: _withSans(
        const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          height: 1.3,
        ),
      ),
      titleLarge: _withSans(
        const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
      ),
      titleMedium: _withSans(
        const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
      ),
      titleSmall: _withSans(
        const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
      ),
      bodyLarge: _withSans(
        const TextStyle(fontSize: 16, color: darkTextSecondary, height: 1.5),
      ),
      bodyMedium: _withSans(
        const TextStyle(fontSize: 14, color: darkTextSecondary, height: 1.5),
      ),
      bodySmall: _withSans(
        const TextStyle(fontSize: 12, color: darkTextTertiary),
      ),
      labelLarge: _withSans(
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: darkTextSecondary,
        ),
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
}

/// 高质感白卡（有内部高光 + 柔和投影）
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

/// 应用背景
///
/// 用法：
/// - 作为整页背景：`PaperBackground(child: ...)` 直接包裹
/// - 作为独立底层：`Positioned.fill(child: PaperBackground(child: SizedBox.shrink()))`
///   这样在 Stack 中它只绘制渐变+噪点，不影响上层布局
class PaperBackground extends StatelessWidget {
  final Widget child;

  const PaperBackground({super.key, this.child = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) {
    final colors = context.isDarkMode
        ? const [Color(0xFF020A11), Color(0xFF020A11), Color(0xFF071018)]
        : const [Color(0xFFEAF2FB), Color(0xFFEAF2FB), Color(0xFFE3EDF7)];
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // 内容（仅在作为 widget 使用时）
        if (child is! SizedBox) child,
      ],
    );
  }
}
