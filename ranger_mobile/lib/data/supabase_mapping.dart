/// Maps local Dart models (whose own `toJson()`/`fromJson()` use a *local*
/// on-device schema — see each model file) onto the Supabase table row
/// shape defined in `supabase/migrations/0001_ranger_ops.sql`. These two
/// shapes are intentionally different (local ids/keys predate the
/// Supabase schema) so every entity gets its own explicit mapping function
/// here rather than reusing `toJson()`.
///
/// Only [SyncQueueService] should call these — screens/repositories keep
/// talking to the local schema via each model's own `toJson`/`fromJson`.
library;

import '../models/camera_inspection.dart';
import '../models/observation.dart';
import '../models/patrol.dart';
import '../models/ranger.dart';
import '../models/task_item.dart';

Map<String, dynamic> rangerToSupabaseRow(Ranger r) => {
      'ranger_id': r.id,
      'name': r.name,
      'badge_number': r.badgeId,
      'phone': r.phone,
      'role': r.role.name,
      'team_id': r.teamId,
      'avatar_seed': r.avatarSeed,
      'default_beat': null,
    };

Map<String, dynamic> teamToSupabaseRow(Team t) => {
      'team_id': t.id,
      'team_name': t.name,
      'beat_or_zone': t.beatOrZone,
      'leader_ranger_id': null,
    };

List<Map<String, dynamic>> teamMembersToSupabaseRows(Team t) => t.memberIds
    .map((memberId) => {'team_id': t.id, 'ranger_id': memberId})
    .toList();

Map<String, dynamic> patrolToSupabaseRow(Patrol p) {
  final hasRoute = p.route.isNotEmpty;
  final start = hasRoute ? p.route.first : null;
  final end = hasRoute ? p.route.last : null;
  return {
    'patrol_id': p.id,
    'ranger_id': p.rangerId,
    'team_id': p.teamId,
    'patrol_type': p.patrolType.name,
    'patrol_method': p.method.name,
    'status': p.status.name,
    'start_time': p.startedAt.toIso8601String(),
    'end_time': p.endedAt?.toIso8601String(),
    'start_lat': start?.lat,
    'start_lon': start?.lng,
    'end_lat': end?.lat,
    'end_lon': end?.lng,
    'distance_km': p.distanceKm,
    'duration_seconds': p.durationSeconds,
    'coverage_area_km2': p.coverageAreaKm2,
    'notes': p.notes,
    'sync_status': p.syncStatus.name,
    'created_at': p.createdAt.toIso8601String(),
    'updated_at': p.updatedAt.toIso8601String(),
    'armed': false,
    'beat_area': null,
  };
}

/// One row per GPS point in [Patrol.route], for a bulk
/// `.upsert(list, onConflict: 'point_id')` into `gps_track_points`.
List<Map<String, dynamic>> patrolRouteToSupabaseRows(Patrol p) {
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < p.route.length; i++) {
    final point = p.route[i];
    rows.add({
      'point_id': '${p.id}_$i',
      'patrol_id': p.id,
      'lat': point.lat,
      'lon': point.lng,
      'altitude': point.altitude,
      'accuracy': point.accuracy,
      'timestamp':
          DateTime.fromMillisecondsSinceEpoch(point.timestampMs).toIso8601String(),
      'sequence_num': i,
    });
  }
  return rows;
}

Map<String, dynamic> observationToSupabaseRow(Observation o) => {
      'observation_id': o.id,
      'patrol_id': o.patrolId,
      'ranger_id': o.rangerId,
      // Kept as the model's camelCase enum name (e.g. "wildlifeSighting") —
      // the backend's polling logic matches this exact form.
      'obs_type': o.type.name,
      'species_category': o.subtype,
      'severity': o.severity.name,
      'lat': o.lat,
      'lon': o.lng,
      'timestamp': o.timestamp.toIso8601String(),
      'remarks': o.description,
      'sync_status': o.syncStatus.name,
      'created_at': o.createdAt.toIso8601String(),
      'structured_attrs': {
        'title': o.title,
        'follow_up_required': o.followUpRequired,
        // Auto-attached spatial context computed client-side at GPS-capture
        // time (`core/geo_context.dart`) — nested here rather than as its
        // own columns so no Supabase migration is needed (see
        // `supabase/migrations/0001_ranger_ops.sql`).
        'zone_name': o.zoneName,
        'range_name': o.rangeName,
        'nearest_station_id': o.nearestStationId,
        'nearest_station_distance_m': o.nearestStationDistanceM,
        'distance_from_route_m': o.distanceFromRouteM,
      },
    };

Map<String, dynamic> cameraInspectionToSupabaseRow(CameraInspection c) => {
      'inspection_id': c.id,
      'station_camera_id': c.stationCameraId,
      'ranger_id': c.rangerId,
      'timestamp':
          DateTime.fromMillisecondsSinceEpoch(c.timestampMs).toIso8601String(),
      'battery_level': c.batteryLevel,
      'storage_level': c.storageLevel,
      'status': c.status.name,
      'issue_notes': c.issueNotes,
      'maintenance_notes': c.maintenanceNotes,
      'action_taken': c.actionTaken.name,
      'sync_status': c.syncStatus.name,
    };

Map<String, dynamic> taskToSupabaseRow(TaskItem t) => {
      'task_id': t.id,
      'title': t.title,
      'instructions': t.instructions,
      'assigned_ranger_id': t.assignedRangerId,
      'lat': t.lat,
      'lon': t.lng,
      'location_label': t.locationLabel,
      'status': t.status.name,
      'due_at': t.dueAt?.toIso8601String(),
      'completed_at': t.completedAt?.toIso8601String(),
      'sync_status': t.syncStatus.name,
      'created_at': t.createdAt.toIso8601String(),
      'updated_at': t.updatedAt.toIso8601String(),
    };

/// Builds the `photos` row once the file has already been uploaded to
/// Supabase Storage (see `SyncQueueService._pushToSupabase`'s `'photo'`
/// case) — [storagePath]/[publicUrl] come from that upload, not from the
/// local [Photo] model. Exactly one of `observation_id`/`patrol_id`/
/// `camera_inspection_id` is set, based on `entityType`/`entityId` at the
/// call site (`'observation'`, `'patrol'`, `'camera_inspection'` are the
/// values used across `lib/screens`).
Map<String, dynamic> photoToSupabaseRow({
  required String photoId,
  required String entityType,
  required String entityId,
  required String storagePath,
  required String publicUrl,
  required DateTime capturedAt,
}) => {
      'photo_id': photoId,
      'storage_path': storagePath,
      'public_url': publicUrl,
      'lat': null,
      'lon': null,
      'timestamp': capturedAt.toIso8601String(),
      'observation_id': entityType == 'observation' ? entityId : null,
      'patrol_id': entityType == 'patrol' ? entityId : null,
      'camera_inspection_id':
          entityType == 'camera_inspection' ? entityId : null,
    };
