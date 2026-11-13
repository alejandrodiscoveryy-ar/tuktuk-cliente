import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('assigned marker contains only valid heading and exact coordinates', () {
    const point = MarketplaceMapPoint(label: 'assigned', lat: 23.11, lon: -82.36);
    final arrow = jsonDecode(marketplaceVectorDriverGeoJson(point, 90)) as Map;
    final feature = (arrow['features'] as List).single as Map;
    expect(feature['geometry']['coordinates'], [-82.36, 23.11]);
    expect(feature['properties'], {'has_heading': true, 'heading': 90});
    for (final heading in <double?>[null, -1, 360, double.nan]) {
      final raw = jsonDecode(marketplaceVectorDriverGeoJson(point, heading)) as Map;
      expect((raw['features'] as List).single['properties'], {'has_heading': false, 'heading': 0.0});
    }
    expect((jsonDecode(marketplaceVectorDriverGeoJson(null, null)) as Map)['features'], isEmpty);
  });

  test('GPS heading uses valid sensor or meaningful motion, never invented north', () {
    final time = DateTime.utc(2026,11,12,12);
    MarketplaceDriverLiveLocation gps(double lon, {double? heading, double? speed, int seconds = 0}) =>
        MarketplaceDriverLiveLocation(latitude: 23.11, longitude: lon,
          capturedAt: time.add(Duration(seconds: seconds)), accuracyM: 10,
          headingDegrees: heading, speedMps: speed);
    final before = gps(-82.36);
    expect(marketplaceTrackingHeading(gps(-82.36, heading: 180, speed: 3), null), 180);
    expect(marketplaceTrackingHeading(gps(-82.36, heading: 0, speed: 0), null), isNull);
    expect(marketplaceTrackingHeading(gps(-82.35999, seconds: 10), before), isNull);
    expect(marketplaceTrackingHeading(gps(-82.359, seconds: 10), before), closeTo(90, .1));
    expect(marketplaceTrackingHeading(gps(-82.359, seconds: 150), before), isNull);
    expect(MarketplaceDriverLiveLocation.fromMap({'latitude':23.11,'longitude':-82.36,'heading_degrees':90})?.headingDegrees, 90);
    expect(MarketplaceDriverLiveLocation.fromMap({'latitude':23.11,'longitude':-82.36,'heading_degrees':-1})?.headingDegrees, isNull);
    expect(marketplaceTrackingRouteStage('accepted'), 'pickup');
    expect(marketplaceTrackingRouteStage('en_route'), 'pickup');
    expect(marketplaceTrackingRouteStage('pickup'), isNull);
    expect(marketplaceTrackingRouteStage('in_progress'), 'destination');
    expect(marketplaceTrackingRouteStage('settled'), isNull);
  });

  test('display route parses verified points independently of commercial quote', () {
    final route = MarketplaceTrackingRoute.fromMap({'stage':'pickup','route_points':[
      {'lat':23.11,'lon':-82.36},{'lat':23.12,'lon':-82.35},
    ]});
    expect(route.stage, 'pickup');
    expect(route.points.length, 2);
    expect(() => MarketplaceTrackingRoute.fromMap({'stage':'pickup','route_points':[{'lat':100,'lon':0}]}), throwsStateError);
  });

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

