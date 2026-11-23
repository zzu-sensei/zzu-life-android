import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/native_api.dart';

/// Material Design 3 × Miuix (HyperOS) 语义色板扩展。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.card,
    required this.cardSubtle,
    required this.border,
    required this.divider,
    required this.primary,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.navBackground,
  });

  final Color canvas;
  final Color card;
  final Color cardSubtle;
  final Color border;
  final Color divider;
  final Color primary;
  final Color primarySoft;
  final Color onPrimarySoft;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color navBackground;

  static const AppPalette light = AppPalette(
    canvas: Color(0xFFF6F7F9),
    card: Color(0xFFFFFFFF),
    cardSubtle: Color(0xFFEFF2F7),
    border: Color(0xFFE6EAF0),
    divider: Color(0xFFECEFF4),
    primary: Color(0xFF3482FF),
    primarySoft: Color(0xFFEBF3FF),
    onPrimarySoft: Color(0xFF1557C0),
    ink: Color(0xFF14181F),
    inkSecondary: Color(0xFF5C6675),
    inkMuted: Color(0xFF8C95A6),
    success: Color(0xFF16A36A),
    successSoft: Color(0xFFE8F7F0),
    warning: Color(0xFFE08200),
    warningSoft: Color(0xFFFFF4E5),
    danger: Color(0xFFE5484D),
    dangerSoft: Color(0xFFFFECEC),
    info: Color(0xFF0EA5E9),
    infoSoft: Color(0xFFE8F6FE),
    navBackground: Color(0xFAFFFFFF),
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF000000),
    card: Color(0xFF16181D),
    cardSubtle: Color(0xFF22262E),
    border: Color(0xFF272B33),
    divider: Color(0xFF232730),
    primary: Color(0xFF4D96FF),
    primarySoft: Color(0xFF172A45),
    onPrimarySoft: Color(0xFF9AC5FF),
    ink: Color(0xFFF3F5F8),
    inkSecondary: Color(0xFFA0A9B8),
    inkMuted: Color(0xFF6F7888),
    success: Color(0xFF3DD68C),
    successSoft: Color(0xFF123025),
    warning: Color(0xFFFFB74D),
    warningSoft: Color(0xFF332612),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0xFF36191C),
    info: Color(0xFF38BDF8),
    infoSoft: Color(0xFF122B3B),
    navBackground: Color(0xFA121418),
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? card,
    Color? cardSubtle,
    Color? border,
    Color? divider,
    Color? primary,
    Color? primarySoft,
    Color? onPrimarySoft,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? navBackground,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      cardSubtle: cardSubtle ?? this.cardSubtle,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimarySoft: onPrimarySoft ?? this.onPrimarySoft,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      navBackground: navBackground ?? this.navBackground,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardSubtle: Color.lerp(cardSubtle, other.cardSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      onPrimarySoft: Color.lerp(onPrimarySoft, other.onPrimarySoft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// HyperOS 连续曲率圆角（Squircle）。
///
/// Flutter 的 [ContinuousRectangleBorder] 在视觉上比普通圆角略收紧，
/// 因此将传入的基准圆角乘以 1.9 以匹配 Miuix 设计比例。
OutlinedBorder miuixShape(double radius, {BorderSide side = BorderSide.none}) {
  return ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(radius * 1.9),
    side: side,
  );
}

/// 构造浅色或深色 M3 × Miuix 主题。
ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? AppPalette.dark : AppPalette.light;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3482FF),
    brightness: brightness,
  );

  final colorScheme = baseScheme.copyWith(
    primary: palette.primary,
    onPrimary: Colors.white,
    primaryContainer: palette.primarySoft,
    onPrimaryContainer: palette.onPrimarySoft,
    secondary: palette.info,
    secondaryContainer: palette.infoSoft,
    surface: palette.card,
    onSurface: palette.ink,
    onSurfaceVariant: palette.inkSecondary,
    surfaceContainerLowest: palette.card,
    surfaceContainerLow: palette.card,
    surfaceContainer: palette.cardSubtle,
    surfaceContainerHigh: palette.cardSubtle,
    surfaceContainerHighest: palette.cardSubtle,
    outline: palette.border,
    outlineVariant: palette.divider,
    error: palette.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.canvas,
    extensions: [palette],
    dividerColor: palette.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: palette.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: miuixShape(20, side: BorderSide(color: palette.border)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: miuixShape(24, side: BorderSide(color: palette.border)),
      titleTextStyle: TextStyle(
        color: palette.ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: palette.inkSecondary,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: ContinuousRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(52)),
        side: BorderSide(color: palette.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.cardSubtle,
      hintStyle: TextStyle(color: palette.inkMuted, fontSize: 14),
      labelStyle: TextStyle(color: palette.inkSecondary, fontSize: 13),
      prefixIconColor: palette.inkSecondary,
      suffixIconColor: palette.inkSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border.withValues(alpha: 0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.danger, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: miuixShape(16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.border),
        backgroundColor: palette.card,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: miuixShape(15),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        shape: miuixShape(12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.ink,
        shape: miuixShape(14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.card,
      selectedColor: palette.primarySoft,
      labelStyle: TextStyle(
        color: palette.inkSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: palette.onPrimarySoft,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: palette.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return isDark ? const Color(0xFFB0B8C5) : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return palette.primary;
        return isDark ? const Color(0xFF323742) : const Color(0xFFD5DCE6);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.primary,
      inactiveTrackColor: palette.cardSubtle,
      thumbColor: palette.primary,
      overlayColor: palette.primary.withValues(alpha: 0.14),
      valueIndicatorColor: palette.primary,
      valueIndicatorTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      trackHeight: 5,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: palette.navBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: palette.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? palette.primary : palette.inkMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? palette.primary : palette.inkMuted,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF252932) : const Color(0xFF1F242D),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.primary,
      linearTrackColor: palette.cardSubtle,
    ),
  );
}

/// 依据当前有效亮度生成系统状态栏 / 导航栏样式。
SystemUiOverlayStyle systemOverlayStyleFor(
  Brightness brightness,
  AppPalette palette,
) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: palette.navBackground,
    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarDividerColor: palette.border,
  );
}

/// 应用主题模式控制器，持久化到 Android SharedPreferences。
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  Future<void> load() async {
    try {
      final result = await NativeApi.call('getThemeMode');
      final raw = (result['mode'] ?? 'system').toString();
      value = _parseMode(raw);
    } catch (_) {
      // 读取失败保持默认跟随系统，不影响启动。
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      await NativeApi.call('saveThemeMode', {'mode': _encodeMode(mode)});
    } catch (_) {
      // 持久化失败不影响当前界面切换。
    }
  }

  static ThemeMode _parseMode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encodeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
