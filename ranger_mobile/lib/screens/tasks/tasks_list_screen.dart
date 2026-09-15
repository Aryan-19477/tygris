import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../widgets/common.dart';

class TasksListScreen extends ConsumerStatefulWidget {
  const TasksListScreen({super.key});

  @override
  ConsumerState<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends ConsumerState<TasksListScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final tasks = ref.watch(tasksStreamProvider).value ?? const <TaskItem>[];

    final groups = [
      tasks.where((t) => t.status == TaskStatus.assigned).toList(),
      tasks.where((t) => t.status == TaskStatus.inProgress).toList(),
      tasks.where((t) => t.status == TaskStatus.completed).toList(),
    ];
    final labels = [l10n.t('tasks.assigned'), l10n.t('tasks.inProgress'), l10n.t('tasks.completed')];
    final current = groups[_segment]..sort((a, b) => (a.dueAt ?? a.createdAt).compareTo(b.dueAt ?? b.createdAt));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('tasks.title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
              child: SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < labels.length; i++)
                    ButtonSegment(value: i, label: Text('${labels[i]} (${groups[i].length})')),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
            ),
            Expanded(
              child: current.isEmpty
                  ? EmptyState(message: l10n.t('tasks.empty'), icon: Icons.checklist_rtl_rounded)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxxl),
                      itemCount: current.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (context, i) {
                        final t = current[i];
                        return PressableScale(
                          onTap: () => context.push('/tasks/${t.id}'),
                          child: Bezel(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      if (t.locationLabel != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(t.locationLabel!,
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                                        ),
                                      if (t.dueAt != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '${l10n.t('tasks.due')}: ${DateFormat('MMM d, HH:mm').format(t.dueAt!)}',
                                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                          ),
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
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
