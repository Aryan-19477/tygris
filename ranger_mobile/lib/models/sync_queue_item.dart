import '../core/sync_status.dart';

enum SyncAction { create, update }

extension SyncActionX on SyncAction {
  static SyncAction fromName(String? name) => SyncAction.values.firstWhere(
        (v) => v.name == name,
        orElse: () => SyncAction.create,
      );
}

/// One entry in the simulated outbound sync queue. See
/// `lib/services/sync_queue_service.dart` for the worker that drains these.
class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.createdAt,
    required this.status,
    this.retryCount = 0,
    this.lastError,
    this.priority = 0,
  });

  final String id;
  final String entityType;
  final String entityId;
  final SyncAction action;
  final DateTime createdAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;

  /// Higher priority items (e.g. SOS alerts) sync first. 0 = normal.
  final int priority;

  SyncQueueItem copyWith({
    SyncStatus? status,
    int? retryCount,
    String? lastError,
  }) =>
      SyncQueueItem(
        id: id,
        entityType: entityType,
        entityId: entityId,
        action: action,
        createdAt: createdAt,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
        priority: priority,
      );

  factory SyncQueueItem.fromJson(Map<String, dynamic> j) => SyncQueueItem(
        id: j['id'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        action: SyncActionX.fromName(j['action'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        status: SyncStatusX.fromName(j['status'] as String?),
        retryCount: j['retry_count'] as int? ?? 0,
        lastError: j['last_error'] as String?,
        priority: j['priority'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action.name,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'retry_count': retryCount,
        'last_error': lastError,
        'priority': priority,
      };
}
