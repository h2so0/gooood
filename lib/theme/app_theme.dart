import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme mode provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Minimal color palette: background + text + 1 accent for price drop
class AppColors {
  // Dark theme
  static const darkBg = Color(0xFF000000);
  static const darkSurface = Color(0xFF0A0A0A);
  static const darkCard = Color(0xFF111111);
  static const darkNav = Color(0xFF1A1A1A);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFAAAAAA);
  static const darkTextTertiary = Color(0xFF666666);
  static const darkBorder = Color(0xFF222222);
  static const darkNavBorder = Color(0xFF333333);

  // Light theme
  static const lightBg = Color(0xFFF2F2F7);
  static const lightSurface = Color(0xFFE5E5EA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightNav = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF000000);
  static const lightTextSecondary = Color(0xFF555555);
  static const lightTextTertiary = Color(0xFFAAAAAA);
  static const lightBorder = Color(0xFFE0E0E0);
  static const lightNavBorder = Color(0xFFD0D0D0);

  // Semantic
  static const drop = Color(0xFFE04040);   // price drop percentage
  static const badge = Color(0xFF888888);  // badge/tag inside content
  static const rankUp = Color(0xFFFF5252);   // 순위 상승 / NEW
  static const rankDown = Color(0xFF448AFF); // 순위 하락
  static const star = Color(0xFFFFB800);     // 별점
}

class TteolgaTheme {
  final Color bg;
  final Color surface;
  final Color card;
  final Color nav;
  final Color navBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color drop;
  final Color badge;
  final Color rankUp;
  final Color rankDown;
  final Color star;
  final Brightness brightness;

  const TteolgaTheme({
    required this.bg,
    required this.surface,
    required this.card,
    required this.nav,
    required this.navBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.drop,
    required this.badge,
    required this.rankUp,
    required this.rankDown,
    required this.star,
    required this.brightness,
  });

  static const dark = TteolgaTheme(
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    card: AppColors.darkCard,
    nav: AppColors.darkNav,
    navBorder: AppColors.darkNavBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    border: AppColors.darkBorder,
    drop: AppColors.drop,
    badge: AppColors.badge,
    rankUp: AppColors.rankUp,
    rankDown: AppColors.rankDown,
    star: AppColors.star,
    brightness: Brightness.dark,
  );

  static const light = TteolgaTheme(
    bg: AppColors.lightBg,
    surface: AppColors.lightSurface,
    card: AppColors.lightCard,
    nav: AppColors.lightNav,
    navBorder: AppColors.lightNavBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    border: AppColors.lightBorder,
    drop: AppColors.drop,
    badge: AppColors.badge,
    rankUp: AppColors.rankUp,
    rankDown: AppColors.rankDown,
    star: AppColors.star,
    brightness: Brightness.light,
  );

  ThemeData toThemeData() {
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: brightness == Brightness.dark
          ? ColorScheme.dark(primary: drop, surface: surface)
          : ColorScheme.light(primary: drop, surface: surface),
      fontFamily: 'Pretendard',
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
    );
  }
}

/// Access current theme colors from anywhere via ref
final tteolgaThemeProvider = Provider<TteolgaTheme>((ref) {
  final mode = ref.watch(themeModeProvider);
  return mode == ThemeMode.light ? TteolgaTheme.light : TteolgaTheme.dark;
});
