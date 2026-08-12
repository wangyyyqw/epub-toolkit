import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 应用主题配置 —「极简生产力工具」（Minimal Productivity）
///
/// 设计理念（参考 Linear / Notion / Figma 的桌面工作台风格）：
/// - 中性灰页面底色 + 纯白卡片，卡片以 1px 细分隔线区隔而非投影
/// - 主操作统一墨黑（高对比黑白），唯一强调色为靛蓝（聚焦边框、链接、进度高亮）
/// - 强调色靛蓝仅用于焦点/选中/进度，不喧宾夺主
/// - 组件形态采用 TDesign Flutter（腾讯设计体系），圆角收敛（6-10px），间距紧凑
/// - 拒绝高饱和渐变、粗投影、毛玻璃等强装饰
///
/// 注意：修改色板时保持 [AppThemeExt] 上的 getter 名称不变，所有页面依赖其稳定。

/// 启用 TDesign 多主题：组件按 context 读取注入的主题（品牌色）
void initTDesignTheme() => TDTheme.needMultiTheme();

/// TDesign 品牌色配置：亮色为墨黑、暗色为浅靛蓝，与全局配色一致
const String _tdThemeConfig = '''
{
  "epubGadget": {
    "color": {
      "brandNormalColor": "#18181B",
      "brandNormalColorLight": "#F0F0F2",
      "brandNormalColorFocused": "#F0F0F2",
      "brandNormalColorDisabled": "#F0F0F2",
      "textColorPrimary": "#18181B",
      "textColorSecondary": "#52525B",
      "textColorTertiary": "#A1A1AA",
      "bgColorPage": "#F7F7F8",
      "bgColorContainer": "#FFFFFF",
      "borderColor": "#E4E4E7",
      "dangerColor": "#DC2626"
    }
  },
  "epubGadgetDark": {
    "color": {
      "brandNormalColor": "#7C86EE",
      "brandNormalColorLight": "#272B45",
      "brandNormalColorFocused": "#272B45",
      "brandNormalColorDisabled": "#2A2A2E",
      "textColorPrimary": "#EDEDEF",
      "textColorSecondary": "#A6A6AC",
      "textColorTertiary": "#70707A",
      "bgColorPage": "#161618",
      "bgColorContainer": "#1E1E21",
      "borderColor": "#2E2E33",
      "dangerColor": "#F87171"
    }
  }
}
''';

TDThemeData? _cachedTdTheme;

