import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Ranger Reports — mirrors frontend-v2's RangerReportsView: patrols and
/// field observations written by the Ranger app, with the backend's
/// territory-check intelligence runnable per wildlife observation. Reads
/// through the backend's /api/ranger/reports (the web reads Supabase
/// directly) so the mobile app needs no Supabase credentials.
class RangerReportsScreen extends ConsumerStatefulWidget {
  const RangerReportsScreen({super.key});

  @override
  ConsumerState<RangerReportsScreen> createState() =>
      _RangerReportsScreenState();
}

enum _Tab { all, observations, patrols }

class _RangerReportsScreenState extends ConsumerState<RangerReportsScreen> {
  RangerReports? _reports;
  Object? _error;
  bool _refreshing = false;
  bool _runningPending = false;
  _Tab _tab = _Tab.all;
  final Map<String, TerritoryCheck> _checks = {};
  final Set<String> _running = {};
  final Set<String> _failed = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // The web polls every 2s; a slower cadence is kinder to field data plans.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final r = await ref.read(repositoryProvider).rangerReports();
      if (mounted) {
        setState(() {
          _reports = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _runCheck(String observationId) async {
    setState(() {
      _running.add(observationId);
      _failed.remove(observationId);
    });
    try {
      final check =
          await ref.read(repositoryProvider).runTerritoryCheck(observationId);
      if (mounted) setState(() => _checks[observationId] = check);
    } catch (_) {
      if (mounted) setState(() => _failed.add(observationId));
    } finally {
      if (mounted) setState(() => _running.remove(observationId));
    }
  }

  Future<void> _runPending() async {
    setState(() => _runningPending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(repositoryProvider).runPendingTerritoryChecks();
      messenger.showSnackBar(SnackBar(
          content: Text(n == 0
              ? 'No pending territory checks.'
              : 'Ran $n territory check${n == 1 ? '' : 's'}.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _runningPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScreenAppBar(
        title: 'Ranger Reports',
        actions: [
          IconButton(
            tooltip: 'Run pending territory checks',
            onPressed: _runningPending || _reports?.configured != true
                ? null
                : _runPending,
            icon: _runningPending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
                : const Icon(Icons.radar_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final reports = _reports;
    if (reports == null) {
      if (_error != null) {
        return ErrorState(message: describeError(_error), onRetry: _load);
      }
      return const LoadingList(height: 120);
    }
    if (!reports.configured) {
      return const EmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Ranger Ops not configured',
        subtitle:
            'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on the backend to see field reports.',
      );
    }

    final byPatrol = <String, List<RangerObservation>>{};
    for (final o in reports.observations) {
      if (o.patrolId != null) (byPatrol[o.patrolId!] ??= []).add(o);
    }

    // Newest first, observations and patrols interleaved like the web.
    final entries = <(DateTime, Object)>[
      if (_tab != _Tab.patrols)
        for (final o in reports.observations)
          (_parse(o.timestamp ?? o.createdAt), o),
      if (_tab != _Tab.observations)
        for (final p in reports.patrols) (_parse(p.startTime ?? p.createdAt), p),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxl + bottomInset),
        children: [
          Row(
            children: [
              const EyebrowTag(label: 'Live', icon: Icons.sensors_rounded),
              const Spacer(),
              if (_error != null)
                const Icon(Icons.cloud_off_outlined,
                    size: 16, color: AppColors.danger),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoicePill(
                label: 'All',
                count: reports.observations.length + reports.patrols.length,
                selected: _tab == _Tab.all,
                onTap: () => setState(() => _tab = _Tab.all),
              ),
              ChoicePill(
                label: 'Observations',
                count: reports.observations.length,
                selected: _tab == _Tab.observations,
                onTap: () => setState(() => _tab = _Tab.observations),
              ),
              ChoicePill(
                label: 'Patrols',
                count: reports.patrols.length,
                selected: _tab == _Tab.patrols,
                onTap: () => setState(() => _tab = _Tab.patrols),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpace.xxl),
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No field reports yet',
                subtitle: 'Reports sync here from the Ranger app.',
              ),
            ),
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: SpringEntry(
                delay: staggerDelay(i),
                child: switch (entries[i].$2) {
                  final RangerObservation o => _ObservationCard(
                      obs: o,
                      check: _checks[o.observationId],
                      running: _running.contains(o.observationId),
                      failed: _failed.contains(o.observationId),
                      onRunCheck: () => _runCheck(o.observationId),
                    ),
                  final RangerPatrol p => _PatrolCard(
                      patrol: p,
                      observations: byPatrol[p.patrolId] ?? const [],
                      checks: _checks,
                      running: _running,
                      failed: _failed,
                      onRunCheck: _runCheck,
                    ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
        ],
      ),
    );
  }

  static DateTime _parse(String? iso) =>
      DateTime.tryParse(iso ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
}

({String label, Color color, IconData icon}) _checkTone(String status) {
  switch (status) {
    case 'confirmed_present':
      return (
        label: 'Resident confirmed',
        color: AppColors.positive,
        icon: Icons.check_circle_rounded
      );
    case 'possible_move':
      return (
        label: 'Possible territory shift',
        color: AppColors.caution,
        icon: Icons.warning_rounded
      );
    case 'no_location':
      return (
        label: 'No location',
        color: AppColors.muted,
        icon: Icons.help_rounded
      );
    default:
      return (
        label: 'No recent camera data',
        color: AppColors.muted,
        icon: Icons.help_rounded
      );
  }
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

class _TypeTag extends StatelessWidget {
  const _TypeTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.muted)),
    );
  }
}

/// Territory-check result or the "run check" affordance for one
/// wildlife observation — shared by standalone and in-patrol cards.
class _CheckSection extends StatelessWidget {
  const _CheckSection({
    required this.obs,
    required this.check,
    required this.running,
    required this.failed,
    required this.onRunCheck,
    this.compact = false,
  });

  final RangerObservation obs;
  final TerritoryCheck? check;
  final bool running;
  final bool failed;
  final VoidCallback onRunCheck;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (check != null) {
      final tone = _checkTone(check!.status);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(tone.icon, size: 15, color: tone.color),
              Text(tone.label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tone.color)),
              if (check!.residentTigerId != null)
                Text('· Resident ${check!.residentTigerId}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          if (!compact && check!.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(check!.summary,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.foreground, height: 1.45)),
          ],
        ],
      );
    } else if (obs.hasCoords) {
      content = Row(
        children: [
          const Expanded(
            child: Text('Territory check pending',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
          TextButton.icon(
            onPressed: running ? null : onRunCheck,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              backgroundColor: AppColors.accentSoft,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            icon: running
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: AppColors.accent))
                : const Icon(Icons.radar_rounded, size: 15),
            label: Text(running ? 'Running…' : 'Run check',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    } else {
      content = const Text('No coordinates recorded',
          style: TextStyle(fontSize: 12, color: AppColors.muted));
    }

    return Container(
      margin: EdgeInsets.only(top: compact ? 8 : AppSpace.md),
      padding: EdgeInsets.only(top: compact ? 8 : AppSpace.md),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (failed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Territory check failed. Try again.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({
    required this.obs,
    required this.check,
    required this.running,
    required this.failed,
    required this.onRunCheck,
  });

  final RangerObservation obs;
  final TerritoryCheck? check;
  final bool running;
  final bool failed;
  final VoidCallback onRunCheck;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REPORTED BY ${obs.rangerId.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Text(obs.speciesCategory ?? obs.obsType,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 16.5)),
                    const SizedBox(height: 2),
                    Text(formatTimestamp(obs.timestamp ?? obs.createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: _TypeTag(obs.obsType)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  obs.hasCoords
                      ? '${obs.lat!.toStringAsFixed(5)}, ${obs.lon!.toStringAsFixed(5)}'
                      : 'No coordinates',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.mutedStrong),
                ),
              ),
            ],
          ),
          if (obs.remarks?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpace.sm),
            Text(obs.remarks!,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.foreground, height: 1.45)),
          ],
          if (obs.isWildlife)
            _CheckSection(
              obs: obs,
              check: check,
              running: running,
              failed: failed,
              onRunCheck: onRunCheck,
            ),
        ],
      ),
    );
  }
}

class _PatrolCard extends StatefulWidget {
  const _PatrolCard({
    required this.patrol,
    required this.observations,
    required this.checks,
    required this.running,
    required this.failed,
    required this.onRunCheck,
  });

  final RangerPatrol patrol;
  final List<RangerObservation> observations;
  final Map<String, TerritoryCheck> checks;
  final Set<String> running;
  final Set<String> failed;
  final ValueChanged<String> onRunCheck;

  @override
  State<_PatrolCard> createState() => _PatrolCardState();
}

class _PatrolCardState extends State<_PatrolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.patrol;
    final obs = widget.observations;
    final isVehicle = p.patrolType?.toLowerCase() == 'vehicle';
    final completed = p.status?.toLowerCase() == 'completed';
    final type = (p.patrolType?.isNotEmpty == true) ? p.patrolType! : 'Foot';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                    isVehicle
                        ? Icons.directions_car_rounded
                        : Icons.directions_walk_rounded,
                    size: 20,
                    color: AppColors.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REPORTED BY ${p.rangerId.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Text(
                        '${type[0].toUpperCase()}${type.substring(1)} patrol',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 16.5)),
                    const SizedBox(height: 2),
                    Text(formatTimestamp(p.startTime ?? p.createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              StatusBadge(
                label: (p.status ?? 'Active').toUpperCase(),
                level: completed ? 'low' : 'medium',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                    child: _Metric(
                        label: 'Distance',
                        value:
                            '${(p.distanceKm ?? 0).toStringAsFixed(2)} km')),
                Expanded(
                    child: _Metric(
                        label: 'Duration',
                        value: _formatDuration(p.durationSeconds))),
              ],
            ),
          ),
          if (p.startLat != null && p.startLon != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Start ${p.startLat!.toStringAsFixed(4)}, ${p.startLon!.toStringAsFixed(4)}'
              '${p.endLat != null && p.endLon != null ? '  ·  End ${p.endLat!.toStringAsFixed(4)}, ${p.endLon!.toStringAsFixed(4)}' : ''}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
          if (p.notes?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpace.sm),
            Text(p.notes!,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.foreground, height: 1.45)),
          ],
          const SizedBox(height: AppSpace.md),
          PressableScale(
            scaleDown: 0.98,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      obs.isEmpty
                          ? 'No observations in this patrol'
                          : '${obs.length} observation${obs.length == 1 ? '' : 's'} logged',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppMotionDuration.quick,
                    child: const Icon(Icons.expand_more_rounded,
                        size: 18, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotionDuration.quick,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded || obs.isEmpty
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final o in obs)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: AppSpace.sm),
                          padding: const EdgeInsets.all(AppSpace.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(o.speciesCategory ?? o.obsType,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Flexible(child: _TypeTag(o.obsType)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatTimestamp(o.timestamp ?? o.createdAt) +
                                    (o.hasCoords
                                        ? '  ·  ${o.lat!.toStringAsFixed(4)}, ${o.lon!.toStringAsFixed(4)}'
                                        : ''),
                                style: const TextStyle(
                                    fontSize: 11.5, color: AppColors.muted),
                              ),
                              if (o.remarks?.isNotEmpty == true) ...[
                                const SizedBox(height: 6),
                                Text(o.remarks!,
                                    style: const TextStyle(
                                        fontSize: 12.5, height: 1.4)),
                              ],
                              if (o.isWildlife)
                                _CheckSection(
                                  obs: o,
                                  check: widget.checks[o.observationId],
                                  running:
                                      widget.running.contains(o.observationId),
                                  failed:
                                      widget.failed.contains(o.observationId),
                                  onRunCheck: () =>
                                      widget.onRunCheck(o.observationId),
                                  compact: true,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
