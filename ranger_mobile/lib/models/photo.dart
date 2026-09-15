import '../core/sync_status.dart';

/// A captured photo's metadata. The actual image bytes stay on-device at
/// [localPath] (local-first) — only this metadata record is "synced" in
/// the simulation, mirroring how a real Supabase Storage integration would
/// upload the file separately from the row that references it.
class Photo {
  Photo({
    required this.id,
    required this.localPath,
    required this.entityType,
    required this.entityId,
    required this.capturedAt,
    required this.syncStatus,
  });

  final String id;
  final String localPath;
  final String entityType;
  final String entityId;
  final DateTime capturedAt;
  final SyncStatus syncStatus;

  Photo copyWith({SyncStatus? syncStatus}) => Photo(
        id: id,
        localPath: localPath,
        entityType: entityType,
        entityId: entityId,
        capturedAt: capturedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
        id: j['id'] as String,
        localPath: j['local_path'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        capturedAt: DateTime.parse(j['captured_at'] as String),
        syncStatus: SyncStatusX.fromName(j['sync_status'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'local_path': localPath,
        'entity_type': entityType,
        'entity_id': entityId,
        'captured_at': capturedAt.toIso8601String(),
        'sync_status': syncStatus.name,
      };
}
