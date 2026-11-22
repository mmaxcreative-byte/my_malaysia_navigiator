import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:navigator_app/mapbox_api.dart';
import 'package:navigator_app/models.dart';
import 'package:navigator_app/navigation_screen.dart';
import 'package:navigator_app/toll_api.dart';
import 'package:navigator_app/widgets.dart';

void main() {
  test('Mapbox mengekalkan susunan lorong dan mengesan lampu serta tol', () {
    final junction = {
      'location': [101.0, 3.0],
      'traffic_signal': true,
      'classes': ['toll'],
      'lanes': [
        {
          'indications': ['left'],
          'valid': false,
        },
        {
          'indications': ['left', 'straight'],
          'valid': true,
          'active': true,
          'valid_indication': 'straight',
        },
        {
          'indications': ['straight'],
          'valid': true,
          'active': false,
        },
        {
          'indications': ['right'],
          'valid': false,
        },
      ],
    };
    final route = MapboxApi.parseRoute({
      'geometry': {
        'coordinates': [
          [101.0, 3.0],
          [101.01, 3.01],
        ],
      },
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'location': [101.0, 3.0],
              },
              'intersections': [
                junction,
                junction,
                {
                  'location': [101.01, 3.01],
                  'traffic_signal': true,
                },
              ],
            },
          ],
        },
      ],
    });
    expect(route.hasToll, isTrue);
    expect(route.trafficSignals, hasLength(2));
    final step = route.steps.single;
    expect(step.trafficSignal, isTrue);
    expect(step.lanes, hasLength(4));
    expect(step.lanes[1].indications, ['left', 'straight']);
    expect(step.lanes[1].active, isTrue);
    expect(step.lanes[2].valid, isTrue);
    expect(step.lanes[2].active, isFalse);
  });

  testWidgets('empat lorong muat dan semua arah ditunjukkan', (tester) async {
    expect(const NavigationScreen(), isA<StatefulWidget>());
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 190,
            child: LaneStrip(
              modifier: 'straight',
              lanes: [
                LaneInfo(indications: ['left'], valid: false),
                LaneInfo(
                  indications: ['left', 'straight'],
                  valid: true,
                  active: true,
                  validIndication: 'straight',
                ),
                LaneInfo(indications: ['straight'], valid: true),
                LaneInfo(indications: ['right'], valid: false),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.turn_left), findsNWidgets(2));
    expect(find.byIcon(Icons.straight), findsNWidgets(2));
    expect(find.byIcon(Icons.turn_right), findsOneWidget);
  });

  testWidgets('paparkan harga, laluan percuma dan caj yang belum diketahui', (
    tester,
  ) async {
    NavRoute route({bool avoidTolls = false, bool hasToll = false}) => NavRoute(
      distance: 12000,
      duration: 900,
      coordinates: const [],
      steps: const [],
      avoidTolls: avoidTolls,
      hasToll: hasToll,
    );
    final priced = route(hasToll: true);
    final free = route(avoidTolls: true);
    final unknown = route(hasToll: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteOptionsSheet(
            options: [priced, free, unknown],
            selected: priced,
            quotes: {priced: Future.value(4.5)},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anggaran tol kereta • RM 4.50'), findsOneWidget);
    expect(find.text('Tanpa tol • RM 0.00'), findsOneWidget);
    expect(find.text('Bertol • Caj tidak tersedia'), findsOneWidget);
    expect(
      parseTollQuote({'currency': 'MYR', 'amount': 4.5}, hasToll: true),
      4.5,
    );
    expect(
      parseTollQuote({'currency': 'MYR', 'amount': 0}, hasToll: true),
      isNull,
    );
    expect(
      parseTollQuote({'currency': 'USD', 'amount': 3}, hasToll: false),
      isNull,
    );
  });
}
