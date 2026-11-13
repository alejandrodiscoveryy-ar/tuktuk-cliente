import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mi TukTuk preserves approved landing and existing booking flow', () {
    final entry = File('lib/presentation/marketplace_promo_entry.dart').readAsStringSync();
    final shell = File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    final booking = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final service = File('lib/data/marketplace_customer_service.dart').readAsStringSync();
    for (final label in ['Viaja con', '¿A dónde vamos hoy?', 'Punto de recogida',
      '¿Cuál es tu destino?', 'Solicitar transporte', 'Intentaremos localizar primero']) {
      expect(entry, contains(label));
    }
    expect(entry, contains('MarketplaceLocationPicker('));
    expect(entry, isNot(contains('Buscar en toda la flota')));
    expect(entry, isNot(contains('publishJob(')));
    expect(shell, contains("Uri.base.queryParameters['conductor']"));
    expect(shell, contains('_activeJobId == null && !_promoEntryAccepted'));
    expect(shell, contains('flow.applyPromo('));
    expect(booking, contains("if (promoProfile != null) 'target_promo_code': promoProfile!.code"));
    expect(booking, contains('category == promo.category'));
    expect(booking, contains('promoProfile = null;'));
    expect(service, contains("_gateway('promo_profile'"));
    expect(service, contains('raw[\'verified\'] == true'));
  });
}
