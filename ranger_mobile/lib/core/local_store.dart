import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin persistence primitive wrapping `shared_preferences`.
///
/// *** This is the single seam every repository in `lib/data/repository.dart`
/// writes through. *** When the real backend (Supabase) is wired up, this
/// class is the only thing that needs to be replaced/augmented (e.g. with a
/// SQLite-backed offline cache plus a Supabase realtime client) — no screen
/// or repository consumer needs to change, because they only ever talk to
/// the repository interfaces, never to [LocalStore] directly outside of
/// `lib/data`.
///
/// Data is stored as JSON strings under a "box" key, mirroring a tiny
/// document-store shape: each box holds a `List<Map<String, dynamic>>`.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  List<Map<String, dynamic>> getJsonList(String box) {
    final raw = _prefs.getString(_boxKey(box));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> setJsonList(String box, List<Map<String, dynamic>> items) {
    return _prefs.setString(_boxKey(box), jsonEncode(items));
  }

  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(_singleKey(key));
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) {
    return _prefs.setString(_singleKey(key), jsonEncode(value));
  }

  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(_singleKey(key)) ?? defaultValue;

  Future<void> setBool(String key, bool value) =>
      _prefs.setBool(_singleKey(key), value);

  String? getString(String key) => _prefs.getString(_singleKey(key));

  Future<void> setString(String key, String value) =>
      _prefs.setString(_singleKey(key), value);

  Future<void> clearBox(String box) => _prefs.remove(_boxKey(box));

  String _boxKey(String box) => 'ranger_box_$box';
  String _singleKey(String key) => 'ranger_kv_$key';
}
