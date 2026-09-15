import '../core/sync_status.dart';

enum CameraInspectionStatus { ok, issue, replaced, collected }

extension CameraInspectionStatusX on CameraInspectionStatus {
  static CameraInspectionStatus fromName(String? name) =>
      CameraInspectionStatus.values.firstWhere(
        (v) => v.name == name,
        orElse: () => CameraInspectionStatus.ok,
      );
}

enum CameraActionTaken {
  none,
  replacedCard,
  replacedBattery,
  collectedCamera,
  repositioned,
  other,
}

extension CameraActionTakenX on CameraActionTaken {
  static CameraActionTaken fromName(String? name) =>
      CameraActionTaken.values.firstWhere(
        (v) => v.name == name,
        orElse: () => CameraActionTaken.none,
      );
}

/// A field inspection of a camera-trap station, referencing
/// [GISStation.cameraId] via [stationCameraId].
class CameraInspection {
  CameraInspection({
    required this.id,
    required this.stationCameraId,
    required this.rangerId,
    required this.timestampMs,
    this.batteryLevel,
    this.storageLevel,
    required this.status,
    this.issueNotes,
    this.maintenanceNotes,
    required this.photoIds,
    required this.actionTaken,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String stationCameraId;
  final String rangerId;
  final int timestampMs;

  /// 0-100, or null when unknown/not read.
  final int? batteryLevel;
  final int? storageLevel;
  final CameraInspectionStatus status;
  final String? issueNotes;
  final String? maintenanceNotes;
  final List<String> photoIds;
  final CameraActionTaken actionTaken;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  CameraInspection copyWith({
    SyncStatus? syncStatus,
    CameraInspectionStatus? status,
    List<String>? photoIds,
    DateTime? updatedAt,
  }) =>
      CameraInspection(
        id: id,
        stationCameraId: stationCameraId,
        rangerId: rangerId,
        timestampMs: timestampMs,
        batteryLevel: batteryLevel,
        storageLevel: storageLevel,
        status: status ?? this.status,
        issueNotes: issueNotes,
        maintenanceNotes: maintenanceNotes,
        photoIds: photoIds ?? this.photoIds,
        actionTaken: actionTaken,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  factory CameraInspection.fromJson(Map<String, dynamic> j) =>
      CameraInspection(
        id: j['id'] as String,
        stationCameraId: j['station_camera_id'] as String,
        rangerId: j['ranger_id'] as String,
        timestampMs: j['timestamp_ms'] as int,
        batteryLevel: j['battery_level'] as int?,
        storageLevel: j['storage_level'] as int?,
        status: CameraInspectionStatusX.fromName(j['status'] as String?),
        issueNotes: j['issue_notes'] as String?,
        maintenanceNotes: j['maintenance_notes'] as String?,
        photoIds: ((j['photo_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        actionTaken:
            CameraActionTakenX.fromName(j['action_taken'] as String?),
        syncStatus: SyncStatusX.fromName(j['sync_status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'station_camera_id': stationCameraId,
        'ranger_id': rangerId,
        'timestamp_ms': timestampMs,
        'battery_level': batteryLevel,
        'storage_level': storageLevel,
        'status': status.name,
        'issue_notes': issueNotes,
        'maintenance_notes': maintenanceNotes,
        'photo_ids': photoIds,
        'action_taken': actionTaken.name,
        'sync_status': syncStatus.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
