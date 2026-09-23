import 'package:tuktuk_cliente/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeMapService extends MarketplaceMapService {
  FakeMapService(super.client);
  int routeCalls = 0;
  int priceCalls = 0;
  int createCalls = 0;

  @override
  Future<MarketplaceRouteQuote> route({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required Map<String, dynamic> pricing,
  }) async {
    routeCalls++;
    return const MarketplaceRouteQuote(
      distanceKm: 9,
      durationSeconds: 1200,
      routePoints: [],
      routeToken: 'signed',
      prices: {
        'passenger': {'recommended_price': 3900}
      },
    );
  }

  @override
  Future<MarketplaceRouteQuote> reprice({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required String routeToken,
    required Map<String, dynamic> pricing,
  }) async {
    priceCalls++;
    return MarketplaceRouteQuote(
      distanceKm: 9,
      durationSeconds: 1200,
      routePoints: const [],
      routeToken: routeToken,
      prices: {
        'passenger': {
          'recommended_price': pricing['urgent'] == true ? 4900 : 3900
        }
      },
    );
  }

  @override
  Future<MarketplaceCustomerRequestDraft> create({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required String routeToken,
    required Map<String, dynamic> params,
  }) async {
    createCalls++;
    return const MarketplaceCustomerRequestDraft(
      jobId: 'job',
      serviceRequestId: 'request',
      status: 'requested',
      recommendedPrice: 3900,
      minimumPrice: 1200,
      lowPriceWarningThreshold: 0,
      currency: 'CUP',
      pricingVersion: 'test',
      pricingBreakdown: {},
    );
  }
}

void main() {
  final client = SupabaseClient('https://example.supabase.co', 'test-key');
  final map = FakeMapService(client);
  final flow = CustomerBookingFlowController(
    map,
    MarketplaceCustomerService(client),
    const MarketplaceCustomerSessionSnapshot(
      sessionId: 'session',
      customerId: 'customer',
      token: 'token',
    ),
  );
  const origin = MarketplaceMapPoint(label: 'Origen', lat: 23.1, lon: -82.3);
  const destination =
      MarketplaceMapPoint(label: 'Destino', lat: 23.2, lon: -82.4);

  test('route waits for both points, origin change invalidates old route',
      () async {
    await flow.refreshRoute();
    expect(map.routeCalls, 0);
    flow.setOrigin(origin);
    await flow.refreshRoute();
    expect(map.routeCalls, 0);
    flow.setDestination(destination);
    await Future<void>.delayed(Duration.zero);
    expect(map.routeCalls, 1);
    expect(flow.route?.distanceKm, 9);
    flow.setOrigin(origin);
    expect(flow.route, isNull);
    expect(flow.destination, isNull);
  });

  test('passenger and urgency changes only reprice verified route', () async {
    flow.setDestination(destination);
    await Future<void>.delayed(Duration.zero);
    final before = map.routeCalls;
    flow.passengerCount = 2;
    await flow.reprice();
    flow.urgent = true;
    await flow.reprice();
    expect(map.routeCalls, before);
    expect(map.priceCalls, 2);
    expect(map.createCalls, 0);
    expect(flow.selectedPrice?['recommended_price'], 4900);
    await flow.submit();
    expect(map.createCalls, 1);
  });
}
