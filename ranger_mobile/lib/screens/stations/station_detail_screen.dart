import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_shell.dart';
import '../../core/map_focus.dart';
import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart';

class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({super.key, required this.cameraId});
  final String cameraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appLocalizationsProvider);
    final stations = ref.watch(stationsStreamProvider).value ?? const [];
    final station = stations.where((s) => s.cameraId == cameraId).toList();
    final inspections = (ref.watch(cameraInspectionsStreamProvider).value ?? const [])
        .where((i) => i.stationCameraId == cameraId)
        .toList()
      ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));

    if (station.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(cameraId)),
        body: Center(child: Text(l10n.t('common.unknown'))),
      );
    }
    final s = station.first;

    return Scaffold(
      appBar: AppBar(title: Text(s.cameraId)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            Row(
              children: [
                Flexible(
                  child: StatusPill(
                    label: l10n.t(stationStatusLabelKey(s.operationalStatus)),
                    color: stationStatusColor(s.operationalStatus),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(mapFocusStationIdProvider.notifier).state = s.cameraId;
                      ref.read(bottomNavIndexProvider.notifier).state = 1;
                      context.go('/');
                    },
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: Text(
                      l10n.t('stations.navigate'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            Bezel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(context, l10n.t('stations.zone'), s.zone),
                  if (s.habitat != null) _infoRow(context, l10n.t('stations.habitat'), s.habitat!),
                  if (s.trailType != null) _infoRow(context, l10n.t('stations.trail'), s.trailType!),
                  if (s.uptimeRatio != null)
                    _infoRow(context, l10n.t('stations.uptime'), '${(s.uptimeRatio! * 100).round()}%'),
                  if (s.nearestWaterKm != null)
                    _infoRow(context, l10n.t('stations.nearestWater'), '${s.nearestWaterKm!.toStringAsFixed(1)} ${l10n.t('common.km')}'),
                  if (s.nearestVillageKm != null)
                    _infoRow(context, l10n.t('stations.nearestVillage'), '${s.nearestVillageKm!.toStringAsFixed(1)} ${l10n.t('common.km')}'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('stations.title')),
            const SizedBox(height: AppSpace.sm),
            _ActionButton(
              icon: Icons.report_problem_outlined,
              label: l10n.t('stations.reportIssue'),
              onTap: () => context.push('/stations/${s.cameraId}/inspect', extra: {'reason': 'issue'}),
            ),
            const SizedBox(height: AppSpace.sm),
            _ActionButton(
              icon: Icons.swap_horiz_rounded,
              label: l10n.t('stations.replaceCollect'),
              onTap: () => context.push('/stations/${s.cameraId}/inspect', extra: {'reason': 'replace'}),
            ),
            const SizedBox(height: AppSpace.sm),
            _ActionButton(
              icon: Icons.edit_note_rounded,
              label: l10n.t('stations.addNote'),
              onTap: () => context.push('/stations/${s.cameraId}/inspect', extra: {'reason': 'note'}),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('stations.lastInspection')),
            const SizedBox(height: AppSpace.sm),
            if (inspections.isEmpty)
              Text(l10n.t('stations.noInspections'), style: const TextStyle(color: AppColors.muted))
            else
              for (final insp in inspections.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Bezel(
                    child: Row(
                      children: [
                        Icon(Icons.build_outlined, color: inspectionStatusColor(insp.status)),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.t(inspectionActionLabelKey(insp.actionTaken)),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                DateFormat('MMM d, yyyy · HH:mm').format(insp.timestamp),
                                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        SyncStatusChip(status: insp.syncStatus, l10n: l10n),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
    );
  }
}
