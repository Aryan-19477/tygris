import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';
import '../data/repository.dart';

/// Reads/writes the (optional) Supabase project URL + anon key.
///
/// This is deliberately separate from [LocalStore]'s generic get/set so
/// every call site that cares about "are we configured for real sync"
/// goes through one place. Saving here does NOT re-initialize the live
/// Supabase client mid-session (the SDK has no clean story for that) — see
/// `lib/screens/settings_screen.dart`, which asks the user to restart the
/// app after saving. `lib/main.dart` is the only place that reads these
/// values to actually call `Supabase.initialize`.
class SupabaseConfig {
  static const _urlKey = 'supabase_url_v1';
  static const _keyKey = 'supabase_anon_key_v1';

  /// Flag flipped once after the first successful `Supabase.initialize` +
  /// ranger/team seed upsert, so that seed step only ever runs once.
  static const seededFlagKey = 'supabase_seeded_v1';

  const SupabaseConfig(this._store);

  final LocalStore _store;

  static const defaultUrl = 'https://dggkktyblzezhqavndqc.supabase.co';
  static const defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRnZ2trdHlibHplemhxYXZuZHFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0MDczODIsImV4cCI6MjEwNDk4MzM4Mn0.--axOs4M68WsbWmorJPBvS3HfWblTni1K2EFbYZm7yI';

  String? get url {
    final v = _store.getString(_urlKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return defaultUrl;
  }

  String? get anonKey {
    final v = _store.getString(_keyKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return defaultAnonKey;
  }

  bool get isConfigured => url != null && anonKey != null;

  Future<void> save({required String url, required String anonKey}) async {
    await _store.setString(_urlKey, url.trim());
    await _store.setString(_keyKey, anonKey.trim());
  }

  Future<void> clear() async {
    await _store.setString(_urlKey, '');
    await _store.setString(_keyKey, '');
    // Allow re-seeding ranger/team rows if the user reconnects later
    // (possibly to a different project).
    await _store.setBool(seededFlagKey, false);
  }
}

final supabaseConfigProvider = Provider<SupabaseConfig>((ref) {
  final store = ref.watch(localStoreProvider);
  return SupabaseConfig(store);
});

/// True when both a URL and anon key are saved. Note this reflects what is
/// *saved*, not necessarily what the live client was initialized with this
/// session (a value changed after startup only takes effect on restart —
/// see [SupabaseConfig] doc comment).
final supabaseConfiguredProvider = Provider<bool>((ref) {
  return ref.watch(supabaseConfigProvider).isConfigured;
});

/// Set to true in `main.dart` or `ensureSupabaseInitialized` iff
/// `Supabase.initialize` actually succeeded for *this* running process.
bool supabaseReady = false;

/// Initializes Supabase dynamically mid-session if not already initialized.
Future<bool> ensureSupabaseInitialized({String? url, String? anonKey}) async {
  if (supabaseReady) return true;
  final effectiveUrl = (url?.trim().isNotEmpty == true) ? url!.trim() : SupabaseConfig.defaultUrl;
  final effectiveKey = (anonKey?.trim().isNotEmpty == true) ? anonKey!.trim() : SupabaseConfig.defaultAnonKey;

  try {
    await Supabase.initialize(
      url: effectiveUrl,
      anonKey: effectiveKey,
    );
    supabaseReady = true;
    return true;
  } catch (e) {
    try {
      final _ = Supabase.instance.client;
      supabaseReady = true;
      return true;
    } catch (_) {}
    return false;
  }
}

