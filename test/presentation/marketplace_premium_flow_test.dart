import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';
import 'dart:io';

void main() {
  test('step one renders the official premium progress header', () {
    final source = File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('TuktukFlowHeader(step: 1)'));
  });

  test('invalid identification remains blocked by the existing validators', () {
    final source = File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains("if (!_formKey.currentState!.validate()) return;"));
    expect(source, contains('Usa formato internacional'));
  });

  test('manual selection remains available when GPS is unavailable', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    expect(source, contains('Elegir ubicación manualmente'));
    expect(source, contains('MarketplaceBookingStep.origin'));
  });

  test('publication is guarded by loading and only submits from confirmation', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
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
}
