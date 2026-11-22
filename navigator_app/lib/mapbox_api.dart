import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'geo_utils.dart';
import 'models.dart';

class MapboxApiException implements Exception {
  MapboxApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Panggilan ke API Mapbox: carian tempat, stesen minyak dan laluan.
class MapboxApi {
  MapboxApi(this.token);

  final String token;

  static const String _host = 'api.mapbox.com';

  static String _lngLat(LatLng p) =>
      '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}';

  // -----------------------------------------------------------------------
  // Carian
  // -----------------------------------------------------------------------

  /// Cari tempat di Malaysia (termasuk POI seperti KLCC, Mid Valley).
  ///
  /// Cara kerja (lebih mirip Google):
  /// 1. Cari berhampiran anda DAN di seluruh Malaysia serentak.
  /// 2. Jika tiada hasil yang sepadan dengan SEMUA perkataan (contoh
  ///    "bank islam banting"), anggap perkataan terakhir ialah nama tempat
  ///    ("banting") dan cari "bank islam" di sekitar tempat itu.
  /// 3. Susun ikut berapa banyak perkataan yang sepadan, kemudian jarak.
  Future<List<PlaceResult>> search(String query, {LatLng? near}) async {
    final tokens = _tokens(query);
    final batches = await Future.wait([
      _forward(query, near: near),
      if (near != null)
        _forward(query).catchError((Object _) => <PlaceResult>[]),
    ]);
    final scores = <PlaceResult, double>{};
    void addAll(Iterable<PlaceResult> list, {double minScore = 0}) {
      for (final p in list) {
        if (scores.keys.any((q) => _samePlace(p, q))) continue;
        final sc = _score(p, tokens);
        scores[p] = sc < minScore ? minScore : sc;
      }
    }

    for (final b in batches) {
      addAll(b);
    }

    final fullMatch = scores.values.any((sc) => sc >= tokens.length);
    if (tokens.length >= 2 && !fullMatch) {
      for (final split in const [1, 2]) {
        if (tokens.length <= split) break;
        final where = tokens.sublist(tokens.length - split).join(' ');
        final what = tokens.sublist(0, tokens.length - split).join(' ');
        final area = await _locality(where);
        if (area == null) continue;
        final nearArea = await _forward(what, near: area.location)
            .catchError((Object _) => <PlaceResult>[]);
        final within = nearArea
            .where((p) => distanceBetween(p.location, area.location) < 25000)
            .toList();
        if (within.isEmpty) continue;
        // Hasil di kawasan itu dianggap sepadan dengan nama tempat.
        addAll(within, minScore: tokens.length - 0.5);
        break;
      }
    }

    final list = scores.keys.toList()
      ..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        if (byScore != 0 || near == null) return byScore;
        return distanceBetween(near, a.location)
            .compareTo(distanceBetween(near, b.location));
      });
    return list.take(10).toList();
  }

  Future<List<PlaceResult>> _forward(String query, {LatLng? near}) async {
    final params = <String, String>{
      'q': query,
      'country': 'MY',
      'limit': '10',
      'access_token': token,
    };
    if (near != null) params['proximity'] = _lngLat(near);
    final json = await _getJson(
      Uri.https(_host, '/search/searchbox/v1/forward', params),
    );
    return _parsePlaces(json);
  }

  /// Cari bandar/kawasan (contoh "Banting") untuk dijadikan pusat carian.
  Future<PlaceResult?> _locality(String name) async {
    try {
      final json = await _getJson(Uri.https(_host, '/search/geocode/v6/forward', {
        'q': name,
        'country': 'MY',
        'types': 'place,locality,district,neighborhood',
        'limit': '1',
        'access_token': token,
      }));
      final list = _parsePlaces(json);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static List<String> _tokens(String q) => q
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 2)
      .toList();

  /// Bilangan perkataan carian yang ada dalam nama atau alamat.
  static double _score(PlaceResult p, List<String> tokens) {
    final text = '${p.name} ${p.address}'.toLowerCase();
    return tokens.where(text.contains).length.toDouble();
  }

  static bool _samePlace(PlaceResult a, PlaceResult b) =>
      a.name == b.name && distanceBetween(a.location, b.location) < 50;

  /// Cari stesen minyak. Jika [routeAhead] diberi, cari di sepanjang
  /// laluan (lencongan maksimum ~5 minit); jika tidak, cari berhampiran.
  Future<List<PlaceResult>> fuelStations({
    LatLng? near,
    List<LatLng>? routeAhead,
  }) async {
    Future<List<PlaceResult>> category(bool alongRoute) async {
      final params = <String, String>{
        'country': 'MY',
        'limit': '10',
        'access_token': token,
      };
      if (near != null) params['proximity'] = _lngLat(near);
      if (alongRoute) {
        params['route'] = encodePolyline(sample(routeAhead!, 80));
        params['route_geometry'] = 'polyline';
        params['sar_type'] = 'isochrone';
        params['time_deviation'] = '5';
      }
      final json = await _getJson(Uri.https(
        _host,
        '/search/searchbox/v1/category/gas_station',
        params,
      ));
      return _parsePlaces(json);
    }

    final canUseRoute = routeAhead != null && routeAhead.length > 1;
    try {
      if (canUseRoute) {
        final along = await category(true);
        if (along.isNotEmpty) return along;
      }
      if (near == null) return const [];
      final nearby = await category(false);
      if (nearby.isNotEmpty) return nearby;
    } on MapboxApiException {
      if (near == null) rethrow;
    }
    // Sandaran: carian teks biasa.
    return search('stesen minyak petrol', near: near);
  }

  List<PlaceResult> _parsePlaces(Map<String, dynamic> json) {
    final features = json['features'];
    if (features is! List) return const [];

    final results = <PlaceResult>[];
    for (final f in features) {
      if (f is! Map) continue;
      final props = f['properties'];
      final geom = f['geometry'];
      if (props is! Map || geom is! Map) continue;
      final coords = geom['coordinates'];
      if (coords is! List || coords.length < 2) continue;

      final name = (props['name'] ?? '').toString();
      final address =
          (props['full_address'] ?? props['place_formatted'] ?? '').toString();
      final brandRaw = props['brand'];
      String? brand;
      if (brandRaw is List && brandRaw.isNotEmpty) {
        brand = brandRaw.first.toString();
      } else if (brandRaw is String && brandRaw.isNotEmpty) {
        brand = brandRaw;
      }

      results.add(PlaceResult(
        name: name.isEmpty ? address : name,
        address: address,
        brand: brand,
        location: LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        ),
      ));
    }
    return results;
  }

  // -----------------------------------------------------------------------
  // Laluan
  // -----------------------------------------------------------------------

  /// Dapatkan laluan memandu (dengan trafik semasa) melalui [points]
  /// (asal, hentian jika ada, destinasi).
  Future<NavRoute> route(List<LatLng> points, {bool avoidTolls = false}) async {
    final routes = await _routes(points, avoidTolls: avoidTolls);
    if (!avoidTolls) return routes.first;
    return routes.firstWhere(
      (route) => !route.hasToll,
      orElse: () => throw MapboxApiException('Laluan tanpa tol tidak dijumpai.'),
    );
  }

  Future<List<NavRoute>> routeOptions(List<LatLng> points) async {
    final batches = await Future.wait([
      _routes(points, alternatives: true),
      _routes(points, avoidTolls: true).catchError(
        (Object _) => <NavRoute>[],
      ),
    ]);
    final routes = batches.first;
    for (final free in batches.last.where((route) => !route.hasToll)) {
      final same = routes.indexWhere((route) {
        final a = route.coordinates;
        final b = free.coordinates;
        return a.length == b.length &&
            Iterable<int>.generate(a.length).every(
              (i) => a[i].lat == b[i].lat && a[i].lng == b[i].lng,
            );
      });
      if (same < 0) {
        routes.add(free);
      } else {
        routes[same] = free;
      }
    }
    return routes;
  }

  Future<List<NavRoute>> _routes(
    List<LatLng> points, {
    bool alternatives = false,
    bool avoidTolls = false,
  }) async {
    final path =
        '/directions/v5/mapbox/driving-traffic/${points.map(_lngLat).join(';')}';
    final json = await _getJson(Uri.https(_host, path, {
      'alternatives': alternatives.toString(),
      if (avoidTolls) 'exclude': 'toll',
      'geometries': 'geojson',
      'overview': 'full',
      'steps': 'true',
      'annotations': 'congestion,maxspeed',
      'access_token': token,
    }));

    final routes = json['routes'];
    if (json['code'] != 'Ok' || routes is! List || routes.isEmpty) {
      throw MapboxApiException(
        (json['message'] ?? 'Laluan tidak dijumpai.').toString(),
      );
    }
    final result = routes
        .whereType<Map>()
        .map((route) => parseRoute(route, avoidTolls: avoidTolls))
        .where((route) => route.coordinates.length > 1)
        .toList();
    if (result.isEmpty) throw MapboxApiException('Laluan tidak dijumpai.');
    return result;
  }

  static NavRoute parseRoute(Map r, {bool avoidTolls = false}) {

    // Garisan laluan.
    final coordinates = <LatLng>[];
    final geom = r['geometry'];
    if (geom is Map && geom['coordinates'] is List) {
      for (final p in geom['coordinates'] as List) {
        if (p is List && p.length >= 2) {
          coordinates.add(
            LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          );
        }
      }
    }
    final segCount = coordinates.isEmpty ? 0 : coordinates.length - 1;
    final congestion = List<String>.filled(segCount, 'unknown');
    final maxSpeed = List<double?>.filled(segCount, null);

    final steps = <NavStep>[];
    final incidents = <RouteIncident>[];
    final signals = <(double, double), LatLng>{};
    var hasToll = false;
    final legs = r['legs'];
    var legStart = 0;

    if (legs is List) {
      for (var li = 0; li < legs.length; li++) {
        final leg = legs[li];
        if (leg is! Map) continue;
        final isLastLeg = li == legs.length - 1;

        // Langkah-langkah.
        final legSteps = <NavStep>[];
        if (leg['steps'] is List) {
          for (final s in leg['steps'] as List) {
            if (s is Map && s['intersections'] is List) {
              final intersections = (s['intersections'] as List).whereType<Map>();
              for (final intersection in intersections) {
                final classes = intersection['classes'];
                if (intersection['toll_collection'] is Map ||
                    (classes is List && classes.contains('toll'))) {
                  hasToll = true;
                }
                final location = intersection['location'];
                if (intersection['traffic_signal'] == true &&
                    location is List &&
                    location.length >= 2 &&
                    location[0] is num &&
                    location[1] is num) {
                  final lng = (location[0] as num).toDouble();
                  final lat = (location[1] as num).toDouble();
                  signals[(lat, lng)] = LatLng(lat, lng);
                }
              }
            }
            final step = _parseStep(s, waypoint: !isLastLeg);
            if (step != null) legSteps.add(step);
          }
        }
        if (legSteps.isNotEmpty) {
          legStart = nearestIndex(coordinates, legSteps.first.location,
              from: legStart);
        }
        steps.addAll(legSteps);

        // Kesesakan & had laju untuk setiap segmen.
        final ann = leg['annotation'];
        if (ann is Map) {
          final cong = ann['congestion'];
          if (cong is List) {
            for (var k = 0; k < cong.length; k++) {
              final idx = legStart + k;
              if (idx >= segCount) break;
              congestion[idx] = (cong[k] ?? 'unknown').toString();
            }
          }
          final ms = ann['maxspeed'];
          if (ms is List) {
            for (var k = 0; k < ms.length; k++) {
              final idx = legStart + k;
              if (idx >= segCount) break;
              final m = ms[k];
              if (m is Map && m['speed'] is num) {
                final v = (m['speed'] as num).toDouble();
                maxSpeed[idx] = m['unit'] == 'mph' ? v * 1.609 : v;
              }
            }
          }
        }

        // Insiden (kemalangan, kerja jalan, cuaca, dll.).
        final incs = leg['incidents'];
        if (incs is List) {
          for (final inc in incs) {
            if (inc is! Map) continue;
            final start = (inc['geometry_index_start'] as num?)?.toInt() ?? 0;
            var idx = legStart + start;
            if (idx >= coordinates.length) idx = coordinates.length - 1;
            if (idx < 0) continue;
            incidents.add(RouteIncident(
              type: (inc['type'] ?? 'miscellaneous').toString(),
              description: (inc['description'] ?? '').toString(),
              impact: (inc['impact'] ?? 'unknown').toString(),
              closed: inc['closed'] == true,
              geometryIndex: idx,
            ));
          }
        }
      }
    }

    return NavRoute(
      distance: (r['distance'] as num? ?? 0).toDouble(),
      duration: (r['duration'] as num? ?? 0).toDouble(),
      durationTypical: (r['duration_typical'] as num?)?.toDouble(),
      coordinates: coordinates,
      steps: steps,
      congestion: congestion,
      maxSpeedKmh: maxSpeed,
      incidents: incidents,
      trafficSignals: signals.values.toList(),
      hasToll: hasToll,
      avoidTolls: avoidTolls,
    );
  }

  static NavStep? _parseStep(Object? s, {required bool waypoint}) {
    if (s is! Map || s['maneuver'] is! Map) return null;
    final m = s['maneuver'] as Map;
    final loc = m['location'];
    if (loc is! List || loc.length < 2) return null;

    var name = (s['name'] ?? '').toString();
    if (name.isEmpty) name = (s['ref'] ?? '').toString();
    final type = (m['type'] ?? '').toString();

    // Lorong di persimpangan gerakan ini.
    final lanes = <LaneInfo>[];
    final inters = s['intersections'];
    final junction = inters is List && inters.isNotEmpty && inters.first is Map
        ? inters.first as Map
        : null;
    if (junction != null) {
      final rawLanes = junction['lanes'];
      if (rawLanes is List) {
        for (final l in rawLanes) {
          if (l is! Map) continue;
          final ind = l['indications'];
          lanes.add(LaneInfo(
            indications: ind is List
                ? ind.map((e) => e.toString()).toList()
                : const [],
            valid: l['valid'] == true,
            active: l['active'] == true,
            validIndication: l['valid_indication']?.toString(),
          ));
        }
      }
    }

    return NavStep(
      type: type,
      modifier: (m['modifier'] ?? '').toString(),
      name: name,
      distance: (s['distance'] as num? ?? 0).toDouble(),
      duration: (s['duration'] as num? ?? 0).toDouble(),
      location: LatLng(
        (loc[1] as num).toDouble(),
        (loc[0] as num).toDouble(),
      ),
      exit: (m['exit'] as num?)?.toInt(),
      lanes: lanes,
      waypointArrival: waypoint && type == 'arrive',
      trafficSignal: junction?['traffic_signal'] == true,
    );
  }

  // -----------------------------------------------------------------------
  // HTTP
  // -----------------------------------------------------------------------

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        var message = 'Ralat pelayan Mapbox (${response.statusCode}).';
        if (response.statusCode == 401) {
          message = 'Token Mapbox tidak sah. Semak token anda.';
        } else {
          try {
            final j = jsonDecode(body);
            if (j is Map && j['message'] is String) {
              message = j['message'] as String;
            }
          } catch (_) {}
        }
        throw MapboxApiException(message);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw MapboxApiException('Jawapan pelayan tidak dijangka.');
      }
      return decoded;
    } on SocketException {
      throw MapboxApiException('Tiada sambungan internet.');
    } on TimeoutException {
      throw MapboxApiException('Sambungan terlalu perlahan. Cuba lagi.');
    } on HandshakeException {
      throw MapboxApiException('Sambungan selamat gagal. Cuba lagi.');
    } finally {
      client.close();
    }
  }
}
