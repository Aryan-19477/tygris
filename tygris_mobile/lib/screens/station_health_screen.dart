import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Maps a raw `operational_status` string from the backend into the
/// semantic level vocabulary `statusColor()`/`StatusBadge` understand
/// (positive/low, caution/medium, danger/high), plus a short display label.
class _StatusInfo {
  const _StatusInfo(this.label, this.level);
  final String label;
  final String level; // 'low' | 'medium' | 'high'
}

_StatusInfo _statusInfo(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('operational') || s.contains('active') || s.contains('online')) {
    return const _StatusInfo('Operational', 'low');
  }
  if (s.contains('degrad') || s.contains('maint')) {
    return const _StatusInfo('Degraded', 'medium');
  }
  if (s.contains('offline') || s.contains('down')) {
    return const _StatusInfo('Offline', 'high');
  }
  return _StatusInfo(raw.isEmpty ? 'Unknown' : raw, 'medium');
}

Color _uptimeColor(double ratio) {
  if (ratio >= 0.85) return AppColors.positive;
  if (ratio >= 0.6) return AppColors.caution;
  return AppColors.danger;
}

enum _SortMode { uptimeAsc, uptimeDesc, cameraId }

/// A simple future provider so pull-to-refresh can re-invoke the repository
/// without wiring a full StateNotifier for what is effectively a one-shot
/// list fetch per screen visit.
final _stationsProvider = FutureProvider.autoDispose<List<GISStation>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.stations();
});

final _statsProvider = FutureProvider.autoDispose<DashboardStats>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.stats();
});

class StationHealthScreen extends ConsumerStatefulWidget {
  const StationHealthScreen({super.key});

  @override
  ConsumerState<StationHealthScreen> createState() =>
      _StationHealthScreenState();
}

