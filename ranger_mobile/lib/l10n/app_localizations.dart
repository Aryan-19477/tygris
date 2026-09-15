import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_strings_en.dart';
import 'app_strings_hi.dart';
import 'app_strings_mr.dart';

/// Hand-written runtime i18n — deliberately *not* `flutter gen-l10n` /
/// ARB-based codegen, since this environment can't run `flutter pub get`
/// or a build step to generate `.arb`-derived Dart. Instead every string
/// lives in a plain `Map<String, String>` per language (see
/// `app_strings_en.dart` etc.) and is looked up at runtime through
/// [AppLocalizations.t]. Adding a language later is: create
/// `app_strings_xx.dart` with the same keys, add it to [_tables], and add
/// one entry to [AppLocale.values] + the Settings language list.
enum AppLocale { en, hi, mr }

extension AppLocaleX on AppLocale {
  Locale get locale => Locale(name);

  String get displayNameKey {
    switch (this) {
      case AppLocale.en:
        return 'settings.languageEnglish';
      case AppLocale.hi:
        return 'settings.languageHindi';
      case AppLocale.mr:
        return 'settings.languageMarathi';
    }
  }

  static AppLocale fromCode(String? code) {
    return AppLocale.values.firstWhere(
      (v) => v.name == code,
      orElse: () => AppLocale.en,
    );
  }

  static AppLocale? fromDeviceLocale(Locale locale) {
    for (final v in AppLocale.values) {
      if (v.name == locale.languageCode) return v;
    }
    return null;
  }
}

const Map<AppLocale, Map<String, String>> _tables = {
  AppLocale.en: appStringsEn,
  AppLocale.hi: appStringsHi,
  AppLocale.mr: appStringsMr,
};

/// Holds the active locale's string table and resolves `t(key)` lookups
/// with graceful fallback: active locale -> English -> the raw key itself
/// (so a missing translation is visible/debuggable rather than crashing).
class AppLocalizations {
  AppLocalizations(this.appLocale);

  final AppLocale appLocale;

  Map<String, String> get _table => _tables[appLocale] ?? appStringsEn;

  String t(String key, [Map<String, String>? params]) {
    var value = _table[key] ?? appStringsEn[key] ?? key;
    if (params != null) {
      for (final entry in params.entries) {
        value = value.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return value;
  }
}

/// Persists the chosen locale to shared_preferences and defaults to the
/// device locale when supported, else English.
class LocaleController extends StateNotifier<AppLocale> {
  LocaleController(this._prefs) : super(_initial(_prefs));

  static const _prefKey = 'ranger_locale_v1';
  final SharedPreferences _prefs;

  static AppLocale _initial(SharedPreferences prefs) {
    final saved = prefs.getString(_prefKey);
    if (saved != null) return AppLocaleX.fromCode(saved);
    final deviceLocale = PlatformDispatcher.instance.locale;
    return AppLocaleX.fromDeviceLocale(deviceLocale) ?? AppLocale.en;
  }

  void setLocale(AppLocale locale) {
    state = locale;
    unawaited(_prefs.setString(_prefKey, locale.name));
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, AppLocale>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocaleController(prefs);
});

/// Overridden in `main.dart` once `SharedPreferences.getInstance()`
/// resolves (mirrors how `localStoreProvider` is wired).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final appLocalizationsProvider = Provider<AppLocalizations>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return AppLocalizations(locale);
});
