import 'package:material_ui/material_ui.dart';

import 'models.dart';

/// Arahan pemanduan dalam Bahasa Melayu, dijana daripada jenis
/// gerakan Mapbox (supaya tidak bergantung pada bahasa API).
String instructionFor(NavStep step) {
  final road = step.name.trim();
  final toRoad = road.isEmpty ? '' : ' ke $road';
  final dir = _direction(step.modifier);

  switch (step.type) {
    case 'depart':
      return road.isEmpty ? 'Mula perjalanan' : 'Mula perjalanan di $road';
    case 'arrive':
      if (step.waypointArrival) return 'Tiba di hentian';
      if (step.modifier == 'left') return 'Destinasi di sebelah kiri';
      if (step.modifier == 'right') return 'Destinasi di sebelah kanan';
      return 'Anda tiba di destinasi';
    case 'turn':
      return '${_turnPhrase(step.modifier)}$toRoad';
    case 'end of road':
      return 'Di hujung jalan, ${_turnPhrase(step.modifier).toLowerCase()}$toRoad';
    case 'merge':
      return dir.isEmpty ? 'Bergabung$toRoad' : 'Bergabung $dir$toRoad';
    case 'on ramp':
      return dir.isEmpty
          ? 'Ambil susur masuk$toRoad'
          : 'Ambil susur masuk $dir$toRoad';
    case 'off ramp':
      return dir.isEmpty
          ? 'Ambil susur keluar$toRoad'
          : 'Ambil susur keluar $dir$toRoad';
    case 'fork':
      if (step.modifier.contains('left')) return 'Ikut cabang kiri$toRoad';
      if (step.modifier.contains('right')) return 'Ikut cabang kanan$toRoad';
      return 'Ikut cabang$toRoad';
    case 'roundabout':
    case 'rotary':
      final exit = step.exit;
      return exit == null
          ? 'Masuk bulatan$toRoad'
          : 'Di bulatan, ambil susur keluar ke-$exit$toRoad';
    case 'roundabout turn':
      return 'Di bulatan, ${_turnPhrase(step.modifier).toLowerCase()}$toRoad';
    case 'exit roundabout':
    case 'exit rotary':
      return 'Keluar dari bulatan$toRoad';
    case 'continue':
      if (step.modifier == 'uturn') return 'Buat pusingan U$toRoad';
      return dir.isEmpty || step.modifier == 'straight'
          ? 'Teruskan$toRoad'
          : 'Teruskan $dir$toRoad';
    case 'new name':
    case 'notification':
    default:
      return 'Teruskan$toRoad';
  }
}

String _turnPhrase(String modifier) {
  switch (modifier) {
    case 'left':
      return 'Belok kiri';
    case 'right':
      return 'Belok kanan';
    case 'slight left':
      return 'Belok sedikit ke kiri';
    case 'slight right':
      return 'Belok sedikit ke kanan';
    case 'sharp left':
      return 'Belok tajam ke kiri';
    case 'sharp right':
      return 'Belok tajam ke kanan';
    case 'uturn':
      return 'Buat pusingan U';
    case 'straight':
      return 'Jalan terus';
    default:
      return 'Teruskan';
  }
}

String _direction(String modifier) {
  if (modifier.contains('left')) return 'ke kiri';
  if (modifier.contains('right')) return 'ke kanan';
  return '';
}

/// Ikon untuk setiap jenis gerakan.
IconData iconFor(NavStep step) {
  final m = step.modifier;
  switch (step.type) {
    case 'arrive':
      return Icons.flag;
    case 'depart':
      return Icons.navigation;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
    case 'exit roundabout':
    case 'exit rotary':
      return Icons.roundabout_left;
    case 'merge':
      return Icons.merge;
    case 'fork':
      return m.contains('left') ? Icons.fork_left : Icons.fork_right;
    case 'on ramp':
    case 'off ramp':
      return m.contains('left') ? Icons.ramp_left : Icons.ramp_right;
  }
  switch (m) {
    case 'left':
      return Icons.turn_left;
    case 'right':
      return Icons.turn_right;
    case 'slight left':
      return Icons.turn_slight_left;
    case 'slight right':
      return Icons.turn_slight_right;
    case 'sharp left':
      return Icons.turn_sharp_left;
    case 'sharp right':
      return Icons.turn_sharp_right;
    case 'uturn':
      return Icons.u_turn_right;
    default:
      return Icons.straight;
  }
}

/// 350 m, 1.2 km, 25 km
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100
        ? (meters / 5).round() * 5
        : (meters / 10).round() * 10;
    return '$rounded m';
  }
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// 1 min, 14 min, 1 j 25 min
String formatDuration(double seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin < 1) return '1 min';
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '$h j' : '$h j $m min';
}

/// Waktu tiba, contoh: 23:45
String formatClock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}


