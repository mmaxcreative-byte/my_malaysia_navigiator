// Ujian untuk fungsi tulen (tidak perlukan peta atau GPS).
import 'package:flutter_test/flutter_test.dart';

import 'package:navigator_app/geo_utils.dart';
import 'package:navigator_app/instructions_ms.dart';
import 'package:navigator_app/models.dart';

NavStep _step(String type, [String modifier = '', String name = '', int? exit]) =>
    NavStep(
      type: type,
      modifier: modifier,
      name: name,
      distance: 100,
      duration: 10,
      location: const LatLng(3.15, 101.7),
      exit: exit,
    );

void main() {
  test('arahan Bahasa Melayu', () {
    expect(instructionFor(_step('turn', 'left', 'Jalan Duta')),
        'Belok kiri ke Jalan Duta');
    expect(instructionFor(_step('turn', 'slight right')),
        'Belok sedikit ke kanan');
    expect(instructionFor(_step('roundabout', '', 'Jalan Ampang', 2)),
        'Di bulatan, ambil susur keluar ke-2 ke Jalan Ampang');
    expect(instructionFor(_step('arrive', 'left')),
        'Destinasi di sebelah kiri');
    expect(instructionFor(_step('off ramp', 'slight left', 'E1')),
        'Ambil susur keluar ke kiri ke E1');
  });

  test('format jarak & masa', () {
    expect(formatDistance(42), '40 m');
    expect(formatDistance(356), '360 m');
    expect(formatDistance(1234), '1.2 km');
    expect(formatDistance(25400), '25 km');
    expect(formatDuration(30), '1 min');
    expect(formatDuration(14 * 60), '14 min');
    expect(formatDuration(85 * 60), '1 j 25 min');
    expect(formatClock(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });

  test('jarak geografi', () {
    const klcc = LatLng(3.1579, 101.7116);
    const midValley = LatLng(3.1180, 101.6770);
    final d = distanceBetween(klcc, midValley);
    expect(d, greaterThan(5500));
    expect(d, lessThan(6000));

    const line = [LatLng(3.0, 101.0), LatLng(3.0, 101.01)];
    final off = distanceToPolyline(const LatLng(3.0005, 101.005), line);
    expect(off, closeTo(55.6, 2));
  });
}