class _StationHealthScreenState extends ConsumerState<StationHealthScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _zoneFilter;
  String? _statusFilter; // 'low' | 'medium' | 'high'
  _SortMode _sortMode = _SortMode.uptimeAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(_stationsProvider);
    ref.invalidate(_statsProvider);
    await ref.read(_stationsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(_stationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ScreenAppBar(title: 'Station Health'),
      body: SafeArea(
        child: stationsAsync.when(
          loading: () => const LoadingList(itemCount: 8, height: 96),
          error: (err, _) => ErrorState(
            message: 'Could not load station data.\n${err.toString()}',
            onRetry: _refresh,
          ),
          data: (stations) {
            if (stations.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.videocam_off_outlined,
                      title: 'No stations configured',
                      subtitle:
                          'Camera trap stations will appear here once the reserve grid is set up.',
                    ),
                  ],
                ),
              );
            }
            return _StationHealthBody(
              stations: stations,
              query: _query,
              zoneFilter: _zoneFilter,
              statusFilter: _statusFilter,
              sortMode: _sortMode,
              searchController: _searchController,
              onQueryChanged: (v) => setState(() => _query = v),
              onZoneChanged: (v) => setState(() => _zoneFilter = v),
              onStatusChanged: (v) => setState(() => _statusFilter = v),
              onSortChanged: (v) => setState(() => _sortMode = v),
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

class _StationHealthBody extends ConsumerWidget {
  const _StationHealthBody({
    required this.stations,
    required this.query,
    required this.zoneFilter,
    required this.statusFilter,
    required this.sortMode,
    required this.searchController,
    required this.onQueryChanged,
    required this.onZoneChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final List<GISStation> stations;
  final String query;
  final String? zoneFilter;
  final String? statusFilter;
  final _SortMode sortMode;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onZoneChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<_SortMode> onSortChanged;
  final Future<void> Function() onRefresh;

  List<String> get _zones {
    final z = stations.map((s) => s.zone).where((z) => z.isNotEmpty).toSet().toList();
    z.sort();
    return z;
  }

  List<GISStation> get _filtered {
    var list = stations.where((s) {
      if (query.isNotEmpty &&
          !s.cameraId.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      if (zoneFilter != null && s.zone != zoneFilter) return false;
      if (statusFilter != null &&
          _statusInfo(s.operationalStatus).level != statusFilter) {
        return false;
      }
      return true;
    }).toList();

    switch (sortMode) {
      case _SortMode.uptimeAsc:
        list.sort((a, b) => a.uptimeRatio.compareTo(b.uptimeRatio));
        break;
      case _SortMode.uptimeDesc:
        list.sort((a, b) => b.uptimeRatio.compareTo(a.uptimeRatio));
        break;
      case _SortMode.cameraId:
        list.sort((a, b) => a.cameraId.compareTo(b.cameraId));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = _filtered;
    final grouped = <String, List<GISStation>>{};
    for (final s in filtered) {
      grouped.putIfAbsent(s.zone.isEmpty ? 'Unassigned' : s.zone, () => []).add(s);
    }
    final zoneKeys = grouped.keys.toList()..sort();

    final statsAsync = ref.watch(_statsProvider);

    // Running index across zones so the entrance stagger continues smoothly
    // rather than restarting at each zone boundary; staggerDelay already
    // caps the total wait so later items don't lag the scroll.
    var runningIndex = 0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: SpringEntry(
                child: _SummarySection(stations: stations, statsAsync: statsAsync),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: _SearchField(controller: searchController, onChanged: onQueryChanged),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _FilterSortBar(
                zones: _zones,
                zoneFilter: zoneFilter,
                statusFilter: statusFilter,
                sortMode: sortMode,
                onZoneChanged: onZoneChanged,
                onStatusChanged: onStatusChanged,
                onSortChanged: onSortChanged,
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No stations match your filters',
                subtitle: 'Try clearing the search or filters above.',
              ),
            )
          else
            for (final zone in zoneKeys) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _ZoneHeaderDelegate(
                  zone: zone,
                  count: grouped[zone]!.length,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.xs,
                ),
                sliver: SliverList.separated(
                  itemCount: grouped[zone]!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm + 2),
                  itemBuilder: (context, i) {
                    final station = grouped[zone]![i];
                    final delay = staggerDelay(runningIndex);
                    runningIndex++;
                    return SpringEntry(
                      delay: delay,
                      offset: 18,
                      child: _StationCard(station: station),
                    );
                  },
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.stations, required this.statsAsync});

  final List<GISStation> stations;
  final AsyncValue<DashboardStats> statsAsync;

  @override
  Widget build(BuildContext context) {
    final operational = stations
        .where((s) => _statusInfo(s.operationalStatus).level == 'low')
        .length;
    final degraded = stations
        .where((s) => _statusInfo(s.operationalStatus).level == 'medium')
        .length;
    final offline = stations
        .where((s) => _statusInfo(s.operationalStatus).level == 'high')
        .length;

    final total = stations.length;
    final activeFromStats = statsAsync.maybeWhen(
      data: (s) => s.activeStations,
      orElse: () => null,
    );
    final totalFromStats = statsAsync.maybeWhen(
      data: (s) => s.totalStations,
      orElse: () => null,
    );
    final headlineActive = activeFromStats ?? operational;
    final headlineTotal = totalFromStats ?? total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EyebrowTag(label: 'Network Status'),
        const SizedBox(height: AppSpace.md),
        Bezel(
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
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.fraunces(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foreground,
                              height: 1.05,
                              letterSpacing: -0.5,
                            ),
                            children: [
                              TextSpan(text: '$headlineActive'),
                              TextSpan(
                                text: ' / $headlineTotal',
                                style: GoogleFonts.fraunces(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'stations active',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.muted,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: total == 0
                        ? const SizedBox.shrink()
                        : _AnimatedPieChart(
                            operational: operational,
                            degraded: degraded,
                            offline: offline,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Container(height: 1, color: AppColors.hairline),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  _LegendChip(color: AppColors.positive, label: 'Operational', value: operational),
                  const SizedBox(width: AppSpace.md),
                  _LegendChip(color: AppColors.caution, label: 'Degraded', value: degraded),
                  const SizedBox(width: AppSpace.md),
                  _LegendChip(color: AppColors.danger, label: 'Offline', value: offline),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Spring-driven fill-in for the summary pie chart — the sweep grows from
/// zero on first build rather than snapping straight to its final value.
class _AnimatedPieChart extends StatefulWidget {
  const _AnimatedPieChart({
    required this.operational,
    required this.degraded,
    required this.offline,
  });

  final int operational;
  final int degraded;
  final int offline;

  @override
  State<_AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<_AnimatedPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppSpring.drive(_controller, AppSpring.gentle, from: 0, to: 1);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value.clamp(0.0, 1.0);
        final op = widget.operational * t;
        final de = widget.degraded * t;
        final off = widget.offline * t;
        final remainder = (widget.operational + widget.degraded + widget.offline) * (1 - t);
        return PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 26,
            sections: [
              if (op > 0)
                PieChartSectionData(
                  value: op,
                  color: AppColors.positive,
                  showTitle: false,
                  radius: 16,
                ),
              if (de > 0)
                PieChartSectionData(
                  value: de,
                  color: AppColors.caution,
                  showTitle: false,
                  radius: 16,
                ),
              if (off > 0)
                PieChartSectionData(
                  value: off,
                  color: AppColors.danger,
                  showTitle: false,
                  radius: 16,
                ),
              if (remainder > 0.001)
                PieChartSectionData(
                  value: remainder,
                  color: AppColors.surfaceSunken,
                  showTitle: false,
                  radius: 16,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: GoogleFonts.workSans(fontSize: 14, color: AppColors.foreground),
        decoration: InputDecoration(
          hintText: 'Search by camera ID…',
          hintStyle: GoogleFonts.workSans(color: AppColors.muted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.muted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _FilterSortBar extends StatelessWidget {
  const _FilterSortBar({
    required this.zones,
    required this.zoneFilter,
    required this.statusFilter,
    required this.sortMode,
    required this.onZoneChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final List<String> zones;
  final String? zoneFilter;
  final String? statusFilter;
  final _SortMode sortMode;
  final ValueChanged<String?> onZoneChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<_SortMode> onSortChanged;

  static const _statusOptions = [
    ('low', 'Operational'),
    ('medium', 'Degraded'),
    ('high', 'Offline'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        children: [
          _SortMenuChip(sortMode: sortMode, onSortChanged: onSortChanged),
          const SizedBox(width: AppSpace.sm),
          _FilterChoiceChip(
            label: 'All zones',
            selected: zoneFilter == null,
            onSelected: () => onZoneChanged(null),
          ),
          for (final z in zones) ...[
            const SizedBox(width: AppSpace.sm),
            _FilterChoiceChip(
              label: z,
              selected: zoneFilter == z,
              onSelected: () => onZoneChanged(zoneFilter == z ? null : z),
            ),
          ],
          const SizedBox(width: AppSpace.md),
          Container(width: 1, height: 20, color: AppColors.border),
          const SizedBox(width: AppSpace.md),
          for (final opt in _statusOptions) ...[
            _FilterChoiceChip(
              label: opt.$2,
              color: statusColor(opt.$1),
              selected: statusFilter == opt.$1,
              onSelected: () => onStatusChanged(statusFilter == opt.$1 ? null : opt.$1),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}

class _SortMenuChip extends StatelessWidget {
  const _SortMenuChip({required this.sortMode, required this.onSortChanged});
  final _SortMode sortMode;
  final ValueChanged<_SortMode> onSortChanged;

  String _label(_SortMode m) => switch (m) {
        _SortMode.uptimeAsc => 'Worst uptime first',
        _SortMode.uptimeDesc => 'Best uptime first',
        _SortMode.cameraId => 'Camera ID',
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortMode>(
      onSelected: onSortChanged,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      itemBuilder: (context) => _SortMode.values
          .map((m) => PopupMenuItem(
                value: m,
                child: Text(
                  _label(m),
                  style: GoogleFonts.workSans(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 15, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              _label(sortMode),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChoiceChip extends StatelessWidget {
  const _FilterChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return PressableScale(
      onTap: onSelected,
      scaleDown: 0.94,
      haptic: false,
      child: AnimatedContainer(
        duration: AppMotionDuration.quick,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.14) : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.45) : AppColors.border,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppMotionDuration.quick,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? c : AppColors.muted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _ZoneHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ZoneHeaderDelegate({required this.zone, required this.count});
  final String zone;
  final int count;

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
      child: Row(
        children: [
          Text(
            zone.toUpperCase(),
            style: GoogleFonts.workSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: AppColors.border)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.workSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ZoneHeaderDelegate oldDelegate) =>
      oldDelegate.zone != zone || oldDelegate.count != count;
}

class _StationCard extends StatelessWidget {
  const _StationCard({required this.station});
  final GISStation station;

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(station.operationalStatus);
    final uptimeColor = _uptimeColor(station.uptimeRatio);
    final uptimePct = (station.uptimeRatio * 100).clamp(0, 100).toStringAsFixed(0);

    final subLine = [
      if (station.subRegion != null && station.subRegion!.isNotEmpty) station.subRegion,
      if (station.habitat != null && station.habitat!.isNotEmpty) station.habitat,
    ].whereType<String>().join(' · ');

    return Bezel(
      padding: const EdgeInsets.all(AppSpace.md),
      outerRadius: AppRadius.lg,
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.videocam_rounded, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.cameraId,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                      ),
                    ),
                    if (subLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subLine,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: info.label, level: info.level),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Text(
                'Uptime',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
              const Spacer(),
              Text(
                '$uptimePct%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: uptimeColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _UptimeBar(ratio: station.uptimeRatio, color: uptimeColor),
          if (station.nearestWaterKm != null ||
              station.nearestVillageKm != null ||
              (station.trailType != null && station.trailType!.isNotEmpty)) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (station.nearestWaterKm != null)
                  _MetaTag(
                    icon: Icons.water_drop_outlined,
                    text: '${station.nearestWaterKm!.toStringAsFixed(1)} km to water',
                  ),
                if (station.nearestVillageKm != null)
                  _MetaTag(
                    icon: Icons.home_outlined,
                    text: '${station.nearestVillageKm!.toStringAsFixed(1)} km to village',
                  ),
                if (station.trailType != null && station.trailType!.isNotEmpty)
                  _MetaTag(icon: Icons.route_outlined, text: station.trailType!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Uptime progress bar with a spring-driven fill-in on first build, instead
/// of an instant static bar.
class _UptimeBar extends StatefulWidget {
  const _UptimeBar({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  State<_UptimeBar> createState() => _UptimeBarState();
}

class _UptimeBarState extends State<_UptimeBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppSpring.drive(_controller, AppSpring.settle, from: 0, to: 1);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value.clamp(0.0, 1.0);
          return LinearProgressIndicator(
            value: widget.ratio.clamp(0.0, 1.0) * t,
            minHeight: 6,
            backgroundColor: AppColors.surfaceSunken,
            valueColor: AlwaysStoppedAnimation(widget.color),
          );
        },
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ],
    );
  }
}
