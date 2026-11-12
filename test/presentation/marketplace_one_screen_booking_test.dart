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
    expect(source, contains('onPointTap: flow.origin == null && _selectingOrigin == null'));
    expect(source, contains('_floatingPlaceSelection()'));
    expect(source, contains('publishJob('));
    expect(source, contains('saveActiveJobId('));
  });

  test('la forma de pago se muestra junto al precio antes de solicitar', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final footer = source.split('Widget _quoteStickyFooter()').last.split('Widget _destinationSearchPrompt()').first;
    expect(footer, contains('_ridePaymentSelector()'));
    expect(footer.indexOf('_ridePaymentSelector()'), lessThan(footer.indexOf('? _submit')));
    expect(source, contains("_option('cash', 'Efectivo', Icons.payments_outlined)"));
    expect(source, contains("_option('transfer', 'Transferencia', Icons.account_balance_outlined)"));
    expect(source, contains('value: flow.ridePaymentMethod'));
    expect(source, contains('onChanged: flow.setRidePaymentMethod'));
    expect(footer, contains("Text('Forma de pago'"));
    final selector = source.split('class MarketplaceRidePaymentSelector').last
        .split('class MarketplaceCustomerBookingFlow').first;
    expect(selector, isNot(contains('DropdownButton')));
    expect(selector, contains('selected: selected'));
    expect(selector, contains('TuktukTheme.mint'));
    expect(selector, contains('minimumSize: const Size(0, 44)'));
    expect(source, contains("'ride_payment_method': _ridePaymentMethod"));
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
    flow.publicationReady = true;
    flow.publishedCategoriesByService = {
      'passenger': marketplacePassengerVehicleCategories,
    };
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
  test('recuperar GPS de recogida muestra control y protege selecciones nuevas', () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains("tooltip: 'Volver a mi ubicación'"));
    expect(source, contains('Future<void> _restoreGpsPickup() async'));
    expect(source, contains('_commitPlace(point, true)'));
    expect(source, contains('revision != _pickupLocationRevision'));
    expect(source, contains('pickupRevisionAtTap != _pickupLocationRevision'));
    expect(source, contains('accuracy: LocationAccuracy.high'));
    expect(source, contains('_showPickupGpsMessage('));
    expect(source, contains('showRestoreGps: true'));
    expect(source, contains('restoringGps: _locatingPickup'));
    // El boton GPS original esta a la izquierda, antes de la direccion.
    // No debe existir un segundo boton junto al lapiz de editar.
    final pickupRow = source
        .split('Widget _floatingLocationRow({')
        .last
        .split('Widget _floatingBookingPanel()')
        .first;
    expect(RegExp(r'if \(showRestoreGps\)').allMatches(pickupRow).length, 1);
    expect(pickupRow.indexOf("tooltip: 'Volver a mi ubicación'"),
        lessThan(pickupRow.indexOf('const SizedBox(width: 10)')));
    expect(pickupRow, contains('onPressed: onRestoreGps'));
    expect(pickupRow, contains('Icons.edit_location_alt_outlined'));
  });
}
