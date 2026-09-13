import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/repository.dart';
import '../core/theme.dart';
import '../core/motion.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Combines the review queue (ambiguous re-ID matches needing a ranger's
/// call) and recent high-priority alerts in one triage-focused screen —
/// mirrors frontend-v2's AttentionQueueView but redesigned for fast
/// thumb-driven decisions on a phone rather than a dense desktop table.
class AttentionQueueScreen extends ConsumerStatefulWidget {
  const AttentionQueueScreen({super.key});

  @override
  ConsumerState<AttentionQueueScreen> createState() =>
      _AttentionQueueScreenState();
}

class _AttentionQueueScreenState extends ConsumerState<AttentionQueueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Review queue state
  List<ReviewQueueItem>? _reviewItems;
  Object? _reviewError;
  bool _reviewLoading = true;
  final Set<String> _resolvingItemIds = {};

  // Alerts state
  List<Sighting>? _alerts;
  Object? _alertsError;
  bool _alertsLoading = true;
  String _levelFilter = 'all'; // all | critical | caution
  final Set<String> _acknowledgingEventIds = {};
  final Set<String> _acknowledgedEventIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReviewQueue();
    _loadAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReviewQueue() async {
    setState(() {
      _reviewLoading = true;
      _reviewError = null;
    });
    try {
      final items = await ref.read(repositoryProvider).reviewQueue();
      if (!mounted) return;
      setState(() {
        _reviewItems = items;
        _reviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reviewError = e;
        _reviewLoading = false;
      });
    }
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _alertsLoading = true;
      _alertsError = null;
    });
    try {
      final level = _levelFilter == 'all' ? null : _levelFilter;
      final result =
          await ref.read(repositoryProvider).alerts(level: level, limit: 50);
      if (!mounted) return;
      setState(() {
        _alerts = result.alerts;
        _alertsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _alertsError = e;
        _alertsLoading = false;
      });
    }
  }

  Future<void> _onFilterChanged(String level) async {
    setState(() => _levelFilter = level);
    await _loadAlerts();
  }

  Future<void> _resolveReview(ReviewQueueItem item, String? tigerId) async {
    setState(() => _resolvingItemIds.add(item.itemId));
    try {
      await ref.read(repositoryProvider).resolveReview(item.itemId, tigerId);
      if (!mounted) return;
      setState(() {
        _reviewItems?.removeWhere((e) => e.itemId == item.itemId);
        _resolvingItemIds.remove(item.itemId);
      });
      _showSnack(
        tigerId != null
            ? 'Matched to $tigerId'
            : 'Recorded as new individual',
        success: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolvingItemIds.remove(item.itemId));
      _showSnack('Failed to resolve: could not reach server', success: false);
    }
  }

  Future<void> _acknowledgeAlert(Sighting alert) async {
    final eventId = alert.eventId;
    if (eventId == null) return;
    setState(() {
      _acknowledgingEventIds.add(eventId);
      _acknowledgedEventIds.add(eventId); // optimistic
    });
    try {
      await ref.read(repositoryProvider).acknowledgeAlert(eventId);
      if (!mounted) return;
      setState(() {
        _alerts?.removeWhere((e) => e.eventId == eventId);
        _acknowledgingEventIds.remove(eventId);
        _acknowledgedEventIds.remove(eventId);
      });
      _showSnack('Alert acknowledged', success: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // rollback
        _acknowledgingEventIds.remove(eventId);
        _acknowledgedEventIds.remove(eventId);
      });
      _showSnack('Failed to acknowledge alert', success: false);
    }
  }

  void _showSnack(String message, {required bool success}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? AppColors.accent : AppColors.danger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reviewCount = _reviewItems?.length ?? 0;
    final alertCount = _alerts?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.surface,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.hairline, width: 1),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.accent,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    text: _reviewLoading
                        ? 'Review Queue'
                        : 'Review Queue ($reviewCount)',
                  ),
                  Tab(
                    text: _alertsLoading ? 'Alerts' : 'Alerts ($alertCount)',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ReviewQueueTab(
                    loading: _reviewLoading,
                    error: _reviewError,
                    items: _reviewItems,
                    resolvingItemIds: _resolvingItemIds,
                    onRefresh: _loadReviewQueue,
                    onResolve: _resolveReview,
                  ),
                  _AlertsTab(
                    loading: _alertsLoading,
                    error: _alertsError,
                    alerts: _alerts,
                    levelFilter: _levelFilter,
                    acknowledgingEventIds: _acknowledgingEventIds,
                    acknowledgedEventIds: _acknowledgedEventIds,
                    onRefresh: _loadAlerts,
                    onFilterChanged: _onFilterChanged,
                    onAcknowledge: _acknowledgeAlert,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review Queue tab
// ---------------------------------------------------------------------------

class _ReviewQueueTab extends StatelessWidget {
  const _ReviewQueueTab({
    required this.loading,
    required this.error,
    required this.items,
    required this.resolvingItemIds,
    required this.onRefresh,
    required this.onResolve,
  });

  final bool loading;
  final Object? error;
  final List<ReviewQueueItem>? items;
  final Set<String> resolvingItemIds;
  final Future<void> Function() onRefresh;
  final void Function(ReviewQueueItem item, String? tigerId) onResolve;

  @override
  Widget build(BuildContext context) {
    if (loading && items == null) {
      return const LoadingList(itemCount: 4, height: 220);
    }
    if (error != null && items == null) {
      return ErrorState(
        message: 'Could not load the review queue.',
        onRetry: onRefresh,
      );
    }
    final list = items ?? [];
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppColors.accent,
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'All caught up',
                subtitle: 'No ambiguous matches waiting for review.',
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xl),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
        itemBuilder: (context, index) {
          final item = list[index];
          return SpringEntry(
            delay: staggerDelay(index),
            child: _ReviewQueueCard(
              key: ValueKey(item.itemId),
              item: item,
              resolving: resolvingItemIds.contains(item.itemId),
              onResolve: (tigerId) => onResolve(item, tigerId),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewQueueCard extends StatelessWidget {
  const _ReviewQueueCard({
    super.key,
    required this.item,
    required this.resolving,
    required this.onResolve,
  });

  final ReviewQueueItem item;
  final bool resolving;
  final void Function(String? tigerId) onResolve;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: resolving ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: Bezel(
        padding: const EdgeInsets.all(AppSpace.md),
        child: IgnorePointer(
          ignoring: resolving,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumbnail(url: item.uploadedImage),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 13, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Text(
                              relativeTime(item.timestamp),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (item.stationId != null) item.stationId!,
                            if (item.zone != null) item.zone!,
                          ].join(' · '),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  fontSize: 14, color: AppColors.foreground),
                        ),
                        if (item.reason != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.reason!,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.muted),
                          ),
                        ],
                        if (item.nearestDistance != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Nearest match distance: ${item.nearestDistance!.toStringAsFixed(3)}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.muted,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (resolving)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              const Divider(height: 1, color: AppColors.hairline),
              const SizedBox(height: AppSpace.md),
              Text(
                'CANDIDATE MATCHES',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              if (item.candidates.isEmpty)
                const Text('No close candidates found.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted))
              else
                Column(
                  children: item.candidates
                      .map((c) => _CandidateRow(
                            candidate: c,
                            onTap: () => onResolve(c.tigerId),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: PressableScale(
                  onTap: () => onResolve(null),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_add_alt_1_outlined,
                            size: 17, color: AppColors.foreground),
                        const SizedBox(width: 8),
                        Text(
                          'New Individual',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.foreground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.onTap});

  final Candidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = (candidate.similarity * 100).clamp(0, 100);
    final color = pct >= 80
        ? AppColors.positive
        : pct >= 60
            ? AppColors.caution
            : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.pets_rounded, size: 16, color: AppColors.foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  candidate.tigerId,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alerts tab
// ---------------------------------------------------------------------------

class _AlertsTab extends StatelessWidget {
  const _AlertsTab({
    required this.loading,
    required this.error,
    required this.alerts,
    required this.levelFilter,
    required this.acknowledgingEventIds,
    required this.acknowledgedEventIds,
    required this.onRefresh,
    required this.onFilterChanged,
    required this.onAcknowledge,
  });

  final bool loading;
  final Object? error;
  final List<Sighting>? alerts;
  final String levelFilter;
  final Set<String> acknowledgingEventIds;
  final Set<String> acknowledgedEventIds;
  final Future<void> Function() onRefresh;
  final void Function(String level) onFilterChanged;
  final void Function(Sighting alert) onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xs),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: levelFilter == 'all',
                onTap: () => onFilterChanged('all'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Critical',
                selected: levelFilter == 'critical',
                color: AppColors.priorityHigh,
                onTap: () => onFilterChanged('critical'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Caution',
                selected: levelFilter == 'caution',
                color: AppColors.priorityMedium,
                onTap: () => onFilterChanged('caution'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (loading && alerts == null) {
      return const LoadingList(itemCount: 5, height: 110);
    }
    if (error != null && alerts == null) {
      return ErrorState(
        message: 'Could not load alerts.',
        onRetry: onRefresh,
      );
    }
    final list = alerts ?? [];
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppColors.accent,
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  const SizedBox(height: AppSpace.xl),
                  const EyebrowTag(
                    label: 'Active Alerts',
                    icon: Icons.shield_outlined,
                  ),
                  const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'All caught up',
                    subtitle: 'No pending alerts at this level.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xl),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
        itemBuilder: (context, index) {
          final alert = list[index];
          final eventId = alert.eventId ?? 'evt-$index';
          return SpringEntry(
            delay: staggerDelay(index),
            child: _AlertCard(
              key: ValueKey(eventId),
              alert: alert,
              acknowledging: acknowledgingEventIds.contains(eventId),
              acknowledged: acknowledgedEventIds.contains(eventId),
              onAcknowledge: () => onAcknowledge(alert),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.accent;
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      scaleDown: 0.94,
      child: AnimatedContainer(
        duration: AppMotionDuration.standard,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withValues(alpha: 0.14)
              : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? chipColor.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppMotionDuration.standard,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? chipColor : AppColors.muted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    super.key,
    required this.alert,
    required this.acknowledging,
    required this.acknowledged,
    required this.onAcknowledge,
  });

  final Sighting alert;
  final bool acknowledging;
  final bool acknowledged;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final level = alert.alertLevel ?? 'low';
    return AnimatedOpacity(
      opacity: acknowledged ? 0.45 : 1,
      duration: const Duration(milliseconds: 200),
      child: Bezel(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(url: alert.image, size: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.tigerId,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  fontSize: 14, color: AppColors.foreground),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusBadge(label: level.toUpperCase(), level: level),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (alert.station != null) alert.station!,
                      if (alert.zone != null) alert.zone!,
                    ].join(' · '),
                    style:
                        const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        relativeTime(alert.timestamp),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted),
                      ),
                      if (alert.speedKmh != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.speed_rounded,
                            size: 12, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(
                          '${alert.speedKmh!.toStringAsFixed(1)} km/h',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                  if (alert.threatReason != null &&
                      alert.threatReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor(level).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alert.threatReason!,
                        style: TextStyle(
                            fontSize: 12,
                            color: statusColor(level),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: PressableScale(
                      onTap: acknowledging || acknowledged
                          ? null
                          : onAcknowledge,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: acknowledging || acknowledged
                              ? AppColors.muted.withValues(alpha: 0.35)
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            acknowledging
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(
                                    acknowledged
                                        ? Icons.check_circle_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 16,
                                    color: AppColors.accentForeground,
                                  ),
                            const SizedBox(width: 8),
                            Text(
                              acknowledged ? 'Acknowledged' : 'Acknowledge',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentForeground),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, this.size = 72});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? _placeholder()
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (context, _) => _loadingBox(),
                errorWidget: (context, _, __) => _placeholder(),
              ),
      ),
    );
  }

  Widget _loadingBox() => Container(color: AppColors.surfaceSunken);

  Widget _placeholder() => Container(
        color: AppColors.surfaceSunken,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined,
            size: 20, color: AppColors.muted),
      );
}

/// Formats an ISO-8601-ish timestamp string as a short relative label
/// ("2h ago", "just now", "3d ago"), falling back to the raw value (or a
/// dash) when parsing fails so the UI never crashes on odd backend data.
String relativeTime(String? timestamp) {
  if (timestamp == null || timestamp.isEmpty) return '—';
  DateTime? dt;
  try {
    dt = DateTime.parse(timestamp).toLocal();
  } catch (_) {
    return timestamp;
  }
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.isNegative || diff.inSeconds < 30) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dt);
}
