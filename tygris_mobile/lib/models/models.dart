/// Data models mirroring frontend-v2/src/lib/api.ts 1:1 so the mobile app
/// speaks the exact same backend contract as the web dashboard.
library;

class Candidate {
  Candidate({required this.tigerId, required this.similarity});

  final String tigerId;
  final double similarity;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        tigerId: j['tiger_id'] as String,
        similarity: (j['similarity'] as num).toDouble(),
      );
}

class IdentifyResult {
  IdentifyResult({
    required this.decision,
    required this.status,
    required this.tigerId,
    required this.predictedTigerId,
    required this.confidence,
    required this.candidates,
    required this.gallerySize,
    this.autoAcceptThreshold,
    this.reviewFloor,
    required this.uploadedImage,
    this.stationId,
    this.recordedEventId,
    this.recordedStatus,
  });

  final String decision; // auto_match | needs_review
  final String status; // KNOWN | UNKNOWN_CANDIDATE
  final String? tigerId;
  final String? predictedTigerId;
  final double confidence;
  final List<Candidate> candidates;
  final int gallerySize;
  final double? autoAcceptThreshold;
  final double? reviewFloor;
  final String uploadedImage;
  final String? stationId;
  final String? recordedEventId;
  final String? recordedStatus;

  factory IdentifyResult.fromJson(Map<String, dynamic> j) => IdentifyResult(
        decision: j['decision'] as String,
        status: j['status'] as String,
        tigerId: j['tiger_id'] as String?,
        predictedTigerId: j['predicted_tiger_id'] as String?,
        confidence: (j['confidence'] as num).toDouble(),
        candidates: (j['candidates'] as List<dynamic>? ?? [])
            .map((e) => Candidate.fromJson(e as Map<String, dynamic>))
            .toList(),
        gallerySize: j['gallery_size'] as int? ?? 0,
        autoAcceptThreshold: (j['auto_accept_threshold'] as num?)?.toDouble(),
        reviewFloor: (j['review_floor'] as num?)?.toDouble(),
        uploadedImage: j['uploaded_image'] as String? ?? '',
        stationId: j['station_id'] as String?,
        recordedEventId: j['recorded_event_id'] as String?,
        recordedStatus: j['recorded_status'] as String?,
      );
}

class GalleryIndividual {
  GalleryIndividual({
    required this.tigerId,
    this.name,
    this.sex,
    this.ageYears,
    this.lifeStage,
    this.territorialStatus,
    this.mcpAreaKm2,
    required this.numCaptures,
    required this.stations,
    this.lastSeen,
    this.thumbnail,
  });

  final String tigerId;
  final String? name;
  final String? sex;
  final double? ageYears;
  final String? lifeStage;
  final String? territorialStatus;
  final double? mcpAreaKm2;
  final int numCaptures;
  final List<String> stations;
  final String? lastSeen;
  final String? thumbnail;

