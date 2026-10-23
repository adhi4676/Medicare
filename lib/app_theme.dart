import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemePreset {
  const AppThemePreset({
    required this.name,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.secondary,
  });

  final String name;
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color secondary;
}

class AppTheme {
  static const String _themePrefKey = 'medicare_theme_mode';
  static const String _presetPrefKey = 'medicare_theme_preset';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const List<AppThemePreset> presets = [
    AppThemePreset(
      name: 'Medical Blue',
      primary: Color(0xFF1E88E5),
      primaryDark: Color(0xFF1565C0),
      primaryLight: Color(0xFF64B5F6),
      secondary: Color(0xFF00897B),
    ),
    AppThemePreset(
      name: 'Emerald Teal',
      primary: Color(0xFF00897B),
      primaryDark: Color(0xFF00695C),
      primaryLight: Color(0xFF4DB6AC),
      secondary: Color(0xFF1E88E5),
    ),
    AppThemePreset(
      name: 'Royal Purple',
      primary: Color(0xFF7B1FA2),
      primaryDark: Color(0xFF4A148C),
      primaryLight: Color(0xFFBA68C8),
      secondary: Color(0xFF00897B),
    ),
    AppThemePreset(
      name: 'Coral Sunset',
      primary: Color(0xFFE65100),
      primaryDark: Color(0xFFBF360C),
      primaryLight: Color(0xFFFF8A65),
      secondary: Color(0xFF00897B),
    ),
    AppThemePreset(
      name: 'Forest Green',
      primary: Color(0xFF2E7D32),
      primaryDark: Color(0xFF1B5E20),
      primaryLight: Color(0xFF81C784),
      secondary: Color(0xFF00897B),
    ),
  ];

  /// Global reactive notifier for switching between Light, Dark, and System mode.
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Global reactive notifier for the selected color theme preset name.
  static final ValueNotifier<String> themePresetNotifier =
      ValueNotifier<String>('Medical Blue');

  static AppThemePreset get currentPreset {
    return presets.firstWhere(
      (p) => p.name == themePresetNotifier.value,
      orElse: () => presets.first,
    );
  }

  /// Load saved theme mode and color preset preferences on startup.
  static Future<void> initThemeMode() async {
    try {
      final rawMode = await _storage.read(key: _themePrefKey);
      if (rawMode == 'dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else if (rawMode == 'system') {
        themeModeNotifier.value = ThemeMode.system;
      } else {
        themeModeNotifier.value = ThemeMode.light;
      }

      final rawPreset = await _storage.read(key: _presetPrefKey);
      if (rawPreset != null && presets.any((p) => p.name == rawPreset)) {
        themePresetNotifier.value = rawPreset;
      }
    } catch (_) {
      // Fallback to defaults if secure storage is unavailable in tests.
    }
  }

  /// Toggle between Light and Dark theme and persist the preference.
  static Future<void> toggleTheme() async {
    final nextMode = themeModeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setThemeMode(nextMode);
  }

