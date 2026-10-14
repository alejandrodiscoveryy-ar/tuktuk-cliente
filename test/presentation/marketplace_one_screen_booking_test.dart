import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';

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
    expect(source,
        contains('Selecciona origen y destino para ver precios reales.'));
    expect(source, contains("'Solicitar transporte'"));
    expect(source, contains('? _submit'));
    expect(source, contains('if (_showAdvancedOptions) ...['));
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
}
