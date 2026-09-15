import '../core/sync_status.dart';

enum TaskStatus { assigned, inProgress, completed }

extension TaskStatusX on TaskStatus {
  static TaskStatus fromName(String? name) => TaskStatus.values.firstWhere(
        (v) => v.name == name,
        orElse: () => TaskStatus.assigned,
      );
}

/// Named `TaskItem` (not `Task`) purely for clarity against `dart:async`'s
/// vocabulary and Flutter's own widget-tree naming conventions.
class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    required this.instructions,
    required this.assignedRangerId,
    this.lat,
    this.lng,
    this.locationLabel,
    required this.status,
    this.dueAt,
    required this.evidencePhotoIds,
    this.completedAt,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String instructions;
  final String assignedRangerId;
  final double? lat;
  final double? lng;
  final String? locationLabel;
  final TaskStatus status;
  final DateTime? dueAt;
  final List<String> evidencePhotoIds;
  final DateTime? completedAt;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasLocation => lat != null && lng != null;

  TaskItem copyWith({
    TaskStatus? status,
    List<String>? evidencePhotoIds,
    DateTime? completedAt,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) =>
      TaskItem(
        id: id,
        title: title,
        instructions: instructions,
        assignedRangerId: assignedRangerId,
        lat: lat,
        lng: lng,
        locationLabel: locationLabel,
        status: status ?? this.status,
        dueAt: dueAt,
        evidencePhotoIds: evidencePhotoIds ?? this.evidencePhotoIds,
        completedAt: completedAt ?? this.completedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        instructions: j['instructions'] as String? ?? '',
        assignedRangerId: j['assigned_ranger_id'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        locationLabel: j['location_label'] as String?,
        status: TaskStatusX.fromName(j['status'] as String?),
        dueAt:
            j['due_at'] != null ? DateTime.parse(j['due_at'] as String) : null,
        evidencePhotoIds: ((j['evidence_photo_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'] as String)
            : null,
        syncStatus: SyncStatusX.fromName(j['sync_status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'instructions': instructions,
        'assigned_ranger_id': assignedRangerId,
        'lat': lat,
        'lng': lng,
        'location_label': locationLabel,
        'status': status.name,
        'due_at': dueAt?.toIso8601String(),
        'evidence_photo_ids': evidencePhotoIds,
        'completed_at': completedAt?.toIso8601String(),
        'sync_status': syncStatus.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
