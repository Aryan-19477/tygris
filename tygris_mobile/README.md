# TYGRIS Field

Mobile companion app to the TYGRIS wildlife-monitoring platform (`backend/` FastAPI + `frontend-v2/` Next.js dashboard), for rangers in Pench Tiger Reserve.

## Setup

```
flutter pub get
```

## Pointing at the backend

The FastAPI backend serves on `http://127.0.0.1:8420` by default (see `frontend-v2/.env.local`). Mobile devices/emulators cannot use `127.0.0.1` to reach your dev machine:

- Android emulator: `http://10.0.2.2:8420` (default baked into the app)
- iOS simulator: `http://127.0.0.1:8420`
- Physical device on same WiFi: `http://<your-machine-LAN-IP>:8420`

Change the base URL from the **Settings** screen inside the app (More → Settings) — it persists across restarts.

## Run

```
flutter run
```

## Structure

- `lib/core/theme.dart` — colors/typography ported from frontend-v2's institutional field-report palette.
- `lib/core/api_client.dart`, `lib/core/repository.dart` — Dio client + repository matching `frontend-v2/src/lib/api.ts` 1:1.
- `lib/models/models.dart` — typed models for every backend response shape.
- `lib/screens/` — one file per feature, mirroring frontend-v2's views (Reserve Map, Identify, Attention Queue, Tiger Catalogue/Dossier, Station Health, Blank Frame Trash, Settings).
- `lib/core/app_shell.dart` — bottom nav (5 primary tabs) + overflow sheet for Trash/Settings.
