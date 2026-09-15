import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/map_focus.dart';
import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/gis_sync.dart';
import '../../data/mock_seed.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/observation.dart';
import '../../models/patrol.dart';
import '../../models/shared_gis.dart';
import '../../models/task_item.dart';
import '../../services/active_patrol_controller.dart';
import '../../services/location_status.dart';
import '../../widgets/common.dart';
import '../../widgets/gis_sync_banner.dart';
import '../../widgets/observation_detail_sheet.dart';

/// The single reserve map used everywhere in the app: reuses the ported
/// [GISStation]/[GISMapBundle]-shaped data for camera stations + zone
/// context, plus ranger-specific layers (current GPS, live/most-recent
/// patrol route, observation pins, task pins). Station detail's
/// "Navigate", task location, and the active patrol screen all route
/// through here rather than building a second map implementation — this
/// screen additionally honors [mapFocusStationIdProvider] /
/// [mapFocusTaskIdProvider] to center on a specific pin when asked.
class RangerMapScreen extends ConsumerStatefulWidget {
  const RangerMapScreen({super.key});

  @override
  ConsumerState<RangerMapScreen> createState() => _RangerMapScreenState();
}

class _RangerMapScreenState extends ConsumerState<RangerMapScreen> {
  final _mapController = MapController();
  bool _showStations = true;
  bool _showRoute = true;
  bool _showObservations = true;
  bool _showTasks = true;
  bool _showZones = true;
  bool _showMe = true;
  Timer? _positionRefreshTimer;

