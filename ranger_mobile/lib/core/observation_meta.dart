import 'package:flutter/material.dart';

import '../models/camera_inspection.dart';
import '../models/observation.dart';
import 'theme.dart';

/// Central icon/label/color mapping for the 9 field-logging categories and
/// severity levels, plus camera-station / inspection status — kept in one
/// place so every screen (quick-log sheet, map pins, history list, station
/// detail) draws these identically.
IconData observationTypeIcon(ObservationType type) {
  switch (type) {
    case ObservationType.wildlifeSighting:
      return Icons.pets_rounded;
    case ObservationType.wildlifeSign:
      return Icons.track_changes_rounded;
    case ObservationType.mortalityInjury:
      return Icons.healing_rounded;
    case ObservationType.humanImpact:
      return Icons.agriculture_rounded;
    case ObservationType.illegalActivity:
      return Icons.gpp_bad_rounded;
    case ObservationType.conflict:
      return Icons.warning_rounded;
    case ObservationType.fire:
      return Icons.local_fire_department_rounded;
    case ObservationType.water:
      return Icons.water_drop_rounded;
    case ObservationType.infrastructure:
      return Icons.construction_rounded;
    case ObservationType.camera:
      return Icons.videocam_rounded;
  }
}

String observationTypeLabelKey(ObservationType type) => 'obs.${type.name}';

String severityLabelKey(ObservationSeverity severity) =>
    'obs.severity.${severity.name}';

/// Label key for an auto-classified zone ('CORE'/'BUFFER'/'OUTSIDE' — see
/// `core/geo_context.dart#classifyZone`).
String zoneLabelKey(String zone) => 'obs.zone.${zone.toLowerCase()}';

Color severityColor(ObservationSeverity severity) {
  switch (severity) {
    case ObservationSeverity.info:
      return AppColors.muted;
    case ObservationSeverity.low:
      return AppColors.positive;
    case ObservationSeverity.medium:
      return AppColors.caution;
    case ObservationSeverity.high:
      return AppColors.priorityHigh;
    case ObservationSeverity.critical:
      return AppColors.sos;
  }
}

// The real PTR camera-station register (`camera_stations` in the shared
// backend DB) only ever carries `OPERATIONAL` — it's a GPS/beat inventory,
// not a live fleet-health feed — while the demo mock-seed data uses
// online/offline/issue for a richer status-chip demo. Both vocabularies are
// recognized here so real stations don't all render as "Unknown".
Color stationStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'online':
    case 'operational':
    case 'active':
      return AppColors.positive;
    case 'issue':
    case 'maintenance':
    case 'malfunction':
      return AppColors.caution;
    case 'offline':
    case 'damaged':
    case 'missing':
    case 'inactive':
      return AppColors.danger;
    default:
      return AppColors.muted;
  }
}

String stationStatusLabelKey(String status) {
  switch (status.toLowerCase()) {
    case 'online':
    case 'operational':
    case 'active':
      return 'stations.status.online';
    case 'issue':
    case 'maintenance':
    case 'malfunction':
      return 'stations.status.issue';
    case 'offline':
    case 'damaged':
    case 'missing':
    case 'inactive':
      return 'stations.status.offline';
    default:
      return 'stations.status.unknown';
  }
}

Color inspectionStatusColor(CameraInspectionStatus status) {
  switch (status) {
    case CameraInspectionStatus.ok:
      return AppColors.positive;
    case CameraInspectionStatus.issue:
      return AppColors.caution;
    case CameraInspectionStatus.replaced:
      return AppColors.accent;
    case CameraInspectionStatus.collected:
      return AppColors.muted;
  }
}

String inspectionStatusLabelKey(CameraInspectionStatus status) =>
    'inspection.status.${status.name}';

String inspectionActionLabelKey(CameraActionTaken action) =>
    'inspection.action.${action.name}';

IconData patrolTypeIcon(String typeName) {
  switch (typeName) {
    case 'foot':
      return Icons.directions_walk_rounded;
    case 'vehicle':
      return Icons.directions_car_rounded;
    case 'boat':
      return Icons.directions_boat_rounded;
    case 'bicycle':
      return Icons.pedal_bike_rounded;
    default:
      return Icons.directions_walk_rounded;
  }
}