  factory GalleryIndividual.fromJson(Map<String, dynamic> j) =>
      GalleryIndividual(
        tigerId: j['tiger_id'] as String,
        name: j['name'] as String?,
        sex: j['sex'] as String?,
        ageYears: (j['age_years'] as num?)?.toDouble(),
        lifeStage: j['life_stage'] as String?,
        territorialStatus: j['territorial_status'] as String?,
        mcpAreaKm2: (j['mcp_area_km2'] as num?)?.toDouble(),
        numCaptures: j['num_captures'] as int? ?? 0,
        stations: (j['stations'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        lastSeen: j['last_seen'] as String?,
        thumbnail: j['thumbnail'] as String?,
      );
}

class GalleryProfile {
  GalleryProfile({
    required this.tigerId,
    required this.name,
    required this.sex,
    required this.ageYears,
    required this.lifeStage,
    required this.territorialStatus,
    required this.homeRangeTargetKm2,
    required this.mcpAreaKm2,
    required this.coreCentroidLat,
    required this.coreCentroidLon,
    this.thumbnail,
    this.totalCaptures,
  });

  final String tigerId;
  final String name;
  final String sex;
  final double ageYears;
  final String lifeStage;
  final String territorialStatus;
  final double homeRangeTargetKm2;
  final double mcpAreaKm2;
  final double coreCentroidLat;
  final double coreCentroidLon;
  final String? thumbnail;
  final int? totalCaptures;

  factory GalleryProfile.fromJson(Map<String, dynamic> j) => GalleryProfile(
        tigerId: j['tiger_id'] as String,
        name: j['name'] as String? ?? j['tiger_id'] as String,
        sex: j['sex'] as String? ?? '',
        ageYears: (j['age_years'] as num?)?.toDouble() ?? 0,
        lifeStage: j['life_stage'] as String? ?? '',
        territorialStatus: j['territorial_status'] as String? ?? '',
        homeRangeTargetKm2:
            (j['home_range_target_km2'] as num?)?.toDouble() ?? 0,
        mcpAreaKm2: (j['mcp_area_km2'] as num?)?.toDouble() ?? 0,
        coreCentroidLat: (j['core_centroid_lat'] as num?)?.toDouble() ?? 0,
        coreCentroidLon: (j['core_centroid_lon'] as num?)?.toDouble() ?? 0,
        thumbnail: j['thumbnail'] as String?,
        totalCaptures: j['total_captures'] as int?,
      );
}

class CaptureRecord {
  CaptureRecord({
    this.eventId,
    this.image,
    this.station,
    this.cameraId,
    this.latitude,
    this.longitude,
    this.zone,
    this.flankSide,
    this.timestamp,
    this.alertLevel,
    this.speedKmh,
  });

  final String? eventId;
  final String? image;
  final String? station;
  final String? cameraId;
  final double? latitude;
  final double? longitude;
  final String? zone;
  final String? flankSide;
  final String? timestamp;
  final String? alertLevel;
  final double? speedKmh;

  factory CaptureRecord.fromJson(Map<String, dynamic> j) => CaptureRecord(
        eventId: j['event_id'] as String?,
        image: j['image'] as String?,
        station: j['station'] as String?,
        cameraId: j['camera_id'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        zone: j['zone'] as String?,
        flankSide: j['flank_side'] as String?,
        timestamp: j['timestamp'] as String?,
        alertLevel: j['alert_level'] as String?,
        speedKmh: (j['speed_kmh'] as num?)?.toDouble(),
      );
}

class GalleryDetail {
  GalleryDetail({
    this.profile,
    this.tigerId,
    required this.captures,
    this.trajectory,
  });

  final GalleryProfile? profile;
  final String? tigerId;
  final List<CaptureRecord> captures;
  final List<List<double>>? trajectory;

  factory GalleryDetail.fromJson(Map<String, dynamic> j) => GalleryDetail(
        profile: j['profile'] != null
            ? GalleryProfile.fromJson(j['profile'] as Map<String, dynamic>)
            : null,
        tigerId: j['tiger_id'] as String?,
        captures: (j['captures'] as List<dynamic>? ?? [])
            .map((e) => CaptureRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        trajectory: (j['trajectory'] as List<dynamic>?)
            ?.map((e) => (e as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList(),
      );
}

class ReviewQueueItem {
  ReviewQueueItem({
    required this.itemId,
    this.timestamp,
    this.stationId,
    this.zone,
    required this.candidates,
    this.uploadedImage,
    this.reason,
    this.nearestDistance,
  });

  final String itemId;
  final String? timestamp;
  final String? stationId;
  final String? zone;
  final List<Candidate> candidates;
  final String? uploadedImage;
  final String? reason;
  final double? nearestDistance;

  factory ReviewQueueItem.fromJson(Map<String, dynamic> j) => ReviewQueueItem(
        itemId: j['item_id'] as String,
        timestamp: j['timestamp'] as String?,
        stationId: j['station_id'] as String?,
        zone: j['zone'] as String?,
        candidates: (j['candidates'] as List<dynamic>? ?? [])
            .map((e) => Candidate.fromJson(e as Map<String, dynamic>))
            .toList(),
        uploadedImage: j['uploaded_image'] as String?,
        reason: j['reason'] as String?,
        nearestDistance: (j['nearest_distance'] as num?)?.toDouble(),
      );
}

class DashboardStats {
  DashboardStats({
    required this.totalIndividuals,
    this.totalStations,
    this.activeStations,
    required this.totalCaptures,
    required this.pendingReview,
    this.criticalAlerts,
    this.cautionAlerts,
    this.trapNightsSimulated,
    this.coreAreaKm2,
    this.bufferAreaKm2,
    this.stations,
  });

  final int totalIndividuals;
  final int? totalStations;
  final int? activeStations;
  final int totalCaptures;
  final int pendingReview;
  final int? criticalAlerts;
  final int? cautionAlerts;
  final double? trapNightsSimulated;
  final double? coreAreaKm2;
  final double? bufferAreaKm2;
  final List<String>? stations;

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        totalIndividuals: j['total_individuals'] as int? ?? 0,
        totalStations: j['total_stations'] as int?,
        activeStations: j['active_stations'] as int?,
        totalCaptures: j['total_captures'] as int? ?? 0,
        pendingReview: j['pending_review'] as int? ?? 0,
        criticalAlerts: j['critical_alerts'] as int?,
        cautionAlerts: j['caution_alerts'] as int?,
        trapNightsSimulated: (j['trap_nights_simulated'] as num?)?.toDouble(),
        coreAreaKm2: (j['core_area_km2'] as num?)?.toDouble(),
        bufferAreaKm2: (j['buffer_area_km2'] as num?)?.toDouble(),
        stations: (j['stations'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );
}

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
    required this.uptimeRatio,
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
  final double uptimeRatio;
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
        uptimeRatio: (j['uptime_ratio'] as num?)?.toDouble() ?? 0,
        nearestWaterKm: (j['nearest_water_km'] as num?)?.toDouble(),
        nearestVillageKm: (j['nearest_village_km'] as num?)?.toDouble(),
        trailType: j['trail_type'] as String?,
      );
}

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

class GISMapBundle {
  GISMapBundle({
    required this.reserve,
    required this.totalStations,
    required this.totalTigers,
    required this.coreAreaKm2,
    required this.bufferAreaKm2,
    required this.coreBoundary,
    required this.bufferBoundary,
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
  final List<GISStation> stations;
  final List<Territory> territories;
  final List<Sighting> recentSightings;

  factory GISMapBundle.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'] as Map<String, dynamic>? ?? {};
    final territoriesJson =
        j['territories'] as Map<String, dynamic>? ?? {};
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
}

class ModelStatus {
  ModelStatus({
    required this.isFullyTrained,
    required this.weightsLoaded,
    required this.checkpointsDir,
  });

  final bool isFullyTrained;
  final Map<String, bool> weightsLoaded;
  final String checkpointsDir;

  factory ModelStatus.fromJson(Map<String, dynamic> j) => ModelStatus(
        isFullyTrained: j['is_fully_trained'] as bool? ?? false,
        weightsLoaded: (j['weights_loaded'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v as bool)),
        checkpointsDir: j['checkpoints_dir'] as String? ?? '',
      );
}
