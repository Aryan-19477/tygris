/// Lightweight GPS sample — used inside [Patrol.route] and for "current
/// GPS" readouts across capture screens.
library;

class GPSPoint {
  GPSPoint({
    required this.lat,
    required this.lng,
    required this.timestampMs,
    this.accuracy,
    this.altitude,
  });

  final double lat;
  final double lng;
  final int timestampMs;
  final double? accuracy;
  final double? altitude;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  factory GPSPoint.fromJson(Map<String, dynamic> j) => GPSPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        timestampMs: j['timestamp_ms'] as int,
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        altitude: (j['altitude'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'timestamp_ms': timestampMs,
        'accuracy': accuracy,
        'altitude': altitude,
      };
}
