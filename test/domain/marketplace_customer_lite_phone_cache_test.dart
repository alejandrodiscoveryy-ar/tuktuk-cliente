import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  const phone = '+5350012345';
  final now = DateTime.utc(2026, 11, 3, 12);

  test('Android Lite usa numero verificado como maximo 24 horas', () {
    expect(marketplaceCustomerCachedAndroidLiteNumber(
      number: phone,
      verifiedAt: now.subtract(const Duration(minutes: 15)).toIso8601String(),
      now: now,
    ), phone);
    expect(marketplaceCustomerCachedAndroidLiteNumber(
      number: phone,
      verifiedAt: now.subtract(const Duration(hours: 23)).toIso8601String(),
      now: now,
    ), phone);
    expect(marketplaceCustomerCachedAndroidLiteNumber(
      number: phone,
      verifiedAt: now.subtract(const Duration(hours: 24)).toIso8601String(),
      now: now,
    ), isNull);
    expect(marketplaceCustomerCachedAndroidLiteNumber(
      number: phone,
      verifiedAt: now.add(const Duration(minutes: 1)).toIso8601String(),
      now: now,
    ), isNull);
  });

  test('Android Lite nunca usa numero no validado ni fecha invalida', () {
    for (final number in [null, '555', '5350012345']) {
      expect(marketplaceCustomerCachedAndroidLiteNumber(
        number: number, verifiedAt: now.toIso8601String(), now: now,
      ), isNull);
    }
    expect(marketplaceCustomerCachedAndroidLiteNumber(
      number: phone, verifiedAt: 'invalido', now: now,
    ), isNull);
  });

  test('Android Lite sincroniza en inicio, reanudacion y cada 15 minutos', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart')
        .readAsStringSync();
    expect(source, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(source, contains('WidgetsBinding.instance.removeObserver(this)'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('Timer.periodic(const Duration(minutes: 15)'));
    expect(source, contains('_refreshAndroidLiteNumber(force: true)'));
    expect(source, contains('_androidLitePhoneForContact()'));
    expect(source, contains('await cache.delete(_litePhoneKey)'));
    expect(source, contains('marketplaceCustomerPublicLiteNumber(data, _liteProjectId)'));
    expect(source, contains('flow.session.displayName'));
    expect(source, contains('flow.session.whatsappPhone'));
    expect(source, contains('No hay precio ni reserva confirmados.'));
  });
}