/// 解析后的 TDesign 主题数据（含亮/暗两套）
TDThemeData get _tdTheme =>
    _cachedTdTheme ??= TDThemeData.fromJson('epubGadget', _tdThemeConfig)!;

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
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'Source Han Sans CN',
  'Microsoft YaHei',
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

  /// 主色：墨黑（主按钮、激活态、图标，高对比黑白）
  static const Color accent = Color(0xFF18181B);
  static const Color accentDark = Color(0xFF000000);
  static const Color accentLight = Color(0xFFF0F0F2);
  static const Color accentSoft = Color(0xFFF6F6F7);

  /// 强调色：靛蓝（唯一彩色，仅用于聚焦、选中、链接、进度高亮）
  static const Color warm = Color(0xFF5661D6);
  static const Color warmLight = Color(0xFFEDEFFB);

  /// 背景：中性浅灰（生产力工具底色）
  static const Color bgBase = Color(0xFFF7F7F8);
  static const Color bgWarm = Color(0xFFEFEFF1);
  static const Color bgPaper = Color(0xFFF7F7F8);

  /// 卡片：纯白 + 细分隔线
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFFAFAFB);

  /// 文字
  static const Color textPrimary = Color(0xFF18181B);
  static const Color textSecondary = Color(0xFF52525B);
  static const Color textTertiary = Color(0xFFA1A1AA);

  /// 分隔线
  static const Color divider = Color(0xFFE4E4E7);
  static const Color dividerLight = Color(0xFFECECEF);

  /// 标签/芯片背景
  static const Color chipBg = Color(0xFFF4F4F5);

  /// 功能色（克制低调）
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // ==================== 暗色色板 ====================

  /// 主色：亮墨（暗色下主按钮反转为浅色）
  static const Color darkAccent = Color(0xFFF4F4F5);
  static const Color darkAccentDark = Color(0xFFE4E4E7);
  static const Color darkAccentLight = Color(0xFF2A2A2E);
  static const Color darkAccentSoft = Color(0xFF242428);
  static const Color darkWarm = Color(0xFF7C86EE);
  static const Color darkWarmLight = Color(0xFF252A44);
  static const Color darkBgBase = Color(0xFF161618);
  static const Color darkBgWarm = Color(0xFF1C1C1F);
  static const Color darkBgPaper = Color(0xFF161618);
  static const Color darkCard = Color(0xFF1E1E21);
  static const Color darkCardSoft = Color(0xFF232327);
  static const Color darkTextPrimary = Color(0xFFEDEDEF);
  static const Color darkTextSecondary = Color(0xFFA6A6AC);
  static const Color darkTextTertiary = Color(0xFF70707A);
  static const Color darkDivider = Color(0xFF2E2E33);
  static const Color darkDividerLight = Color(0xFF26262B);
  static const Color darkChipBg = Color(0xFF26262B);
  static const Color darkSuccess = Color(0xFF4ADE80);
  static const Color darkWarning = Color(0xFFFBBF24);
  static const Color darkError = Color(0xFFF87171);
  static const Color darkInfo = Color(0xFF818CF8);

  // ==================== 阴影 ====================

  /// 极轻投影（生产力风格：以描边为主，投影仅作浮起提示）
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.035),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// 轻浮起（用于内嵌卡片）
  static List<BoxShadow> get cardShadowLight => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.025),
          blurRadius: 1.5,
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

  /// 生产力风格圆角：输入 8、卡片 10、浮层 14
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

  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durBase = Duration(milliseconds: 180);
  static const Duration durSlow = Duration(milliseconds: 260);

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
          onSecondary: Colors.white,
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
            borderRadius: BorderRadius.circular(radiusM),
            side: const BorderSide(color: dividerLight, width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: textPrimary,
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.1,
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            // 强焦点边框：靛蓝 1.5px
            borderSide: const BorderSide(color: warm, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: error, width: 1.5),
          ),
          hintStyle: const TextStyle(fontSize: 13, color: textTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: warm,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXS),
            ),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: chipBg,
          selectedColor: warmLight,
          labelStyle: const TextStyle(fontSize: 12.5, color: textSecondary),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXS),
            side: const BorderSide(color: dividerLight, width: 1),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          dividerColor: Colors.transparent,
          labelColor: warm,
          unselectedLabelColor: textTertiary,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          indicatorSize: TabBarIndicatorSize.label,
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 0.5,
          space: 1,
        ),
        // 精致开关：靛蓝选中轨道 + 白色圆钮，无描边
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
        // 精致滑块：细轨道 + 圆钮，进度高亮用靛蓝
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
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.4,
            height: 1.25,
          ),
          headlineLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: -0.1,
            height: 1.3,
          ),
          titleLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.1,
          ),
          titleMedium: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: textPrimary,
            letterSpacing: 0.1,
          ),
          titleSmall: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: textPrimary,
            letterSpacing: 0.2,
          ),
          bodyLarge: TextStyle(
              fontSize: 15, color: textSecondary, height: 1.5),
          bodyMedium: TextStyle(
              fontSize: 13.5, color: textSecondary, height: 1.5),
          bodySmall: TextStyle(
              fontSize: 12, color: textTertiary, letterSpacing: 0.1),
          labelLarge: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: textSecondary,
            letterSpacing: 0.1,
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
          onPrimary: Color(0xFF141416),
          secondary: darkWarm,
          onSecondary: Color(0xFF141416),
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
            borderRadius: BorderRadius.circular(radiusM),
            side: const BorderSide(color: darkDividerLight, width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: darkTextPrimary,
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.1,
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkCard,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            borderSide: const BorderSide(color: darkWarm, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkError, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusS),
            borderSide: const BorderSide(color: darkError, width: 1.5),
          ),
          hintStyle: const TextStyle(fontSize: 13, color: darkTextTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkAccent,
            foregroundColor: const Color(0xFF141416),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusS),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: darkWarm,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXS),
            ),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: darkChipBg,
          selectedColor: darkWarmLight,
          labelStyle: const TextStyle(fontSize: 12.5, color: darkTextSecondary),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXS),
            side: const BorderSide(color: darkDividerLight, width: 1),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          dividerColor: Colors.transparent,
          labelColor: darkWarm,
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
                ? const Color(0xFF141416)
                : const Color(0xFF70707A),
          ),
          overlayColor: WidgetStatePropertyAll(
            darkWarm.withValues(alpha: 0.12),
          ),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: darkWarm,
          inactiveTrackColor: darkDivider,
          thumbColor: const Color(0xFFEDEDEF),
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
            color: Color(0xFF141416),
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.4,
            height: 1.25,
          ),
          headlineLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          headlineSmall: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: -0.1,
            height: 1.3,
          ),
          titleLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.1,
          ),
          titleMedium: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: darkTextPrimary,
            letterSpacing: 0.1,
          ),
          titleSmall: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
            letterSpacing: 0.2,
          ),
          bodyLarge: TextStyle(
              fontSize: 15, color: darkTextSecondary, height: 1.5),
          bodyMedium: TextStyle(
              fontSize: 13.5, color: darkTextSecondary, height: 1.5),
          bodySmall: TextStyle(
              fontSize: 12, color: darkTextTertiary, letterSpacing: 0.1),
          labelLarge: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: darkTextSecondary,
            letterSpacing: 0.1,
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

  /// 强调色背景上使用的文字/图标前景色（亮色黑底白字，暗色浅底深字）
  Color get themeAccentFg => isDarkMode ? const Color(0xFF141416) : Colors.white;
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

/// 高质感白卡（细分隔线描边 + 极轻投影）
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
      borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusM),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusM),
        splashColor: Colors.black.withValues(alpha: 0.03),
        highlightColor: Colors.black.withValues(alpha: 0.02),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? context.themeCard,
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppTheme.radiusM),
            boxShadow: context.themeCardShadow,
            border: Border.all(
              color: selected
                  ? context.themeWarm.withValues(alpha: 0.6)
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

/// 应用背景 — 中性浅灰（亮色）/ 深墨灰（暗色），不做渐变
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
