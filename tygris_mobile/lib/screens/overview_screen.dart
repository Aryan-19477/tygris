import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Real-time overview — the analytics column of frontend-v2's HomeView,
/// computed from live /api/stats and the GIS bundle rather than the web's
/// placeholder series.
class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  late Future<(DashboardStats, GISMapBundle)> _future = _load();

  Future<(DashboardStats, GISMapBundle)> _load() async {
    final repo = ref.read(repositoryProvider);
    final results = await Future.wait([repo.stats(), repo.gisBundle()]);
    return (results[0] as DashboardStats, results[1] as GISMapBundle);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenAppBar(title: 'Overview'),
      body: FutureBuilder<(DashboardStats, GISMapBundle)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 130, itemCount: 4);
          }
          if (snap.hasError) {
            return ErrorState(
                message: describeError(snap.error), onRetry: _refresh);
          }
          final (stats, bundle) = snap.data!;

          var core = 0, buffer = 0, other = 0, online = 0;
          for (final s in bundle.stations) {
            final z = s.zone.toUpperCase();
            if (z == 'CORE') {
              core++;
            } else if (z == 'BUFFER') {
              buffer++;
            } else {
              other++;
            }
            if (s.operationalStatus.toUpperCase() == 'OPERATIONAL') online++;
          }
          final offline = bundle.stations.length - online;
          final territoryArea =
              bundle.territories.fold<double>(0, (a, t) => a + t.areaKm2);
          final totalTigers = bundle.totalTigers > 0
              ? bundle.totalTigers
              : stats.totalIndividuals;

          final cards = <Widget>[
            _Card(
              icon: Icons.pets_rounded,
              title: 'Identified tigers',
              value: '$totalTigers',
              subtitle: '${bundle.territories.length} territories · '
                  '${territoryArea.toStringAsFixed(1)} km² mapped',
            ),
            _Card(
              icon: Icons.camera_alt_rounded,
              title: 'Captures',
              value: '${stats.totalCaptures}',
              subtitle: '${stats.pendingReview} pending review',
            ),
            _Card(
              icon: Icons.warning_amber_rounded,
              title: 'Active alerts',
              value:
                  '${(stats.criticalAlerts ?? 0) + (stats.cautionAlerts ?? 0)}',
              split: [
                ('Critical', (stats.criticalAlerts ?? 0).toDouble(),
                    AppColors.danger),
                ('Caution', (stats.cautionAlerts ?? 0).toDouble(),
                    AppColors.caution),
              ],
            ),
            _Card(
              icon: Icons.videocam_rounded,
              title: 'Camera network',
              value: '${bundle.stations.length}',
              split: [
                ('Operational', online.toDouble(), AppColors.positive),
                ('Offline', offline.toDouble(), AppColors.danger),
              ],
            ),
            _Card(
              icon: Icons.place_rounded,
              title: 'Stations by zone',
              value: '${core + buffer + other}',
              subtitle: stats.coreAreaKm2 != null
                  ? 'Core ${stats.coreAreaKm2!.toStringAsFixed(0)} km² · '
                      'Buffer ${(stats.bufferAreaKm2 ?? 0).toStringAsFixed(0)} km²'
                  : null,
              split: [
                ('Core', core.toDouble(), AppColors.accent),
                ('Buffer', buffer.toDouble(), const Color(0xFF8AAB7E)),
                ('Other', other.toDouble(), AppColors.ochre),
              ],
            ),
          ];

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: _refresh,
            child: LayoutBuilder(builder: (context, c) {
              // One column on phones, two on wide phones/tablets.
              final cols = c.maxWidth >= 640 ? 2 : 1;
              final itemWidth =
                  (c.maxWidth - AppSpace.lg * 2 - AppSpace.md * (cols - 1)) /
                      cols;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg,
                    AppSpace.lg, AppSpace.xxl + MediaQuery.paddingOf(context).bottom),
                children: [
                  EyebrowTag(
                      label: bundle.reserve, icon: Icons.sensors_rounded),
                  const SizedBox(height: AppSpace.lg),
                  Wrap(
                    spacing: AppSpace.md,
                    runSpacing: AppSpace.md,
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        SizedBox(
                          width: itemWidth,
                          child: SpringEntry(
                              delay: staggerDelay(i), child: cards[i]),
                        ),
                    ],
                  ),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.split,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final List<(String, double, Color)>? split;

  @override
  Widget build(BuildContext context) {
    final total = split?.fold<double>(0, (a, p) => a + p.$2) ?? 0;
    return SectionCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 17, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontSize: 34)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
          if (split != null) ...[
            const SizedBox(height: AppSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 8,
                child: total == 0
                    ? Container(color: AppColors.surfaceSunken)
                    : Row(
                        children: [
                          for (final p in split!)
                            if (p.$2 > 0)
                              Expanded(
                                flex: (p.$2 * 1000 / total).round().clamp(1, 1000),
                                child: Container(color: p.$3),
                              ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.lg,
              runSpacing: 4,
              children: [
                for (final p in split!)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: p.$3, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text('${p.$1} ${p.$2.round()}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.mutedStrong)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
