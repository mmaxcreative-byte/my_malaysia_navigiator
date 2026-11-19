import 'dart:math' as math;

import 'models.dart';

const double _earthRadius = 6371000.0; // meter

double _rad(double deg) => deg * math.pi / 180.0;

/// Jarak antara dua titik (meter), formula haversine.
double distanceBetween(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Jarak terdekat (meter) dari [p] ke garisan [line].
/// Guna unjuran rata tempatan — cukup tepat untuk jarak pendek.
double distanceToPolyline(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return double.infinity;
  if (line.length == 1) return distanceBetween(p, line.first);

  final cosLat = math.cos(_rad(p.lat));
  double x(LatLng q) => _rad(q.lng - p.lng) * cosLat * _earthRadius;
  double y(LatLng q) => _rad(q.lat - p.lat) * _earthRadius;

  var best = double.infinity;
  for (var i = 0; i < line.length - 1; i++) {
    final ax = x(line[i]), ay = y(line[i]);
    final bx = x(line[i + 1]), by = y(line[i + 1]);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy);
    if (d < best) best = d;
  }
  return best;
}

/// Kurangkan bilangan titik (untuk muatkan kamera ke laluan).
List<LatLng> sample(List<LatLng> points, int maxPoints) {
  if (points.length <= maxPoints) return points;
  final step = points.length / maxPoints;
  final out = <LatLng>[];
  for (var i = 0.0; i < points.length; i += step) {
    out.add(points[i.floor()]);
  }
  if (out.last != points.last) out.add(points.last);
  return out;
}
