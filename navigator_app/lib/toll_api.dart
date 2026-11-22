import 'dart:convert';
import 'dart:io';

import 'geo_utils.dart';
import 'models.dart';

/// Anggaran untuk kereta penumpang, menggunakan geometri laluan yang dipilih.
Future<double?> estimateToll(NavRoute route, Uri endpoint) async {
  if (endpoint.scheme != 'https' || endpoint.host.isEmpty) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(endpoint);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'polyline': encodePolyline(route.coordinates)}));
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) return null;
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    return parseTollQuote(jsonDecode(body), hasToll: route.hasToll);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

double? parseTollQuote(Object? quote, {required bool hasToll}) {
  if (quote is! Map || quote['currency'] != 'MYR') return null;
  final amount = quote['amount'];
  if (amount is! num || !amount.isFinite || amount < 0) return null;
  if (hasToll && amount == 0) return null;
  return amount.toDouble();
}
