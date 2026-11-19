import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class MapboxApiException implements Exception {
  MapboxApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Panggilan ke API Mapbox: carian tempat dan laluan.
class MapboxApi {
  MapboxApi(this.token);

  final String token;

  static const String _host = 'api.mapbox.com';

  /// Cari tempat di Malaysia (termasuk POI seperti KLCC, Mid Valley).
  Future<List<PlaceResult>> search(String query, {LatLng? near}) async {
    final params = <String, String>{
      'q': query,
      'country': 'MY',
      'limit': '8',
      'access_token': token,
    };
    if (near != null) {
      params['proximity'] =
          '${near.lng.toStringAsFixed(6)},${near.lat.toStringAsFixed(6)}';
    }
    final json = await _getJson(
      Uri.https(_host, '/search/searchbox/v1/forward', params),
    );

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
      results.add(PlaceResult(
        name: name.isEmpty ? address : name,
        address: address,
        location: LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        ),
      ));
    }
    return results;
  }

  /// Dapatkan laluan memandu (dengan trafik semasa) dari [from] ke [to].
  Future<NavRoute> route(LatLng from, LatLng to) async {
    String c(LatLng p) =>
        '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}';
    final path = '/directions/v5/mapbox/driving-traffic/${c(from)};${c(to)}';
    final json = await _getJson(Uri.https(_host, path, {
      'alternatives': 'false',
      'geometries': 'geojson',
      'overview': 'full',
      'steps': 'true',
      'access_token': token,
    }));

    final routes = json['routes'];
    if (json['code'] != 'Ok' || routes is! List || routes.isEmpty) {
      throw MapboxApiException(
        (json['message'] ?? 'Laluan tidak dijumpai.').toString(),
      );
    }
    final r = routes.first as Map;

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

    final steps = <NavStep>[];
    final legs = r['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map || leg['steps'] is! List) continue;
        for (final s in leg['steps'] as List) {
          if (s is! Map || s['maneuver'] is! Map) continue;
          final m = s['maneuver'] as Map;
          final loc = m['location'];
          if (loc is! List || loc.length < 2) continue;

          var name = (s['name'] ?? '').toString();
          if (name.isEmpty) name = (s['ref'] ?? '').toString();

          steps.add(NavStep(
            type: (m['type'] ?? '').toString(),
            modifier: (m['modifier'] ?? '').toString(),
            name: name,
            distance: (s['distance'] as num? ?? 0).toDouble(),
            duration: (s['duration'] as num? ?? 0).toDouble(),
            location: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
            exit: (m['exit'] as num?)?.toInt(),
          ));
        }
      }
    }

    return NavRoute(
      distance: (r['distance'] as num? ?? 0).toDouble(),
      duration: (r['duration'] as num? ?? 0).toDouble(),
      coordinates: coordinates,
      steps: steps,
    );
  }

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
