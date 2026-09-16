import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'tiger_dossier_screen.dart';

/// Pairs & Family Groups — mirrors frontend-v2's PairsView: tiger pairs
/// repeatedly captured at the same camera within a 72h window, classified
/// with the same rules (any juvenile → family, opposite known sexes →
/// courtship, otherwise shared territory).
class PairsScreen extends ConsumerStatefulWidget {
  const PairsScreen({super.key});

  @override
  ConsumerState<PairsScreen> createState() => _PairsScreenState();
}

const _windowHours = 72;

enum _PairKind { courtship, family, overlap }

class _KindStyle {
  const _KindStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

const _kindStyles = {
  _PairKind.courtship:
      _KindStyle('Courtship', AppColors.danger, Icons.favorite_rounded),
  _PairKind.family:
      _KindStyle('Family group', AppColors.positive, Icons.groups_rounded),
  _PairKind.overlap:
      _KindStyle('Shared territory', AppColors.caution, Icons.place_rounded),
};

class _PairsData {
  _PairsData(this.pairs, this.byId);
  final List<(TigerAssociationPair, _PairKind)> pairs;
  final Map<String, GalleryIndividual> byId;
}

bool _isJuvenile(GalleryIndividual? t) {
  final stage = (t?.lifeStage ?? '').toUpperCase();
  return stage.contains('CUB') ||
      stage.contains('SUBADULT') ||
      stage.contains('JUVENILE');
}

_PairKind _classify(
    TigerAssociationPair p, Map<String, GalleryIndividual> byId) {
  if (_isJuvenile(byId[p.tigerA]) || _isJuvenile(byId[p.tigerB])) {
    return _PairKind.family;
  }
  if (p.sexA != p.sexB && p.sexA != 'U' && p.sexB != 'U') {
    return _PairKind.courtship;
  }
  return _PairKind.overlap;
}

class _PairsScreenState extends ConsumerState<PairsScreen> {
  late Future<_PairsData> _future = _load();
  _PairKind? _filter;

  Future<_PairsData> _load() async {
    final repo = ref.read(repositoryProvider);
    final results = await Future.wait([
      repo.tigerAssociations(
          limit: 30, oppositeSexOnly: false, windowHours: _windowHours),
      repo.gallery(),
    ]);
    final pairs = results[0] as List<TigerAssociationPair>;
    final gallery = results[1] as List<GalleryIndividual>;
    final byId = {for (final g in gallery) g.tigerId: g};
    return _PairsData([for (final p in pairs) (p, _classify(p, byId))], byId);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenAppBar(title: 'Pairs & Family Groups'),
      body: FutureBuilder<_PairsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 110);
          }
          if (snap.hasError) {
            return ErrorState(
                message: describeError(snap.error), onRetry: _refresh);
          }
          final data = snap.data!;
          final counts = {
            for (final k in _PairKind.values)
              k: data.pairs.where((p) => p.$2 == k).length,
          };
          final visible = _filter == null
              ? data.pairs
              : data.pairs.where((p) => p.$2 == _filter).toList();

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg,
                  AppSpace.lg, AppSpace.xxl + MediaQuery.paddingOf(context).bottom),
              children: [
                const EyebrowTag(
                    label: 'Co-occurrence', icon: Icons.favorite_rounded),
                const SizedBox(height: AppSpace.md),
                const Text(
                  'Pairs of tigers repeatedly captured at the same camera '
                  'within $_windowHours hours of each other — a signal of '
                  'courtship, a mother with cubs, or overlapping territory.',
                  style: TextStyle(
                      fontSize: 13.5, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: AppSpace.lg),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    ChoicePill(
                      label: 'All',
                      count: data.pairs.length,
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final k in _PairKind.values)
                      ChoicePill(
                        label: _kindStyles[k]!.label,
                        count: counts[k],
                        selected: _filter == k,
                        onTap: () => setState(() => _filter = k),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.xxl),
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No pairs match',
                      subtitle: 'Try a different filter.',
                    ),
                  )
                else
                  for (var i = 0; i < visible.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: SpringEntry(
                        delay: staggerDelay(i),
                        child: _PairCard(
                          pair: visible[i].$1,
                          kind: visible[i].$2,
                          byId: data.byId,
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

class _PairCard extends StatelessWidget {
  const _PairCard(
      {required this.pair, required this.kind, required this.byId});

  final TigerAssociationPair pair;
  final _PairKind kind;
  final Map<String, GalleryIndividual> byId;

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TigerDossierScreen(tigerId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final style = _kindStyles[kind]!;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            height: 46,
            child: Stack(
              children: [
                _Avatar(
                    tiger: byId[pair.tigerA],
                    onTap: () => _open(context, pair.tigerA)),
                Positioned(
                  left: 28,
                  child: _Avatar(
                      tiger: byId[pair.tigerB],
                      onTap: () => _open(context, pair.tigerB)),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _IdLink(
                        id: pair.tigerA,
                        onTap: () => _open(context, pair.tigerA)),
                    const Text('&', style: TextStyle(color: AppColors.muted)),
                    _IdLink(
                        id: pair.tigerB,
                        onTap: () => _open(context, pair.tigerB)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: style.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(style.icon, size: 11, color: style.color),
                          const SizedBox(width: 4),
                          Text(style.label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: style.color)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${pair.coOccurrences} co-occurrence${pair.coOccurrences == 1 ? '' : 's'} · within ${_windowHours}h',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (pair.sharedStations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.videocam_outlined,
                          size: 13, color: AppColors.muted),
                      for (final s in pair.sharedStations)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSunken,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.mutedStrong,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdLink extends StatelessWidget {
  const _IdLink({required this.id, required this.onTap});
  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(id,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground)),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.tiger, required this.onTap});
  final GalleryIndividual? tiger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadowTint,
                blurRadius: 6,
                offset: Offset(0, 2)),
          ],
        ),
        child: ClipOval(
          child: MediaImage(
              path: tiger?.thumbnail, fallbackIcon: Icons.pets_rounded),
        ),
      ),
    );
  }
}
