import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

// -----------------------------------------------------------------------
// Blank Frame Trash
//
// Mirrors the intent of frontend-v2's BlankFrameTrashView.tsx: camera-trap
// captures that an on-device/edge classifier flagged as "blank" (no animal
// — a false trigger from wind, leaves, heat shimmer, etc.) are quarantined
// here instead of being silently discarded. A ranger reviews the thumbnails
// and either:
//   - restores a frame back into the working dataset (the classifier was
//     wrong and an animal actually was present), or
//   - purges it permanently (confirmed genuinely blank).
//
// TODO(backend): There is no `/api/blank-frames` route on the FastAPI
// backend yet (confirmed against lib/core/repository.dart — only
// stats/gallery/gis/stations/alerts/identify/review-queue/model-status are
// wired). frontend-v2's own blankFrames.ts is itself mock/local-only, so
// this mirrors that: everything below is in-memory demo state. Once a real
// endpoint exists, replace `_BlankFrameNotifier`'s seed/restore/purge logic
// with calls like:
//   GET    /api/blank-frames                (list quarantined frames)
//   POST   /api/blank-frames/{id}/restore   (return frame to dataset)
//   DELETE /api/blank-frames/{id}           (purge one frame)
//   DELETE /api/blank-frames?ids=...        (bulk purge)
// and thread them through TygrisRepository the same way `reviewQueue()` /
// `resolveReview()` are wired today, instead of the local notifier here.
// -----------------------------------------------------------------------

enum BlankFrameStatus { quarantined, kept, purged }

@immutable
class BlankFrameItem {
  const BlankFrameItem({
    required this.id,
    required this.station,
    required this.filename,
    required this.capturedAt,
    required this.confidence,
    required this.fileSizeKb,
    required this.possiblyMisclassified,
    this.status = BlankFrameStatus.quarantined,
  });

  final String id;
  final String station;
  final String filename;
  final DateTime capturedAt;
  final double confidence; // model confidence the frame is blank, 0-1
  final int fileSizeKb;
  final bool possiblyMisclassified; // heuristic "check this" flag
  final BlankFrameStatus status;

  BlankFrameItem copyWith({BlankFrameStatus? status}) {
    return BlankFrameItem(
      id: id,
      station: station,
      filename: filename,
      capturedAt: capturedAt,
      confidence: confidence,
      fileSizeKb: fileSizeKb,
      possiblyMisclassified: possiblyMisclassified,
      status: status ?? this.status,
    );
  }
}

String formatKb(int kb) {
  if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
  return '$kb KB';
}

/// In-memory notifier standing in for the not-yet-built backend endpoint.
/// Seeds a small, plausible quarantine batch so the review/restore/purge
/// workflow can be demoed end to end — see TODO(backend) above.
class BlankFrameNotifier extends StateNotifier<List<BlankFrameItem>> {
  BlankFrameNotifier() : super(_seed());

  static List<BlankFrameItem> _seed() {
    final stations = [
      'PENCH-CAM-014',
      'PENCH-CAM-027',
      'PENCH-CAM-041',
      'PENCH-CAM-058',
    ];
    final rand = Random(42);
    final now = DateTime.now();
    final items = <BlankFrameItem>[];
    var counter = 4000;
    for (var b = 0; b < 3; b++) {
      final station = stations[b % stations.length];
      final ingestedAt = now.subtract(Duration(days: 3 - b));
      final count = 4 + rand.nextInt(4);
      for (var i = 0; i < count; i++) {
        final confidence = 0.55 + rand.nextDouble() * 0.44;
        final misclassified = rand.nextDouble() < 0.15;
        items.add(BlankFrameItem(
          id: 'F${counter++}',
          station: station,
          filename: 'IMG_$counter.JPG',
          capturedAt:
              ingestedAt.subtract(Duration(minutes: rand.nextInt(240))),
          confidence: confidence.clamp(0.0, 0.99),
          fileSizeKb: 1800 + rand.nextInt(2600),
          possiblyMisclassified: misclassified,
        ));
      }
    }
    return items;
  }

  void restore(Iterable<String> ids) => _setStatus(ids, BlankFrameStatus.kept);

  void purge(Iterable<String> ids) =>
      _setStatus(ids, BlankFrameStatus.purged);

  /// Undoes a purge (used by the undo snackbar) by putting frames back into
  /// quarantine rather than "kept", since nothing was actually reviewed yet.
  void unpurge(Iterable<String> ids) =>
      _setStatus(ids, BlankFrameStatus.quarantined);

