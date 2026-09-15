/// Shared GIS entities mirrored — field-for-field, key-for-key — from:
///   - `frontend-v2/src/lib/api.ts` (TypeScript source of truth, Admin web app)
///   - `tygris_mobile/lib/models/models.dart` (existing analyst/monitoring
///     Flutter app's Dart port of the same contract)
///
/// This file must stay schema-compatible with both so that, once Supabase
/// sync is wired up, all three clients (Admin web, tygris_mobile, and this
/// app) can read/write the same `camera_stations` / GIS rows without any
/// per-client translation layer. Do NOT invent a second, divergent
/// camera-station shape elsewhere in this app — every Ranger screen that
/// deals with camera stations consumes [GISStation] from this file.
library;

/// A camera-trap station, as surfaced by the reserve's GIS layer.
class GISStation {
  GISStation({
    required this.cameraId,
    required this.latitude,
    required this.longitude,
    this.gridId,
    required this.zone,
    this.subRegion,
    this.habitat,
    required this.operationalStatus,
    this.uptimeRatio,
    this.nearestWaterKm,
    this.nearestVillageKm,
    this.trailType,
  });

  final String cameraId;
  final double latitude;
  final double longitude;
  final String? gridId;
  final String zone;
  final String? subRegion;
  final String? habitat;
  final String operationalStatus;
  // Nullable: the real PTR camera-station dataset carries no live uptime
  // telemetry (it's a GPS/beat register, not a fleet-health feed) — the
  // Admin/backend contract still calls the field `uptime_ratio`, but it
  // comes back `null` for every real station, so we show "no data" rather
  // than fabricating "0% uptime".
  final double? uptimeRatio;
  final double? nearestWaterKm;
  final double? nearestVillageKm;
  final String? trailType;

