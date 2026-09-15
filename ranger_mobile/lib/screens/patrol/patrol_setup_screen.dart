import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/observation_meta.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/patrol.dart';
import '../../services/active_patrol_controller.dart';
import '../../widgets/common.dart';

class PatrolSetupScreen extends ConsumerStatefulWidget {
  const PatrolSetupScreen({super.key});

  @override
  ConsumerState<PatrolSetupScreen> createState() => _PatrolSetupScreenState();
}

class _PatrolSetupScreenState extends ConsumerState<PatrolSetupScreen> {
  PatrolType _type = PatrolType.foot;
  PatrolMethod _method = PatrolMethod.routine;
  final Set<String> _selectedTeammates = {};
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final ranger = ref.watch(currentRangerProvider);
    final teams = ref.watch(teamsStreamProvider).value ?? const [];
    final rangers = ref.watch(rangersStreamProvider).value ?? const [];
    final myTeam = teams.where((t) => t.id == ranger?.teamId).toList();
    final teammates = rangers.where((r) => r.id != ranger?.id && r.teamId == ranger?.teamId).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('patrol.setupTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            SectionLabel(l10n.t('patrol.type')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final t in PatrolType.values)
                  IconChoiceChip(
                    label: l10n.t('patrol.${t.name}'),
                    icon: patrolTypeIcon(t.name),
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('patrol.method')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final m in PatrolMethod.values)
                  IconChoiceChip(
                    label: l10n.t('patrol.${m.name}'),
                    icon: m == PatrolMethod.routine
                        ? Icons.repeat_rounded
                        : m == PatrolMethod.targeted
                            ? Icons.center_focus_strong_rounded
                            : Icons.bolt_rounded,
                    selected: _method == m,
                    onTap: () => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('patrol.team')),
            const SizedBox(height: AppSpace.sm),
            Bezel(
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, color: AppColors.accent),
                  const SizedBox(width: AppSpace.md),
                  Text(
                    myTeam.isNotEmpty ? myTeam.first.name : l10n.t('common.none'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (teammates.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              SectionLabel(l10n.t('patrol.teammates')),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final r in teammates)
                    FilterChip(
                      label: Text(r.name),
                      selected: _selectedTeammates.contains(r.id),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedTeammates.add(r.id);
                        } else {
                          _selectedTeammates.remove(r.id);
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.xxl),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: (_starting || ranger == null) ? null : () => _start(ranger.id, myTeam.isNotEmpty ? myTeam.first.id : null),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.t('patrol.start')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(String rangerId, String? teamId) async {
    setState(() => _starting = true);
    await ref.read(activePatrolControllerProvider.notifier).start(
          type: _type,
          method: _method,
          rangerId: rangerId,
          teamId: teamId,
        );
    if (!mounted) return;
    context.pushReplacement('/patrol/active');
  }
}
