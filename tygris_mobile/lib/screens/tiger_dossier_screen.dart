import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Local, self-contained family provider — auto-disposes when the pushed
/// route is popped so we don't keep every visited tiger's detail in memory.
final _galleryDetailProvider =
    FutureProvider.autoDispose.family<GalleryDetail, String>((ref, tigerId) {
  return ref.watch(repositoryProvider).galleryDetail(tigerId);
});

/// The tiger's profile page — the "star" screen of the app. Pushed route
/// with its own AppBar/back button, deep-linked from the catalogue grid.
/// Mirrors frontend-v2's TigerDossierView but redesigned as a native,
/// scrollable mobile dossier (hero card + station stats + capture timeline).
class TigerDossierScreen extends ConsumerWidget {
  const TigerDossierScreen({super.key, required this.tigerId});
  final String tigerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_galleryDetailProvider(tigerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailAsync.asData?.value.profile?.name ?? tigerId,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: detailAsync.when(
        loading: () => const _DossierShimmer(),
        error: (err, _) => ErrorState(
          message: err is Exception
              ? err.toString().replaceFirst('Exception: ', '')
              : 'Failed to load this tiger\'s dossier.',
          onRetry: () => ref.invalidate(_galleryDetailProvider(tigerId)),
        ),
        data: (detail) {
          if (detail.profile == null && detail.captures.isEmpty) {
            return const EmptyState(
              icon: Icons.pets_outlined,
              title: 'No dossier data available',
              subtitle: 'This individual has no recorded profile or captures yet.',
            );
          }
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async =>
                ref.invalidate(_galleryDetailProvider(tigerId)),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SpringEntry(
                    child: _HeroProfileCard(tigerId: tigerId, detail: detail),
                  ),
                ),
                if (detail.trajectory != null && detail.trajectory!.length >= 2)
                  SliverToBoxAdapter(
                    child: SpringEntry(
                      delay: staggerDelay(1),
                      child: _TrajectoryPreview(trajectory: detail.trajectory!),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _CapturesHeader(count: detail.captures.length),
                ),
                if (detail.captures.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24, bottom: 48),
                      child: EmptyState(
                        icon: Icons.camera_alt_outlined,
                        title: 'No captures recorded',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, 0, AppSpace.lg, AppSpace.xxl),
                    sliver: SliverList.separated(
                      itemCount: detail.captures.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => SpringEntry(
                        delay: staggerDelay(i),
                        child: _CaptureTile(capture: detail.captures[i]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroProfileCard extends StatelessWidget {
  const _HeroProfileCard({required this.tigerId, required this.detail});
  final String tigerId;
  final GalleryDetail detail;

  @override
  Widget build(BuildContext context) {
    final profile = detail.profile;
    final displayName = (profile?.name.trim().isNotEmpty ?? false)
        ? profile!.name
        : tigerId;
    final thumbnail = profile?.thumbnail;
    final totalCaptures = profile?.totalCaptures ?? detail.captures.length;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EyebrowTag(
            label: profile?.territorialStatus.isNotEmpty ?? false
                ? profile!.territorialStatus
                : 'Tiger Dossier',
            icon: Icons.badge_rounded,
          ),
          const SizedBox(height: AppSpace.md),
          Bezel(
            padding: EdgeInsets.zero,
            outerRadius: AppRadius.bezelOuter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.bezelInner),
                    topRight: Radius.circular(AppRadius.bezelInner),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 11,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbnail != null && thumbnail.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: thumbnail,
                            fit: BoxFit.cover,
                            placeholder: (context, _) =>
                                Container(color: AppColors.surfaceSunken),
                            errorWidget: (context, _, __) => const _HeroFallback(),
                          )
                        else
                          const _HeroFallback(),
                        // Gradient scrim for legibility of overlaid title/badges.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.accentDeep.withValues(alpha: 0.5),
                                Colors.transparent,
                                AppColors.accentDeep.withValues(alpha: 0.75),
                              ],
                              stops: const [0.0, 0.42, 1.0],
                            ),
                          ),
                        ),
                        if (profile?.territorialStatus.isNotEmpty ?? false)
                          Positioned(
                            top: 14,
                            left: 14,
                            child: _PillBadge(text: profile!.territorialStatus),
                          ),
                        Positioned(
                          bottom: 16,
                          left: 18,
                          right: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tigerId,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (profile?.sex.isNotEmpty ?? false)
                            _AttributeChip(
                              icon: profile!.sex.toUpperCase().startsWith('M')
                                  ? Icons.male_rounded
                                  : Icons.female_rounded,
                              label: profile.sex.toUpperCase(),
                            ),
                          if (profile != null && profile.ageYears > 0)
                            _AttributeChip(
                              icon: Icons.cake_rounded,
                              label: '${profile.ageYears.toStringAsFixed(1)}y',
                            ),
                          if (profile?.lifeStage.isNotEmpty ?? false)
                            _AttributeChip(
                              icon: Icons.pets_rounded,
                              label: profile!.lifeStage,
                            ),
                          if (profile?.territorialStatus.isNotEmpty ?? false)
                            _AttributeChip(
                              icon: Icons.shield_rounded,
                              label: profile!.territorialStatus,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'MCP Area',
                              value: profile != null && profile.mcpAreaKm2 > 0
                                  ? '${profile.mcpAreaKm2.toStringAsFixed(1)} km²'
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              label: 'Home Range',
                              value: profile != null &&
                                      profile.homeRangeTargetKm2 > 0
                                  ? '${profile.homeRangeTargetKm2.toStringAsFixed(1)} km²'
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              label: 'Captures',
                              value: '$totalCaptures',
                            ),
                          ),
                        ],
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

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      alignment: Alignment.center,
      child: const Icon(Icons.pets_rounded, size: 56, color: AppColors.muted),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.ochreSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.ochre.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.ochre),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPreview extends StatelessWidget {
  const _TrajectoryPreview({required this.trajectory});
  final List<List<double>> trajectory;

  @override
  Widget build(BuildContext context) {
    // Normalize lat/lon into a 0..1 box so fl_chart's LineChart can render
    // a lightweight sparkline-style path preview without a real map.
    final lats = trajectory.map((p) => p[0]).toList();
    final lons = trajectory.map((p) => p[1]).toList();
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b);
    final maxLon = lons.reduce((a, b) => a > b ? a : b);
    final latRange = (maxLat - minLat).abs() < 1e-9 ? 1.0 : maxLat - minLat;
    final lonRange = (maxLon - minLon).abs() < 1e-9 ? 1.0 : maxLon - minLon;

    final spots = <FlSpot>[
      for (var i = 0; i < trajectory.length; i++)
        FlSpot(
          (trajectory[i][1] - minLon) / lonRange,
          (trajectory[i][0] - minLat) / latRange,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
      child: Bezel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EyebrowTag(
              label: 'Movement Trace',
              icon: Icons.route_rounded,
              color: AppColors.ochre,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '${trajectory.length} recorded points',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              height: 90,
              child: LineChart(
                LineChartData(
                  minX: -0.1,
                  maxX: 1.1,
                  minY: -0.1,
                  maxY: 1.1,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: AppColors.accent,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          final isEndpoint =
                              index == 0 || index == spots.length - 1;
                          return FlDotCirclePainter(
                            radius: isEndpoint ? 4 : 2,
                            color: isEndpoint
                                ? AppColors.accentStrong
                                : AppColors.accent,
                            strokeWidth: 0,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.accent.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Full route rendering is available on the Reserve Map screen.',
              style: TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapturesHeader extends StatelessWidget {
  const _CapturesHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.xl, AppSpace.lg, AppSpace.md),
      child: Row(
        children: [
          Text(
            'Capture History',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.capture});
  final CaptureRecord capture;

  @override
  Widget build(BuildContext context) {
    final station = capture.cameraId ?? capture.station ?? 'Unknown station';
    final alertLevel = capture.alertLevel ?? 'SAFE';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowTint,
            blurRadius: 12,
            spreadRadius: -9,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: capture.image != null && capture.image!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: capture.image!,
                      fit: BoxFit.cover,
                      placeholder: (context, _) =>
                          Container(color: AppColors.surfaceSunken),
                      errorWidget: (context, _, __) => const _CaptureFallback(),
                    )
                  : const _CaptureFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        station,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    StatusBadge(label: alertLevel.toUpperCase(), level: alertLevel),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(capture.timestamp),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (capture.zone != null && capture.zone!.isNotEmpty)
                      _MetaBit(icon: Icons.map_rounded, text: capture.zone!),
                    if (capture.flankSide != null &&
                        capture.flankSide!.isNotEmpty)
                      _MetaBit(
                          icon: Icons.flip_camera_android_rounded,
                          text: '${capture.flankSide} flank'),
                    if (capture.speedKmh != null)
                      _MetaBit(
                          icon: Icons.speed_rounded,
                          text: '${capture.speedKmh!.toStringAsFixed(1)} km/h'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown time';
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('MMM d, yyyy · h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _MetaBit extends StatelessWidget {
  const _MetaBit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11.5, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
      ],
    );
  }
}

class _CaptureFallback extends StatelessWidget {
  const _CaptureFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      alignment: Alignment.center,
      child: const Icon(Icons.camera_alt_rounded, size: 18, color: AppColors.muted),
    );
  }
}

class _DossierShimmer extends StatelessWidget {
  const _DossierShimmer();

  @override
  Widget build(BuildContext context) {
    return LoadingList(itemCount: 6, height: 84);
  }
}
