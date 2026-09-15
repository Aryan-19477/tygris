import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/connectivity_status.dart';
import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/gis_sync.dart';
import '../../l10n/app_localizations.dart';
import '../../models/observation.dart';
import '../../models/patrol.dart';
import '../../services/active_patrol_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/gis_sync_banner.dart';
import '../../widgets/reserve_map_layers.dart';

/// Full-bleed live-tracking HUD shown while a patrol is in progress.
///
/// Visual language: the map fills the entire screen and every control —
/// identity badge, stats, quick actions — floats over it as a translucent
/// "glass" circle/pill/panel, echoing a drone-controller-style navigation
/// HUD. Every control here maps 1:1 onto functionality this screen already
/// had before the restyle (close/end/pause/resume/quick-log/offline-mode/
/// recenter) — nothing new was invented beyond a live speed readout, which
/// falls out of the GPS route this screen already tracks.
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
    final bundle = ref.watch(gisSyncStateProvider).value?.bundle;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

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
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                backgroundColor: isOnline ? const Color(0xFFE0E0E0) : AppColors.mapOfflineBase,
              ),
              children: [
                if (reserveTileLayer(isOnline) != null) reserveTileLayer(isOnline)!,
                ...reserveBoundaryLayers(bundle),
                rangeLabelMarkers(bundle),
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
          ),

          // Top row: identity badge (left) + close (right) — both floating
          // directly over the map, no app bar / no bounding card.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityBadge(patrol: patrol, isPaused: isPaused, l10n: l10n),
                    const Spacer(),
                    _GlassIconButton(
                      icon: Icons.close_rounded,
                      onTap: () => _confirmClose(context, l10n),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Left edge: vertical stack of floating circular controls.
          Positioned(
            left: AppSpace.lg,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GlassIconButton(
                        icon: Icons.my_location_rounded,
                        onTap: () => _recenter(points),
                      ),
                      const SizedBox(height: AppSpace.md),
                      _GlassOfflineBadge(l10n: l10n, isOnline: isOnline),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Right edge: borderless stat readouts, drone-HUD typography.
          Positioned(
            right: AppSpace.lg,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: _StatsRail(patrol: patrol, l10n: l10n),
                ),
              ),
            ),
          ),

          // Bottom-center: pause/resume + big end-patrol stop + quick-log.
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpace.xl,
            child: SafeArea(
              top: false,
              child: _BottomActionCluster(l10n: l10n, patrol: patrol),
            ),
          ),
        ],
      ),
    );
  }

  void _recenter(List<ll.LatLng> points) {
    if (points.isEmpty) return;
    _mapController.move(points.last, _mapController.camera.zoom);
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

/// Translucent white circular "glass" button — the floating-HUD equivalent
/// of the old bordered [_RoundIconButton].
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 12)],
        ),
        child: Icon(icon, color: color ?? AppColors.foreground),
      ),
    );
  }
}

/// Top-left status badge — patrol type icon + method, with a small
/// active/paused indicator dot overlapping the corner (the HUD-reference's
/// "verified" checkmark, repurposed for a status this app actually has).
class _IdentityBadge extends StatelessWidget {
  const _IdentityBadge({required this.patrol, required this.isPaused, required this.l10n});
  final Patrol patrol;
  final bool isPaused;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 12)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(patrolTypeIcon(patrol.patrolType.name), size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                l10n.t('patrol.${patrol.method.name}'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.foreground),
              ),
            ],
          ),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isPaused ? AppColors.caution : AppColors.positive,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill echoing [OfflineMapModeChip] but sized/styled to sit inside
/// the left-edge floating-button column rather than the old app-bar row.
class _GlassOfflineBadge extends StatelessWidget {
  const _GlassOfflineBadge({required this.l10n, required this.isOnline});
  final AppLocalizations l10n;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 12)],
      ),
      child: Icon(
        isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        color: isOnline ? AppColors.synced : AppColors.offline,
      ),
    );
  }
}

