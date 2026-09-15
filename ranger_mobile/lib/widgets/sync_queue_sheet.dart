import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/sync_status.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../models/sync_queue_item.dart';
import '../services/sync_queue_service.dart';
import 'common.dart';

String _entityLabelKey(String entityType) {
  switch (entityType) {
    case 'patrol':
      return 'history.patrols';
    case 'observation':
      return 'report.title';
    case 'camera_inspection':
      return 'history.inspections';
    case 'task':
      return 'history.tasks';
    case 'sos':
      return 'home.sos';
    default:
      return 'common.unknown';
  }
}

/// Bottom sheet listing the sync queue — opened by tapping the sync status
/// chip on Home's top bar. Shows pending/syncing/failed items with a
/// "retry all" action.
class SyncQueueSheet extends ConsumerWidget {
  const SyncQueueSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SyncQueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appLocalizationsProvider);
    final stateAsync = ref.watch(syncQueueStateProvider);
    final service = ref.read(syncQueueServiceProvider);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpace.md),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: stateAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpace.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Padding(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: Text('$e'),
          ),
          data: (state) {
            final items = [...state.items]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.t('sync.queueTitle'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (state.failedCount > 0)
                        TextButton(
                          onPressed: () => service.retryAllFailed(),
                          child: Text(l10n.t('sync.retryAll')),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  child: Row(
                    children: [
                      StatusPill(
                        label: l10n.t('sync.pendingCount',
                            {'count': '${state.pendingCount}'}),
                        color: AppColors.syncing,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      if (state.failedCount > 0)
                        StatusPill(
                          label: l10n.t('sync.failedCount',
                              {'count': '${state.failedCount}'}),
                          color: AppColors.syncFailed,
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Divider(height: 1),
                ),
                Flexible(
                  child: items.isEmpty
                      ? EmptyState(message: l10n.t('sync.empty'))
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg, vertical: AppSpace.sm),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 0),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            return _QueueRow(item: item, l10n: l10n);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    l10n.t('sync.disclaimer'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.item, required this.l10n});
  final SyncQueueItem item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(syncQueueServiceProvider);
    final timeStr = DateFormat('MMM d, HH:mm').format(item.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.priority > 0)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.priority_high_rounded,
                            size: 14, color: AppColors.sos),
                      ),
                    Text(
                      l10n.t(_entityLabelKey(item.entityType)),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(timeStr,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.muted)),
                if (item.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.lastError!,
                      style: const TextStyle(color: AppColors.syncFailed, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          SyncStatusChip(status: item.status, l10n: l10n),
          if (item.status == SyncStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => service.retryOne(item.id),
            ),
        ],
      ),
    );
  }
}
