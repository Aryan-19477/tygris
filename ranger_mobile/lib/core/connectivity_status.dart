import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device currently has *any* network path (wifi/mobile/
/// ethernet) — not a guarantee the backend itself is reachable, just cheap
/// enough to decide whether it's worth pointing `flutter_map` at the live
/// OpenStreetMap tile server or falling back to a vector-only basemap.
///
/// Used by every map surface (`RangerMapScreen`, `ActivePatrolScreen`,
/// `PatrolReviewScreen`) so all three branch the same way instead of each
/// duplicating a connectivity check.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool toOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield toOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(toOnline);
});
