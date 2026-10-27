import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('la ubicación inválida o ajena al contrato nunca se dibuja', () {
    expect(MarketplaceDriverLiveLocation.fromMap(null), isNull);
    expect(
        MarketplaceDriverLiveLocation.fromMap(
            {'latitude': 91, 'longitude': -82}),
        isNull);
    expect(
        MarketplaceDriverLiveLocation.fromMap(
            {'latitude': 'NaN', 'longitude': -82}),
        isNull);
  });

  test('una ubicación reciente y precisa se puede mostrar', () {
    final gps = MarketplaceDriverLiveLocation.fromMap({
      'latitude': 23.13,
      'longitude': -82.36,
      'accuracy_m': 14.0,
      'speed_mps': 2.0,
      'captured_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 10))
          .toIso8601String(),
    });
    expect(gps, isNotNull);
    expect(gps!.isFresh, isTrue);
  });

  test('GPS viejo o impreciso no aparece como posición actual', () {
    final older = MarketplaceDriverLiveLocation.fromMap({
      'latitude': 23.13,
      'longitude': -82.36,
      'accuracy_m': 10,
      'captured_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 3))
          .toIso8601String(),
    });
    final inaccurate = MarketplaceDriverLiveLocation.fromMap({
      'latitude': 23.13,
      'longitude': -82.36,
      'accuracy_m': 85,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    });
    expect(older!.isFresh, isFalse);
    expect(inaccurate!.isFresh, isFalse);
  });
}
