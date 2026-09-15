import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/observation_meta.dart';
import '../../core/sync_status.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/observation.dart';
import '../../models/photo.dart';
import '../../services/active_patrol_controller.dart';
import '../../services/sync_queue_service.dart';
import '../../widgets/captured_photo_image.dart';
import '../../widgets/common.dart';

/// Shared structured form for all 9 field-logging categories. Used both
/// mid-patrol (`patrolId` set, reached from the active patrol's "+" sheet)
/// and stand-alone via Quick Report (`patrolId` null — see the design
/// note in `models/observation.dart` about Report == Observation with a
/// null patrolId).
class QuickLogFormScreen extends ConsumerStatefulWidget {
  const QuickLogFormScreen({super.key, required this.category, this.patrolId});

  final ObservationType category;
  final String? patrolId;

  @override
  ConsumerState<QuickLogFormScreen> createState() => _QuickLogFormScreenState();
}

class _QuickLogFormScreenState extends ConsumerState<QuickLogFormScreen> {
  ObservationSeverity _severity = ObservationSeverity.info;
  String? _subtype;
  final _descriptionController = TextEditingController();
  final List<XFile> _photos = [];
  double? _lat;
  double? _lng;
  bool _locating = true;
  bool _gpsFailed = false;
  bool _saving = false;
  final _now = DateTime.now();

  static const Map<ObservationType, List<String>> _subtypes = {
    ObservationType.wildlifeSighting: ['Tiger', 'Leopard', 'Deer', 'Wild boar', 'Elephant', 'Other'],
    ObservationType.wildlifeSign: ['Pugmarks', 'Scat', 'Scratch marks', 'Kill remains', 'Call heard'],
    ObservationType.mortalityInjury: ['Natural', 'Suspicious', 'Roadkill', 'Injured — needs response'],
    ObservationType.humanImpact: ['Grazing', 'Encroachment', 'Firewood collection', 'Tourism pressure'],
    ObservationType.illegalActivity: ['Snare', 'Poaching sign', 'Trespassing', 'Timber felling'],
    ObservationType.conflict: ['Livestock loss', 'Crop damage', 'Human injury', 'Property damage'],
    ObservationType.fire: ['Ground fire', 'Canopy fire', 'Controlled burn', 'Extinguished'],
    ObservationType.water: ['Waterhole level', 'Contamination', 'Dried up', 'Routine check'],
    ObservationType.infrastructure: ['Fence damage', 'Signage', 'Road/trail', 'Watchtower'],
    ObservationType.camera: ['Routine check', 'Malfunction', 'Tampered', 'Missing'],
  };

  @override
  void initState() {
    super.initState();
    _prefillLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _prefillLocation() async {
    // Mid-patrol: reuse the live patrol position instantly, no wait.
    final patrol = ref.read(activePatrolControllerProvider);
    if (widget.patrolId != null && patrol?.route.isNotEmpty == true) {
      setState(() {
        _lat = patrol!.route.last.lat;
        _lng = patrol.route.last.lng;
        _locating = false;
      });
      return;
    }
    setState(() {
      _locating = true;
      _gpsFailed = false;
    });
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locating = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Never fabricate a location for a real field report — an
      // observation's GPS is load-bearing data, unlike the map's demo
      // patrol-route simulation. If we can't get a real fix, say so and
      // let the ranger retry rather than silently attaching a fake
      // Pench-area coordinate to what they're about to submit.
      setState(() {
        _lat = null;
        _lng = null;
        _locating = false;
        _gpsFailed = true;
      });
    }
  }

  Future<void> _addPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      if (picked != null) setState(() => _photos.add(picked));
    } catch (_) {
      // Camera unavailable in this environment — silently ignore so the
      // rest of the form remains usable.
    }
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null || _saving) return;
    setState(() => _saving = true);

    final ranger = ref.read(currentRangerProvider);
    final id = newId();
    final photoIds = <String>[];
    final photoRepo = ref.read(photoRepositoryProvider);
    for (final photo in _photos) {
      final photoId = newId();
      await photoRepo.save(Photo(
        id: photoId,
        localPath: photo.path,
        entityType: 'observation',
        entityId: id,
        capturedAt: DateTime.now(),
        syncStatus: SyncStatus.local,
      ));
      await ref.read(syncQueueServiceProvider).enqueue(entityType: 'photo', entityId: photoId);
      photoIds.add(photoId);
    }

    final observation = Observation(
      id: id,
      patrolId: widget.patrolId,
      rangerId: ranger?.id ?? 'unknown',
      type: widget.category,
      subtype: _subtype,
      severity: _severity,
      description: _descriptionController.text.trim(),
      lat: _lat!,
      lng: _lng!,
      timestampMs: _now.millisecondsSinceEpoch,
      photoIds: photoIds,
      syncStatus: SyncStatus.local,
      createdAt: _now,
      updatedAt: _now,
    );

    await ref.read(observationRepositoryProvider).save(observation);
    if (widget.patrolId != null) {
      ref.read(activePatrolControllerProvider.notifier).addObservation(id);
    }
    await ref.read(syncQueueServiceProvider).enqueue(
          entityType: 'observation',
          entityId: id,
          priority: _severity == ObservationSeverity.critical ? 10 : 0,
        );

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    final ranger = ref.watch(currentRangerProvider);
    final subtypes = _subtypes[widget.category] ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t(observationTypeLabelKey(widget.category)))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            Bezel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_gpsFailed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.location_off_outlined, size: 18, color: AppColors.danger),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(l10n.t('obs.gpsUnavailable'),
                                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                          ),
                          TextButton(
                            onPressed: _prefillLocation,
                            child: Text(l10n.t('common.retry')),
                          ),
                        ],
                      ),
                    )
                  else
                    _readonlyRow(
                      Icons.place_outlined,
                      l10n.t('obs.gpsLabel'),
                      _locating
                          ? l10n.t('common.loading')
                          : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    ),
                  _readonlyRow(Icons.access_time_rounded, l10n.t('obs.timestampLabel'),
                      DateFormat('MMM d, yyyy · HH:mm').format(_now)),
                  _readonlyRow(Icons.badge_outlined, l10n.t('obs.rangerLabel'), ranger?.name ?? '—'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            if (subtypes.isNotEmpty) ...[
              SectionLabel(l10n.t('obs.subtype')),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final s in subtypes)
                    ChoiceChip(
                      label: Text(s),
                      selected: _subtype == s,
                      onSelected: (v) => setState(() => _subtype = v ? s : null),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
            ],
            SectionLabel(l10n.t('obs.severity.label')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final sev in ObservationSeverity.values)
                  IconChoiceChip(
                    label: l10n.t(severityLabelKey(sev)),
                    icon: Icons.circle,
                    color: severityColor(sev),
                    selected: _severity == sev,
                    onTap: () => setState(() => _severity = sev),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('obs.description')),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(hintText: l10n.t('obs.descriptionHint')),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('common.photos')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final p in _photos)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: capturedPhotoImage(
                      p.path,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.photo_outlined),
                    ),
                  ),
                PressableScale(
                  onTap: _addPhoto,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.borderStrong, style: BorderStyle.solid),
                      color: AppColors.surfaceSunken,
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xxl),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: (_locating || _saving || _lat == null || _lng == null) ? null : _save,
                child: Text(l10n.t('obs.save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readonlyRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: AppSpace.sm),
          Text('$label: ', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
