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

/// Jarak terkumpul (meter) di setiap titik garisan.
List<double> cumulativeDistances(List<LatLng> line) {
  final out = <double>[];
  var total = 0.0;
  for (var i = 0; i < line.length; i++) {
    if (i > 0) total += distanceBetween(line[i - 1], line[i]);
    out.add(total);
  }
  return out;
}

/// Indeks titik garisan yang paling hampir dengan [p], bermula dari [from].
int nearestIndex(List<LatLng> line, LatLng p, {int from = 0}) {
  if (line.isEmpty) return 0;
  var best = from.clamp(0, line.length - 1).toInt();
  var bestD = double.infinity;
  for (var i = best; i < line.length; i++) {
    final d = distanceBetween(line[i], p);
    if (d < bestD) {
      bestD = d;
      best = i;
      if (d < 1) break; // tepat di atas garisan — cukup
    }
  }
  return best;
}

/// Hasil "snap" kedudukan ke garisan laluan.
class Snap {
  const Snap(this.segment, this.offRoute, this.along);

  /// Indeks segmen (titik permulaan segmen).
  final int segment;

  /// Jarak dari garisan (meter).
  final double offRoute;

  /// Jarak sepanjang laluan dari permulaan (meter).
  final double along;
}

/// Cari titik terdekat pada garisan [line] untuk [p].
/// Guna unjuran rata tempatan — cukup tepat untuk jarak pendek.
Snap snapToLine(LatLng p, List<LatLng> line, [List<double>? cumulative]) {
  if (line.isEmpty) return const Snap(0, double.infinity, 0);
  if (line.length == 1) return Snap(0, distanceBetween(p, line.first), 0);

  final cum = cumulative ?? cumulativeDistances(line);
  final cosLat = math.cos(_rad(p.lat));
  double x(LatLng q) => _rad(q.lng - p.lng) * cosLat * _earthRadius;
  double y(LatLng q) => _rad(q.lat - p.lat) * _earthRadius;

  var bestD = double.infinity;
  var bestSeg = 0;
  var bestT = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final ax = x(line[i]), ay = y(line[i]);
    final bx = x(line[i + 1]), by = y(line[i + 1]);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy);
    if (d < bestD) {
      bestD = d;
      bestSeg = i;
      bestT = t;
    }
  }
  final segLen = cum[bestSeg + 1] - cum[bestSeg];
  return Snap(bestSeg, bestD, cum[bestSeg] + segLen * bestT);
}

/// Jarak terdekat (meter) dari [p] ke garisan [line].
double distanceToPolyline(LatLng p, List<LatLng> line) =>
    snapToLine(p, line).offRoute;

/// Kurangkan bilangan titik.
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

/// Kod garisan dalam format "polyline" Google/Mapbox (ketepatan 5).
String encodePolyline(List<LatLng> points) {
  final sb = StringBuffer();
  var prevLat = 0, prevLng = 0;

  void encode(int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lng = (p.lng * 1e5).round();
    encode(lat - prevLat);
    encode(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return sb.toString();
}
