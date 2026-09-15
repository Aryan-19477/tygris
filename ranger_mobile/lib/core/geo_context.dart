/// Pure-Dart, fully-offline spatial helpers used to auto-attach "where does
/// this observation sit relative to the reserve" context (range/zone,
/// nearest camera station, distance from the active patrol route) the
/// moment GPS is captured — see `quick_log_form_screen.dart`.
///
/// Ported from the same reference logic the backend simulation already
/// implements in `backend/app/simulation/pench_environment.py`
/// (`is_point_in_polygon`, `haversine_distance_km`, `classify_zone`,
/// `get_nearest_sub_region`) so the two stay conceptually in sync, without
/// this app ever calling the backend for it.
library;

import 'dart:math' as math;

import '../models/gps_point.dart';
import '../models/shared_gis.dart';

/// Result of classifying a lat/lng against the reserve's Core/Buffer
/// boundaries and sub-regions ("ranges").
class ZoneClassification {
  ZoneClassification({required this.zone, this.rangeName});

  /// 'CORE', 'BUFFER', or 'OUTSIDE' (point falls in neither boundary).
  final String zone;

  /// Name of the nearest sub-region ("range"), if any sub-regions are
  /// known — set even when [zone] is 'OUTSIDE' (nearest range by
  /// distance), per the "handle gracefully" requirement.
  final String? rangeName;
}

/// Nearest camera station to a point, with its distance.
class NearestStationResult {
  NearestStationResult({required this.station, required this.distanceKm});
  final GISStation station;
  final double distanceKm;
}

/// Ray-casting point-in-polygon test. `polygon` is a list of `[lat, lng]`
/// pairs, matching the shape stored in [GISMapBundle.coreBoundary] /
/// [GISMapBundle.bufferBoundary]. Direct port of
/// `is_point_in_polygon` in `pench_environment.py`.
bool isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
  if (polygon.length < 3) return false;
  final n = polygon.length;
  var inside = false;
  var p1x = polygon[0][1];
  var p1y = polygon[0][0];
  for (var i = 0; i <= n; i++) {
    final p2x = polygon[i % n][1];
    final p2y = polygon[i % n][0];
    if (math.min(p1y, p2y) < lat && lat <= math.max(p1y, p2y)) {
      if (lng <= math.max(p1x, p2x)) {
        double xinters = p1x;
        if (p1y != p2y) {
          xinters = (lat - p1y) * (p2x - p1x) / (p2y - p1y) + p1x;
        }
        if (p1x == p2x || lng <= xinters) {
          inside = !inside;
        }
      }
    }
    p1x = p2x;
    p1y = p2y;
  }
  return inside;
}

/// Great-circle distance in kilometers. Direct port of
/// `haversine_distance_km` in `pench_environment.py`.
double haversineDistanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final phi1 = lat1 * math.pi / 180.0;
  final phi2 = lat2 * math.pi / 180.0;
  final dPhi = (lat2 - lat1) * math.pi / 180.0;
  final dLambda = (lng2 - lng1) * math.pi / 180.0;
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
}

/// Classifies a point into CORE / BUFFER / OUTSIDE against the bundle's
/// boundaries, and finds the nearest named range (sub-region) by distance
/// to its center — mirrors `PenchEnvironment.classify_zone` +
/// `get_nearest_sub_region`.
ZoneClassification classifyZone({
  required double lat,
  required double lng,
  required List<List<double>> coreBoundary,
  required List<List<double>> bufferBoundary,
  required List<SubRegion> subRegions,
}) {
  String zone = 'OUTSIDE';
  if (isPointInPolygon(lat, lng, coreBoundary)) {
    zone = 'CORE';
  } else if (isPointInPolygon(lat, lng, bufferBoundary)) {
    zone = 'BUFFER';
  }

  String? rangeName;
  var bestDistance = double.infinity;
  for (final sr in subRegions) {
    final d = haversineDistanceKm(lat, lng, sr.centerLat, sr.centerLng);
    if (d < bestDistance) {
      bestDistance = d;
      rangeName = sr.name;
    }
  }
  return ZoneClassification(zone: zone, rangeName: rangeName);
}

/// Finds the nearest [GISStation] to a point by haversine distance, or
/// `null` when [stations] is empty.
NearestStationResult? findNearestStation({
  required double lat,
  required double lng,
  required List<GISStation> stations,
}) {
  GISStation? best;
  var bestDistance = double.infinity;
  for (final s in stations) {
    final d = haversineDistanceKm(lat, lng, s.latitude, s.longitude);
    if (d < bestDistance) {
      bestDistance = d;
      best = s;
    }
  }
  if (best == null) return null;
  return NearestStationResult(station: best, distanceKm: bestDistance);
}

/// Shortest distance in meters from a point to the active patrol's
/// recorded route, as true point-to-segment distance against every leg of
/// the polyline (not just the nearest recorded vertex) — accurate enough
/// given the route is many closely-spaced GPS fixes, while still being
/// cheap (single pass, no external geometry package).
///
/// Distances are computed on a local flat projection (equirectangular,
/// centered on the observation point) rather than true geodesics — over
/// the few-hundred-meter scale of "distance from route" this is well
/// within GPS accuracy and avoids much more expensive spherical
/// point-to-segment math. Returns `null` for an empty route.
double? distanceFromRouteMeters({
  required double lat,
  required double lng,
  required List<GPSPoint> route,
}) {
  if (route.isEmpty) return null;

  // Meters-per-degree at this latitude, for the local projection.
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = 111320.0 * math.cos(lat * math.pi / 180.0);

  double toX(double pointLng) => (pointLng - lng) * metersPerDegLng;
  double toY(double pointLat) => (pointLat - lat) * metersPerDegLat;

  if (route.length == 1) {
    final dx = toX(route.first.lng);
    final dy = toY(route.first.lat);
    return math.sqrt(dx * dx + dy * dy);
  }

  var best = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    final ax = toX(route[i].lng);
    final ay = toY(route[i].lat);
    final bx = toX(route[i + 1].lng);
    final by = toY(route[i + 1].lat);
    final d = _pointToSegmentDistance(0, 0, ax, ay, bx, by);
    if (d < best) best = d;
  }
  return best;
}

/// Standard point-to-segment distance in a flat plane: projects `(px,py)`
/// onto the segment `a`-`b`, clamped to the segment's extent.
double _pointToSegmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final abx = bx - ax;
  final aby = by - ay;
  final lengthSq = abx * abx + aby * aby;
  double t = 0;
  if (lengthSq > 0) {
    t = (((px - ax) * abx) + ((py - ay) * aby)) / lengthSq;
    t = t.clamp(0.0, 1.0);
  }
  final cx = ax + t * abx;
  final cy = ay + t * aby;
  final dx = px - cx;
  final dy = py - cy;
  return math.sqrt(dx * dx + dy * dy);
}
