import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';
import 'marketplace_booking_controller_test.dart' show FakeMapService, waitForVerifiedRoute;

const code = '0123456789abcdef0123456789abcdef';
const profile = MarketplacePromoProfile(code: code, name: 'Gerson',
    category: 'motorcycle', services: ['passenger'], city: 'La Habana', verified: true);
const origin = MarketplaceMapPoint(label: 'Origen', lat: 23.1, lon: -82.3);
const destination = MarketplaceMapPoint(label: 'Destino', lat: 23.2, lon: -82.4);

void main() {
  test('validates opaque link and public profile without private IDs', () {
    expect(MarketplacePromoProfile.codeFromUri(Uri.parse('https://www.vrixora.com/cliente/tuk/?conductor=$code')), code);
    expect(MarketplacePromoProfile.codeFromUri(Uri.parse('https://www.vrixora.com/cliente/tuk/?conductor=invalid')), isNull);
    final data = MarketplacePromoProfile.fromMap(code, {
      'public_name': 'Gerson', 'category_code': 'tricycle',
      'service_codes': ['passenger', 'passenger', 'invalid'],
      'photo_url': 'javascript:alert(1)', 'driver_user_id': 'private',
    });
    expect(data?.services, ['passenger']);
    expect(data?.photoUrl, isNull);
    expect(data?.verified, isFalse);
    expect(MarketplacePromoProfile.fromMap(code, {
      'public_name': 'Gerson', 'category_code': 'truck', 'service_codes': ['passenger'],
    }), isNull);
  });

  testWidgets('approved entry has both address fields, single CTA and honest badge', (tester) async {
    var pickup = 0, dropoff = 0, continuation = 0;
    await tester.pumpWidget(MaterialApp(home: MarketplacePromoEntry(
      profile: profile, origin: null, destination: null, serviceCode: 'passenger',
      onOrigin: () => pickup++, onDestination: () => dropoff++, onContinue: () => continuation++,
    )));
    expect(find.text('Viaja con Gerson'), findsOneWidget);
    expect(find.text('Conductor verificado'), findsOneWidget);
    expect(find.text('¿A dónde vamos hoy?'), findsOneWidget);
    expect(find.text('Buscar en toda la flota'), findsNothing);
    await tester.ensureVisible(find.text('Punto de recogida'));
    await tester.tap(find.text('Punto de recogida'));
    await tester.ensureVisible(find.text('¿Cuál es tu destino?'));
    await tester.tap(find.text('¿Cuál es tu destino?'));
    await tester.ensureVisible(find.text('Solicitar transporte'));
    await tester.tap(find.text('Solicitar transporte'));
    expect([pickup, dropoff, continuation], [1, 1, 1]);
    expect(find.textContaining('buscaremos otro conductor de TukTuk'), findsOneWidget);
  });

  test('personal code travels through the same verified-route and payment flow', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final map = FakeMapService(client);
    final flow = CustomerBookingFlowController(map, MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(sessionId: 'session', customerId: 'customer', token: 'token'),
      promo: profile);
    addTearDown(flow.dispose);
    expect(flow.selectedVehicleCategoryCode, 'motorcycle');
    expect(flow.serviceCode, 'passenger');
    flow.publicationReady = true;
    flow.publishedServices = const ['passenger'];
    flow.publishedPassengerCategories = const ['motorcycle'];
    flow.publishedCategoriesByService = const {'passenger': ['motorcycle']};
    flow.setOrigin(origin);
    flow.setDestination(destination);
    await waitForVerifiedRoute(flow);
    flow.setRidePaymentMethod('transfer');
    await flow.submit();
    expect(map.lastCreateParams?['target_promo_code'], code);
    expect(map.lastCreateParams?['target_vehicle_category_code'], 'motorcycle');
    expect(map.lastCreateParams?['target_details']['ride_payment_method'], 'transfer');
    expect(map.createCalls, 1);
  });

  test('ordinary booking has no promo code', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final map = FakeMapService(client);
    final flow = CustomerBookingFlowController(map, MarketplaceCustomerService(client),
      const MarketplaceCustomerSessionSnapshot(sessionId: 'session', customerId: 'customer', token: 'token'));
    addTearDown(flow.dispose);
    flow.publicationReady = true;
    flow.publishedServices = const ['passenger'];
    flow.publishedPassengerCategories = const ['motorcycle'];
    flow.publishedCategoriesByService = const {'passenger': ['motorcycle']};
    flow.setOrigin(origin);
    flow.setDestination(destination);
    await waitForVerifiedRoute(flow);
    await flow.submit();
    expect(map.lastCreateParams?.containsKey('target_promo_code'), isFalse);
  });
}