/// Right-edge stat readouts — no card/background, just the reference HUD's
/// "small light label above a large bold number" typography, laid over the
/// map with a text shadow for legibility.
class _StatsRail extends StatelessWidget {
  const _StatsRail({required this.patrol, required this.l10n});
  final Patrol patrol;
  final AppLocalizations l10n;

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  /// Live speed derived from the last two GPS fixes already recorded on the
  /// route — no new tracking state, just distance/time already on hand
  /// (distance via `latlong2`'s `Distance`, the same package already used
  /// for map coordinates on this screen).
  double? _currentSpeedKmh() {
    final route = patrol.route;
    if (route.length < 2) return null;
    final a = route[route.length - 2];
    final b = route[route.length - 1];
    final dtHours = (b.timestampMs - a.timestampMs) / 3600000.0;
    if (dtHours <= 0) return null;
    final distKm = const ll.Distance().as(
          ll.LengthUnit.Kilometer,
          ll.LatLng(a.lat, a.lng),
          ll.LatLng(b.lat, b.lng),
        );
    final speed = distKm / dtHours;
    return speed.isFinite ? speed : null;
  }

  @override
  Widget build(BuildContext context) {
    final paceMinPerKm = patrol.distanceKm > 0.05
        ? (patrol.durationSeconds / 60) / patrol.distanceKm
        : 0.0;
    final speedKmh = patrol.status == PatrolStatus.active ? _currentSpeedKmh() : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (speedKmh != null) ...[
          _HudStat(label: l10n.t('patrol.speed'), value: speedKmh.toStringAsFixed(1), unit: 'km/h'),
          const SizedBox(height: AppSpace.lg),
        ],
        _HudStat(
          label: l10n.t('patrol.distance'),
          value: patrol.distanceKm.toStringAsFixed(2),
          unit: l10n.t('common.km'),
        ),
        const SizedBox(height: AppSpace.lg),
        _HudStat(label: l10n.t('patrol.duration'), value: _fmtDuration(patrol.durationSeconds), unit: ''),
        const SizedBox(height: AppSpace.lg),
        _HudStat(
          label: l10n.t('patrol.pace'),
          value: paceMinPerKm > 0 ? paceMinPerKm.toStringAsFixed(1) : '—',
          unit: paceMinPerKm > 0 ? 'min/km' : '',
        ),
      ],
    );
  }
}

class _HudStat extends StatelessWidget {
  const _HudStat({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  static const _shadow = [Shadow(color: Colors.black45, blurRadius: 6)];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            shadows: _shadow,
          ),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  shadows: _shadow,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: _shadow,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom-center action cluster: pause/resume (smaller, left) + end patrol
/// (large red circle, center) + quick-log (right) — the same three actions
/// the old bottom panel exposed, now floating over the map.
class _BottomActionCluster extends ConsumerWidget {
  const _BottomActionCluster({required this.l10n, required this.patrol});
  final AppLocalizations l10n;
  final Patrol patrol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(activePatrolControllerProvider.notifier);
    final isPaused = patrol.status == PatrolStatus.paused;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _GlassIconButton(
          icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          onTap: () => isPaused ? controller.resume() : controller.pause(),
          color: isPaused ? AppColors.positive : AppColors.caution,
        ),
        const SizedBox(width: AppSpace.xl),
        PressableScale(
          onTap: () => _confirmEnd(context, ref),
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: AppColors.shadowTintStrong, blurRadius: 16)],
            ),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: AppSpace.xl),
        _GlassIconButton(
          icon: Icons.add_rounded,
          onTap: () => _openQuickLogSheet(context, l10n, patrol.id),
          color: AppColors.accent,
        ),
      ],
    );
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
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
    if (action == 'end' && context.mounted) {
      ref.read(activePatrolControllerProvider.notifier).end();
      context.pushReplacement('/patrol/review');
    }
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
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