  factory GISStation.fromJson(Map<String, dynamic> j) => GISStation(
        cameraId: j['camera_id'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        gridId: j['grid_id'] as String?,
        zone: j['zone'] as String? ?? '',
        subRegion: j['sub_region'] as String?,
        habitat: j['habitat'] as String?,
        operationalStatus: j['operational_status'] as String? ?? 'unknown',
        uptimeRatio: (j['uptime_ratio'] as num?)?.toDouble(),
        nearestWaterKm: (j['nearest_water_km'] as num?)?.toDouble(),
        nearestVillageKm: (j['nearest_village_km'] as num?)?.toDouble(),
        trailType: j['trail_type'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'camera_id': cameraId,
        'latitude': latitude,
        'longitude': longitude,
        'grid_id': gridId,
        'zone': zone,
        'sub_region': subRegion,
        'habitat': habitat,
        'operational_status': operationalStatus,
        'uptime_ratio': uptimeRatio,
        'nearest_water_km': nearestWaterKm,
        'nearest_village_km': nearestVillageKm,
        'trail_type': trailType,
      };
}

/// A tiger territory polygon, part of the map bundle.
class Territory {
  Territory({
    required this.tigerId,
    required this.name,
    required this.sex,
    required this.lifeStage,
    required this.centroid,
    required this.areaKm2,
    required this.polygon,
  });

  final String tigerId;
  final String name;
  final String sex;
  final String lifeStage;
  final List<double> centroid;
  final double areaKm2;
  final List<List<double>> polygon;

  factory Territory.fromJson(Map<String, dynamic> j) => Territory(
        tigerId: j['tiger_id'] as String,
        name: j['name'] as String? ?? '',
        sex: j['sex'] as String? ?? '',
        lifeStage: j['life_stage'] as String? ?? '',
        centroid: (j['centroid'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
        areaKm2: (j['area_km2'] as num?)?.toDouble() ?? 0,
        polygon: (j['polygon'] as List<dynamic>? ?? [])
            .map((e) => (e as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList(),
      );
}

/// A recent tiger sighting event, part of the map bundle.
class Sighting {
  Sighting({
    this.eventId,
    required this.tigerId,
    this.image,
    this.station,
    this.cameraId,
    this.latitude,
    this.longitude,
    this.zone,
    this.timestamp,
    this.alertLevel,
    this.threatReason,
    this.speedKmh,
  });

  final String? eventId;
  final String tigerId;
  final String? image;
  final String? station;
  final String? cameraId;
  final double? latitude;
  final double? longitude;
  final String? zone;
  final String? timestamp;
  final String? alertLevel;
  final String? threatReason;
  final double? speedKmh;

  factory Sighting.fromJson(Map<String, dynamic> j) => Sighting(
        eventId: j['event_id'] as String?,
        tigerId: j['tiger_id'] as String,
        image: j['image'] as String?,
        station: j['station'] as String?,
        cameraId: j['camera_id'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        zone: j['zone'] as String?,
        timestamp: j['timestamp'] as String?,
        alertLevel: j['alert_level'] as String?,
        threatReason: j['threat_reason'] as String?,
        speedKmh: (j['speed_kmh'] as num?)?.toDouble(),
      );
}

/// A reserve sub-region/zone, part of the map bundle — used by the Ranger
/// map to label zones instead of the hardcoded demo `seedZoneLabels`.
class SubRegion {
  SubRegion({
    required this.name,
    required this.zone,
    required this.centerLat,
    required this.centerLng,
    required this.areaKm2,
    this.habitat,
  });

  final String name;
  final String zone;
  final double centerLat;
  final double centerLng;
  final double areaKm2;
  final String? habitat;

  factory SubRegion.fromJson(Map<String, dynamic> j) {
    final center = (j['center'] as List<dynamic>? ?? [0, 0])
        .map((v) => (v as num).toDouble())
        .toList();
    return SubRegion(
      name: j['name'] as String? ?? '',
      zone: j['zone'] as String? ?? '',
      centerLat: center.isNotEmpty ? center[0] : 0,
      centerLng: center.length > 1 ? center[1] : 0,
      areaKm2: (j['area_km2'] as num?)?.toDouble() ?? 0,
      habitat: j['habitat'] as String?,
    );
  }
}

/// Full reserve GIS bundle: boundaries, sub-regions, stations, territories,
/// sightings — as returned by `GET /api/gis/bundle` on the shared FastAPI
/// backend (`backend/app/api/routes_gis.py`), the same endpoint
/// `frontend-v2`'s Admin map consumes.
class GISMapBundle {
  GISMapBundle({
    required this.reserve,
    required this.totalStations,
    required this.totalTigers,
    required this.coreAreaKm2,
    required this.bufferAreaKm2,
    required this.coreBoundary,
    required this.bufferBoundary,
    required this.subRegions,
    required this.stations,
    required this.territories,
    required this.recentSightings,
  });

  final String reserve;
  final int totalStations;
  final int totalTigers;
  final double coreAreaKm2;
  final double bufferAreaKm2;
  final List<List<double>> coreBoundary;
  final List<List<double>> bufferBoundary;
  final List<SubRegion> subRegions;
  final List<GISStation> stations;
  final List<Territory> territories;
  final List<Sighting> recentSightings;

  factory GISMapBundle.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'] as Map<String, dynamic>? ?? {};
    final territoriesJson = j['territories'] as Map<String, dynamic>? ?? {};
    return GISMapBundle(
      reserve: meta['reserve'] as String? ?? 'Pench Tiger Reserve',
      totalStations: meta['total_stations'] as int? ?? 0,
      totalTigers: meta['total_tigers'] as int? ?? 0,
      coreAreaKm2: (meta['core_area_km2'] as num?)?.toDouble() ?? 0,
      bufferAreaKm2: (meta['buffer_area_km2'] as num?)?.toDouble() ?? 0,
      coreBoundary: ((j['core_boundary'] as List<dynamic>?) ?? [])
          .map((e) => (e as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList(),
      bufferBoundary: ((j['buffer_boundary'] as List<dynamic>?) ?? [])
          .map((e) => (e as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList(),
      subRegions: ((j['sub_regions'] as List<dynamic>?) ?? [])
          .map((e) => SubRegion.fromJson(e as Map<String, dynamic>))
          .toList(),
      stations: ((j['stations'] as List<dynamic>?) ?? [])
          .map((e) => GISStation.fromJson(e as Map<String, dynamic>))
          .toList(),
      territories: territoriesJson.values
          .map((e) => Territory.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentSightings: ((j['recent_sightings'] as List<dynamic>?) ?? [])
          .map((e) => Sighting.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'metadata': {
          'reserve': reserve,
          'total_stations': totalStations,
          'total_tigers': totalTigers,
          'core_area_km2': coreAreaKm2,
          'buffer_area_km2': bufferAreaKm2,
        },
        'core_boundary': coreBoundary,
        'buffer_boundary': bufferBoundary,
        'sub_regions': subRegions
            .map((s) => {
                  'name': s.name,
                  'zone': s.zone,
                  'center': [s.centerLat, s.centerLng],
                  'area_km2': s.areaKm2,
                  'habitat': s.habitat,
                })
            .toList(),
        'stations': stations.map((s) => s.toJson()).toList(),
        'territories': {
          for (final t in territories)
            t.tigerId: {
              'tiger_id': t.tigerId,
              'name': t.name,
              'sex': t.sex,
              'life_stage': t.lifeStage,
              'centroid': t.centroid,
              'area_km2': t.areaKm2,
              'polygon': t.polygon,
            },
        },
        'recent_sightings': [],
      };
}

/// Lightweight zone / sub-region label used to give the Ranger map context
/// even without a live GIS bundle. Not part of the frontend-v2 contract —
/// purely a Ranger-app convenience derived from station `zone`/`sub_region`
/// strings, kept here alongside the models it decorates.
class ZoneLabel {
  ZoneLabel({required this.name, required this.centerLat, required this.centerLng});
  final String name;
  final double centerLat;
  final double centerLng;
}
