import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// One-shot check of whether device GPS is usable right now — used only
/// for the lightweight "GPS locked / unavailable" chip on Home. The actual
/// patrol tracking (`ActivePatrolController`) does its own, more careful,
/// permission handling + simulated fallback.
final gpsReadyProvider = FutureProvider<bool>((ref) async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
});

/// Best-effort current position for "distance from me" sorts (Stations
/// list). Returns null (never throws) when location isn't available —
/// callers should treat that as "unknown distance" rather than blocking.
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    ).timeout(const Duration(seconds: 6));
  } catch (_) {
    return null;
  }
});