  /// Explicitly set dark mode on or off.
  static Future<void> setDarkMode(bool enabled) async {
    await setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  /// Explicitly set ThemeMode (light, dark, or system).
  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final str = mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.system
              ? 'system'
              : 'light';
      await _storage.write(key: _themePrefKey, value: str);
    } catch (_) {}
  }

  /// Set the active color theme preset by name.
  static Future<void> setThemePreset(String presetName) async {
    if (!presets.any((p) => p.name == presetName)) return;
    themePresetNotifier.value = presetName;
    try {
      await _storage.write(key: _presetPrefKey, value: presetName);
    } catch (_) {}
  }

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // Brand & semantic color tokens (Light defaults + dynamic preset getters)
  static const Color primary = Color(0xFF1E88E5);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color secondary = Color(0xFF00897B);
  static const Color accentPurple = Color(0xFF8E24AA);
  static const Color accentOrange = Color(0xFFF57C00);
  static const Color accentGreen = Color(0xFF43A047);
  static const Color background = Color(0xFFF4F8FD);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color borderSubtle = Color(0xFFE2E8F0);

  // Dark theme palette tokens
  static const Color darkBackground = Color(0xFF0B1120);
  static const Color darkSurface = Color(0xFF151F32);
  static const Color darkSurfaceElevated = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorderSubtle = Color(0xFF283548);

  /// Context-aware price / highlight color based on active theme preset & brightness.
  static Color priceColor(BuildContext context) {
    final preset = currentPreset;
    return isDark(context) ? preset.primaryLight : preset.primaryDark;
  }

  /// Smooth fade + upward slide route transition used across all screens.
  static Route<T> route<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(curved);

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
    );
  }

  static ThemeData get light {
    final preset = currentPreset;
    final activePrimary = preset.primary;
    final activePrimaryDark = preset.primaryDark;
    final activeSecondary = preset.secondary;

    final scheme = ColorScheme.fromSeed(
      seedColor: activePrimary,
      primary: activePrimary,
      secondary: activeSecondary,
      surface: surface,
      brightness: Brightness.light,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: borderSubtle, width: 1.2),
    );

    const baseTextTheme = TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textSecondary,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: baseTextTheme,
      dividerColor: borderSubtle,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: activePrimary, width: 1.8),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: activePrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: activePrimary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: borderSubtle, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: activePrimaryDark,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: activePrimary.withValues(alpha: 0.12),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: activePrimary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: activePrimary),
        unselectedIconTheme: const IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: activePrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }

  static ThemeData get dark {
    final preset = currentPreset;
    final activePrimary = preset.primary;
    final activePrimaryLight = preset.primaryLight;
    final activeSecondary = preset.secondary;

    final scheme = ColorScheme.fromSeed(
      seedColor: activePrimary,
      primary: activePrimary,
      secondary: activeSecondary,
      surface: darkSurface,
      brightness: Brightness.dark,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: darkBorderSubtle, width: 1.2),
    );

    const baseTextTheme = TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: darkTextPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: darkTextPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: darkTextSecondary,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      textTheme: baseTextTheme,
      dividerColor: darkBorderSubtle,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkBorderSubtle),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: darkBorderSubtle),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: darkTextSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
        prefixIconColor: darkTextSecondary,
        suffixIconColor: darkTextSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: activePrimaryLight, width: 1.8),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: activePrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: activePrimaryLight,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: darkBorderSubtle, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: activePrimaryLight,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkSurfaceElevated,
        contentTextStyle: const TextStyle(color: darkTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: activePrimary.withValues(alpha: 0.22),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        indicatorColor: activePrimary.withValues(alpha: 0.22),
        selectedIconTheme: IconThemeData(color: activePrimaryLight),
        unselectedIconTheme: const IconThemeData(color: darkTextSecondary),
        selectedLabelTextStyle: TextStyle(
          color: activePrimaryLight,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: darkTextSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Animated button that toggles between Light and Dark mode with a smooth icon transition.
class ThemeModeToggleButton extends StatelessWidget {
  const ThemeModeToggleButton({super.key, this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        final icon = AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => RotationTransition(
            turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            key: ValueKey<bool>(isDark),
            size: 20,
            color: isDark
                ? Colors.amber.shade300
                : AppTheme.currentPreset.primaryDark,
          ),
        );

        if (showLabel) {
          return ActionChip(
            avatar: icon,
            label: Text(isDark ? 'Light Mode' : 'Dark Mode'),
            onPressed: AppTheme.toggleTheme,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        }

        return IconButton(
          tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          onPressed: AppTheme.toggleTheme,
          icon: icon,
        );
      },
    );
  }
}

/// Interactive card that elevates, scales, and glows on hover (web) or tap (mobile).
class HoverScaleCard extends StatefulWidget {
  const HoverScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.accentColor = AppTheme.primary,
    this.borderRadius = 18,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color accentColor;
  final double borderRadius;

  @override
  State<HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<HoverScaleCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardSurface = isDark ? AppTheme.darkSurface : AppTheme.surface;
    final cardBorder =
        isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle;

    final scale = _pressed
        ? 0.975
        : _hovered
            ? 1.02
            : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withValues(alpha: 0.55)
                  : cardBorder,
              width: _hovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? widget.accentColor.withValues(alpha: isDark ? 0.22 : 0.14)
                    : Colors.black.withValues(alpha: isDark ? 0.20 : 0.03),
                blurRadius: _hovered ? 20 : 8,
                offset: Offset(0, _hovered ? 8 : 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              onTap: widget.onTap,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Smooth entrance fade + upward slide animation for sections and list items.
class StaggeredFadeSlide extends StatelessWidget {
  const StaggeredFadeSlide({
    super.key,
    required this.child,
    this.index = 0,
  });

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final durationMs = 320 + (index.clamp(0, 8) * 65);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Responsive wrapper used across authentication and utility screens so that
/// forms look balanced on both mobile handsets and wide web viewports.
class ResponsiveAuthShell extends StatelessWidget {
  const ResponsiveAuthShell({
    super.key,
    required this.child,
    this.showBackButton = false,
    this.title,
  });

  final Widget child;
  final bool showBackButton;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor =
        isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle;
    final activePrimary = Theme.of(context).colorScheme.primary;

    final animatedChild = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, content) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 20),
            child: content,
          ),
        );
      },
      child: child,
    );

    return Scaffold(
      appBar: showBackButton
          ? AppBar(
              title: title != null ? Text(title!) : null,
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: ThemeModeToggleButton(showLabel: true),
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          // Subtle ambient background glow orbs
          Positioned(
            top: -90,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activePrimary.withValues(alpha: isDark ? 0.12 : 0.07),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      AppTheme.secondary.withValues(alpha: isDark ? 0.12 : 0.07),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWideWeb = constraints.maxWidth >= 900;

                if (isWideWeb) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Card(
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.16),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                            side: BorderSide(color: borderColor),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _WebBrandBanner(),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    color: surfaceColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 48,
                                      vertical: 44,
                                    ),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 420),
                                        child: animatedChild,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // Mobile & Tablet layout
                final isTablet = constraints.maxWidth >= 520;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 32 : 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: isTablet
                          ? Card(
                              elevation: 2,
                              shadowColor:
                                  Colors.black.withValues(alpha: 0.12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(color: borderColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: animatedChild,
                              ),
                            )
                          : animatedChild,
                    ),
                  ),
                );
              },
            ),
          ),
          if (!showBackButton)
            const Positioned(
              top: 12,
              right: 16,
              child: SafeArea(
                child: ThemeModeToggleButton(showLabel: true),
              ),
            ),
        ],
      ),
    );
  }
}

class _WebBrandBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preset = AppTheme.currentPreset;
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [preset.primary, preset.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'MediCare',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'SMART PHARMACY & HEALTH CARE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your trusted digital pharmacy & medicine companion.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Search genuine medicines, upload prescriptions, track orders, and never miss a dose with smart reminders.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              const _BannerFeatureRow(
                icon: Icons.verified_user_outlined,
                text: '100% genuine medicines & verified pharmacies',
              ),
              const SizedBox(height: 12),
              const _BannerFeatureRow(
                icon: Icons.notifications_active_outlined,
                text: 'Smart dosage & refill reminders',
              ),
              const SizedBox(height: 12),
              const _BannerFeatureRow(
                icon: Icons.fingerprint,
                text: 'Secure biometric & Firebase authentication',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '© 2026 MediCare Health Systems',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerFeatureRow extends StatelessWidget {
  const _BannerFeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
