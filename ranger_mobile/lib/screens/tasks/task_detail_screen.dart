import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/app_shell.dart';
import '../../core/ids.dart';
import '../../core/map_focus.dart';
import '../../core/sync_status.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/photo.dart';
import '../../models/sync_queue_item.dart';
import '../../models/task_item.dart';
import '../../services/sync_queue_service.dart';
import '../../widgets/captured_photo_image.dart';
import '../../widgets/common.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final List<XFile> _newEvidence = [];

  Future<void> _addEvidence() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      if (picked != null) setState(() => _newEvidence.add(picked));
    } catch (_) {}
  }

  Future<void> _setStatus(TaskItem task, TaskStatus status) async {
    final repo = ref.read(taskRepositoryProvider);
    final photoRepo = ref.read(photoRepositoryProvider);
    final evidenceIds = <String>[...task.evidencePhotoIds];
    for (final p in _newEvidence) {
      final id = newId();
      await photoRepo.save(Photo(
        id: id,
        localPath: p.path,
        entityType: 'task',
        entityId: task.id,
        capturedAt: DateTime.now(),
        syncStatus: SyncStatus.local,
      ));
      await ref.read(syncQueueServiceProvider).enqueue(entityType: 'photo', entityId: id);
      evidenceIds.add(id);
    }
    final updated = task.copyWith(
      status: status,
      evidencePhotoIds: evidenceIds,
      completedAt: status == TaskStatus.completed ? DateTime.now() : task.completedAt,
      syncStatus: SyncStatus.local,
    );
    await repo.save(updated);
    await ref.read(syncQueueServiceProvider).enqueue(entityType: 'task', entityId: task.id, action: SyncAction.update);
    setState(() => _newEvidence.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final tasks = ref.watch(tasksStreamProvider).value ?? const <TaskItem>[];
    final matches = tasks.where((t) => t.id == widget.taskId).toList();

    if (matches.isEmpty) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(l10n.t('common.unknown'))));
    }
    final task = matches.first;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('tasks.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            Row(
              children: [
                Expanded(child: Text(task.title, style: Theme.of(context).textTheme.headlineSmall)),
                SyncStatusChip(status: task.syncStatus, l10n: l10n),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            if (task.dueAt != null)
              Text('${l10n.t('tasks.due')}: ${DateFormat('MMM d, yyyy · HH:mm').format(task.dueAt!)}',
                  style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: AppSpace.lg),
            SectionLabel(l10n.t('tasks.instructions')),
            const SizedBox(height: AppSpace.sm),
            Bezel(child: Text(task.instructions)),
            if (task.hasLocation) ...[
              const SizedBox(height: AppSpace.lg),
              SectionLabel(l10n.t('tasks.location')),
              const SizedBox(height: AppSpace.sm),
              Bezel(
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, color: AppColors.accent),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text(task.locationLabel ?? '${task.lat}, ${task.lng}')),
                    TextButton.icon(
                      onPressed: () {
                        ref.read(mapFocusTaskIdProvider.notifier).state = task.id;
                        ref.read(bottomNavIndexProvider.notifier).state = 1;
                        context.go('/');
                      },
                      icon: const Icon(Icons.navigation_outlined, size: 16),
                      label: Text(l10n.t('tasks.navigate')),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            SectionLabel(l10n.t('tasks.evidence')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final p in _newEvidence)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: capturedPhotoImage(p.path, fit: BoxFit.cover),
                  ),
                if (task.status != TaskStatus.completed)
                  PressableScale(
                    onTap: _addEvidence,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.borderStrong),
                        color: AppColors.surfaceSunken,
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xxl),
            if (task.status == TaskStatus.assigned)
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => _setStatus(task, TaskStatus.inProgress),
                  child: Text(l10n.t('tasks.start')),
                ),
              ),
            if (task.status == TaskStatus.inProgress)
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => _setStatus(task, TaskStatus.completed),
                  child: Text(l10n.t('tasks.complete')),
                ),
              ),
            if (task.status == TaskStatus.completed && task.completedAt != null)
              Text(
                '${l10n.t('tasks.completedAt')}: ${DateFormat('MMM d, yyyy · HH:mm').format(task.completedAt!)}',
                style: const TextStyle(color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
