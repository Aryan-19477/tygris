import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/gis_sync.dart';
import '../l10n/app_localizations.dart';

/// Small pill showing whether camera-station/GIS data on screen came from
/// the real backend just now, is cached from an earlier sync, or a sync is
/// in flight/failed — tap to retry. Shared by the Map and Stations list
/// screens so both report the same live/cached state the same way.
class GisSyncBanner extends ConsumerWidget {
  const GisSyncBanner({super.key, required this.l10n, this.stationCount});

  final AppLocalizations l10n;
  final int? stationCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(gisSyncStateProvider).value;
    final status = sync?.status ?? GisSyncStatus.idle;
    late final Color color;
    late final IconData icon;
    late final String label;
    switch (status) {
      case GisSyncStatus.loading:
        color = AppColors.syncing;
        icon = Icons.sync_rounded;
        label = l10n.t('gis.syncing');
        break;
      case GisSyncStatus.loaded:
        color = AppColors.synced;
        icon = Icons.cloud_done_rounded;
        label = sync?.lastSyncedAt != null
            ? l10n.t('gis.lastSynced', {'time': _fmtAgo(sync!.lastSyncedAt!)})
            : l10n.t('gis.live');
        break;
      case GisSyncStatus.error:
        color = AppColors.syncFailed;
        icon = Icons.cloud_off_rounded;
        label = sync?.lastSyncedAt != null ? l10n.t('gis.cached') : l10n.t('gis.error');
        break;
      case GisSyncStatus.idle:
        color = AppColors.muted;
        icon = Icons.cloud_outlined;
        label = l10n.t('gis.neverSynced');
        break;
    }

    return GestureDetector(
      onTap: () => ref.read(gisSyncServiceProvider).refresh(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            status == GisSyncStatus.loading
                ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            if (stationCount != null && stationCount! > 0) ...[
              const SizedBox(width: 6),
              Text('· ${l10n.t('gis.stationsCount', {'count': '$stationCount'})}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.refresh_rounded, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  static String _fmtAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
