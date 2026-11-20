import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('vehicle icons have dedicated, never-numeric modality keys', () {
    expect(marketplaceFleetIconKey('light_car'), 'tuktuk-fleet-auto-v1');
    expect(marketplaceFleetIconKey('motorcycle'), 'tuktuk-fleet-moto-v1');
    expect(marketplaceFleetIconKey('tricycle'), 'tuktuk-fleet-triciclo-v1');
    expect(marketplaceFleetIconKey('bicitaxi'), 'tuktuk-fleet-bicitaxi-v1');
    expect(marketplaceFleetIconKey('bicycle'), 'tuktuk-fleet-bici-v1');
    expect(marketplaceFleetIconKey(null), 'tuktuk-fleet-otro-v1');
  });

  test('every anonymous vehicle is rendered; GPS coordinates never shift', () {
    const source = <MarketplaceMapPoint>[
      MarketplaceMapPoint(label: 'secret1', lat: 23.124, lon: -82.347, category: 'light_car'),
      MarketplaceMapPoint(label: 'secret2', lat: 23.124, lon: -82.347, category: 'motorcycle'),
      MarketplaceMapPoint(label: 'secret3', lat: 23.124, lon: -82.347, category: 'tricycle'),
      MarketplaceMapPoint(label: 'secret4', lat: 23.124, lon: -82.347, category: 'bicitaxi'),
      MarketplaceMapPoint(label: 'secret5', lat: 23.124, lon: -82.347, category: 'tricycle'),
      MarketplaceMapPoint(label: 'secret6', lat: 23.128, lon: -82.352, category: 'light_car'),
    ];
    final json = marketplaceVectorFleetGeoJson(source);
    final features = (jsonDecode(json) as Map)['features'] as List;
    expect(features, hasLength(source.length));
    final shared = features.take(5).toList();
    for (final feature in shared) {
      expect(feature['geometry']['coordinates'], [-82.347, 23.124]);
      expect(feature['properties']['offset'], hasLength(2));
      expect(feature['properties']['icon'], startsWith('tuktuk-fleet-'));
      expect(feature['properties'], isNot(contains('count')));
    }
    expect(shared.map((v) => jsonEncode(v['properties']['offset'])).toSet(), hasLength(5));
    expect(features.last['geometry']['coordinates'], [-82.352, 23.128]);
    expect(features.last['properties']['offset'], [0.0, 0.0]);
    expect(json, isNot(contains('secret')));
    expect(json, isNot(contains('driver_user_id')));
    expect(json, isNot(contains('vehicle_id')));
    expect((jsonDecode(marketplaceVectorFleetGeoJson(const [])) as Map)['features'], isEmpty);
  });

  test('backend modality is parsed without exposing identities', () {
    final points = marketplaceFleetPresencePoints([
      {'latitude': 23.124, 'longitude': -82.347, 'available_now': false, 'category_code': 'tricycle', 'driver_user_id': 'private'},
      {'latitude': 23.125, 'longitude': -82.346, 'category_code': 'motorcycle'},
      {'latitude': 23.126, 'longitude': -82.345, 'available_now': true, 'category_code': 'light_car'},
    ]);
    expect(points, hasLength(3));
    expect(points.map((p) => p.category).toList(), ['tricycle', 'motorcycle', 'light_car']);
    expect(points.map((p) => p.source).toList(), ['fleet_coverage', 'fleet_coverage', 'fleet_live']);
    expect(points.every((p) => p.label.isEmpty), isTrue);
    expect(() => marketplaceFleetPresencePoints([
      {'latitude': 0, 'longitude': -82.34, 'available_now': true},
    ]), throwsStateError);
  });

  test('offline preserves each vehicle modality but removes live claim', () {
    const points = [
      MarketplaceMapPoint(label: '', lat: 23.124, lon: -82.347, source: 'fleet_live', category: 'tricycle'),
      MarketplaceMapPoint(label: '', lat: 23.125, lon: -82.346, source: 'fleet_coverage', category: 'bicitaxi'),
    ];
    final fallback = marketplaceFleetAsCoverage(points);
    expect(fallback, hasLength(2));
    expect(fallback.every((p) => p.source == 'fleet_coverage'), isTrue);
    expect(fallback.map((p) => p.category).toList(), ['tricycle', 'bicitaxi']);
    expect(fallback.first.lat, points.first.lat);
    expect(fallback.first.lon, points.first.lon);
  });

  test('customer booking map uses modality symbols, no gigantic numeric dots', () {
    final map = File('lib/presentation/marketplace_vector_map.dart').readAsStringSync();
    final booking = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final service = File('lib/data/marketplace_customer_service.dart').readAsStringSync();
    expect(map, contains("tuktuk-client-fleet-vehicle-coverage"));
    expect(map, contains("tuktuk-client-fleet-vehicle-live"));
    expect(map, contains("iconImageExpression: const ['get', 'icon']"));
    expect(map, contains("iconOffsetExpression: const ['array', 'number', 2, ['get', 'offset']]"));
    expect(map, isNot(contains('tuktuk-client-working-fleet-count')));
    expect(map, isNot(contains('tuktuk-client-fleet-coverage-count')));
    expect(map, isNot(contains('tuktuk-client-working-fleet-points')));
    expect(map, isNot(contains('marketplaceSpreadCoincidentFleetPoints')));
    expect(map, contains('Timer.periodic(const Duration(seconds: 30)'));
    expect(booking, contains('loadFleetPoints: () => widget.service.workingFleet('));
    expect(service, contains("_gateway('fleet_presence_v2'"));
    expect(service, contains("'target_session_id': sessionId"));
    expect(service, contains("'target_session_token': sessionToken"));
    expect(service, isNot(contains("from('marketplace_driver_locations')")));
  });
}