  void _setStatus(Iterable<String> ids, BlankFrameStatus status) {
    final idSet = ids.toSet();
    state = [
      for (final item in state)
        if (idSet.contains(item.id)) item.copyWith(status: status) else item,
    ];
  }
}

final blankFrameProvider =
    StateNotifierProvider<BlankFrameNotifier, List<BlankFrameItem>>(
        (ref) => BlankFrameNotifier());

class BlankFrameTrashScreen extends ConsumerStatefulWidget {
  const BlankFrameTrashScreen({super.key});

  @override
  ConsumerState<BlankFrameTrashScreen> createState() =>
      _BlankFrameTrashScreenState();
}

class _BlankFrameTrashScreenState
    extends ConsumerState<BlankFrameTrashScreen> {
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _clearSelection() => setState(_selected.clear);

  Future<void> _restoreSelected() async {
    ref.read(blankFrameProvider.notifier).restore(_selected);
    final count = _selected.length;
    _clearSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored $count frame${count == 1 ? '' : 's'} to dataset')),
    );
  }

  Future<void> _restoreOne(BlankFrameItem item) async {
    ref.read(blankFrameProvider.notifier).restore([item.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored ${item.filename} to dataset')),
    );
  }

  Future<void> _confirmPurge(List<BlankFrameItem> items) async {
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PurgeConfirmDialog(count: items.length),
    );
    if (confirmed != true) return;
    final ids = items.map((e) => e.id).toList();
    ref.read(blankFrameProvider.notifier).purge(ids);
    _clearSelection();
    if (!mounted) return;
    final count = ids.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Purged $count frame${count == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () =>
              ref.read(blankFrameProvider.notifier).unpurge(ids),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(blankFrameProvider);
    final quarantined =
        all.where((f) => f.status == BlankFrameStatus.quarantined).toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(_selecting ? '${_selected.length} selected' : 'Blank Frame Trash'),
        centerTitle: false,
        actions: _selecting
            ? [
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('Cancel'),
                ),
              ]
            : null,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: quarantined.isEmpty
          ? const _EmptyTrashState()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
                  child: const EyebrowTag(
                    label: 'Quarantine review',
                    icon: Icons.shield_moon_outlined,
                    color: AppColors.ochre,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                  child: _SummaryStrip(
                      all: all, quarantinedCount: quarantined.length),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                  child: const _Explainer(),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: quarantined.length,
                    itemBuilder: (context, index) {
                      final item = quarantined[index];
                      return SpringEntry(
                        delay: staggerDelay(index),
                        child: _FrameCard(
                          item: item,
                          selectMode: _selecting,
                          selected: _selected.contains(item.id),
                          onTap: () {
                            if (_selecting) {
                              _toggleSelect(item.id);
                            }
                          },
                          onLongPress: () => _toggleSelect(item.id),
                          onRestore: () => _restoreOne(item),
                          onPurge: () => _confirmPurge([item]),
                          onDismissedRestore: () => _restoreOne(item),
                          onDismissedPurge: () => _confirmPurge([item]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _selecting
          ? _SelectionActionBar(
              count: _selected.length,
              onRestore: _restoreSelected,
              onPurge: () => _confirmPurge(
                quarantined.where((f) => _selected.contains(f.id)).toList(),
              ),
            )
          : (quarantined.isNotEmpty
              ? _EmptyTrashBar(
                  count: quarantined.length,
                  onEmptyTrash: () => _confirmPurge(quarantined),
                )
              : null),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.all, required this.quarantinedCount});

  final List<BlankFrameItem> all;
  final int quarantinedCount;

  @override
  Widget build(BuildContext context) {
    final purged =
        all.where((f) => f.status == BlankFrameStatus.purged).toList();
    final kept = all.where((f) => f.status == BlankFrameStatus.kept).length;
    final spaceSavedKb =
        purged.fold<int>(0, (sum, f) => sum + f.fileSizeKb);

    return Bezel(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: AppSpace.sm),
      child: SizedBox(
        height: 78,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            _StatChip(
              icon: Icons.shield_moon_outlined,
              label: 'In quarantine',
              value: '$quarantinedCount',
              tone: quarantinedCount > 0 ? AppColors.caution : null,
            ),
            const SizedBox(width: 10),
            _StatChip(
              icon: Icons.save_outlined,
              label: 'Space saved',
              value: spaceSavedKb > 0 ? formatKb(spaceSavedKb) : '—',
            ),
            const SizedBox(width: 10),
            _StatChip(
              icon: Icons.restore_outlined,
              label: 'Restored',
              value: '$kept',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.label, required this.value, this.tone});

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 144,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tone ?? AppColors.foreground,
                ),
          ),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: AppColors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Frames classified as blank are staged here, not deleted '
              'immediately. Restore anything misclassified back into the '
              'working dataset, or purge once confirmed empty. Purging is '
              'permanent.',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.item,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRestore,
    required this.onPurge,
    required this.onDismissedRestore,
    required this.onDismissedPurge,
  });

  final BlankFrameItem item;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRestore;
  final VoidCallback onPurge;
  final VoidCallback onDismissedRestore;
  final VoidCallback onDismissedPurge;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      background: _swipeBackground(
        alignment: Alignment.centerLeft,
        color: AppColors.positive,
        icon: Icons.restore_outlined,
        label: 'Restore',
      ),
      secondaryBackground: _swipeBackground(
        alignment: Alignment.centerRight,
        color: AppColors.danger,
        icon: Icons.delete_outline,
        label: 'Purge',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDismissedRestore();
          return true;
        } else {
          // Purge requires explicit confirmation — never dismiss silently.
          onDismissedPurge();
          return false;
        }
      },
      child: PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.shadowTint,
                blurRadius: selected ? 10 : 10,
                spreadRadius: -6,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppRadius.bezelGap),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.circular(AppRadius.md - AppRadius.bezelGap),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: AppColors.surfaceSunken,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 28,
                          color: AppColors.borderStrong,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _pill(
                          '${(item.confidence * 100).toStringAsFixed(0)}% blank',
                          Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                      if (item.possiblyMisclassified)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: _pill(
                            'Check this',
                            AppColors.caution,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GestureDetector(
                          onTap: onLongPress,
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              selected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 15,
                              color: selected
                                  ? AppColors.navActiveBg
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.station,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          Text(
                            formatKb(item.fileSizeKb),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _miniButton(
                              label: 'Restore',
                              icon: Icons.restore_outlined,
                              color: AppColors.positive,
                              onTap: onRestore,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _miniButton(
                              label: 'Purge',
                              icon: Icons.delete_outline,
                              color: AppColors.danger,
                              onTap: onPurge,
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
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.onRestore,
    required this.onPurge,
  });

  final int count;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: PressableScale(
                onTap: onRestore,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.positiveSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: AppColors.positive.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.restore_outlined,
                          size: 16, color: AppColors.positive),
                      const SizedBox(width: 8),
                      Text(
                        'Restore $count',
                        style: const TextStyle(
                          color: AppColors.positive,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PressableScale(
                onTap: onPurge,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Purge $count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrashBar extends StatelessWidget {
  const _EmptyTrashBar({required this.count, required this.onEmptyTrash});

  final int count;
  final VoidCallback onEmptyTrash;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: PressableScale(
          onTap: onEmptyTrash,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.delete_sweep_outlined,
                    size: 16, color: AppColors.danger),
                const SizedBox(width: 8),
                Text(
                  'Empty trash ($count)',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurgeConfirmDialog extends StatelessWidget {
  const _PurgeConfirmDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(AppRadius.bezelGap),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowTintStrong,
              blurRadius: 24,
              spreadRadius: -8,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.circular(AppRadius.lg - AppRadius.bezelGap),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.dangerSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_forever_rounded,
                        color: AppColors.danger, size: 22),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      'Permanently purge $count frame${count == 1 ? '' : 's'}?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              const Text(
                'This removes the frames from quarantine for good. Nothing '
                'in the working dataset is affected — this only touches '
                'frames already staged as blank.',
                style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: AppSpace.xl),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.mutedStrong,
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpace.md),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: PressableScale(
                      onTap: () => Navigator.of(context).pop(true),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline,
                                size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Purge permanently',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.recycling_outlined,
      title: 'No blank frames pending review',
      subtitle:
          'Camera traps are running clean. New auto-flagged blanks from '
          'ingestion will appear here for review before permanent removal.',
    );
  }
}

/// Small date formatter kept local to this file; used if a future revision
/// surfaces capturedAt in the UI (e.g. a detail sheet).
String formatCapturedAt(DateTime dt) => DateFormat('MMM d, HH:mm').format(dt);
