import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set by "Navigate" actions (station detail, task detail) to ask the
/// shared Map screen (`ranger_map_screen.dart`) to center on a specific
/// camera station or task the next time it builds. The map screen reads
/// and clears this after consuming it.
final mapFocusStationIdProvider = StateProvider<String?>((ref) => null);
final mapFocusTaskIdProvider = StateProvider<String?>((ref) => null);
