import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TYGRIS Field design bible — "Field Journal" aesthetic.
///
/// Ported near-verbatim from `tygris_mobile/lib/core/theme.dart` so the
/// Ranger app matches the visual language of the rest of the TYGRIS family
/// (Admin web app + the analyst/monitoring Flutter app). A handful of
/// ranger-specific semantic colors (sos/offline/syncing/synced) are added
/// at the bottom — additions only, nothing here has been removed or
/// renamed relative to the source of truth.
///
/// Vibe archetype: Editorial Luxury, tuned for a naturalist's field journal
/// crossed with a premium outdoor brand — warm paper, deep canopy green,
/// ochre/rust accents pulled from the reserve's own soil and dry-season
/// grass. Fraunces (a "wonky", high-contrast serif with real character) for
/// display type; Work Sans for UI/body — warmer and more humanist than
/// Inter/Roboto while staying legible at small sizes for data readouts.
class AppColors {
  AppColors._();

  static const background = Color(0xFFF7F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFEFEBE0);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF1F2420);
  static const muted = Color(0xFF6B7268);
  static const mutedStrong = Color(0xFF4B534C);
  static const border = Color(0xFFE2DFD6);
  static const borderStrong = Color(0xFFCBC6B7);
  static const hairline = Color(0xFFDFDACE);

  static const nav = Color(0xFFFFFFFF);
  static const navForeground = Color(0xFF1F2420);
  static const navMuted = Color(0xFF6B7268);
  static const navActive = Color(0xFF2F5233);
  static const navActiveBg = Color(0xFFE7EDE3);
  static const navActiveBorder = Color(0xFFB9CBB4);
  static const navBorder = Color(0xFFCBC6B7);

  static const accent = Color(0xFF2F5233);
  static const accentStrong = Color(0xFF1D3319);
  static const accentDeep = Color(0xFF14240F);
  static const accentSoft = Color(0x1A2F5233);
  static const accentForeground = Color(0xFFFFFFFF);

  /// Secondary editorial accent — sun-baked ochre, used sparingly for
  /// eyebrow tags and single highlight moments, never alongside accent
  /// green in the same component.
  static const ochre = Color(0xFFB0793A);
  static const ochreSoft = Color(0x1FB0793A);

  static const positive = Color(0xFF2F5233);
  static const positiveSoft = Color(0x1A2F5233);
  static const caution = Color(0xFF9C6B1E);
  static const cautionSoft = Color(0x1F9C6B1E);
  static const danger = Color(0xFFA23B2C);
  static const dangerSoft = Color(0x1AA23B2C);

  static const priorityHigh = Color(0xFFA23B2C);
  static const priorityMedium = Color(0xFF9C6B1E);
  static const priorityLow = Color(0xFF2F5233);

  /// Warm-tinted shadow (never pure black) — carries the paper hue so
  /// elevation reads as soft depth rather than a generic drop shadow.
  static const shadowTint = Color(0x1F2B2A20);
  static const shadowTintStrong = Color(0x332B2A20);
  static const highlight = Color(0xB3FFFFFF);

  // --- Ranger-specific additions (not present in tygris_mobile) ---

  /// Emergency / SOS red — deliberately more saturated than [danger] so the
  /// SOS control is unmistakable at a glance and never confused with a
  /// routine "high severity" observation chip.
  static const sos = Color(0xFFD32F2F);
  static const sosSoft = Color(0x1FD32F2F);

  /// Sync-status semantics used on status chips throughout the app.
  static const offline = Color(0xFF8A8F87);
  static const offlineSoft = Color(0x1F8A8F87);
  static const syncing = Color(0xFFB0793A);
  static const syncingSoft = Color(0x1FB0793A);
  static const synced = Color(0xFF2F5233);
  static const syncedSoft = Color(0x1A2F5233);
  static const syncFailed = Color(0xFFA23B2C);
  static const syncFailedSoft = Color(0x1AA23B2C);

  // --- Reserve map additions (boundary zones / offline vector basemap) ---

  /// Buffer-zone fill/border — light yellow-green, matching the reference
  /// reserve map's outer ring.
  static const zoneBufferBase = Color(0xFF8FAF5C);
  static const zoneBufferFill = Color(0x668FAF5C);
  static const zoneBufferBorder = Color(0xFF6C8A3F);

  /// Core-zone fill/border — deeper canopy green, drawn on top of the
  /// buffer polygon so the two read as concentric zones like the paper map.
  static const zoneCoreBase = Color(0xFF3D6B32);
  static const zoneCoreFill = Color(0x803D6B32);
  static const zoneCoreBorder = Color(0xFF1D3319);

  /// Tiger-territory outline — reuses the ochre editorial accent so it
  /// never fights the green zone fills underneath it.
  static const territoryOutline = ochre;

  /// Flat backdrop shown instead of live OSM tiles when the device has no
  /// network, so boundary polygons/labels/markers render on a clean
  /// vector-only canvas rather than blank/broken tile squares.
  static const mapOfflineBase = Color(0xFFF1ECDD);
}

/// Spacing scale — macro-whitespace bias. Screens should default to the
/// larger end of this scale for section gaps; xs/sm are for internal
/// component padding only.
class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Corner radius scale — concentric double-bezel logic. An outer shell at
/// [bezelOuter] wrapping an inner core at [bezelInner] (outer minus the
/// bezel gap) always reads as genuinely concentric rather than eyeballed.
class AppRadius {
  AppRadius._();
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;

  static const bezelGap = 6.0;
  static const bezelOuter = 26.0;
  static double get bezelInner => bezelOuter - bezelGap;
}

/// Motion tokens — spring-first. Durations are fallbacks for the rare
/// widget that can't take a physics simulation (e.g. implicit
/// AnimatedContainer).
class AppMotionDuration {
  AppMotionDuration._();
  static const quick = Duration(milliseconds: 220);
  static const standard = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 600);
}

class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(TextTheme base) {
    final display = GoogleFonts.frauncesTextTheme(base);
    final body = GoogleFonts.workSansTextTheme(base);
    return body.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.05,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.08,
      ),
      displaySmall: display.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.1,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: body.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: body.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: body.bodyMedium?.copyWith(height: 1.5),
      labelLarge: body.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }

  static ThemeData light() {
    final rawTextTheme = ThemeData.light().textTheme;
    final textTheme = _textTheme(rawTextTheme).apply(
      bodyColor: AppColors.foreground,
      displayColor: AppColors.foreground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        primary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      fontFamily: GoogleFonts.workSans().fontFamily,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.nav,
        foregroundColor: AppColors.navForeground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.foreground,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.nav,
        indicatorColor: AppColors.navActiveBg,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.workSans(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.navActive : AppColors.navMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.navActive : AppColors.navMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentForeground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.workSans(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.foreground,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

/// Semantic status color helper mirroring the web app's alert levels.
Color statusColor(String level) {
  switch (level.toLowerCase()) {
    case 'critical':
    case 'high':
      return AppColors.priorityHigh;
    case 'caution':
    case 'medium':
      return AppColors.priorityMedium;
    default:
      return AppColors.priorityLow;
  }
}
