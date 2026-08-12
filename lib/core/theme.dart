import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 应用主题配置 —「新中式极简」（Neo-Chinese Minimalism）
///
/// 设计理念：
/// - 冷调浅灰蓝页面底色，文人书房般的冷静氛围
/// - 纯白圆角卡片（12px）浮于背景，极轻投影
/// - 唯一强调色：柔粉蓝 #A8C5D8，仅用于等级徽章、进度高亮
/// - 语义色：暗红仅用于破坏性操作
/// - 组件形态采用 TDesign Flutter（腾讯设计体系）
/// - 拒绝高饱和、渐变、粗投影、毛玻璃等强装饰

/// 启用 TDesign 多主题：组件按 context 读取注入的主题（品牌色）
void initTDesignTheme() => TDTheme.needMultiTheme();

/// TDesign 品牌色配置：亮色为墨色、暗色为柔粉蓝，与全局配色一致
const String _tdThemeConfig = '''
{
  "epubGadget": {
    "color": {
      "brandNormalColor": "#1A1A1A",
      "brandNormalColorLight": "#F0F3F6",
      "brandNormalColorFocused": "#F0F3F6",
      "brandNormalColorDisabled": "#EFEFEF",
      "textColorPrimary": "#1A1A1A",
      "textColorSecondary": "#646464",
      "textColorTertiary": "#8E8E8E",
      "bgColorPage": "#E8ECF0",
      "bgColorContainer": "#FFFFFF",
      "borderColor": "#E5E5E5",
      "dangerColor": "#B33A3A"
    }
  },
  "epubGadgetDark": {
    "color": {
      "brandNormalColor": "#A8C5D8",
      "brandNormalColorLight": "#232A33",
      "brandNormalColorFocused": "#232A33",
      "brandNormalColorDisabled": "#2C333B",
      "textColorPrimary": "#E8E8E8",
      "textColorSecondary": "#A0A8B0",
      "textColorTertiary": "#6E7680",
      "bgColorPage": "#171A1E",
      "bgColorContainer": "#1F242A",
      "borderColor": "#2C333B",
      "dangerColor": "#D97A7A"
    }
  }
}
''';

TDThemeData? _cachedTdTheme;

/// 解析后的 TDesign 主题数据（含亮/暗两套）
TDThemeData get _tdTheme =>
    _cachedTdTheme ??= TDThemeData.fromJson('epubGadget', _tdThemeConfig)!;

/// UI 无衬线字体回退链（工具界面用）
const List<String> _sansFallback = [
  'PingFang SC',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'Source Han Sans CN',
  'Microsoft YaHei',
  'Heiti SC',
  'sans-serif',
];

class AppTheme {
  AppTheme._();

  // ==================== 亮色色板 ====================

  /// 主色：墨色（主按钮、激活态、图标，中性近黑）
  static const Color accent = Color(0xFF1A1A1A);
  static const Color accentDark = Color(0xFF000000);
  static const Color accentLight = Color(0xFFE9EEF4);
  static const Color accentSoft = Color(0xFFF4F7FA);

  /// 强调色：柔粉蓝（唯一彩色，仅用于等级徽章、进度高亮）
  static const Color warm = Color(0xFFA8C5D8);
  static const Color warmLight = Color(0xFFEAF0F5);

  /// 背景：冷调浅灰蓝
  static const Color bgBase = Color(0xFFE8ECF0);
  static const Color bgWarm = Color(0xFFE1E6EB);
  static const Color bgPaper = Color(0xFFE8ECF0);

