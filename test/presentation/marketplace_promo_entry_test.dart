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

class _PromoSearchMap extends FakeMapService {
  _PromoSearchMap(super.client);

  @override
  Future<List<MarketplaceMapPoint>> search(String query, {MarketplaceMapPoint? proximity}) async => [destination];
}

void main() {
  test('passenger is the default whenever offered', () {
    const multi = MarketplacePromoProfile(code: code, name: 'Gerson',
      category: 'tricycle', services: ['cargo', 'courier', 'passenger']);
    const cargoOnly = MarketplacePromoProfile(code: code, name: 'Carga',
      category: 'tricycle', services: ['cargo', 'courier']);
    expect(multi.defaultService, 'passenger');
    expect(cargoOnly.defaultService, 'cargo');
  });

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
    MarketplaceMapPoint? selected;
    final map = _PromoSearchMap(SupabaseClient('https://example.supabase.co', 'test-key'));
    await tester.pumpWidget(MaterialApp(home: MarketplacePromoEntry(
      profile: profile, origin: null, destination: null, serviceCode: 'passenger',
      mapService: map, onOriginSelected: (_) {}, onDestinationSelected: (value) => selected = value,
      onOrigin: () => pickup++, onDestination: () => dropoff++, onContinue: () => continuation++,
    )));
    expect(find.text('Viaja con Gerson'), findsOneWidget);
    expect(find.text('Conductor verificado'), findsOneWidget);
    expect(find.text('¿A dónde vamos hoy?'), findsOneWidget);
    expect(find.text('Buscar en toda la flota'), findsNothing);
    expect(find.text('Usar mi ubicación GPS'), findsOneWidget);
    await tester.ensureVisible(find.text('Origen en el mapa'));
    await tester.tap(find.text('Origen en el mapa'));
    await tester.ensureVisible(find.text('Destino en el mapa'));
    await tester.tap(find.text('Destino en el mapa'));
    final destinationField = find.byType(TextField).last;
    await tester.ensureVisible(destinationField);
    await tester.enterText(destinationField, 'Destino');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final suggestion = find.widgetWithText(ListTile, 'Destino');
    expect(suggestion, findsOneWidget);
    await tester.ensureVisible(suggestion);
    await tester.tap(suggestion);
    await tester.pump();
    expect(selected, destination);
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
