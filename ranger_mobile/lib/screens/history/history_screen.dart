import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/camera_inspection.dart';
import '../../models/observation.dart';
import '../../models/patrol.dart';
import '../../models/task_item.dart';
import '../../widgets/common.dart';
import '../../widgets/observation_detail_sheet.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final patrols = (ref.watch(patrolsStreamProvider).value ?? const <Patrol>[])
        .where((p) => p.status == PatrolStatus.completed)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final reports = (ref.watch(observationsStreamProvider).value ?? const <Observation>[])
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final tasks = (ref.watch(tasksStreamProvider).value ?? const <TaskItem>[])
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final inspections = (ref.watch(cameraInspectionsStreamProvider).value ?? const <CameraInspection>[])
        .toList()
      ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('history.title')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: l10n.t('history.patrols')),
            Tab(text: l10n.t('history.reports')),
            Tab(text: l10n.t('history.tasks')),
            Tab(text: l10n.t('history.inspections')),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _patrolsList(l10n, patrols),
            _reportsList(l10n, reports),
            _tasksList(l10n, tasks),
            _inspectionsList(l10n, inspections),
          ],
        ),
      ),
    );
  }

  Widget _patrolsList(AppLocalizations l10n, List<Patrol> items) {
    if (items.isEmpty) return EmptyState(message: l10n.t('history.empty'));
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) {
        final p = items[i];
        return PressableScale(
          onTap: () => context.push('/patrol/detail/${p.id}'),
          child: Bezel(
            child: Row(
              children: [
                Icon(patrolTypeIcon(p.patrolType.name), color: AppColors.accent),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.distanceKm.toStringAsFixed(2)} ${l10n.t('common.km')} · ${p.observationIds.length} obs',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(DateFormat('MMM d, yyyy · HH:mm').format(p.startedAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
                SyncStatusChip(status: p.syncStatus, l10n: l10n),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reportsList(AppLocalizations l10n, List<Observation> items) {
    if (items.isEmpty) return EmptyState(message: l10n.t('history.empty'));
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) {
        final o = items[i];
        return PressableScale(
          onTap: () => showObservationDetail(context, o, l10n),
          child: Bezel(
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: severityColor(o.severity).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(observationTypeIcon(o.type), color: severityColor(o.severity), size: 18),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.t(observationTypeLabelKey(o.type)), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        o.isStandaloneReport ? l10n.t('report.standalone') : DateFormat('MMM d, HH:mm').format(o.timestamp),
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                SyncStatusChip(status: o.syncStatus, l10n: l10n),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tasksList(AppLocalizations l10n, List<TaskItem> items) {
    if (items.isEmpty) return EmptyState(message: l10n.t('history.empty'));
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) {
        final t = items[i];
        return PressableScale(
          onTap: () => context.push('/tasks/${t.id}'),
          child: Bezel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        l10n.t('tasks.${t.status.name}'),
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                SyncStatusChip(status: t.syncStatus, l10n: l10n),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _inspectionsList(AppLocalizations l10n, List<CameraInspection> items) {
    if (items.isEmpty) return EmptyState(message: l10n.t('history.empty'));
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) {
        final insp = items[i];
        return PressableScale(
          onTap: () => context.push('/stations/${insp.stationCameraId}'),
          child: Bezel(
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, color: inspectionStatusColor(insp.status)),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${insp.stationCameraId} · ${l10n.t(inspectionActionLabelKey(insp.actionTaken))}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(DateFormat('MMM d, yyyy · HH:mm').format(insp.timestamp),
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
                SyncStatusChip(status: insp.syncStatus, l10n: l10n),
              ],
            ),
          ),
        );
      },
    );
  }
}
