import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/local_store.dart';
import 'core/supabase_config.dart';
import 'data/gis_sync.dart';
import 'data/mock_seed.dart';
import 'data/repository.dart';
import 'data/supabase_mapping.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final localStore = LocalStore(prefs);

  // Build the real ProviderContainer up front (rather than letting
  // ProviderScope create one implicitly) so first-run seeding can happen
  // *before* the first frame — Home should never flash an empty state on
  // a fresh install.
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localStoreProvider.overrideWithValue(localStore),
    ],
  );

  await seedMockDataIfNeeded(container);

  // Optional real backend: only attempted when the user has saved a
  // project URL + anon key in Settings. Failures here (bad URL typo, no
  // network on first launch, etc.) must never crash startup — the app is
  // fully usable local-only either way.
  final supabaseConfig = SupabaseConfig(localStore);
  if (supabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: supabaseConfig.url!,
        anonKey: supabaseConfig.anonKey!,
      );
      supabaseReady = true;

      // Seed the ranger/team roster into Supabase exactly once, and do it
      // *before* the sync queue worker (started when syncQueueServiceProvider
      // is first read below via seedMockDataIfNeeded / UI) can attempt to
      // push a patrol/observation whose ranger_id/team_id foreign key
      // wouldn't exist yet.
      final alreadySeeded =
          localStore.getBool(SupabaseConfig.seededFlagKey, defaultValue: false);
      if (!alreadySeeded) {
        await _seedRosterToSupabase(container);
        await localStore.setBool(SupabaseConfig.seededFlagKey, true);
      }
    } catch (e, st) {
      supabaseReady = false;
      developer.log('Supabase.initialize failed — continuing local-only',
          name: 'main', error: e, stackTrace: st);
    }
  }

  // Fire-and-forget: pull real camera-station/GIS data from the shared
  // backend right away so the Map/Stations screens upgrade from seeded
  // demo stations to the live reserve dataset as soon as it lands. Never
  // blocks first frame — local-first means the seeded/cached data is
  // already there to show in the meantime.
  unawaited(container.read(gisSyncServiceProvider).refresh());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TygrisRangerApp(),
    ),
  );
}

/// Upserts every locally-seeded [Ranger]/[Team] into Supabase. Best-effort:
/// any failure is logged and swallowed so a flaky first connection never
/// blocks app startup — later patrol/observation syncs would fail on the FK
/// constraint and surface as retryable "failed" items in the sync queue
/// instead, which is an acceptable degraded path.
Future<void> _seedRosterToSupabase(ProviderContainer container) async {
  try {
    final client = Supabase.instance.client;
    final rangers = container.read(rangerRepositoryProvider).getAllSync();
    final teams = container.read(teamRepositoryProvider).getAllSync();

    if (teams.isNotEmpty) {
      await client.from('teams').upsert(teams.map(teamToSupabaseRow).toList());
    }
    if (rangers.isNotEmpty) {
      await client
          .from('rangers')
          .upsert(rangers.map(rangerToSupabaseRow).toList());
    }
    for (final team in teams) {
      final memberRows = teamMembersToSupabaseRows(team);
      if (memberRows.isNotEmpty) {
        await client.from('team_members').upsert(memberRows);
      }
    }
  } catch (e, st) {
    developer.log('Supabase roster seed failed', name: 'main', error: e, stackTrace: st);
  }
}
