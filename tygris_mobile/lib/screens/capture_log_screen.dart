import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'tiger_dossier_screen.dart';

/// Paginated capture history from /api/captures — the "Capture log" tab of
/// frontend-v2's CapturesView. Station chips filter by camera, exactly as
/// the web's station strip does.
class CaptureLogScreen extends ConsumerStatefulWidget {
  const CaptureLogScreen({super.key, this.initialCameraId});

  final String? initialCameraId;

  @override
  ConsumerState<CaptureLogScreen> createState() => _CaptureLogScreenState();
}

class _CaptureLogScreenState extends ConsumerState<CaptureLogScreen> {
  static const _pageSize = 30;

  final List<CaptureLogItem> _items = [];
  List<GISStation> _stations = const [];
  String? _cameraId;
  String? _nextBefore;
  bool _loading = false;
  Object? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _cameraId = widget.initialCameraId;
    _load(reset: true);
    ref.read(repositoryProvider).stations().then((s) {
      if (mounted) setState(() => _stations = s);
    }).catchError((_) {});
  }

  Future<void> _load({bool reset = false}) async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _nextBefore = null;
      }
    });
    try {
      final res = await ref.read(repositoryProvider).captures(
            limit: _pageSize,
            before: reset ? null : _nextBefore,
            cameraId: _cameraId,
          );
      // A newer filter change supersedes this response.
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items.addAll(res.items);
        _nextBefore = res.nextBefore;
      });
    } catch (e) {
      if (mounted && seq == _requestSeq) setState(() => _error = e);
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  void _setCamera(String? id) {
    if (id == _cameraId) return;
    _cameraId = id;
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenAppBar(title: 'Capture Log'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_stations.isNotEmpty) _stationStrip(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _stationStrip() {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xs),
        itemCount: _stations.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          if (i == 0) {
            return ChoicePill(
              label: 'All cameras',
              selected: _cameraId == null,
              onTap: () => _setCamera(null),
            );
          }
          final s = _stations[i - 1];
          final ok = s.operationalStatus.toUpperCase() == 'OPERATIONAL';
          return ChoicePill(
            label: s.cameraId,
            selected: _cameraId == s.cameraId,
            onTap: () =>
                _setCamera(_cameraId == s.cameraId ? null : s.cameraId),
            leading: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: ok ? AppColors.positive : AppColors.danger,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && _loading) {
      return const LoadingList(height: 150);
    }
    if (_items.isEmpty && _error != null) {
      return ErrorState(
        message: describeError(_error),
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No captures logged yet',
              subtitle: 'Captures appear here as camera traps report in.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => SpringEntry(
                  delay: staggerDelay(i),
                  child: _CaptureTile(item: _items[i]),
                ),
                childCount: _items.length,
              ),
            ),
          ),
          if (_nextBefore != null || (_loading && _items.isNotEmpty))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg, 0, AppSpace.lg, AppSpace.xxl),
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _load(),
                  child: Text(_loading ? 'Loading…' : 'Load more'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.item});
  final CaptureLogItem item;

  @override
  Widget build(BuildContext context) {
    final title = item.tigerName ?? item.tigerId ?? 'Unidentified';
    final level = item.alertLevel?.toUpperCase();
    return SectionCard(
      padding: EdgeInsets.zero,
      onTap: item.tigerId == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TigerDossierScreen(tigerId: item.tigerId!))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaImage(path: item.imageUrl),
                  if (level == 'CRITICAL' || level == 'CAUTION')
                    Positioned(
                      top: 8,
                      left: 8,
                      child: StatusBadge(
                          label: level!, level: level.toLowerCase()),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground)),
                  const SizedBox(height: 2),
                  Text(
                    '${item.cameraId} · ${formatTimestamp(item.timestamp)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.muted, height: 1.3),
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
