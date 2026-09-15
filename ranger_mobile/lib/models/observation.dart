import '../core/sync_status.dart';

/// The 9 field-logging categories, used both mid-patrol (quick-log sheet)
/// and stand-alone (Quick Report).
enum ObservationType {
  wildlifeSighting,
  wildlifeSign,
  mortalityInjury,
  humanImpact,
  illegalActivity,
  conflict,
  fire,
  water,
  infrastructure,
  camera,
}

extension ObservationTypeX on ObservationType {
  static ObservationType fromName(String? name) =>
      ObservationType.values.firstWhere(
        (v) => v.name == name,
        orElse: () => ObservationType.wildlifeSighting,
      );
}

enum ObservationSeverity { info, low, medium, high, critical }

extension ObservationSeverityX on ObservationSeverity {
  static ObservationSeverity fromName(String? name) =>
      ObservationSeverity.values.firstWhere(
        (v) => v.name == name,
        orElse: () => ObservationSeverity.info,
      );
}

/// Design note: rather than build a near-duplicate "Report" entity, a
/// Report *is* an [Observation] with `patrolId == null` (an ad hoc field
/// entry not tied to an active patrol). The "Reports" screen is simply a
/// filtered view over the Observation store. Observations logged inside a
/// patrol instead carry a non-null [patrolId]. This keeps a single entity,
/// a single repository, and a single form (`quick_log_form_screen.dart`)
/// for both flows.
class Observation {
  Observation({
    required this.id,
    this.patrolId,
    required this.rangerId,
    required this.type,
    this.subtype,
    required this.severity,
    required this.description,
    required this.lat,
    required this.lng,
    required this.timestampMs,
    required this.photoIds,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.followUpRequired = false,
    this.zoneName,
    this.rangeName,
    this.nearestStationId,
    this.nearestStationDistanceM,
    this.distanceFromRouteM,
  });

  final String id;
  final String? patrolId;
  final String rangerId;
  final ObservationType type;
  final String? subtype;
  final ObservationSeverity severity;
  final String description;
  final double lat;
  final double lng;
  final int timestampMs;
  final List<String> photoIds;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Optional short title — mainly used for stand-alone Reports.
  final String? title;
  final bool followUpRequired;

  // --- Auto-attached context (computed once, at GPS-capture time, in
  // `quick_log_form_screen.dart` via `core/geo_context.dart`) — never
  // ranger-entered. All nullable because classification can fail to
  // resolve (e.g. no GIS bundle loaded yet, or truly no patrol route). ---

  /// 'CORE', 'BUFFER', or 'OUTSIDE' — see `geo_context.dart#classifyZone`.
  final String? zoneName;

  /// Name of the nearest reserve sub-region ("range"), by distance to its
  /// center — set even when [zoneName] is 'OUTSIDE'.
  final String? rangeName;

  /// `camera_id` of the nearest [GISStation] by haversine distance.
  final String? nearestStationId;
  final double? nearestStationDistanceM;

  /// Shortest distance from this observation to the active patrol's
  /// recorded route, in meters. Only set when [patrolId] is non-null
  /// (mid-patrol quick-log) — left `null` for stand-alone Quick Reports,
  /// never fabricated.
  final double? distanceFromRouteM;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  /// True when this observation was logged outside an active patrol
  /// (i.e. via the Quick Report flow) — see class doc.
  bool get isStandaloneReport => patrolId == null;

  Observation copyWith({
    SyncStatus? syncStatus,
    List<String>? photoIds,
    DateTime? updatedAt,
  }) =>
      Observation(
        id: id,
        patrolId: patrolId,
        rangerId: rangerId,
        type: type,
        subtype: subtype,
        severity: severity,
        description: description,
        lat: lat,
        lng: lng,
        timestampMs: timestampMs,
        photoIds: photoIds ?? this.photoIds,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        title: title,
        followUpRequired: followUpRequired,
        zoneName: zoneName,
        rangeName: rangeName,
        nearestStationId: nearestStationId,
        nearestStationDistanceM: nearestStationDistanceM,
        distanceFromRouteM: distanceFromRouteM,
      );

  factory Observation.fromJson(Map<String, dynamic> j) => Observation(
        id: j['id'] as String,
        patrolId: j['patrol_id'] as String?,
        rangerId: j['ranger_id'] as String,
        type: ObservationTypeX.fromName(j['type'] as String?),
        subtype: j['subtype'] as String?,
        severity: ObservationSeverityX.fromName(j['severity'] as String?),
        description: j['description'] as String? ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        timestampMs: j['timestamp_ms'] as int,
        photoIds: ((j['photo_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        syncStatus: SyncStatusX.fromName(j['sync_status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        title: j['title'] as String?,
        followUpRequired: j['follow_up_required'] as bool? ?? false,
        zoneName: j['zone_name'] as String?,
        rangeName: j['range_name'] as String?,
        nearestStationId: j['nearest_station_id'] as String?,
        nearestStationDistanceM: (j['nearest_station_distance_m'] as num?)?.toDouble(),
        distanceFromRouteM: (j['distance_from_route_m'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patrol_id': patrolId,
        'ranger_id': rangerId,
        'type': type.name,
        'subtype': subtype,
        'severity': severity.name,
        'description': description,
        'lat': lat,
        'lng': lng,
        'timestamp_ms': timestampMs,
        'photo_ids': photoIds,
        'sync_status': syncStatus.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'title': title,
        'follow_up_required': followUpRequired,
        'zone_name': zoneName,
        'range_name': rangeName,
        'nearest_station_id': nearestStationId,
        'nearest_station_distance_m': nearestStationDistanceM,
        'distance_from_route_m': distanceFromRouteM,
      };
}