  @override
  void initState() {
    super.initState();
    // `currentPositionProvider` is a one-shot fetch (see location_status.dart)
    // so "My location" would otherwise freeze at whatever it returned the
    // first time this screen ever built. Re-fetch periodically while the
    // map is open so the dot actually tracks the ranger.
    _positionRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) ref.invalidate(currentPositionProvider);
    });
  }

  @override
  void dispose() {
    _positionRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final stations = ref.watch(stationsStreamProvider).value ?? const <GISStation>[];
    final gisSync = ref.watch(gisSyncStateProvider).value;
    final liveSubRegions = gisSync?.bundle?.subRegions ?? const [];
    final observations = ref.watch(observationsStreamProvider).value ?? const <Observation>[];
    final tasks = ref.watch(tasksStreamProvider).value ?? const <TaskItem>[];
    final patrols = ref.watch(patrolsStreamProvider).value ?? const <Patrol>[];
    final activePatrol = ref.watch(activePatrolControllerProvider);

    // Prefer the live in-progress patrol's route; else the most recently
    // completed one, so the map is never empty.
    Patrol? routePatrol = activePatrol;
    if (routePatrol == null && patrols.isNotEmpty) {
      final completed = patrols.where((p) => p.status == PatrolStatus.completed).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (completed.isNotEmpty) routePatrol = completed.first;
    }
    final routePoints = routePatrol?.route.map((p) => ll.LatLng(p.lat, p.lng)).toList() ?? const <ll.LatLng>[];

    // "My location" is the ranger's actual current GPS position — NOT the
    // same thing as the patrol route above. An active patrol's route is
    // ONLY real GPS when `isUsingRealGps` is true; when real GPS isn't
    // available in time, ActivePatrolController falls back to a *simulated*
    // walk anchored on the Pench reserve center purely so the patrol-demo
    // still animates — that fabricated point must never be shown as "my
    // location", or it looks like the app thinks you're standing in Pench
    // when you're not. So: trust the active patrol's route only while it's
    // genuinely GPS-backed; otherwise always fall back to a fresh device
    // GPS read (or nothing, rather than a fake position).
    final activePatrolNotifier = ref.watch(activePatrolControllerProvider.notifier);
    final activePatrolIsRealGps = activePatrol != null && activePatrolNotifier.isUsingRealGps;
    final devicePosition = ref.watch(currentPositionProvider).value;
    final myPosition = activePatrolIsRealGps && routePoints.isNotEmpty
        ? routePoints.last
        : (devicePosition != null ? ll.LatLng(devicePosition.latitude, devicePosition.longitude) : null);

    // Handle a pending "focus on X" request from Station/Task detail.
    final focusStationId = ref.watch(mapFocusStationIdProvider);
    final focusTaskId = ref.watch(mapFocusTaskIdProvider);
    ll.LatLng? focusPoint;
    if (focusStationId != null) {
      final match = stations.where((s) => s.cameraId == focusStationId).toList();
      if (match.isNotEmpty) focusPoint = ll.LatLng(match.first.latitude, match.first.longitude);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(mapFocusStationIdProvider.notifier).state = null;
      });
    } else if (focusTaskId != null) {
      final match = tasks.where((t) => t.id == focusTaskId && t.hasLocation).toList();
      if (match.isNotEmpty) focusPoint = ll.LatLng(match.first.lat!, match.first.lng!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(mapFocusTaskIdProvider.notifier).state = null;
      });
    }
    if (focusPoint != null) {
      final p = focusPoint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(p, 15);
      });
    }

    final center = focusPoint ?? myPosition ?? ll.LatLng(kReserveCenterLat, kReserveCenterLng);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 12.5),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tygris.ranger',
              ),
              if (_showRoute && routePoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: routePoints, strokeWidth: 4, color: AppColors.accent),
                ]),
              if (_showZones)
                MarkerLayer(markers: [
                  // Prefer the live sub-regions from the real GIS bundle
                  // (`/api/gis/bundle`); fall back to the offline demo
                  // labels only until the first successful sync lands.
                  for (final z in liveSubRegions.isNotEmpty
                      ? liveSubRegions.map((s) => ZoneLabel(name: s.name, centerLat: s.centerLat, centerLng: s.centerLng))
                      : seedZoneLabels)
                    Marker(
                      point: ll.LatLng(z.centerLat, z.centerLng),
                      width: 120,
                      height: 28,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.foreground.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(z.name,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                ]),
              if (_showStations)
                MarkerLayer(markers: [
                  for (final s in stations)
                    Marker(
                      point: ll.LatLng(s.latitude, s.longitude),
                      width: 32,
                      height: 32,
                      child: GestureDetector(
                        onTap: () => _showStationSheet(context, l10n, s),
                        child: Container(
                          decoration: BoxDecoration(
                            color: stationStatusColor(s.operationalStatus),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ]),
              if (_showObservations)
                MarkerLayer(markers: [
                  for (final o in observations)
                    Marker(
                      point: ll.LatLng(o.lat, o.lng),
                      width: 26,
                      height: 26,
                      child: GestureDetector(
                        onTap: () => showObservationDetail(context, o, l10n),
                        child: Container(
                          decoration: BoxDecoration(
                            color: severityColor(o.severity),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(observationTypeIcon(o.type), color: Colors.white, size: 12),
                        ),
                      ),
                    ),
                ]),
              if (_showTasks)
                MarkerLayer(markers: [
                  for (final t in tasks.where((t) => t.hasLocation && t.status != TaskStatus.completed))
                    Marker(
                      point: ll.LatLng(t.lat!, t.lng!),
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.ochre,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.flag_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                ]),
              if (_showMe && myPosition != null)
                MarkerLayer(markers: [
                  Marker(
                    point: myPosition,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.accentStrong,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ]),
            ],
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
                  child: Align(alignment: Alignment.centerLeft, child: GisSyncBanner(l10n: l10n, stationCount: stations.length)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _LayerChip(label: l10n.t('map.layer.stations'), value: _showStations, onChanged: (v) => setState(() => _showStations = v)),
                        const SizedBox(width: AppSpace.sm),
                        _LayerChip(label: l10n.t('map.layer.patrolRoute'), value: _showRoute, onChanged: (v) => setState(() => _showRoute = v)),
                        const SizedBox(width: AppSpace.sm),
                        _LayerChip(label: l10n.t('map.layer.observations'), value: _showObservations, onChanged: (v) => setState(() => _showObservations = v)),
                        const SizedBox(width: AppSpace.sm),
                        _LayerChip(label: l10n.t('map.layer.tasks'), value: _showTasks, onChanged: (v) => setState(() => _showTasks = v)),
                        const SizedBox(width: AppSpace.sm),
                        _LayerChip(label: l10n.t('map.layer.zones'), value: _showZones, onChanged: (v) => setState(() => _showZones = v)),
                        const SizedBox(width: AppSpace.sm),
                        _LayerChip(label: l10n.t('map.layer.currentLocation'), value: _showMe, onChanged: (v) => setState(() => _showMe = v)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStationSheet(BuildContext context, AppLocalizations l10n, GISStation s) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.cameraId, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: AppSpace.sm),
                  StatusPill(label: l10n.t(stationStatusLabelKey(s.operationalStatus)), color: stationStatusColor(s.operationalStatus)),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(s.zone, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}


class _LayerChip extends StatelessWidget {
  const _LayerChip({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentSoft,
      side: BorderSide(color: value ? AppColors.accent : AppColors.border),
    );
  }
}
