import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('vector point preserves longitude-latitude coordinate order', () {
    const point = MarketplaceMapPoint(label: 'Origen', lat: 23.11, lon: -82.36);
    final result = jsonDecode(marketplaceVectorPointGeoJson(point)) as Map;
    final features = result['features'] as List;
    final coordinates = (features.single['geometry'] as Map)['coordinates'];
    expect(coordinates, [-82.36, 23.11]);
  });

  test('vector route preserves every street point without shortcuts', () {
    const points = <MarketplaceMapPoint>[
      MarketplaceMapPoint(label: 'Origen', lat: 23.11, lon: -82.36),
      MarketplaceMapPoint(label: 'Intermedio', lat: 23.12, lon: -82.35),
      MarketplaceMapPoint(label: 'Destino', lat: 23.13, lon: -82.34),
    ];
    final result = jsonDecode(marketplaceVectorLineGeoJson(points)) as Map;
    final pointsReturned = (((result['features'] as List).single
        as Map)['geometry'] as Map)['coordinates'];
    expect(pointsReturned, [
      [-82.36, 23.11],
      [-82.35, 23.12],
      [-82.34, 23.13],
    ]);
  });

  test('missing route never becomes an invented straight line', () {
    final result = jsonDecode(
      marketplaceVectorLineGeoJson(const <MarketplaceMapPoint>[
        MarketplaceMapPoint(label: 'solo', lat: 23.1, lon: -82.3),
      ]),
    ) as Map;
    expect(result['features'], isEmpty);
  });
}
