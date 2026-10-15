import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el primer acceso usa el mapa de fondo y una tarjeta compacta', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('Widget _firstTimeCustomerScreen()'));
    expect(source, contains('MarketplaceVectorMap('));
    expect(source, contains('requestedCenter: _welcomeMapCenter'));
    expect(source, contains('Widget _welcomeStartCard()'));
    expect(source, contains('¿A dónde vamos?'));
    expect(source, contains('Widget _welcomeIdentificationForm()'));
    expect(source, contains('_showFirstTimeForm'));
    expect(source, isNot(contains('TuktukFlowHeader(step: 1)')));
  });

  test('alta nueva conserva validaciones y llamada de sesión', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('validator: _validateName'));
    expect(source, contains('validator: _validateWhatsapp'));
    expect(source, contains('validator: _validateEmail'));
    expect(source, contains('if (!_formKey.currentState!.validate()) return;'));
    expect(source, contains('await _service.startSession('));
    expect(source, contains('await _sessionStore.save('));
    expect(source, contains('_bookingFlow = CustomerBookingFlowController('));
  });

  test('sin GPS o token de mapa, el cliente puede registrarse', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(source, contains('MarketplaceMapService.publicToken.startsWith'));
    expect(source, contains('TuktukHavanaBackdrop('));
    expect(source, contains('Future<void> _centerFirstEntryMap()'));
    expect(source, contains('Geolocator.requestPermission()'));
    expect(source,
        contains("label: _loading ? 'Conectando...' : 'Continuar al mapa'"));
  });
}
