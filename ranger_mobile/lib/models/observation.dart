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
      };
}
