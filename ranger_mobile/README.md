# Tygris Ranger

Field-ranger companion app for the TYGRIS wildlife-management system (Pench
Tiger Reserve). A brand-new, standalone Flutter app — package `ranger_mobile`,
application id `com.tygris.ranger` — built **local-first**: there is no real
backend wired up yet. Everything a ranger does (patrols, observations,
camera-station inspections, task completions, SOS) is written to on-device
storage immediately and simulated through a sync queue, ready for a real
Supabase backend to be dropped in later without touching UI code.

## Running it

This was hand-authored in an environment without the Flutter CLI, so it has
never been `pub get`'d or analyzed by `flutter analyze`. From a machine with
Flutter installed:

```
flutter pub get
flutter run
```

If Android/iOS build tooling complains about a missing `local.properties`
(Android) or code-signing (iOS), that's normal first-run scaffolding —
`flutter run` regenerates what it needs.

## Architecture

### Local-first seam

- `lib/core/local_store.dart` — the only thing that talks to
  `shared_preferences`. Every repository writes through it. **This is the
  seam to replace/extend when Supabase is wired up** (e.g. swap for a
  SQLite cache + Supabase realtime client) — nothing above this layer needs
  to change.
- `lib/data/repository.dart` — `LocalRepository<T>` generic + named
  per-entity providers (`PatrolRepository`, `ObservationRepository`,
  `CameraInspectionRepository`, `TaskRepository`, `PhotoRepository`,
  `RangerRepository`, `TeamRepository`, `StationRepository`). Each exposes a
  Riverpod `StreamProvider` so UI updates the instant a local write happens
  — the point of "local-first": the UI never waits on a network call.
- `lib/services/sync_queue_service.dart` — **simulation only**, clearly
  commented as such. A `Timer`-driven worker walks a queue of
  `SyncQueueItem`s through `pendingSync → syncing → synced` (90%) or
  `failed` (10%, retryable), flipping the underlying entity's own
  `syncStatus` field as it goes. No network call is ever made. Replacing
  this with real Supabase sync means rewriting `_processOne`-equivalent
  logic inside this file; the queue data model and every `enqueue()` call
  site elsewhere in the app stay the same.
- `lib/services/active_patrol_controller.dart` — owns the in-progress
  patrol: real GPS via `geolocator` when available, otherwise a random-walk
  simulated route (clearly commented) so the demo works without hardware
  GPS. Persists to `PatrolRepository` on every meaningful change.

### Shared GIS models

`lib/models/shared_gis.dart` ports `GISStation`, `GISMapBundle`, `Territory`,
`Sighting` field-for-field from `tygris_mobile/lib/models/models.dart` (itself
a 1:1 port of `frontend-v2/src/lib/api.ts`), so all three TYGRIS clients can
eventually read/write the same Supabase rows with zero translation. Do not
diverge this shape — every screen that touches camera stations consumes
`GISStation` from this file.

### Design language

`lib/core/theme.dart` ports `tygris_mobile`'s "Field Journal" theme
(Fraunces + Work Sans, warm paper background, forest-green accent) verbatim,
with additive ranger-only semantic colors: `sos`, `offline`, `syncing`,
`synced`, `syncFailed`.

### One entity, not two: Report == Observation

Rather than build a near-duplicate "Report" model, a stand-alone Quick
Report **is** an `Observation` with `patrolId == null` (see the design note
in `lib/models/observation.dart`). The History "Reports" tab is a filtered
view over the same Observation store, and both the mid-patrol quick-log
sheet and the stand-alone Quick Report screen open the exact same form
(`lib/screens/patrol/quick_log_form_screen.dart`).

### Localization

Hand-written runtime i18n (`lib/l10n/`) — deliberately not
`flutter gen-l10n`/ARB codegen, since this environment can't run a build
step. `app_strings_en.dart` / `_hi.dart` / `_mr.dart` are plain
`Map<String, String>` tables with identical key sets; `AppLocalizations.t()`
looks a key up with `{param}` interpolation and falls back to English, then
the raw key, if a translation is missing. `LocaleController`
(`StateNotifierProvider`) persists the chosen locale and switches the whole
app instantly — see Settings → Language / भाषा.

**To add a language:** copy `app_strings_en.dart` to `app_strings_xx.dart`,
translate every value (keep the keys identical), add it to `_tables` in
`app_localizations.dart`, add `xx` to `AppLocale`, and add one line to
Settings' language list.

### Navigation

`lib/app.dart` (go_router) + `lib/core/app_shell.dart` (5-tab bottom nav:
Home, Map, Tasks, Stations, History — tab selection is a Riverpod
`StateProvider`, not route-driven, so any screen can switch tabs
programmatically). Patrol, Quick Report, and SOS are reached from Home's
prominent actions rather than being separate tabs, keeping the primary
nav surface small for a field context. Full-screen flows (patrol setup /
active / review, quick-log form, station inspection form, task detail,
settings) are pushed on top via go_router routes.

## Known gaps / follow-ups

- **Never run through `flutter analyze` or a real device/emulator** — this
  was authored entirely by hand without a Dart toolchain in this
  environment. The code was manually re-read for brace/paren balance,
  import correctness, and cross-checked key-by-key against all three
  localization tables, but a full compiler pass has not happened. Run
  `flutter analyze` first after `pub get`.
- `permission_handler`, `camera`, `connectivity_plus`, and `path_provider`
  are declared in `pubspec.yaml` (per spec, mirroring `tygris_mobile`/future
  needs) but not directly imported yet — location permission currently
  goes through `geolocator`'s own permission calls, and photo capture goes
  through `image_picker`'s camera source rather than the raw `camera`
  plugin, which is simpler and sufficient for this demo.
- No app icons/launch images were generated (the copied Android/iOS
  scaffold references `@mipmap/ic_launcher` / storyboards that
  `flutter create`-style tooling normally fills in — regenerate with
  `flutter create .` over this project if needed, or supply your own).
- The Supabase section in Settings is intentionally inert (greyed-out
  fields) — wiring it up is future work, not part of this build.
- Android `local.properties` and the Gradle wrapper jar are not present
  (consistent with how `tygris_mobile`'s scaffold was copied from) —
  `flutter run`/`flutter build` regenerates these on first run.
