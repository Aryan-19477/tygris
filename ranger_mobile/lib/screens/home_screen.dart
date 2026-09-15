import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/app_shell.dart';
import '../core/ids.dart';
import '../core/observation_meta.dart';
import '../core/sync_status.dart';
import '../core/theme.dart';
import '../data/repository.dart';
import '../l10n/app_localizations.dart';
import '../models/observation.dart';
import '../models/patrol.dart';
import '../models/sync_queue_item.dart';
import '../models/task_item.dart';
import '../services/active_patrol_controller.dart';
import '../services/location_status.dart';
import '../services/sync_queue_service.dart';
import '../widgets/common.dart';
import '../widgets/observation_detail_sheet.dart';
import '../widgets/sync_queue_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appLocalizationsProvider);
    final ranger = ref.watch(currentRangerProvider);
    final activePatrol = ref.watch(activePatrolControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TopBar(l10n: l10n),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxxl),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    l10n.t('home.greeting'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  Text(
                    ranger?.name ?? l10n.t('home.title'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _PatrolActionCard(l10n: l10n, activePatrol: activePatrol),
                  const SizedBox(height: AppSpace.xl),
                  _QuickActionGrid(l10n: l10n),
                  const SizedBox(height: AppSpace.xl),
                  SectionLabel(l10n.t('home.recentActivity')),
                  const SizedBox(height: AppSpace.sm),
                  _RecentActivity(l10n: l10n),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpsAsync = ref.watch(gpsReadyProvider);
    final syncStateAsync = ref.watch(syncQueueStateProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
      child: Row(
        children: [
          gpsAsync.when(
            loading: () => StatusPill(
              label: l10n.t('home.gpsAcquiring'),
              color: AppColors.muted,
              icon: Icons.gps_not_fixed_rounded,
            ),
            error: (_, __) => StatusPill(
              label: l10n.t('home.gpsAcquiring'),
              color: AppColors.muted,
              icon: Icons.gps_not_fixed_rounded,
            ),
            data: (ready) => StatusPill(
              label: ready ? l10n.t('home.gpsLocked') : l10n.t('home.gpsAcquiring'),
              color: ready ? AppColors.positive : AppColors.caution,
              icon: ready ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => SyncQueueSheet.show(context),
              child: syncStateAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (s) {
                  final label = s.failedCount > 0
                      ? l10n.t('sync.failedCount', {'count': '${s.failedCount}'})
                      : s.pendingCount > 0
                          ? l10n.t('sync.pendingCount', {'count': '${s.pendingCount}'})
                          : l10n.t('sync.allSynced');
                  final color = s.failedCount > 0
                      ? AppColors.syncFailed
                      : s.isSyncing
                          ? AppColors.syncing
                          : AppColors.synced;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(
                      label: label,
                      color: color,
                      icon: s.isSyncing ? Icons.sync_rounded : Icons.cloud_done_rounded,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          const _SosButton(),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _SosButton extends ConsumerStatefulWidget {
  const _SosButton();

  @override
  ConsumerState<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<_SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _sendSos();
        _holdController.reset();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _sendSos() async {
    final l10n = ref.read(appLocalizationsProvider);
    await ref.read(syncQueueServiceProvider).enqueue(
          entityType: 'sos',
          entityId: newId(),
          action: SyncAction.create,
          priority: 100,
        );
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.sos, size: 36),
        title: Text(l10n.t('home.sosSent')),
        content: Text(l10n.t('home.sosSentBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.t('common.ok'))),
        ],
      ),
    );
  }

  Future<void> _confirmViaDialog() async {
    final l10n = ref.read(appLocalizationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('home.sosConfirmTitle')),
        content: Text(l10n.t('home.sosConfirmBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) _sendSos();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    return Tooltip(
      message: l10n.t('home.sosHold'),
      child: GestureDetector(
        onTap: _confirmViaDialog,
        onLongPressStart: (_) => _holdController.forward(from: 0),
        onLongPressEnd: (_) => _holdController.reverse(),
        onLongPressCancel: () => _holdController.reverse(),
        child: AnimatedBuilder(
          animation: _holdController,
          builder: (context, child) {
            return Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.sos,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sos.withValues(alpha: 0.35),
                    blurRadius: 10 + 10 * _holdController.value,
                    spreadRadius: 1 + 3 * _holdController.value,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_holdController.value > 0)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: _holdController.value,
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  const Text(
                    'SOS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatrolActionCard extends ConsumerWidget {
  const _PatrolActionCard({required this.l10n, required this.activePatrol});
  final AppLocalizations l10n;
  final Patrol? activePatrol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = activePatrol != null &&
        (activePatrol!.status == PatrolStatus.active || activePatrol!.status == PatrolStatus.paused);

    return PressableScale(
      onTap: () {
        if (isActive) {
          context.push('/patrol/active');
        } else {
          context.push('/patrol/setup');
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.xl),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : AppColors.accentStrong,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                isActive ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive
                        ? (activePatrol!.status == PatrolStatus.paused
                            ? l10n.t('patrol.paused')
                            : l10n.t('home.patrolActive'))
                        : l10n.t('home.startPatrol'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? l10n.t('home.resumePatrol') : l10n.t('patrol.setupTitle'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _QuickActionGrid extends ConsumerWidget {
  const _QuickActionGrid({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void goToTab(int index) => ref.read(bottomNavIndexProvider.notifier).state = index;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpace.md,
      crossAxisSpacing: AppSpace.md,
      childAspectRatio: 1.7,
      children: [
        BigTile(
          label: l10n.t('home.quickReport'),
          icon: Icons.note_add_rounded,
          color: AppColors.ochre,
          onTap: () => context.push('/quick-report'),
        ),
        BigTile(
          label: l10n.t('home.cameraStations'),
          icon: Icons.videocam_rounded,
          onTap: () => goToTab(3),
        ),
        BigTile(
          label: l10n.t('home.tasksAction'),
          icon: Icons.checklist_rounded,
          onTap: () => goToTab(2),
        ),
        BigTile(
          label: l10n.t('home.mapAction'),
          icon: Icons.map_rounded,
          onTap: () => goToTab(1),
        ),
      ],
    );
  }
}

class _ActivityEntry {
  _ActivityEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.time,
    required this.syncStatus,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final DateTime time;
  final SyncStatus syncStatus;
  final VoidCallback onTap;
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patrols = ref.watch(patrolsStreamProvider).value ?? const <Patrol>[];
    final observations = ref.watch(observationsStreamProvider).value ?? const <Observation>[];
    final tasks = ref.watch(tasksStreamProvider).value ?? const <TaskItem>[];

    final entries = <_ActivityEntry>[
      for (final p in patrols.where((p) => p.status == PatrolStatus.completed))
        _ActivityEntry(
          title: l10n.t('patrol.review.title'),
          subtitle: DateFormat('MMM d, HH:mm').format(p.startedAt),
          icon: patrolTypeIcon(p.patrolType.name),
          color: AppColors.accent,
          time: p.updatedAt,
          syncStatus: p.syncStatus,
          onTap: () => context.push('/patrol/detail/${p.id}'),
        ),
      for (final o in observations)
        _ActivityEntry(
          title: l10n.t(observationTypeLabelKey(o.type)),
          subtitle: o.description.isEmpty
              ? DateFormat('MMM d, HH:mm').format(o.timestamp)
              : o.description,
          icon: observationTypeIcon(o.type),
          color: severityColor(o.severity),
          time: o.updatedAt,
          syncStatus: o.syncStatus,
          onTap: () => showObservationDetail(context, o, l10n),
        ),
      for (final t in tasks.where((t) => t.status == TaskStatus.completed))
        _ActivityEntry(
          title: t.title,
          subtitle: l10n.t('tasks.completedAt'),
          icon: Icons.check_circle_rounded,
          color: AppColors.positive,
          time: t.updatedAt,
          syncStatus: t.syncStatus,
          onTap: () => context.push('/tasks/${t.id}'),
        ),
    ]..sort((a, b) => b.time.compareTo(a.time));

    final top = entries.take(6).toList();

    if (top.isEmpty) {
      return EmptyState(message: l10n.t('home.noActivity'), icon: Icons.history_rounded);
    }

    return Column(
      children: [
        for (final e in top)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: PressableScale(
              onTap: e.onTap,
              child: Bezel(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: e.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(e.icon, color: e.color, size: 20),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            e.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    SyncStatusChip(status: e.syncStatus, l10n: l10n),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
