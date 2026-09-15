import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';

import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/gis_sync.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/shared_gis.dart';
import '../../services/location_status.dart';
import '../../widgets/common.dart';
import '../../widgets/gis_sync_banner.dart';

class StationsListScreen extends ConsumerStatefulWidget {
  const StationsListScreen({super.key});

  @override
  ConsumerState<StationsListScreen> createState() => _StationsListScreenState();
}

class _StationsListScreenState extends ConsumerState<StationsListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final stations = ref.watch(stationsStreamProvider).value ?? const <GISStation>[];
    final position = ref.watch(currentPositionProvider).value;

    final filtered = stations
        .where((s) =>
            _query.isEmpty ||
            s.cameraId.toLowerCase().contains(_query.toLowerCase()) ||
            (s.zone.toLowerCase().contains(_query.toLowerCase())))
        .toList();

    double? distanceKm(GISStation s) {
      if (position == null) return null;
      return Geolocator.distanceBetween(position.latitude, position.longitude, s.latitude, s.longitude) / 1000.0;
    }

    filtered.sort((a, b) {
      final da = distanceKm(a);
      final db = distanceKm(b);
      if (da == null || db == null) return a.cameraId.compareTo(b.cameraId);
      return da.compareTo(db);
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('stations.title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
              child: Row(
                children: [
                  GisSyncBanner(l10n: l10n, stationCount: stations.length),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: l10n.t('stations.search'),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(gisSyncServiceProvider).refresh(),
                child: filtered.isEmpty
                  ? ListView(
                      children: [
                        EmptyState(message: l10n.t('stations.empty'), icon: Icons.videocam_off_outlined),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxxl),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (context, i) {
                        final s = filtered[i];
                        final dist = distanceKm(s);
                        return PressableScale(
                          onTap: () => context.push('/stations/${s.cameraId}'),
                          child: Bezel(
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: stationStatusColor(s.operationalStatus).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Icon(Icons.videocam_rounded, color: stationStatusColor(s.operationalStatus)),
                                ),
                                const SizedBox(width: AppSpace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.cameraId, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(
                                        '${s.zone}${s.habitat != null ? ' · ${s.habitat}' : ''}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (s.uptimeRatio != null) ...[
                                            const Icon(Icons.battery_full_rounded, size: 14, color: AppColors.muted),
                                            const SizedBox(width: 2),
                                            Text('${(s.uptimeRatio! * 100).round()}%', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                          ],
                                          if (dist != null) ...[
                                            const SizedBox(width: AppSpace.sm),
                                            const Icon(Icons.near_me_outlined, size: 14, color: AppColors.muted),
                                            const SizedBox(width: 2),
                                            Text('${dist.toStringAsFixed(1)} ${l10n.t('common.km')}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(
                                  label: l10n.t(stationStatusLabelKey(s.operationalStatus)),
                                  color: stationStatusColor(s.operationalStatus),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
