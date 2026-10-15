import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';

class _QuoteMapForPickupEdit extends MarketplaceMapService {
  _QuoteMapForPickupEdit(super.client);
  int routeCalls = 0;

  @override
  Future<MarketplaceRouteQuote> route({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required Map<String, dynamic> pricing,
  }) async {
    routeCalls++;
    return const MarketplaceRouteQuote(
      distanceKm: 3,
      durationSeconds: 600,
      routePoints: [],
      routeToken: 'test-route',
      prices: {
        'passenger_by_category': {
          'motorcycle': {'recommended_price': 500, 'currency': 'CUP'},
        },
      },
    );
  }
}

void main() {
  test('la contratacion inicia directamente en cotizacion sin seis pantallas',
      () {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final flow = CustomerBookingFlowController(
      MarketplaceMapService(client),
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
        sessionId: 's',
        customerId: 'c',
        token: 't',
      ),
    );
    expect(flow.step, MarketplaceBookingStep.quote);
    expect(flow.origin, isNull);
    expect(flow.destination, isNull);
    flow.dispose();
  });

  test('la principal tiene origen destino cotizacion y un solo CTA', () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains('Widget _bookingHeader()'));
    expect(
        source, contains('Future<void> _selectPoint({required bool origin})'));
    expect(source, contains('¿A dónde vamos?'));
    expect(source, contains("'Solicitar transporte'"));
    expect(source, contains('? _submit'));
    expect(source, contains('Widget _floatingBookingPanel()'));
    expect(source, contains('MarketplaceVectorMap('));
    expect(source, contains('onPointTap: _selectingOrigin == null'));
    expect(source, contains('_floatingPlaceSelection()'));
    expect(source, contains('publishJob('));
    expect(source, contains('saveActiveJobId('));
  });

  test('moto ajusta automaticamente a un pasajero', () {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final flow = CustomerBookingFlowController(
      MarketplaceMapService(client),
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
        sessionId: 's',
        customerId: 'c',
        token: 't',
      ),
    );
    flow.setPassengerVehicleCategory('tricycle');
    flow.passengerCount = 3;
    flow.setPassengerVehicleCategory('motorcycle');
    expect(flow.passengerCount, 1);
    expect(flow.pricing['vehicle_category_code'], 'motorcycle');
    flow.dispose();
  });
  test('cambiar la recogida mantiene destino y actualiza la ruta', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final map = _QuoteMapForPickupEdit(client);
    final flow = CustomerBookingFlowController(
      map,
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
        sessionId: 's',
        customerId: 'c',
        token: 't',
      ),
    );
    const previous =
        MarketplaceMapPoint(label: 'Anterior', lat: 23.1, lon: -82.3);
    const updated =
        MarketplaceMapPoint(label: 'Nueva recogida', lat: 23.12, lon: -82.31);
    const destination =
        MarketplaceMapPoint(label: 'Destino', lat: 23.15, lon: -82.37);
    flow.origin = previous;
    flow.destination = destination;
    flow.setPickupForQuote(updated);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(flow.origin, updated);
    expect(flow.destination, destination);
    expect(flow.step, MarketplaceBookingStep.quote);
    expect(map.routeCalls, 1);
    expect(flow.route?.distanceKm, 3);
    flow.dispose();
    client.dispose();
  });

  test('GPS automatico y editar recogida no reabren los seis pasos', () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains('unawaited(_autoLocatePickup())'));
    expect(source, contains('Geolocator.getCurrentPosition('));
    expect(source, contains('flow.setPickupForQuote(point)'));
    expect(source, contains('tooltip: \'Cambiar recogida\''));
  });
}
