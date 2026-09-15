import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/observation_meta.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../models/observation.dart';
import 'common.dart';

/// Read-only detail sheet for an [Observation] (used for both mid-patrol
/// observations and stand-alone Quick Reports — see the design note in
/// `models/observation.dart`). Reused from Home's "recent activity" and
/// the History screen so there's a single report-detail view in the app.
void showObservationDetail(BuildContext context, Observation o, AppLocalizations l10n) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ObservationDetailSheet(observation: o, l10n: l10n),
  );
}

class _ObservationDetailSheet extends StatelessWidget {
  const _ObservationDetailSheet({required this.observation, required this.l10n});
  final Observation observation;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final o = observation;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpace.md),
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: severityColor(o.severity).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(observationTypeIcon(o.type), color: severityColor(o.severity)),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    o.title?.isNotEmpty == true ? o.title! : l10n.t(observationTypeLabelKey(o.type)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(
                  label: l10n.t(severityLabelKey(o.severity)),
                  color: severityColor(o.severity),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            if (o.description.isNotEmpty) ...[
              Text(o.description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpace.md),
            ],
            _row(context, Icons.access_time_rounded, DateFormat('MMM d, yyyy · HH:mm').format(o.timestamp)),
            _row(context, Icons.place_outlined,
                '${o.lat.toStringAsFixed(5)}, ${o.lng.toStringAsFixed(5)}'),
            _row(context, Icons.photo_camera_outlined,
                '${o.photoIds.length} ${l10n.t('common.photos').toLowerCase()}'),
            // Auto-attached spatial context, if this observation has it
            // (computed at capture time — see `core/geo_context.dart`;
            // older observations logged before this feature simply omit
            // these rows rather than showing fabricated values).
            if (o.rangeName != null)
              _row(context, Icons.map_outlined, '${l10n.t('obs.rangeLabel')}: ${o.rangeName}'),
            if (o.zoneName != null)
              _row(context, Icons.layers_outlined,
                  '${l10n.t('obs.zoneLabel')}: ${l10n.t(zoneLabelKey(o.zoneName!))}'),
            if (o.nearestStationId != null && o.nearestStationDistanceM != null)
              _row(
                context,
                Icons.videocam_outlined,
                '${l10n.t('obs.nearestStationLabel')}: ${o.nearestStationId} · '
                    '${_formatDistanceM(o.nearestStationDistanceM!)}',
              ),
            if (o.distanceFromRouteM != null)
              _row(context, Icons.route_outlined,
                  '${l10n.t('obs.distanceFromRouteLabel')}: ${_formatDistanceM(o.distanceFromRouteM!)}'),
            const SizedBox(height: AppSpace.sm),
            SyncStatusChip(status: o.syncStatus, l10n: l10n),
          ],
        ),
      ),
    );
  }

  String _formatDistanceM(double meters) =>
      meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(2)} km';

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
