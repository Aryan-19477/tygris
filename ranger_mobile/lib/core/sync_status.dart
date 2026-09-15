import 'package:flutter/material.dart';
import 'theme.dart';

/// Lifecycle of any locally-created record on its way to the (future)
/// Supabase backend. Every entity the ranger creates carries one of these.
enum SyncStatus {
  /// Device has no connectivity / user forced "offline" in Settings.
  offline,

  /// Written to local storage, not yet queued for sync (rare — most writes
  /// immediately become [pendingSync]).
  local,

  /// Waiting in the [SyncQueueService] queue for the simulated worker.
  pendingSync,

  /// The simulated worker is actively "uploading" this record right now.
  syncing,

  /// Simulated upload succeeded.
  synced,

  /// Simulated upload failed; retryable from the sync queue sheet.
  failed,
}

extension SyncStatusX on SyncStatus {
  String labelKey() {
    switch (this) {
      case SyncStatus.offline:
        return 'sync.offline';
      case SyncStatus.local:
        return 'sync.local';
      case SyncStatus.pendingSync:
        return 'sync.pending';
      case SyncStatus.syncing:
        return 'sync.syncing';
      case SyncStatus.synced:
        return 'sync.synced';
      case SyncStatus.failed:
        return 'sync.failed';
    }
  }

  IconData get icon {
    switch (this) {
      case SyncStatus.offline:
        return Icons.cloud_off_rounded;
      case SyncStatus.local:
        return Icons.save_outlined;
      case SyncStatus.pendingSync:
        return Icons.schedule_rounded;
      case SyncStatus.syncing:
        return Icons.sync_rounded;
      case SyncStatus.synced:
        return Icons.cloud_done_rounded;
      case SyncStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case SyncStatus.offline:
        return AppColors.offline;
      case SyncStatus.local:
        return AppColors.offline;
      case SyncStatus.pendingSync:
        return AppColors.syncing;
      case SyncStatus.syncing:
        return AppColors.syncing;
      case SyncStatus.synced:
        return AppColors.synced;
      case SyncStatus.failed:
        return AppColors.syncFailed;
    }
  }

  Color get softColor {
    switch (this) {
      case SyncStatus.offline:
        return AppColors.offlineSoft;
      case SyncStatus.local:
        return AppColors.offlineSoft;
      case SyncStatus.pendingSync:
        return AppColors.syncingSoft;
      case SyncStatus.syncing:
        return AppColors.syncingSoft;
      case SyncStatus.synced:
        return AppColors.syncedSoft;
      case SyncStatus.failed:
        return AppColors.syncFailedSoft;
    }
  }

  static SyncStatus fromName(String? name) {
    return SyncStatus.values.firstWhere(
      (v) => v.name == name,
      orElse: () => SyncStatus.local,
    );
  }
}
