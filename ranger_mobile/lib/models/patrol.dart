import '../core/sync_status.dart';
import 'gps_point.dart';

enum PatrolType { foot, vehicle, boat, bicycle }

extension PatrolTypeX on PatrolType {
  static PatrolType fromName(String? name) => PatrolType.values.firstWhere(
        (v) => v.name == name,
        orElse: () => PatrolType.foot,
      );
}

enum PatrolMethod { routine, targeted, response }

extension PatrolMethodX on PatrolMethod {
  static PatrolMethod fromName(String? name) =>
      PatrolMethod.values.firstWhere(
        (v) => v.name == name,
        orElse: () => PatrolMethod.routine,
      );
}

enum PatrolStatus { notStarted, active, paused, completed }

extension PatrolStatusX on PatrolStatus {
  static PatrolStatus fromName(String? name) =>
      PatrolStatus.values.firstWhere(
        (v) => v.name == name,
        orElse: () => PatrolStatus.notStarted,
      );
}

/// A ranger patrol — foot/vehicle/boat/bicycle — tracked start to finish
/// with a growing GPS route and any [Observation]s logged along the way
/// (referenced by id in [observationIds]).
class Patrol {
  Patrol({
    required this.id,
    required this.rangerId,
    this.teamId,
    required this.patrolType,
    required this.method,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.route,
    required this.distanceKm,
    required this.durationSeconds,
    required this.observationIds,
    this.coverageAreaKm2,
    this.notes,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String rangerId;
  final String? teamId;
  final PatrolType patrolType;
  final PatrolMethod method;
  final PatrolStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<GPSPoint> route;
  final double distanceKm;
  final int durationSeconds;
  final List<String> observationIds;
  final double? coverageAreaKm2;
  final String? notes;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  Patrol copyWith({
    PatrolStatus? status,
    DateTime? endedAt,
    List<GPSPoint>? route,
    double? distanceKm,
    int? durationSeconds,
    List<String>? observationIds,
    double? coverageAreaKm2,
    String? notes,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) =>
      Patrol(
        id: id,
        rangerId: rangerId,
        teamId: teamId,
        patrolType: patrolType,
        method: method,
        status: status ?? this.status,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        route: route ?? this.route,
        distanceKm: distanceKm ?? this.distanceKm,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        observationIds: observationIds ?? this.observationIds,
        coverageAreaKm2: coverageAreaKm2 ?? this.coverageAreaKm2,
        notes: notes ?? this.notes,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  factory Patrol.fromJson(Map<String, dynamic> j) => Patrol(
        id: j['id'] as String,
        rangerId: j['ranger_id'] as String,
        teamId: j['team_id'] as String?,
        patrolType: PatrolTypeX.fromName(j['patrol_type'] as String?),
        method: PatrolMethodX.fromName(j['method'] as String?),
        status: PatrolStatusX.fromName(j['status'] as String?),
        startedAt: DateTime.parse(j['started_at'] as String),
        endedAt: j['ended_at'] != null
            ? DateTime.parse(j['ended_at'] as String)
            : null,
        route: ((j['route'] as List<dynamic>?) ?? [])
            .map((e) => GPSPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
        durationSeconds: j['duration_seconds'] as int? ?? 0,
        observationIds: ((j['observation_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        coverageAreaKm2: (j['coverage_area_km2'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
        syncStatus: SyncStatusX.fromName(j['sync_status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ranger_id': rangerId,
        'team_id': teamId,
        'patrol_type': patrolType.name,
        'method': method.name,
        'status': status.name,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'route': route.map((e) => e.toJson()).toList(),
        'distance_km': distanceKm,
        'duration_seconds': durationSeconds,
        'observation_ids': observationIds,
        'coverage_area_km2': coverageAreaKm2,
        'notes': notes,
        'sync_status': syncStatus.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
