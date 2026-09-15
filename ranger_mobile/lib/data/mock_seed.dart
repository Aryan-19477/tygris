import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../core/local_store.dart';
import '../core/sync_status.dart';
import '../models/gps_point.dart';
import '../models/observation.dart';
import '../models/patrol.dart';
import '../models/ranger.dart';
import '../models/shared_gis.dart';
import '../models/task_item.dart';
import 'repository.dart';

/// Pench-reserve-like bounding box center used to scatter plausible demo
/// coordinates. Not the reserve's real precise boundary — just enough to
/// make the map/list screens feel geographically grounded.
const kReserveCenterLat = 21.68;
const kReserveCenterLng = 79.29;

/// Zone/sub-region labels used to give the Ranger map context even without
/// a live GISMapBundle from a real backend.
final List<ZoneLabel> seedZoneLabels = [
  ZoneLabel(name: 'Turia Core', centerLat: 21.72, centerLng: 79.27),
  ZoneLabel(name: 'Karmajhiri Buffer', centerLat: 21.64, centerLng: 79.33),
  ZoneLabel(name: 'Jamtara Range', centerLat: 21.69, centerLng: 79.22),
  ZoneLabel(name: 'Kurai Corridor', centerLat: 21.62, centerLng: 79.28),
];

/// Seeds a believable first-run dataset (idempotent — guarded by the
/// `seeded_v1` flag in [LocalStore]) so History, Tasks, Stations and the
/// Map are never empty on first launch.
Future<void> seedMockDataIfNeeded(ProviderContainer container) async {
  final store = container.read(localStoreProvider);
  if (store.getBool('seeded_v1')) return;

  final random = Random(42);

  // --- Ranger + team -----------------------------------------------
  const canonicalRangerId = '0dc2bb32-999a-4c09-8bc2-49ee9f0aa982';
  const canonicalTeamId = '227f78c4-e3c1-49e3-91e2-01ec8982c8dc';

  final ranger = Ranger(
    id: canonicalRangerId,
    name: 'Arjun Rathore',
    badgeId: 'PTR-0417',
    phone: '+91 98765 43210',
    role: RangerRole.ranger,
    teamId: canonicalTeamId,
    avatarSeed: 'arjun-rathore',
  );
  final team = Team(
    id: canonicalTeamId,
    name: 'Turia Beat Patrol',
    memberIds: [ranger.id],
    beatOrZone: 'Turia Core',
  );
  final seededRanger = ranger;

  await container.read(rangerRepositoryProvider).save(seededRanger);
  await container.read(teamRepositoryProvider).save(team);

  // --- Camera stations ------------------------------------------------
  final zones = ['Turia Core', 'Karmajhiri Buffer', 'Jamtara Range', 'Kurai Corridor'];
  final habitats = ['Dry deciduous', 'Bamboo mix', 'Riverine', 'Grassland'];
  final trailTypes = ['Forest road', 'Game trail', 'Fireline', 'Waterhole approach'];
  final statuses = ['online', 'online', 'online', 'offline', 'issue'];

  final stationRepo = container.read(stationRepositoryProvider);
  for (var i = 0; i < 15; i++) {
    final jitterLat = (random.nextDouble() - 0.5) * 0.14;
    final jitterLng = (random.nextDouble() - 0.5) * 0.14;
    final station = GISStation(
      cameraId: 'CAM-${(i + 1).toString().padLeft(3, '0')}',
      latitude: kReserveCenterLat + jitterLat,
      longitude: kReserveCenterLng + jitterLng,
      gridId: 'G${(i % 8) + 1}',
      zone: zones[i % zones.length],
      subRegion: zones[i % zones.length],
      habitat: habitats[i % habitats.length],
      operationalStatus: statuses[i % statuses.length],
      uptimeRatio: 0.55 + random.nextDouble() * 0.44,
      nearestWaterKm: double.parse((random.nextDouble() * 3).toStringAsFixed(1)),
      nearestVillageKm: double.parse((random.nextDouble() * 6).toStringAsFixed(1)),
      trailType: trailTypes[i % trailTypes.length],
    );
    await stationRepo.save(station);
  }

  // --- Tasks ------------------------------------------------------
  final taskRepo = container.read(taskRepositoryProvider);
  final now = DateTime.now();
  final taskSeeds = <TaskItem>[
    TaskItem(
      id: newId(),
      title: 'Inspect CAM-004 — reported low battery',
      instructions:
          'Station flagged low battery in last sync. Replace battery, confirm the unit powers on, and log an inspection.',
      assignedRangerId: seededRanger.id,
      lat: kReserveCenterLat + 0.03,
      lng: kReserveCenterLng - 0.02,
      locationLabel: 'CAM-004, Turia Core',
      status: TaskStatus.assigned,
      dueAt: now.add(const Duration(days: 1)),
      evidencePhotoIds: const [],
      syncStatus: SyncStatus.synced,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
    TaskItem(
      id: newId(),
      title: 'Clear fallen tree on Jamtara fireline',
      instructions:
          'A fallen tree is blocking the fireline access road near Jamtara. Coordinate with the forestry crew if needed; confirm the path is clear.',
      assignedRangerId: seededRanger.id,
      lat: kReserveCenterLat - 0.04,
      lng: kReserveCenterLng + 0.05,
      locationLabel: 'Jamtara Range, KM 3.2',
      status: TaskStatus.inProgress,
      dueAt: now.add(const Duration(hours: 6)),
      evidencePhotoIds: const [],
      syncStatus: SyncStatus.synced,
      createdAt: now.subtract(const Duration(hours: 20)),
      updatedAt: now.subtract(const Duration(hours: 2)),
    ),
    TaskItem(
      id: newId(),
      title: 'Waterhole check — Karmajhiri buffer',
      instructions:
          'Dry-season waterhole level check. Photograph water level marker and note any wildlife activity nearby.',
      assignedRangerId: seededRanger.id,
      lat: kReserveCenterLat + 0.01,
      lng: kReserveCenterLng + 0.06,
      locationLabel: 'Karmajhiri Buffer waterhole 2',
      status: TaskStatus.assigned,
      dueAt: now.add(const Duration(days: 2)),
      evidencePhotoIds: const [],
      syncStatus: SyncStatus.synced,
      createdAt: now.subtract(const Duration(hours: 10)),
      updatedAt: now.subtract(const Duration(hours: 10)),
    ),
    TaskItem(
      id: newId(),
      title: 'Deliver medical supplies to Kurai outpost',
      instructions:
          'Drop off first-aid restock at the Kurai forward outpost and confirm receipt with the duty ranger.',
      assignedRangerId: seededRanger.id,
      lat: kReserveCenterLat - 0.06,
      lng: kReserveCenterLng - 0.01,
      locationLabel: 'Kurai Corridor outpost',
      status: TaskStatus.completed,
      dueAt: now.subtract(const Duration(days: 2)),
      evidencePhotoIds: const [],
      completedAt: now.subtract(const Duration(days: 2, hours: -3)),
      syncStatus: SyncStatus.synced,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
    TaskItem(
      id: newId(),
      title: 'Replace SD card — CAM-011',
      instructions:
          'Storage nearing capacity. Swap SD card, offload existing footage per protocol, and log the inspection.',
      assignedRangerId: seededRanger.id,
      lat: kReserveCenterLat + 0.05,
      lng: kReserveCenterLng - 0.05,
      locationLabel: 'CAM-011, Turia Core',
      status: TaskStatus.assigned,
      dueAt: now.add(const Duration(days: 3)),
      evidencePhotoIds: const [],
      syncStatus: SyncStatus.synced,
      createdAt: now.subtract(const Duration(hours: 5)),
      updatedAt: now.subtract(const Duration(hours: 5)),
    ),
  ];
  for (final t in taskSeeds) {
    await taskRepo.save(t);
  }

  // --- Historical patrols + observations --------------------------
  final patrolRepo = container.read(patrolRepositoryProvider);
  final obsRepo = container.read(observationRepositoryProvider);

  Future<void> seedHistoricalPatrol({
    required DateTime startedAt,
    required PatrolType type,
    required int minutes,
    required List<ObservationType> obsTypes,
  }) async {
    final route = <GPSPoint>[];
    var lat = kReserveCenterLat + (random.nextDouble() - 0.5) * 0.05;
    var lng = kReserveCenterLng + (random.nextDouble() - 0.5) * 0.05;
    final points = 8 + random.nextInt(6);
    for (var i = 0; i < points; i++) {
      lat += (random.nextDouble() - 0.5) * 0.004;
      lng += (random.nextDouble() - 0.5) * 0.004;
      route.add(GPSPoint(
        lat: lat,
        lng: lng,
        timestampMs: startedAt
            .add(Duration(minutes: (minutes * i / points).round()))
            .millisecondsSinceEpoch,
      ));
    }
    final patrolId = newId();
    final obsIds = <String>[];
    for (final t in obsTypes) {
      final o = Observation(
        id: newId(),
        patrolId: patrolId,
        rangerId: seededRanger.id,
        type: t,
        severity: ObservationSeverity.values[random.nextInt(3)],
        description: _sampleDescriptionFor(t),
        lat: lat + (random.nextDouble() - 0.5) * 0.01,
        lng: lng + (random.nextDouble() - 0.5) * 0.01,
        timestampMs: startedAt.add(Duration(minutes: minutes ~/ 2)).millisecondsSinceEpoch,
        photoIds: const [],
        syncStatus: SyncStatus.synced,
        createdAt: startedAt,
        updatedAt: startedAt,
      );
      await obsRepo.save(o);
      obsIds.add(o.id);
    }
    final patrol = Patrol(
      id: patrolId,
      rangerId: seededRanger.id,
      teamId: team.id,
      patrolType: type,
      method: PatrolMethod.routine,
      status: PatrolStatus.completed,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(minutes: minutes)),
      route: route,
      distanceKm: double.parse((2.5 + random.nextDouble() * 4).toStringAsFixed(2)),
      durationSeconds: minutes * 60,
      observationIds: obsIds,
      coverageAreaKm2: double.parse((1 + random.nextDouble() * 2).toStringAsFixed(2)),
      notes: 'Routine patrol — no major incidents.',
      syncStatus: SyncStatus.synced,
      createdAt: startedAt,
      updatedAt: startedAt.add(Duration(minutes: minutes)),
    );
    await patrolRepo.save(patrol);
  }

  await seedHistoricalPatrol(
    startedAt: now.subtract(const Duration(days: 2, hours: 3)),
    type: PatrolType.foot,
    minutes: 95,
    obsTypes: [ObservationType.wildlifeSign, ObservationType.water],
  );
  await seedHistoricalPatrol(
    startedAt: now.subtract(const Duration(days: 5, hours: 1)),
    type: PatrolType.vehicle,
    minutes: 130,
    obsTypes: [ObservationType.wildlifeSighting, ObservationType.infrastructure, ObservationType.humanImpact],
  );

  await store.setBool('seeded_v1', true);
}

String _sampleDescriptionFor(ObservationType t) {
  switch (t) {
    case ObservationType.wildlifeSighting:
      return 'Adult tigress sighted crossing the fire trail, moved off into cover.';
    case ObservationType.wildlifeSign:
      return 'Fresh pugmarks and scat found near the trail junction.';
    case ObservationType.mortalityInjury:
      return 'Carcass of a spotted deer found, appears to be natural predation.';
    case ObservationType.humanImpact:
      return 'Signs of unauthorized grazing near the buffer boundary.';
    case ObservationType.illegalActivity:
      return 'Old snare wire found and removed from the area.';
    case ObservationType.conflict:
      return 'Villagers reported livestock loss near the corridor edge.';
    case ObservationType.fire:
      return 'Small ground fire, contained, likely from a discarded cigarette.';
    case ObservationType.water:
      return 'Waterhole level checked — adequate for the season.';
    case ObservationType.infrastructure:
      return 'Boundary fence post damaged, needs repair.';
    case ObservationType.camera:
      return 'Routine camera station check during patrol.';
  }
}
