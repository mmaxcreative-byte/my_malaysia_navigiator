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
  });

  final String name;
  final String address;
  final LatLng location;
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
}

/// Laluan penuh dari asal ke destinasi.
class NavRoute {
  const NavRoute({
    required this.distance,
    required this.duration,
    required this.coordinates,
    required this.steps,
  });

  /// Jumlah jarak (meter).
  final double distance;

  /// Jumlah masa (saat), termasuk trafik semasa.
  final double duration;

  /// Garisan laluan untuk dilukis di peta.
  final List<LatLng> coordinates;

  final List<NavStep> steps;
}
