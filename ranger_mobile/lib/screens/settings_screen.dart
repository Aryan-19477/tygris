import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase_config.dart';
import '../core/theme.dart';
import '../data/gis_sync.dart';
import '../data/repository.dart';
import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../widgets/common.dart';
import '../widgets/gis_sync_banner.dart';
import '../services/sync_queue_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _backendUrlController =
      TextEditingController(text: ApiClient.instance.baseUrl);
  late final TextEditingController _supabaseUrlController;
  late final TextEditingController _supabaseKeyController;
  String? _supabaseSavedNote;

  @override
  void initState() {
    super.initState();
    final config = ref.read(supabaseConfigProvider);
    _supabaseUrlController = TextEditingController(text: config.url ?? '');
    _supabaseKeyController = TextEditingController(text: config.anonKey ?? '');
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final locale = ref.watch(localeControllerProvider);
    final ranger = ref.watch(currentRangerProvider);
    final syncState = ref.watch(syncQueueStateProvider).value;
    final service = ref.read(syncQueueServiceProvider);
    final gisSync = ref.watch(gisSyncStateProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('settings.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            SectionLabel(l10n.t('settings.profile')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.accentSoft,
                    child: Text(
                      (ranger != null && ranger.name.isNotEmpty) ? ranger.name.substring(0, 1) : '?',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ranger?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${l10n.t('settings.badge')}: ${ranger?.badgeId ?? '—'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('settings.language')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final loc in AppLocale.values)
                    RadioListTile<AppLocale>(
                      value: loc,
                      groupValue: locale,
                      onChanged: (v) {
                        if (v != null) ref.read(localeControllerProvider.notifier).setLocale(v);
                      },
                      title: Text(l10n.t(loc.displayNameKey)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('settings.connectivity')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: syncState?.online ?? service.isOnline,
                    onChanged: (v) => service.setOnline(v),
                    title: Text((syncState?.online ?? service.isOnline) ? l10n.t('settings.online') : l10n.t('settings.forceOffline')),
                    subtitle: Text(l10n.t('settings.forceOfflineHint'), style: const TextStyle(fontSize: 11)),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Text(l10n.t('settings.syncQueueSummary'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (syncState != null) ...[
                        StatusPill(label: l10n.t('sync.pendingCount', {'count': '${syncState.pendingCount}'}), color: AppColors.syncing),
                        if (syncState.failedCount > 0) ...[
                          const SizedBox(width: AppSpace.xs),
                          StatusPill(label: l10n.t('sync.failedCount', {'count': '${syncState.failedCount}'}), color: AppColors.syncFailed),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => service.setOnline(true),
                      child: Text(l10n.t('settings.syncNow')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('settings.backendData')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.centerLeft, child: GisSyncBanner(l10n: l10n)),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: _backendUrlController,
                    decoration: InputDecoration(
                      labelText: l10n.t('settings.backendUrl'),
                      helperText: l10n.t('settings.backendUrlHint'),
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: AppSpace.md),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        final url = _backendUrlController.text.trim();
                        if (url.isEmpty) return;
                        ApiClient.instance.configureBaseUrl(url);
                        ref.read(gisSyncServiceProvider).refresh();
                      },
                      child: Text(l10n.t('settings.backendSave')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('settings.supabase')),
            const SizedBox(height: AppSpace.sm),
            Builder(builder: (context) {
              final config = ref.watch(supabaseConfigProvider);
              final connected = config.isConfigured;
              return Bezel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (connected)
                      Row(
                        children: [
                          const Icon(Icons.cloud_done_rounded, color: AppColors.synced, size: 18),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text(
                              l10n.t('settings.supabaseConnected', {'url': config.url ?? ''}),
                              style: const TextStyle(color: AppColors.synced, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(l10n.t('settings.supabaseNote'),
                          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _supabaseUrlController,
                      decoration: InputDecoration(labelText: l10n.t('settings.supabaseUrl')),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      controller: _supabaseKeyController,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.t('settings.supabaseKey')),
                    ),
                    if (_supabaseSavedNote != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(_supabaseSavedNote!,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                    const SizedBox(height: AppSpace.md),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: connected
                          ? OutlinedButton(
                              onPressed: () async {
                                await ref.read(supabaseConfigProvider).clear();
                                setState(() {
                                  _supabaseUrlController.clear();
                                  _supabaseKeyController.clear();
                                  _supabaseSavedNote = l10n.t('settings.supabaseRestartNote');
                                });
                              },
                              child: Text(l10n.t('settings.supabaseDisconnect')),
                            )
                          : FilledButton(
                              onPressed: () async {
                                final url = _supabaseUrlController.text.trim();
                                final key = _supabaseKeyController.text.trim();
                                if (url.isEmpty || key.isEmpty) return;
                                await ref.read(supabaseConfigProvider).save(url: url, anonKey: key);
                                setState(() {
                                  _supabaseSavedNote = l10n.t('settings.supabaseRestartNote');
                                });
                              },
                              child: Text(l10n.t('settings.supabaseConnect')),
                            ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('settings.appInfo')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Row(
                children: [
                  Text(l10n.t('settings.version'), style: const TextStyle(color: AppColors.muted)),
                  const Spacer(),
                  const Text('1.0.0'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
