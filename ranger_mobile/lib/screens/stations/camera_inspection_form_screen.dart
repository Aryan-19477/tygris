import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ids.dart';
import '../../core/observation_meta.dart';
import '../../core/sync_status.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/camera_inspection.dart';
import '../../models/photo.dart';
import '../../services/sync_queue_service.dart';
import '../../widgets/captured_photo_image.dart';
import '../../widgets/common.dart';

class CameraInspectionFormScreen extends ConsumerStatefulWidget {
  const CameraInspectionFormScreen({super.key, required this.cameraId, this.reason});
  final String cameraId;

  /// 'issue' | 'replace' | 'note' — just used to pre-select a sensible
  /// default status/action; the form itself always shows every field.
  final String? reason;

  @override
  ConsumerState<CameraInspectionFormScreen> createState() => _CameraInspectionFormScreenState();
}

class _CameraInspectionFormScreenState extends ConsumerState<CameraInspectionFormScreen> {
  late CameraInspectionStatus _status;
  late CameraActionTaken _action;
  int? _battery;
  int? _storage;
  final _issueController = TextEditingController();
  final _maintenanceController = TextEditingController();
  final List<XFile> _photos = [];
  bool _saving = false;

  static const _levels = [0, 25, 50, 75, 100];

  @override
  void initState() {
    super.initState();
    switch (widget.reason) {
      case 'issue':
        _status = CameraInspectionStatus.issue;
        _action = CameraActionTaken.none;
        break;
      case 'replace':
        _status = CameraInspectionStatus.replaced;
        _action = CameraActionTaken.replacedCard;
        break;
      default:
        _status = CameraInspectionStatus.ok;
        _action = CameraActionTaken.none;
    }
  }

  @override
  void dispose() {
    _issueController.dispose();
    _maintenanceController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      if (picked != null) setState(() => _photos.add(picked));
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ranger = ref.read(currentRangerProvider);
    final id = newId();
    final now = DateTime.now();
    final photoRepo = ref.read(photoRepositoryProvider);
    final photoIds = <String>[];
    for (final p in _photos) {
      final photoId = newId();
      await photoRepo.save(Photo(
        id: photoId,
        localPath: p.path,
        entityType: 'camera_inspection',
        entityId: id,
        capturedAt: now,
        syncStatus: SyncStatus.local,
      ));
      await ref.read(syncQueueServiceProvider).enqueue(entityType: 'photo', entityId: photoId);
      photoIds.add(photoId);
    }

    final inspection = CameraInspection(
      id: id,
      stationCameraId: widget.cameraId,
      rangerId: ranger?.id ?? 'unknown',
      timestampMs: now.millisecondsSinceEpoch,
      batteryLevel: _battery,
      storageLevel: _storage,
      status: _status,
      issueNotes: _issueController.text.trim().isEmpty ? null : _issueController.text.trim(),
      maintenanceNotes: _maintenanceController.text.trim().isEmpty ? null : _maintenanceController.text.trim(),
      photoIds: photoIds,
      actionTaken: _action,
      syncStatus: SyncStatus.local,
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(cameraInspectionRepositoryProvider).save(inspection);
    await ref.read(syncQueueServiceProvider).enqueue(entityType: 'camera_inspection', entityId: id);

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(appLocalizationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('${l10n.t('inspection.title')} · ${widget.cameraId}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxxl),
          children: [
            SectionLabel(l10n.t('inspection.status')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final s in CameraInspectionStatus.values)
                  IconChoiceChip(
                    label: l10n.t(inspectionStatusLabelKey(s)),
                    icon: Icons.circle,
                    color: inspectionStatusColor(s),
                    selected: _status == s,
                    onTap: () => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('inspection.action')),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final a in CameraActionTaken.values)
                  ChoiceChip(
                    label: Text(l10n.t(inspectionActionLabelKey(a))),
                    selected: _action == a,
                    onSelected: (_) => setState(() => _action = a),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('inspection.battery')),
            const SizedBox(height: AppSpace.sm),
            _LevelPicker(
              value: _battery,
              levels: _levels,
              unknownLabel: l10n.t('inspection.unknownLevel'),
              onChanged: (v) => setState(() => _battery = v),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('inspection.storage')),
            const SizedBox(height: AppSpace.sm),
            _LevelPicker(
              value: _storage,
              levels: _levels,
              unknownLabel: l10n.t('inspection.unknownLevel'),
              onChanged: (v) => setState(() => _storage = v),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('inspection.issueNotes')),
            const SizedBox(height: AppSpace.sm),
            TextField(controller: _issueController, maxLines: 2),
            const SizedBox(height: AppSpace.xl),
            SectionLabel(l10n.t('inspection.maintenanceNotes')),
            const SizedBox(height: AppSpace.sm),
            TextField(controller: _maintenanceController, maxLines: 2),
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
                    child: capturedPhotoImage(p.path, fit: BoxFit.cover),
                  ),
                PressableScale(
                  onTap: _addPhoto,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.borderStrong),
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
                onPressed: _saving ? null : _save,
                child: Text(l10n.t('inspection.save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.value, required this.levels, required this.unknownLabel, required this.onChanged});
  final int? value;
  final List<int> levels;
  final String unknownLabel;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final lvl in levels)
          ChoiceChip(
            label: Text('$lvl%'),
            selected: value == lvl,
            onSelected: (_) => onChanged(lvl),
          ),
        ChoiceChip(
          label: Text(unknownLabel),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
      ],
    );
  }
}
