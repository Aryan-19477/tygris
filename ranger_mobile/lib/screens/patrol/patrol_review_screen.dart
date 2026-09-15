import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/observation_meta.dart';
import '../../core/sync_status.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/observation.dart';
import '../../models/patrol.dart';
import '../../services/active_patrol_controller.dart';
import '../../services/sync_queue_service.dart';
import '../../widgets/common.dart';

/// Shown either as the end-of-patrol review (no [patrolId] — reads the
/// just-ended draft from [ActivePatrolController], offers Save/Discard) or
/// as a read-only history view (`patrolId` set — loads a completed patrol
/// straight from the repository, no edit actions).
class PatrolReviewScreen extends ConsumerStatefulWidget {
  const PatrolReviewScreen({super.key, this.patrolId});
  final String? patrolId;

  @override
  ConsumerState<PatrolReviewScreen> createState() => _PatrolReviewScreenState();
}

class _PatrolReviewScreenState extends ConsumerState<PatrolReviewScreen> {
  final _notesController = TextEditingController();
  bool _saving = false;

  bool get _isDraft => widget.patrolId == null;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    Patrol? patrol;
    if (_isDraft) {
      patrol = ref.watch(activePatrolControllerProvider);
    } else {
      final all = ref.watch(patrolsStreamProvider).value ?? const <Patrol>[];
      final matches = all.where((p) => p.id == widget.patrolId).toList();
      patrol = matches.isNotEmpty ? matches.first : null;
    }

    if (patrol == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.t('patrol.review.title'))),
        body: Center(child: Text(l10n.t('common.unknown'))),
      );
    }
    final patrol_ = patrol;

    final observations = (ref.watch(observationsStreamProvider).value ?? const [])
        .where((o) => patrol_.observationIds.contains(o.id))
        .toList();

    final byCategory = <ObservationType, int>{};
    for (final o in observations) {
      byCategory[o.type] = (byCategory[o.type] ?? 0) + 1;
    }

    final points = patrol_.route.map((p) => ll.LatLng(p.lat, p.lng)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('patrol.review.title')),
        actions: _isDraft ? null : [Padding(padding: const EdgeInsets.only(right: AppSpace.lg), child: Center(child: SyncStatusChip(status: patrol_.syncStatus, l10n: l10n)))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            if (points.length > 1)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  height: 180,
                  child: IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: points[points.length ~/ 2],
                        initialZoom: 13,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.tygris.ranger',
                        ),
                        PolylineLayer(polylines: [
                          Polyline(points: points, strokeWidth: 4, color: AppColors.accent),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.lg),
            SectionLabel(l10n.t('patrol.review.summary')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryStat(label: l10n.t('patrol.distance'), value: '${patrol_.distanceKm.toStringAsFixed(2)} ${l10n.t('common.km')}'),
                  _SummaryStat(label: l10n.t('patrol.duration'), value: _fmtDuration(patrol_.durationSeconds)),
                  _SummaryStat(label: l10n.t('patrol.review.coverage'), value: patrol_.coverageAreaKm2 != null ? '${patrol_.coverageAreaKm2!.toStringAsFixed(1)} km²' : '—'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(DateFormat('MMM d, yyyy · HH:mm').format(patrol_.startedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('patrol.review.observationsByCategory')),
            const SizedBox(height: AppSpace.sm),
            if (byCategory.isEmpty)
              Text(l10n.t('common.none'), style: const TextStyle(color: AppColors.muted))
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final entry in byCategory.entries)
                    StatusPill(
                      label: '${l10n.t(observationTypeLabelKey(entry.key))} · ${entry.value}',
                      color: AppColors.accent,
                      icon: observationTypeIcon(entry.key),
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('patrol.review.notes')),
            const SizedBox(height: AppSpace.sm),
            if (_isDraft)
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(hintText: l10n.t('patrol.review.notesHint')),
              )
            else
              Text(patrol_.notes?.isNotEmpty == true ? patrol_.notes! : l10n.t('common.none')),
            const SizedBox(height: AppSpace.xxl),
            if (_isDraft) ...[
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(patrol_),
                  child: Text(l10n.t('patrol.review.save')),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _discard(l10n),
                  child: Text(l10n.t('patrol.review.discard')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _save(Patrol patrol) async {
    setState(() => _saving = true);
    final updated = patrol.copyWith(
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      syncStatus: SyncStatus.local,
    );
    await ref.read(patrolRepositoryProvider).save(updated);
    await ref.read(syncQueueServiceProvider).enqueue(entityType: 'patrol', entityId: updated.id);
    await ref.read(activePatrolControllerProvider.notifier).clear(discard: false);
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _discard(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('patrol.review.discard')),
        content: Text(l10n.t('patrol.review.discardConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('common.discard')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(activePatrolControllerProvider.notifier).clear(discard: true);
      if (!mounted) return;
      context.go('/');
    }
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted)),
      ],
    );
  }
}
