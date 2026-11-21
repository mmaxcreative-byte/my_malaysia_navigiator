import 'geo_utils.dart';

/// Koordinat ringkas (latitud, longitud).
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Satu hasil carian tempat.
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.address,
    required this.location,
    this.brand,
  });

  final String name;
  final String address;
  final LatLng location;

  /// Jenama (contoh: Petronas, Shell) — untuk stesen minyak.
  final String? brand;
}

/// Maklumat satu lorong di persimpangan.
class LaneInfo {
  const LaneInfo({
    required this.indications,
    required this.valid,
    this.validIndication,
  });

  /// Arah yang dibenarkan lorong ini: left, straight, right, dll.
  final List<String> indications;

  /// Lorong ini boleh digunakan untuk gerakan seterusnya.
  final bool valid;

  /// Arah lorong yang sepadan dengan laluan (jika diberi).
  final String? validIndication;
}

/// Satu langkah (belokan) dalam laluan.
class NavStep {
  const NavStep({
    required this.type,
    required this.modifier,
    required this.name,
    required this.distance,
    required this.duration,
    required this.location,
    this.exit,
    this.lanes = const [],
    this.waypointArrival = false,
  });

  /// Jenis gerakan Mapbox: depart, turn, arrive, roundabout, dll.
  final String type;

  /// Arah: left, right, slight left, straight, uturn, dll. (boleh kosong)
  final String modifier;

  /// Nama jalan selepas gerakan ini.
  final String name;

  /// Jarak (meter) dari gerakan ini hingga gerakan seterusnya.
  final double distance;

  /// Masa (saat) dari gerakan ini hingga gerakan seterusnya.
  final double duration;

  /// Lokasi gerakan.
  final LatLng location;

  /// Nombor susur keluar di bulatan (jika ada).
  final int? exit;

  /// Lorong di persimpangan gerakan ini (kosong jika tiada data).
  final List<LaneInfo> lanes;

  /// Tiba di hentian (bukan destinasi akhir).
  final bool waypointArrival;
}

/// Insiden di sepanjang laluan (kemalangan, kerja jalan, banjir, dll.).
class RouteIncident {
  const RouteIncident({
    required this.type,
    required this.description,
    required this.impact,
    required this.closed,
    required this.geometryIndex,
  });

  final String type;
  final String description;
  final String impact;
  final bool closed;

  /// Indeks titik dalam garisan laluan.
  final int geometryIndex;
}

/// Laluan penuh dari asal ke destinasi.
class NavRoute {
  NavRoute({
    required this.distance,
    required this.duration,
    required this.coordinates,
    required this.steps,
    this.durationTypical,
    this.congestion = const [],
    this.maxSpeedKmh = const [],
    this.incidents = const [],
  }) {
    cumulative = cumulativeDistances(coordinates);
    final total = cumulative.isEmpty ? 0.0 : cumulative.last;

    // Kedudukan setiap gerakan di sepanjang garisan laluan.
    var from = 0;
    stepAlong = [];
    for (final s in steps) {
      final i = nearestIndex(coordinates, s.location, from: from);
      from = i;
      stepAlong.add(cumulative.isEmpty ? 0.0 : cumulative[i]);
    }
    if (stepAlong.isNotEmpty) stepAlong[stepAlong.length - 1] = total;
  }

  /// Jumlah jarak (meter).
  final double distance;

  /// Jumlah masa (saat), termasuk trafik semasa.
  final double duration;

  /// Masa biasa tanpa trafik semasa (saat), jika ada.
  final double? durationTypical;

  /// Garisan laluan untuk dilukis di peta.
  final List<LatLng> coordinates;

  final List<NavStep> steps;

  /// Tahap kesesakan bagi setiap segmen garisan:
  /// low, moderate, heavy, severe, unknown.
  final List<String> congestion;

  /// Had laju (km/j) bagi setiap segmen; null jika tidak diketahui.
  final List<double?> maxSpeedKmh;

  final List<RouteIncident> incidents;

  /// Jarak terkumpul (meter) di setiap titik garisan.
  late final List<double> cumulative;

  /// Jarak terkumpul di mana setiap gerakan berlaku.
  late final List<double> stepAlong;

  double get geometryLength => cumulative.isEmpty ? 0 : cumulative.last;

  /// Lewat berbanding biasa (saat). 0 jika tiada data.
  double get trafficDelay {
    final typical = durationTypical;
    if (typical == null) return 0;
    final d = duration - typical;
    return d > 0 ? d : 0;
  }
}
