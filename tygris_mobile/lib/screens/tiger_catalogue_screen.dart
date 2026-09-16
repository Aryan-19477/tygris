import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'tiger_dossier_screen.dart';

/// Tab-root screen (embedded in AppShell's IndexedStack): a searchable,
/// filterable grid of every identified tiger, mirroring frontend-v2's
/// TigerCatalogueView but redesigned mobile-first as a 2-column card grid.
class TigerCatalogueScreen extends ConsumerStatefulWidget {
  const TigerCatalogueScreen({super.key});

  @override
  ConsumerState<TigerCatalogueScreen> createState() =>
      _TigerCatalogueScreenState();
}

enum _SexFilter { all, male, female }

class _TigerCatalogueScreenState extends ConsumerState<TigerCatalogueScreen> {
  late Future<List<GalleryIndividual>> _future;
  final _searchController = TextEditingController();
  String _query = '';
  _SexFilter _sexFilter = _SexFilter.all;
  String? _lifeStageFilter;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<GalleryIndividual>> _load() {
    return ref.read(repositoryProvider).gallery();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  List<GalleryIndividual> _applyFilters(List<GalleryIndividual> all) {
    var list = all;
    if (_sexFilter != _SexFilter.all) {
      final target = _sexFilter == _SexFilter.male ? 'M' : 'F';
      list = list
          .where((t) => (t.sex ?? '').toUpperCase().startsWith(target))
          .toList();
    }
    if (_lifeStageFilter != null) {
      list = list.where((t) => t.lifeStage == _lifeStageFilter).toList();
    }
    if (_query.isNotEmpty) {
      list = list.where((t) {
        final name = (t.name ?? '').toLowerCase();
        final id = t.tigerId.toLowerCase();
        return name.contains(_query) || id.contains(_query);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenAppBar(title: 'Tiger Catalogue'),
      body: FutureBuilder<List<GalleryIndividual>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Column(
              children: [
                _SearchAndFilterBar(
                  controller: _searchController,
                  sexFilter: _sexFilter,
                  lifeStages: const [],
                  lifeStageFilter: _lifeStageFilter,
                  onSexChanged: null,
                  onLifeStageChanged: null,
                ),
                const Expanded(child: _CatalogueGridShimmer()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error is Exception
                  ? snapshot.error.toString().replaceFirst('Exception: ', '')
                  : 'Failed to load the tiger catalogue.',
              onRetry: _refresh,
            );
          }

          final all = snapshot.data ?? const <GalleryIndividual>[];
          final lifeStages = all
              .map((t) => t.lifeStage)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final filtered = _applyFilters(all);

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: _refresh,
            child: Column(
              children: [
                _SearchAndFilterBar(
                  controller: _searchController,
                  sexFilter: _sexFilter,
                  lifeStages: lifeStages,
                  lifeStageFilter: _lifeStageFilter,
                  onSexChanged: (f) => setState(() => _sexFilter = f),
                  onLifeStageChanged: (s) =>
                      setState(() => _lifeStageFilter = s),
                ),
                Expanded(
                  child: all.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyState(
                              icon: Icons.pets_outlined,
                              title: 'No tigers in the catalogue yet',
                              subtitle:
                                  'Identified individuals will appear here once captures are processed.',
                            ),
                          ],
                        )
                      : filtered.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 80),
                                EmptyState(
                                  icon: Icons.search_off,
                                  title: 'No individuals match',
                                  subtitle: 'Try a different search or filter.',
                                ),
                              ],
                            )
                          : _CatalogueGrid(individuals: filtered),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchAndFilterBar extends StatelessWidget {
  const _SearchAndFilterBar({
    required this.controller,
    required this.sexFilter,
    required this.lifeStages,
    required this.lifeStageFilter,
    required this.onSexChanged,
    required this.onLifeStageChanged,
  });

  final TextEditingController controller;
  final _SexFilter sexFilter;
  final List<String> lifeStages;
  final String? lifeStageFilter;
  final ValueChanged<_SexFilter>? onSexChanged;
  final ValueChanged<String?>? onLifeStageChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EyebrowTag(
            label: 'Enrolled Individuals',
            icon: Icons.pets_rounded,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14.5, color: AppColors.foreground),
            decoration: InputDecoration(
              hintText: 'Search by name or tiger ID',
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.muted),
                      onPressed: controller.clear,
                    ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'All',
                  selected: sexFilter == _SexFilter.all,
                  onTap: onSexChanged == null
                      ? null
                      : () => onSexChanged!(_SexFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Male',
                  selected: sexFilter == _SexFilter.male,
                  onTap: onSexChanged == null
                      ? null
                      : () => onSexChanged!(_SexFilter.male),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Female',
                  selected: sexFilter == _SexFilter.female,
                  onTap: onSexChanged == null
                      ? null
                      : () => onSexChanged!(_SexFilter.female),
                ),
                if (lifeStages.isNotEmpty) ...[
                  Container(
                    width: 1,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: AppColors.border,
                  ),
                  for (final stage in lifeStages) ...[
                    _FilterChip(
                      label: stage,
                      selected: lifeStageFilter == stage,
                      onTap: onLifeStageChanged == null
                          ? null
                          : () => onLifeStageChanged!(
                              lifeStageFilter == stage ? null : stage),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.94,
      child: AnimatedContainer(
        duration: AppMotionDuration.quick,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.accentStrong : AppColors.border,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppMotionDuration.quick,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentForeground : AppColors.muted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _CatalogueGrid extends StatelessWidget {
  const _CatalogueGrid({required this.individuals});
  final List<GalleryIndividual> individuals;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemCount: individuals.length,
      itemBuilder: (context, i) => SpringEntry(
        delay: staggerDelay(i),
        child: _TigerCard(individual: individuals[i]),
      ),
    );
  }
}

class _TigerCard extends StatelessWidget {
  const _TigerCard({required this.individual});
  final GalleryIndividual individual;

  @override
  Widget build(BuildContext context) {
    final displayName = individual.name?.trim().isNotEmpty == true
        ? individual.name!
        : individual.tigerId;

    return PressableScale(
      scaleDown: 0.97,
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TigerDossierScreen(tigerId: individual.tigerId),
        ));
      },
      child: Container(
        padding: const EdgeInsets.all(AppRadius.bezelGap),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowTint,
              blurRadius: 14,
              spreadRadius: -8,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.circular(AppRadius.lg - AppRadius.bezelGap),
            border: Border.all(color: AppColors.hairline, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Thumbnail(url: individual.thumbnail),
                    if (individual.territorialStatus != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _TinyBadge(text: individual.territorialStatus!),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _SexIcon(sex: individual.sex),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontSize: 14.5, color: AppColors.foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(individual),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.camera_alt_rounded,
                            size: 12, color: AppColors.muted),
                        const SizedBox(width: 3),
                        Text('${individual.numCaptures}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                        const Spacer(),
                        Text(
                          _relativeTime(individual.lastSeen),
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(GalleryIndividual t) {
    final parts = <String>[];
    if (t.tigerId.isNotEmpty && t.name?.trim().isNotEmpty == true) {
      parts.add(t.tigerId);
    }
    if (t.ageYears != null) parts.add('${t.ageYears!.toStringAsFixed(1)}y');
    if (t.lifeStage != null && t.lifeStage!.isNotEmpty) parts.add(t.lifeStage!);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _SexIcon extends StatelessWidget {
  const _SexIcon({this.sex});
  final String? sex;

  @override
  Widget build(BuildContext context) {
    final s = (sex ?? '').toUpperCase();
    if (s.isEmpty) return const SizedBox.shrink();
    final isMale = s.startsWith('M');
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isMale ? Icons.male_rounded : Icons.female_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const _ThumbnailFallback();
    }
    return CachedNetworkImage(
      imageUrl: resolveMediaUrl(url!),
      fit: BoxFit.cover,
      placeholder: (context, _) => Container(color: AppColors.surfaceSunken),
      errorWidget: (context, _, __) => const _ThumbnailFallback(),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      alignment: Alignment.center,
      child: const Icon(Icons.pets_rounded, size: 30, color: AppColors.muted),
    );
  }
}

class _CatalogueGridShimmer extends StatelessWidget {
  const _CatalogueGridShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceSunken,
      highlightColor: AppColors.surface,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.68,
        ),
        itemCount: 8,
        itemBuilder: (context, i) => Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

/// Formats an ISO-ish timestamp string as a compact relative time
/// ("3h ago", "5d ago"), falling back to the raw string if unparsable.
String _relativeTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  DateTime? dt;
  try {
    dt = DateTime.parse(iso);
  } catch (_) {
    return iso;
  }
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('MMM d, yyyy').format(dt);
}
