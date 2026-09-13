import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Fetches the full GIS bundle (boundaries, stations, territories, recent
/// sightings) for the Reserve Map tab. Kept as its own provider (rather than
/// folded into a StatefulWidget's initState) so pull-to-retry can simply
/// invalidate/refresh it, matching the FutureProvider pattern already used
/// for `baseUrlInitProvider` in core/repository.dart.
final gisBundleProvider = FutureProvider.autoDispose<GISMapBundle>((ref) {
  return ref.watch(repositoryProvider).gisBundle();
});

/// Fallback center for Pench Tiger Reserve, used only if the bundle has
/// neither a core boundary nor any stations to derive a centroid from.
const _fallbackCenter = LatLng(21.65, 79.25);

class ReserveMapScreen extends ConsumerWidget {
  const ReserveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(gisBundleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: bundleAsync.when(
        loading: () => const _MapLoadingShimmer(),
        error: (err, _) => ErrorState(
          message: 'Could not load the reserve map.\n${err.toString()}',
          onRetry: () => ref.invalidate(gisBundleProvider),
        ),
        data: (bundle) {
          if (bundle.coreBoundary.isEmpty &&
              bundle.stations.isEmpty &&
              bundle.territories.isEmpty) {
            return const EmptyState(
              icon: Icons.map_outlined,
              title: 'No map data available',
              subtitle: 'The reserve GIS bundle returned no boundary, '
                  'station, or territory data yet.',
            );
          }
          return _ReserveMapBody(bundle: bundle);
        },
      ),
    );
  }
}

class _MapLoadingShimmer extends StatelessWidget {
  const _MapLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(child: LoadingList(itemCount: 5, height: 90));
  }
}

class _ReserveMapBody extends StatefulWidget {
  const _ReserveMapBody({required this.bundle});

  final GISMapBundle bundle;

  @override
  State<_ReserveMapBody> createState() => _ReserveMapBodyState();
}

class _ReserveMapBodyState extends State<_ReserveMapBody> {
  final MapController _mapController = MapController();
  late final LatLng _initialCenter;
  late final LatLngBounds? _coreBounds;

  @override
  void initState() {
    super.initState();
    _initialCenter = _resolveCenter(widget.bundle);
    _coreBounds = _resolveBounds(widget.bundle);
  }

  LatLng _resolveCenter(GISMapBundle bundle) {
    if (bundle.coreBoundary.isNotEmpty) {
      final pts = bundle.coreBoundary
          .map((p) => LatLng(p[0], p[1]))
          .toList(growable: false);
      final latSum = pts.fold<double>(0, (s, p) => s + p.latitude);
      final lonSum = pts.fold<double>(0, (s, p) => s + p.longitude);
      return LatLng(latSum / pts.length, lonSum / pts.length);
    }
    if (bundle.stations.isNotEmpty) {
      final s = bundle.stations.first;
      return LatLng(s.latitude, s.longitude);
    }
    return _fallbackCenter;
  }

  LatLngBounds? _resolveBounds(GISMapBundle bundle) {
    if (bundle.coreBoundary.isEmpty) return null;
    final pts = bundle.coreBoundary
        .map((p) => LatLng(p[0], p[1]))
        .toList(growable: false);
    return LatLngBounds.fromPoints(pts);
  }

