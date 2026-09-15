import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/observation.dart';
import '../../models/patrol.dart';
import '../../services/active_patrol_controller.dart';
import '../../widgets/common.dart';

class ActivePatrolScreen extends ConsumerStatefulWidget {
  const ActivePatrolScreen({super.key});

  @override
  ConsumerState<ActivePatrolScreen> createState() => _ActivePatrolScreenState();
}

class _ActivePatrolScreenState extends ConsumerState<ActivePatrolScreen> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final patrol = ref.watch(activePatrolControllerProvider);

    if (patrol == null) {
      // Defensive fallback (e.g. hot-restart lost state) — bounce home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final points = patrol.route.map((p) => ll.LatLng(p.lat, p.lng)).toList();
    final center = points.isNotEmpty ? points.last : const ll.LatLng(21.68, 79.29);
    final isPaused = patrol.status == PatrolStatus.paused;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tygris.ranger',
              ),
              if (points.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: points, strokeWidth: 4, color: AppColors.accent),
                ]),
              if (points.isNotEmpty)
                MarkerLayer(markers: [
                  Marker(
                    point: points.last,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 8)],
                      ),
                    ),
                  ),
                ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => _confirmClose(context, l10n),
                  ),
                  const Spacer(),
                  StatusPill(
                    label: isPaused ? l10n.t('patrol.paused') : l10n.t('patrol.active'),
                    color: isPaused ? AppColors.caution : AppColors.positive,
                    icon: isPaused ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpace.md,
            right: AppSpace.md,
            bottom: AppSpace.md,
            child: SafeArea(
              top: false,
              child: _BottomPanel(l10n: l10n, patrol: patrol),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, AppLocalizations l10n) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.stop_circle_rounded, color: AppColors.danger),
              title: Text(l10n.t('patrol.end')),
              onTap: () => Navigator.pop(ctx, 'end'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: Text(l10n.t('common.cancel')),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );
    if (action == 'end' && mounted) {
      ref.read(activePatrolControllerProvider.notifier).end();
      context.pushReplacement('/patrol/review');
    }
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: AppColors.shadowTint, blurRadius: 8)],
        ),
        child: Icon(icon, color: AppColors.foreground),
      ),
    );
  }
}

class _BottomPanel extends ConsumerWidget {
  const _BottomPanel({required this.l10n, required this.patrol});
  final AppLocalizations l10n;
  final Patrol patrol;

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(activePatrolControllerProvider.notifier);
    final isPaused = patrol.status == PatrolStatus.paused;
    final paceMinPerKm = patrol.distanceKm > 0.05
        ? (patrol.durationSeconds / 60) / patrol.distanceKm
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 16)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(label: l10n.t('patrol.distance'), value: '${patrol.distanceKm.toStringAsFixed(2)} ${l10n.t('common.km')}'),
              _Stat(label: l10n.t('patrol.duration'), value: _fmtDuration(patrol.durationSeconds)),
              _Stat(
                label: l10n.t('patrol.pace'),
                value: paceMinPerKm > 0 ? '${paceMinPerKm.toStringAsFixed(1)} min/km' : '—',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => isPaused ? controller.resume() : controller.pause(),
                    icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(isPaused ? l10n.t('patrol.resume') : l10n.t('patrol.pause')),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => _openQuickLogSheet(context, l10n, patrol.id),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.t('patrol.logObservation')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openQuickLogSheet(BuildContext context, AppLocalizations l10n, String patrolId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickLogCategorySheet(l10n: l10n, patrolId: patrolId),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
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

/// The shared "9 category" picker — used both mid-patrol (here) and from
/// the stand-alone Quick Report flow (`quick_report_screen.dart`).
class _QuickLogCategorySheet extends StatelessWidget {
  const _QuickLogCategorySheet({required this.l10n, this.patrolId});
  final AppLocalizations l10n;
  final String? patrolId;

  @override
  Widget build(BuildContext context) {
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
            Text(l10n.t('patrol.logSheetTitle'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.lg),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpace.sm,
              crossAxisSpacing: AppSpace.sm,
              childAspectRatio: 0.95,
              children: [
                for (final type in ObservationType.values)
                  _CategoryTile(
                    type: type,
                    label: l10n.t(observationTypeLabelKey(type)),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/patrol/quick-log', extra: {
                        'category': type,
                        'patrolId': patrolId,
                      });
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.type, required this.label, required this.onTap});
  final ObservationType type;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(observationTypeIcon(type), color: AppColors.accent),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
