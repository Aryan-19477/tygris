import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  String? get url {
    final v = _store.getString(_urlKey);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  String? get anonKey {
    final v = _store.getString(_keyKey);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
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

/// Set to true in `main.dart` iff `Supabase.initialize` actually succeeded
/// for *this* running process. Code that is about to touch
/// `Supabase.instance.client` must check this, not just
/// [supabaseConfiguredProvider] (which only reflects saved settings and
/// could be stale/invalid, e.g. right after a typo'd save that hasn't been
/// restarted into yet, or an initialize() that threw).
bool supabaseReady = false;