  void _recenter() {
    if (_coreBounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: _coreBounds, padding: const EdgeInsets.all(36)),
      );
    } else {
      _mapController.move(_initialCenter, 11);
    }
  }

  void _showStationSheet(GISStation station) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StationSheet(station: station),
    );
  }

  void _showTerritorySheet(Territory territory) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TerritorySheet(territory: territory),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: 11,
            initialCameraFit: _coreBounds != null
                ? CameraFit.bounds(
                    bounds: _coreBounds,
                    padding: const EdgeInsets.all(36),
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tygris.field',
            ),
            if (bundle.bufferBoundary.isNotEmpty)
              PolygonLayer(polygons: [
                // flutter_map 7.x has no dashed-border support on Polygon
                // (StrokePattern landed in 8.x), so the buffer ring is
                // distinguished from the core boundary by a lighter,
                // thinner, more translucent outline instead of dashing.
                Polygon(
                  points: bundle.bufferBoundary
                      .map((p) => LatLng(p[0], p[1]))
                      .toList(growable: false),
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.05),
                  borderColor: const Color(0xFF06B6D4).withValues(alpha: 0.55),
                  borderStrokeWidth: 1.2,
                ),
              ]),
            if (bundle.coreBoundary.isNotEmpty)
              PolygonLayer(polygons: [
                Polygon(
                  points: bundle.coreBoundary
                      .map((p) => LatLng(p[0], p[1]))
                      .toList(growable: false),
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderColor: AppColors.accent,
                  borderStrokeWidth: 2.2,
                ),
              ]),
            if (bundle.territories.isNotEmpty)
              PolygonLayer(
                polygons: bundle.territories
                    .where((t) => t.polygon.isNotEmpty)
                    .map((t) {
                  final color = _territoryColor(t, bundle.recentSightings);
                  return Polygon(
                    points: t.polygon
                        .map((p) => LatLng(p[0], p[1]))
                        .toList(growable: false),
                    color: color.withValues(alpha: 0.08),
                    borderColor: color,
                    borderStrokeWidth: 1.4,
                  );
                }).toList(growable: false),
              ),
            // Territories aren't individually tappable via PolygonLayer hit
            // testing across flutter_map versions, so overlay an invisible
            // tap target at each territory's centroid to open its sheet —
            // simpler and more reliable than per-polygon gesture detection.
            if (bundle.territories.isNotEmpty)
              MarkerLayer(
                markers: bundle.territories
                    .where((t) => t.centroid.length == 2)
                    .map((t) => Marker(
                          point: LatLng(t.centroid[0], t.centroid[1]),
                          width: 34,
                          height: 34,
                          child: _TerritoryTapTarget(
                            territory: t,
                            color: _territoryColor(t, bundle.recentSightings),
                            onTap: () => _showTerritorySheet(t),
                          ),
                        ))
                    .toList(growable: false),
              ),
            if (bundle.stations.isNotEmpty)
              MarkerLayer(
                markers: bundle.stations
                    .map((s) => Marker(
                          point: LatLng(s.latitude, s.longitude),
                          width: 26,
                          height: 26,
                          child: _StationMarker(
                            station: s,
                            onTap: () => _showStationSheet(s),
                          ),
                        ))
                    .toList(growable: false),
              ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _StatsStrip(bundle: bundle),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 96,
          child: SafeArea(
            top: false,
            child: _RecenterButton(onTap: _recenter),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: _MapLegend(showLastSeen: bundle.recentSightings.isNotEmpty),
          ),
        ),
      ],
    );
  }

  Color _territoryColor(Territory t, List<Sighting> sightings) {
    Sighting? latest;
    for (final s in sightings) {
      if (s.tigerId != t.tigerId) continue;
      if (latest == null) {
        latest = s;
        continue;
      }
      final a = s.timestamp ?? '';
      final b = latest.timestamp ?? '';
      if (a.compareTo(b) > 0) latest = s;
    }
    if (latest?.alertLevel != null) {
      return statusColor(latest!.alertLevel!);
    }
    return AppColors.positive;
  }
}

class _TerritoryTapTarget extends StatelessWidget {
  const _TerritoryTapTarget({
    required this.territory,
    required this.color,
    required this.onTap,
  });

  final Territory territory;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({required this.station, required this.onTap});

  final GISStation station;
  final VoidCallback onTap;

  bool get _operational =>
      station.operationalStatus.toUpperCase() == 'OPERATIONAL';

  @override
  Widget build(BuildContext context) {
    final color = _operational ? AppColors.positive : AppColors.danger;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowTintStrong,
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Icon(
          Icons.videocam_rounded,
          size: 13,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

/// Small fixed/sticky overlay — a safe place for BackdropFilter per the
/// bible's backdrop-blur discipline rule (never on the scrolling map).
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.foreground.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowTintStrong,
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.my_location_rounded,
              size: 20,
              color: AppColors.ochre,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.bundle});

