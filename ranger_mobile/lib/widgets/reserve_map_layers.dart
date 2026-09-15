/// Shared reserve-shape rendering used by every `flutter_map` surface in
/// the app (`RangerMapScreen`, `ActivePatrolScreen`, `PatrolReviewScreen`)
/// so the Core/Buffer zone polygons, range-name labels, camera stations and
/// tiger territories always look the same everywhere, instead of each
/// screen inventing its own version.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../core/theme.dart';
import '../data/mock_seed.dart';
import '../models/shared_gis.dart';

List<ll.LatLng> _toLatLngs(List<List<double>> points) =>
    points.map((p) => ll.LatLng(p[0], p[1])).toList();

/// Buffer zone (drawn first, underneath) + Core zone (drawn on top) as
/// filled polygons — mirrors the reference paper map's light-green outer
/// ring with a darker-green inner core.
List<Widget> reserveBoundaryLayers(GISMapBundle? bundle) {
  if (bundle == null) return const [];
  final layers = <Widget>[];
  if (bundle.bufferBoundary.isNotEmpty) {
    layers.add(PolygonLayer(polygons: [
      Polygon(
        points: _toLatLngs(bundle.bufferBoundary),
        color: AppColors.zoneBufferFill,
        borderColor: AppColors.zoneBufferBorder,
        borderStrokeWidth: 1.5,
      ),
    ]));
  }
  if (bundle.coreBoundary.isNotEmpty) {
    layers.add(PolygonLayer(polygons: [
      Polygon(
        points: _toLatLngs(bundle.coreBoundary),
        color: AppColors.zoneCoreFill,
        borderColor: AppColors.zoneCoreBorder,
        borderStrokeWidth: 1.5,
      ),
    ]));
  }
  return layers;
}

/// Tiger home-range polygons — thin outline only, no/very light fill, so
/// they read as an overlay rather than competing with the zone shading.
Widget territoryLayer(GISMapBundle? bundle) {
  final territories = bundle?.territories ?? const <Territory>[];
  return PolygonLayer(polygons: [
    for (final t in territories)
      if (t.polygon.isNotEmpty)
        Polygon(
          points: _toLatLngs(t.polygon),
          color: AppColors.territoryOutline.withValues(alpha: 0.06),
          borderColor: AppColors.territoryOutline,
          borderStrokeWidth: 1.2,
        ),
  ]);
}

/// Range/sub-region name labels (Deolapar, East Pench, West Pench, …) at
/// their bundle-provided center point — falls back to the offline demo
/// [seedZoneLabels] only until a real bundle (bundled asset or live sync)
/// is available, so this is never empty.
Widget rangeLabelMarkers(GISMapBundle? bundle) {
  final subRegions = bundle?.subRegions ?? const <SubRegion>[];
  final labels = subRegions.isNotEmpty
      ? subRegions.map((s) => ZoneLabel(name: s.name, centerLat: s.centerLat, centerLng: s.centerLng))
      : seedZoneLabels;
  return MarkerLayer(markers: [
    for (final z in labels)
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
  ]);
}

/// The live OSM tile layer, shown only when [isOnline] — callers should
/// omit this entirely (not just hide it) when offline and instead set
/// `MapOptions.backgroundColor: AppColors.mapOfflineBase` so the boundary
/// polygons/labels/markers render on a clean flat canvas instead of
/// blank/broken tile squares.
Widget? reserveTileLayer(bool isOnline) {
  if (!isOnline) return null;
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.tygris.ranger',
  );
}