/// Huruf pertama kecil (untuk sambung ayat: "Dalam 300 meter, belok kiri").
String lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Jarak untuk disebut oleh suara: "300 meter", "1 setengah kilometer".
String spokenDistance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100
        ? ((meters / 10).round() * 10).clamp(10, 100)
        : (meters / 50).round() * 50;
    return '$rounded meter';
  }
  final halves = (meters / 500).round(); // gandaan 0.5 km
  final whole = halves ~/ 2;
  final half = halves.isOdd;
  if (whole == 0) return 'setengah kilometer';
  return half ? '$whole setengah kilometer' : '$whole kilometer';
}

/// Arahan suara sebelum gerakan: "Dalam 300 meter, belok kiri ke Jalan Duta".
String spokenAhead(NavStep step, double meters) =>
    'Dalam ${spokenDistance(meters)}, ${lowerFirst(instructionFor(step))}';

/// Nama insiden dalam Bahasa Melayu.
String incidentLabel(String type) {
  switch (type) {
    case 'accident':
      return 'Kemalangan';
    case 'congestion':
      return 'Kesesakan';
    case 'construction':
      return 'Kerja jalan';
    case 'disabled_vehicle':
      return 'Kenderaan rosak';
    case 'lane_restriction':
      return 'Lorong ditutup';
    case 'road_closure':
      return 'Jalan ditutup';
    case 'road_hazard':
      return 'Bahaya di jalan';
    case 'weather':
      return 'Cuaca buruk / banjir';
    case 'planned_event':
      return 'Acara di jalan';
    case 'mass_transit':
      return 'Gangguan pengangkutan awam';
    default:
      return 'Insiden jalan';
  }
}

IconData incidentIcon(String type) {
  switch (type) {
    case 'accident':
      return Icons.car_crash;
    case 'congestion':
      return Icons.traffic;
    case 'construction':
      return Icons.construction;
    case 'disabled_vehicle':
      return Icons.car_repair;
    case 'road_closure':
      return Icons.block;
    case 'weather':
      return Icons.flood;
    default:
      return Icons.warning_amber_rounded;
  }
}

/// Ikon anak panah untuk satu arah lorong.
IconData laneIcon(String indication) {
  switch (indication) {
    case 'left':
      return Icons.turn_left;
    case 'right':
      return Icons.turn_right;
    case 'slight left':
      return Icons.turn_slight_left;
    case 'slight right':
      return Icons.turn_slight_right;
    case 'sharp left':
      return Icons.turn_sharp_left;
    case 'sharp right':
      return Icons.turn_sharp_right;
    case 'uturn':
      return Icons.u_turn_right;
    default:
      return Icons.straight;
  }
}

/// Pilih arah lorong yang paling sesuai untuk dipaparkan.
String laneDisplayIndication(LaneInfo lane, String maneuverModifier) {
  final v = lane.validIndication;
  if (v != null && v.isNotEmpty) return v;
  if (lane.valid && lane.indications.contains(maneuverModifier)) {
    return maneuverModifier;
  }
  return lane.indications.isEmpty ? 'straight' : lane.indications.first;
}


/// Teks utama papan tanda: destinasi papan tanda (jika ada), atau arahan.
/// "E2: Skudai, Johor Bahru" -> "Skudai / Johor Bahru"
String signTitle(NavStep step) {
  var d = step.destinations.trim();
  if (d.isEmpty) return instructionFor(step);
  final colon = d.indexOf(':');
  if (colon >= 0 && colon < d.length - 1) d = d.substring(colon + 1).trim();
  return d.split(RegExp(r'\s*,\s*')).where((e) => e.isNotEmpty).join(' / ');
}

/// Kod laluan pada papan tanda, contoh "E2" daripada "E2: Skudai".
String? signRoute(NavStep step) {
  final d = step.destinations;
  final colon = d.indexOf(':');
  if (colon <= 0) return null;
  final code = d.substring(0, colon).trim();
  return code.isEmpty ? null : code;
}

/// Waktu 12 jam: (4:25, PTG)
(String, String) formatClock12(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return ('$h12:$mm', t.hour < 12 ? 'PG' : 'PTG');
}

/// Masa sebagai (nilai, unit): (14, min) atau (1:25, jam)
(String, String) durationParts(double seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin < 60) return ('${totalMin < 1 ? 1 : totalMin}', 'min');
  final h = totalMin ~/ 60;
  final m = (totalMin % 60).toString().padLeft(2, '0');
  return ('$h:$m', 'jam');
}

/// Jarak sebagai (nilai, unit): (350, m) atau (8.4, km)
(String, String) distanceParts(double meters) {
  final text = formatDistance(meters);
  final i = text.lastIndexOf(' ');
  return (text.substring(0, i), text.substring(i + 1));
}