  final GISMapBundle bundle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.bezelOuter),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Bezel(
            outerColor: AppColors.surfaceSunken.withValues(alpha: 0.9),
            innerColor: AppColors.surface.withValues(alpha: 0.92),
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const EyebrowTag(
                  label: 'Reserve overview',
                  icon: Icons.travel_explore_rounded,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  bundle.reserve,
                  style: textTheme.headlineSmall?.copyWith(
                    color: AppColors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.videocam_outlined,
                      label: 'Stations',
                      value: '${bundle.totalStations}',
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _StatChip(
                      icon: Icons.pets_outlined,
                      label: 'Tigers',
                      value: '${bundle.totalTigers}',
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.terrain_outlined,
                        label: 'Core / Buffer',
                        value:
                            '${bundle.coreAreaKm2.toStringAsFixed(0)} / ${bundle.bufferAreaKm2.toStringAsFixed(0)} km²',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.showLastSeen});

  final bool showLastSeen;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowTint,
                blurRadius: 14,
                spreadRadius: -4,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LegendRow(color: AppColors.accent, label: 'Core reserve'),
              const SizedBox(height: 5),
              const _LegendRow(color: Color(0xFF06B6D4), label: 'Buffer zone'),
              const SizedBox(height: 5),
              const _LegendRow(
                  color: AppColors.positive, label: 'Station online'),
              const SizedBox(height: 5),
              const _LegendRow(
                  color: AppColors.danger, label: 'Station offline'),
              if (showLastSeen) ...[
                const SizedBox(height: 5),
                const _LegendRow(
                    color: AppColors.priorityMedium,
                    label: 'Territory · recent alert'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Shared chrome for the bottom sheets: transparent scaffold background +
/// a Bezel surface anchored to the bottom, generous padding, drag handle.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, 0, AppSpace.md, AppSpace.md),
        child: Bezel(
          outerRadius: AppRadius.bezelOuter,
          padding: const EdgeInsets.fromLTRB(
              AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xl),
          child: child,
        ),
      ),
    );
  }
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({required this.station});

  final GISStation station;

  bool get _operational =>
      station.operationalStatus.toUpperCase() == 'OPERATIONAL';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = _operational ? AppColors.positive : AppColors.danger;
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.videocam_rounded, color: color),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.cameraId,
                      style: textTheme.titleLarge
                          ?.copyWith(color: AppColors.foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      station.zone,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: station.operationalStatus,
                level: _operational ? 'low' : 'high',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          _DetailRow(
            label: 'Uptime',
            value: '${(station.uptimeRatio * 100).toStringAsFixed(1)}%',
          ),
          if (station.subRegion != null)
            _DetailRow(label: 'Sub-region', value: station.subRegion!),
          if (station.habitat != null)
            _DetailRow(label: 'Habitat', value: station.habitat!),
          if (station.trailType != null)
            _DetailRow(label: 'Trail type', value: station.trailType!),
          if (station.nearestWaterKm != null)
            _DetailRow(
              label: 'Nearest water',
              value: '${station.nearestWaterKm!.toStringAsFixed(1)} km',
            ),
          if (station.nearestVillageKm != null)
            _DetailRow(
              label: 'Nearest village',
              value: '${station.nearestVillageKm!.toStringAsFixed(1)} km',
            ),
          _DetailRow(
            label: 'Coordinates',
            value:
                '${station.latitude.toStringAsFixed(4)}, ${station.longitude.toStringAsFixed(4)}',
          ),
        ],
      ),
    );
  }
}

class _TerritorySheet extends StatelessWidget {
  const _TerritorySheet({required this.territory});

  final Territory territory;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.pets_rounded, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      territory.name.isNotEmpty
                          ? territory.name
                          : territory.tigerId,
                      style: textTheme.titleLarge
                          ?.copyWith(color: AppColors.foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      territory.tigerId,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          _DetailRow(
              label: 'Territory (MCP)',
              value: '${territory.areaKm2.toStringAsFixed(1)} km²'),
          if (territory.sex.isNotEmpty)
            _DetailRow(label: 'Sex', value: territory.sex),
          if (territory.lifeStage.isNotEmpty)
            _DetailRow(label: 'Life stage', value: territory.lifeStage),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
