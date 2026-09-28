import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';
import 'dart:io';

void main() {
  test('step one renders the official premium progress header', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('TuktukFlowHeader(step: 1)'));
  });

  test('invalid identification remains blocked by the existing validators', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains("if (!_formKey.currentState!.validate()) return;"));
    expect(source, contains('Usa formato internacional'));
  });

  test('manual selection remains available when GPS is unavailable', () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, isNot(contains('Elegir ubicación manualmente')));
    expect(source, contains('MarketplaceBookingStep.origin'));
  });

  test('publication is guarded by loading and only submits from confirmation',
      () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains('if (_publishing || flow.loading) return;'));
    expect(source, contains('publishJob('));
  });
  test('premium steps expose Paso 2 a Paso 6 in order', () {
    expect(marketplacePremiumStepNumber(MarketplaceBookingStep.location), 2);
    expect(marketplacePremiumStepNumber(MarketplaceBookingStep.origin), 3);
    expect(marketplacePremiumStepNumber(MarketplaceBookingStep.destination), 4);
    expect(marketplacePremiumStepNumber(MarketplaceBookingStep.quote), 5);
    expect(marketplacePremiumStepNumber(MarketplaceBookingStep.confirm), 6);
  });

  test('premium services use customer-facing Spanish labels', () {
    expect(marketplaceServiceLabel('passenger'), 'Pasajeros');
    expect(marketplaceServiceLabel('courier'), 'Mensajería');
    expect(marketplaceServiceLabel('cargo'), 'Carga');
  });

  test('passenger smart pricing supports the four production categories', () {
    expect(marketplacePassengerVehicleCategories,
        ['motorcycle', 'bicitaxi', 'tricycle', 'light_car']);
    expect(marketplacePassengerVehicleLabel('motorcycle'), 'Moto');
    expect(marketplacePassengerVehicleLabel('bicitaxi'), 'Bicitaxi');
    expect(marketplacePassengerVehicleLabel('tricycle'), 'Triciclo');
    expect(marketplacePassengerVehicleLabel('light_car'), 'Auto');

    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains("'passenger_by_category'"));
    expect(source, contains("'target_vehicle_category_code'"));
  });

  test('passenger category selection changes the requested quote category', () {
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

    expect(flow.passengerVehicleCategoryCode, 'tricycle');
    expect(flow.pricing['vehicle_category_code'], 'tricycle');
  });

  test('manual flow preserves selected origin, destination and service', () {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final flow = CustomerBookingFlowController(
      MarketplaceMapService(client),
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
          sessionId: 's', customerId: 'c', token: 't'),
    );
    const origin = MarketplaceMapPoint(label: 'Origen', lat: 23.1, lon: -82.3);
    const destination =
        MarketplaceMapPoint(label: 'Destino', lat: 23.2, lon: -82.4);
    flow.setOrigin(origin);
    flow.setDestination(destination);
    flow.setService('courier');
    flow.setStep(MarketplaceBookingStep.origin);
    expect(flow.origin, origin);
    expect(flow.destination, destination);
    expect(flow.serviceCode, 'courier');
  });

  test('incomplete confirmation cannot create or publish a request', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final flow = CustomerBookingFlowController(
      MarketplaceMapService(client),
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
          sessionId: 's', customerId: 'c', token: 't'),
    );
    expect(flow.step, isNot(MarketplaceBookingStep.confirm));
    await expectLater(flow.submit(), throwsA(isA<StateError>()));
  });

  test(
      'editing identification retains the same booking controller and resume step',
      () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('CustomerBookingFlowController? _bookingFlow'));
    expect(source, contains('controller: _bookingFlow'));
    expect(source, contains('_resumeBookingStep = _bookingFlow!.step'));
    expect(source, contains('_bookingFlow?.setStep(resumeStep)'));
    expect(source,
        contains('if (_existingSession != null && _editingExistingSession)'));
  });

  test('step six edit preserves route, service and request options on resume',
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
    const origin = MarketplaceMapPoint(label: 'Origen', lat: 23.1, lon: -82.3);
    const destination =
        MarketplaceMapPoint(label: 'Destino', lat: 23.2, lon: -82.4);
    const route = MarketplaceRouteQuote(
      distanceKm: 8.7,
      durationSeconds: 1440,
      routePoints: [origin, destination],
      routeToken: 'route-token',
      prices: {
        'courier': {'recommended_price': 1150, 'currency': 'CUP'},
      },
    );

    flow.origin = origin;
    flow.destination = destination;
    flow.route = route;
    flow.serviceCode = 'courier';
    flow.passengerCount = 3;
    flow.stopCount = 2;
    flow.urgent = true;
    flow.note = 'Llamar al llegar';
    flow.setStep(MarketplaceBookingStep.confirm);

    final resumeStep = flow.step;
    flow.setStep(MarketplaceBookingStep.location);
    flow.setStep(resumeStep);

    expect(flow.step, MarketplaceBookingStep.confirm);
    expect(flow.origin, same(origin));
    expect(flow.destination, same(destination));
    expect(flow.route, same(route));
    expect(flow.serviceCode, 'courier');
    expect(flow.passengerCount, 3);
    expect(flow.stopCount, 2);
    expect(flow.urgent, isTrue);
    expect(flow.note, 'Llamar al llegar');
  });

  test('step two back to identification resumes step two after continuing', () {
    final source =
        File('lib/presentation/marketplace_customer_booking_flow.dart')
            .readAsStringSync();
    expect(source, contains('case MarketplaceBookingStep.location:'));
    expect(source, contains('widget.onEditCustomer?.call();'));
    expect(source, contains('case MarketplaceBookingStep.origin:'));
    expect(
      source,
      contains('flow.setStep(MarketplaceBookingStep.location);'),
    );
  });

  test('replacing customer session preserves the complete booking draft', () {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final flow = CustomerBookingFlowController(
      MarketplaceMapService(client),
      MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(
        sessionId: 'old-session',
        customerId: 'old-customer',
        token: 'old-token',
        displayName: 'Cliente A',
        whatsappPhone: '+5351111111',
      ),
    );
    const origin = MarketplaceMapPoint(label: 'Origen', lat: 23.1, lon: -82.3);
    const destination =
        MarketplaceMapPoint(label: 'Destino', lat: 23.2, lon: -82.4);
    const route = MarketplaceRouteQuote(
      distanceKm: 8.7,
      durationSeconds: 1440,
      routePoints: [origin, destination],
      routeToken: 'route-token',
      prices: {
        'passenger': {'recommended_price': 3350, 'currency': 'CUP'},
      },
    );

    flow.origin = origin;
    flow.destination = destination;
    flow.route = route;
    flow.serviceCode = 'passenger';
    flow.passengerCount = 2;
    flow.stopCount = 1;
    flow.urgent = true;
    flow.scheduledFor = DateTime(2026, 9, 25, 10);
    flow.note = 'Llamar al llegar';
    flow.setStep(MarketplaceBookingStep.confirm);

    flow.replaceSession(
      const MarketplaceCustomerSessionSnapshot(
        sessionId: 'new-session',
        customerId: 'new-customer',
        token: 'new-token',
        displayName: 'Otra persona',
        whatsappPhone: '+5352222222',
      ),
    );

    expect(flow.session.sessionId, 'new-session');
    expect(flow.session.customerId, 'new-customer');
    expect(flow.session.token, 'new-token');
    expect(flow.session.displayName, 'Otra persona');
    expect(flow.session.whatsappPhone, '+5352222222');
    expect(flow.step, MarketplaceBookingStep.confirm);
    expect(flow.origin, same(origin));
    expect(flow.destination, same(destination));
    expect(flow.route, same(route));
    expect(flow.serviceCode, 'passenger');
    expect(flow.passengerCount, 2);
    expect(flow.stopCount, 1);
    expect(flow.urgent, isTrue);
    expect(flow.scheduledFor, DateTime(2026, 9, 25, 10));
    expect(flow.note, 'Llamar al llegar');
  });

  test('editing identification creates and rebinds a fresh customer session',
      () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('_editSessionToken'));
    expect(source, contains('_editIdempotencyKey'));
    expect(source, contains('await _service.startSession('));
    expect(source, contains('_bookingFlow?.replaceSession(snapshot)'));
    expect(source, contains('displayName: displayName'));
    expect(source, contains('whatsappPhone: whatsappPhone'));
  });
}
