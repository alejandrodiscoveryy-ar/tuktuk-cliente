import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('el mapa conserva la geometria de todos los puntos en orden vial', () {
    const points = <MarketplaceMapPoint>[
      MarketplaceMapPoint(label: 'Origen', lat: 23.10, lon: -82.30),
      MarketplaceMapPoint(label: 'Giro 1', lat: 23.11, lon: -82.31),
      MarketplaceMapPoint(label: 'Giro 2', lat: 23.12, lon: -82.32),
      MarketplaceMapPoint(label: 'Destino', lat: 23.13, lon: -82.33),
    ];
    final payload = jsonDecode(marketplaceVectorLineGeoJson(points)) as Map;
    final features = payload['features'] as List;
    expect(features, hasLength(1));
    final geometry = (features.single as Map)['geometry'] as Map;
    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], [
      [-82.30, 23.10],
      [-82.31, 23.11],
      [-82.32, 23.12],
      [-82.33, 23.13],
    ]);
  });

  test('sin geometria real no se inventa una ruta recta', () {
    final payload =
        jsonDecode(marketplaceVectorLineGeoJson(const <MarketplaceMapPoint>[]))
            as Map;
    expect(payload['features'], isEmpty);
  });

  test('la ruta tiene un unico trazo luminoso y no negro superpuesto', () {
    final source = File(
      'lib/presentation/marketplace_vector_map.dart',
    ).readAsStringSync();
    expect(source, contains("id: 'tuktuk-client-route-line'"));
    expect(source, isNot(contains("id: 'tuktuk-client-route-outline'")));
    expect(source, contains('lineColor: 0xFFFFC400'));
    expect(
      source,
      contains('marketplaceVectorLineGeoJson(widget.routePoints)'),
    );
  });

  test('los paneles del cliente dejan ver el mapa a traves', () {
    final source = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    expect(source, contains('TuktukTheme.background.withValues(alpha: .72)'));
    expect(source, contains('TuktukTheme.background.withValues(alpha: .80)'));
    expect(source, contains('TuktukTheme.background.withValues(alpha: .77)'));
    expect(source, contains('Widget _floatingQuoteOptions()'));
    expect(source, contains('Solicitar transporte'));
  });
}
