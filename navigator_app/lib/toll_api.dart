import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Kadar awam bagi kereta Kelas 1. Nama dan koordinat pengguna kekal pada peranti.
class TollRates {
  static const _host = 'mohdsyahid.github.io';
  static const _highways = [1, 19, 24, 26, 28, 33];

  // Kadar rata MEX daripada jadual rasmi pengendali, dalam sen.
  static const _flatRates = {
    'MEX SALAK SELATAN': 200,
    'MEX SERI KEMBANGAN': 220,
    'MEX PUTRAJAYA': 350,
    'MEX PUTRAJAYA UTAMA': 350,
  };

  Future<List<Map<(String, String), int>>?>? _tables;

  Future<double?> estimate(NavRoute route) async {
    if (route.avoidTolls) return 0;
    if (route.tollPlazas.isEmpty || route.tollPlazas.contains(null))
      return null;
    final plazas = route.tollPlazas
        .whereType<String>()
        .map(_normalize)
        .toList();
    if (plazas.every(_flatRates.containsKey)) {
      return plazas.fold<int>(0, (sum, plaza) => sum + _flatRates[plaza]!) /
          100;
    }
    final request = _tables ??= _loadTables();
    final tables = await request;
    if (tables == null) {
      if (identical(_tables, request)) _tables = null;
      return null;
    }
    final cents = totalSen(plazas, tables);
    return cents == null ? null : cents / 100;
  }

  /// Padankan secara berurutan dan tolak jumlah yang liputannya separa atau kabur.
  static int? totalSen(
    List<String> plazas,
    List<Map<(String, String), int>> tables,
  ) {
    if (plazas.isEmpty) return null;
    final names = plazas.map(_normalize).toList();
    var total = 0;
    var i = 0;
    while (i < names.length) {
      final flat = _flatRates[names[i]];
      if (flat != null) {
        total += flat;
        i++;
        continue;
      }
      if (i + 1 >= names.length || _flatRates.containsKey(names[i + 1])) {
        return null;
      }
      final pair = (names[i], names[i + 1]);
      final matches = tables
          .map((table) => table[pair])
          .whereType<int>()
          .toSet();
      if (matches.length != 1) return null;
      total += matches.single;
      i += 2;
    }
    return total;
  }

  static Map<(String, String), int> parseTable(Object? body) {
    if (body is! Map || body['routes'] is! List) {
      throw const FormatException('Jadual kadar tol tidak sah');
    }
    final table = <(String, String), int>{};
    final conflicts = <(String, String)>{};
    for (final route in (body['routes'] as List).whereType<Map>()) {
      final from = route['entryPlaza'];
      final to = route['exitPlaza'];
      final rates = route['rates'];
      if (from is! String || to is! String || rates is! List) continue;
      for (final rate in rates.whereType<Map>()) {
        final amount = rate['rateRM'];
        if (rate['vehicleClass'] == 1 &&
            amount is num &&
            amount.isFinite &&
            amount > 0) {
          final pair = (_normalize(from), _normalize(to));
          final cents = (amount * 100).round();
          final previous = table[pair];
          if (previous != null && previous != cents) conflicts.add(pair);
          table[pair] = cents;
        }
      }
    }
    for (final pair in conflicts) {
      table.remove(pair);
    }
    return table;
  }

  static String _normalize(String name) {
    final plain = name
        .toUpperCase()
        .replaceAll(RegExp(r'\b(PLAZA|TOL|TOLL|SKVE)\b'), ' ')
        .replaceAll(RegExp(r'\bSG\b\.?'), 'SUNGAI')
        .replaceAll('(ARAH UTARA)', '(U)')
        .replaceAll('(ARAH SELATAN)', '(S)')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*\('), ' (')
        .trim();
    return switch (plain) {
      'MEX SALAK SOUTH' => 'MEX SALAK SELATAN',
      _ => plain,
    };
  }

  static Future<List<Map<(String, String), int>>?> _loadTables() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final tables = await Future.wait(
        _highways.map((id) async {
          try {
            final request = await client.getUrl(
              Uri.https(_host, '/kadar-tol-malaysia/data/$id.json'),
            );
            final response = await request.close().timeout(
              const Duration(seconds: 6),
            );
            if (response.statusCode != HttpStatus.ok) {
              await response.drain<void>().timeout(const Duration(seconds: 5));
              return null;
            }
            final json = await response
                .transform(utf8.decoder)
                .join()
                .timeout(const Duration(seconds: 5));
            return parseTable(jsonDecode(json));
          } catch (_) {
            return null;
          }
        }),
      );
      // Kegagalan rangkaian dicuba semula pada carian seterusnya.
      return tables.any((table) => table == null)
          ? null
          : tables.whereType<Map<(String, String), int>>().toList();
    } finally {
      client.close(force: true);
    }
  }
}
