import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';
import 'package:tuktuk_cliente/vector_map_route_geometry.dart';

void main() {
  test('ruta real conserva todos los puntos y el orden longitud-latitud', () {
    const points = [
      MarketplaceMapPoint(label: 'origen', lat: 23.11, lon: -82.36),
      MarketplaceMapPoint(label: 'intermedio', lat: 23.12, lon: -82.35),
      MarketplaceMapPoint(label: 'destino', lat: 23.13, lon: -82.34),
    ];
    final geo = jsonDecode(pilotRouteGeoJson(points)) as Map<String, dynamic>;
    final features = geo['features'] as List;
    final geometry = (features.single as Map)['geometry'] as Map;
    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], [
      [-82.36, 23.11],
      [-82.35, 23.12],
      [-82.34, 23.13],
    ]);
  });

  test('no fabrica rutas si hay menos de dos puntos', () {
    expect(
        (jsonDecode(pilotRouteGeoJson(const [])) as Map)['features'], isEmpty);
    expect(
        (jsonDecode(pilotRouteGeoJson(const [
          MarketplaceMapPoint(label: 'solo', lat: 23.1, lon: -82.3),
        ])) as Map)['features'],
        isEmpty);
  });
}
