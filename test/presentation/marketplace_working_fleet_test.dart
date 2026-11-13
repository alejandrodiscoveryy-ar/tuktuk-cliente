import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('fleet GeoJSON contains anonymous coordinates only, including empty snapshot', () {
    final raw = jsonDecode(marketplaceVectorFleetGeoJson(const [
      MarketplaceMapPoint(label: 'private', lat: 23.124, lon: -82.347),
      MarketplaceMapPoint(label: 'private2', lat: 23.127, lon: -82.350),
    ])) as Map;
    final features = raw['features'] as List;
    expect(features.length, 2);
    expect(features.first['geometry']['coordinates'], [-82.347, 23.124]);
    expect(features.first['properties'], isEmpty);
    expect(jsonEncode(raw), isNot(contains('private')));
    expect((jsonDecode(marketplaceVectorFleetGeoJson(const [])) as Map)['features'], isEmpty);
  });
  test('fleet is optional, anonymous, visible before route and separate from assigned GPS', () {
    final map = File('lib/presentation/marketplace_vector_map.dart').readAsStringSync();
    final booking = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final service = File('lib/data/marketplace_customer_service.dart').readAsStringSync();
    expect(map, contains("tuktuk-client-fleet-coverage-points"));
    expect(map, contains("point.source == 'fleet_live'"));
    expect(map, contains("point.source != 'fleet_live'"));
    expect(map, contains("source: 'fleet_coverage'"));
    expect(service, contains("raw['available_now'] == true"));
    expect(booking, contains('Cobertura TukTuk'));
    expect(booking, contains('Disponibles ahora'));
    expect(map, contains("tuktuk-client-working-fleet-points"));
    expect(map, contains('circleColor: 0xFF329BFF'));
    expect(map, contains('circleRadius: 5.5'));
    final haloStart = map.indexOf("id: 'tuktuk-client-working-fleet-white-halo'");
    final coreStart = map.indexOf("id: 'tuktuk-client-working-fleet-points'");
    expect(haloStart, greaterThanOrEqualTo(0));
    expect(coreStart, greaterThan(haloStart));
    final halo = map.substring(haloStart, coreStart);
    expect(halo, contains('sourceId: _sourceFleet'));
    expect(halo, contains('circleColor: 0xFFFFFFFF'));
    expect(halo, contains('circleRadius: 10'));
    expect(halo, contains('circleOpacity: 0.40'));
    expect(halo, contains('circleEmissiveStrength: 1.0'));
    final core = map.substring(coreStart, map.indexOf('));', coreStart));
    expect(core, contains('circleStrokeColor: 0xFFFFFFFF'));
    expect(core, contains('circleStrokeWidth: 2.2'));
    expect(core, contains('circleStrokeOpacity: 1.0'));
    expect(core, contains('circleEmissiveStrength: 1.0'));
    expect(map, contains('Timer.periodic(const Duration(seconds: 30)'));
    expect(map, contains('if (!mounted || !_fleetForeground || loader == null || _fleetRequestPending) return;'));
    expect(map, contains('_fleetTimer?.cancel();'));
    expect(map, contains('_fleetPoints = points;'));
    expect(map, contains('await _refreshFleetSource();'));
    expect(map, contains('tuktuk-client-driver-live-position'));
    expect(booking, contains('loadFleetPoints: () => widget.service.workingFleet('));
    expect(service, contains("_gateway('fleet_presence_v2'"));
    expect(service, contains("'target_session_id': sessionId"));
    expect(service, contains("'target_session_token': sessionToken"));
    expect(service, isNot(contains("from('marketplace_driver_locations')")));
  });
}