  /// 卡片：纯白
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFFAFBFC);

  /// 文字
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF646464);
  static const Color textTertiary = Color(0xFF8E8E8E);

  /// 分隔线
  static const Color divider = Color(0xFFE5E5E5);
  static const Color dividerLight = Color(0xFFEFEFEF);

  /// 标签/芯片背景
  static const Color chipBg = Color(0xFFF2F4F7);

  /// 功能色（克制低调）
  static const Color success = Color(0xFF5C7A8C);
  static const Color warning = Color(0xFFB08D4E);
  static const Color error = Color(0xFFB33A3A);
  static const Color info = Color(0xFF8CA5B8);

  // ==================== 暗色色板 ====================

  static const Color darkAccent = Color(0xFFA8C5D8);
  static const Color darkAccentDark = Color(0xFF8FAFCC);
  static const Color darkAccentLight = Color(0xFF232A33);
  static const Color darkAccentSoft = Color(0xFF1B2128);
  static const Color darkWarm = Color(0xFF9DBAD0);
  static const Color darkWarmLight = Color(0xFF22303C);
  static const Color darkBgBase = Color(0xFF171A1E);
  static const Color darkBgWarm = Color(0xFF1C2126);
  static const Color darkBgPaper = Color(0xFF171A1E);
  static const Color darkCard = Color(0xFF1F242A);
  static const Color darkCardSoft = Color(0xFF262C33);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFFA0A8B0);
  static const Color darkTextTertiary = Color(0xFF6E7680);
  static const Color darkDivider = Color(0xFF2C333B);
  static const Color darkDividerLight = Color(0xFF262D34);
  static const Color darkChipBg = Color(0xFF232830);
  static const Color darkSuccess = Color(0xFF9DB8C9);
  static const Color darkWarning = Color(0xFFC9A86A);
  static const Color darkError = Color(0xFFD97A7A);
  static const Color darkInfo = Color(0xFF8FAFCC);

  // ==================== 阴影 ====================

  /// 极轻投影（0 1px 3px rgba(0,0,0,0.04)）
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.04),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  /// 轻浮起（用于内嵌卡片）
  static List<BoxShadow> get cardShadowLight => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.03),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// 强调阴影（极少使用）
  static List<BoxShadow> glow(Color color, {double alpha = 0.08}) => [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  // ==================== 圆角 ====================

  static const double radiusXL = 14;
  static const double radiusL = 12;
  static const double radiusM = 10;
  static const double radiusS = 8;
  static const double radiusXS = 6;
  static const double radiusFull = 999;

  // ==================== 间距 ====================

  static const double spaceXL = 24;
  static const double spaceL = 20;
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
        extensions: [_tdTheme.light],
        colorScheme: const ColorScheme.light(
          primary: accent,
          onPrimary: Colors.white,
          secondary: warm,
          onSecondary: Color(0xFF2A3B47),
          surface: card,
          onSurface: textPrimary,
          surfaceContainerHighest: bgWarm,
          outline: divider,
          outlineVariant: dividerLight,
          error: error,
        ),
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
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: divider, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: divider, width: 1),
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
          hintStyle: const TextStyle(fontSize: 13.5, color: textTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
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
          selectedColor: warmLight,
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
        // 精致开关：柔粉蓝选中轨道 + 白色圆钮，无描边
        switchTheme: SwitchThemeData(
          trackOutlineWidth: const WidgetStatePropertyAll(0.0),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? warm
                : chipBg,
          ),
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStatePropertyAll(
            warm.withValues(alpha: 0.10),
          ),
        ),
        // 精致滑块：细轨道 + 圆钮，进度高亮用柔粉蓝
        sliderTheme: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: warm,
          inactiveTrackColor: divider,
          thumbColor: Colors.white,
          overlayColor: warm.withValues(alpha: 0.12),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 6.5,
            elevation: 0.5,
          ),
          tickMarkShape: SliderTickMarkShape.noTickMark,
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          valueIndicatorColor: accent,
          valueIndicatorTextStyle: const TextStyle(
            fontSize: 11,
            color: Colors.white,
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
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
            fontWeight: FontWeight.w500,
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
        extensions: [_tdTheme.dark!],
        colorScheme: const ColorScheme.dark(
          primary: darkAccent,
          onPrimary: Color(0xFF101418),
          secondary: darkWarm,
          onSecondary: Color(0xFF101418),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkDivider, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkDivider, width: 1),
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
          hintStyle: const TextStyle(fontSize: 13.5, color: darkTextTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkAccent,
            foregroundColor: const Color(0xFF101418),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
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
          selectedColor: darkWarmLight,
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
        switchTheme: SwitchThemeData(
          trackOutlineWidth: const WidgetStatePropertyAll(0.0),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? darkWarm
                : darkChipBg,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFF101418)
                : const Color(0xFF6E7680),
          ),
          overlayColor: WidgetStatePropertyAll(
            darkWarm.withValues(alpha: 0.12),
          ),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: darkWarm,
          inactiveTrackColor: darkDivider,
          thumbColor: const Color(0xFFE8E8E8),
          overlayColor: darkWarm.withValues(alpha: 0.14),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 6.5,
            elevation: 0.5,
          ),
          tickMarkShape: SliderTickMarkShape.noTickMark,
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          valueIndicatorColor: darkAccent,
          valueIndicatorTextStyle: const TextStyle(
            fontSize: 11,
            color: Color(0xFF101418),
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
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
            fontWeight: FontWeight.w500,
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

/// 高质感白卡（极轻投影 + 弱描边）
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
        splashColor: Colors.black.withValues(alpha: 0.04),
        highlightColor: Colors.black.withValues(alpha: 0.03),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? context.themeCard,
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppTheme.radiusL),
            boxShadow: context.themeCardShadow,
            border: Border.all(
              color: selected
                  ? context.themeWarm.withValues(alpha: 0.55)
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

/// 应用背景 — 纯色浅灰蓝（亮色）/ 深墨灰（暗色），不做渐变
///
/// 用法：
/// - 作为整页背景：`PaperBackground(child: ...)` 直接包裹
/// - 作为独立底层：`Positioned.fill(child: PaperBackground(child: SizedBox.shrink()))`
///   这样在 Stack 中它只绘制底色，不影响上层布局
class PaperBackground extends StatelessWidget {
  final Widget child;

  const PaperBackground({super.key, this.child = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.themeBg,
      child: child is SizedBox ? null : SizedBox.expand(child: child),
    );
  }
}
