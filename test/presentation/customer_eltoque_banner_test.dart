import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();

  test('valid elTOQUE snapshot shows the value and upward variation', () {
    final snapshot = MarketplacePublicEltoqueRate.parse({
      'available': true,
      'fresh': true,
      'rate': 780,
      'previous_rate': 775,
      'base_currency': 'USD',
      'charge_currency': 'CUP',
      'checked_at': now,
    });
    expect(snapshot, isNotNull);
    expect(snapshot!.canDisplay, isTrue);
    expect(snapshot.change, 5);
    expect(marketplaceEltoqueAmount(snapshot.rate), '780');
  });

  test('header explicitly displays one USD equal to CUP', () {
    expect(marketplaceEltoqueRateLabel(780), '1 USD = 780 CUP');
    expect(marketplaceEltoqueRateLabel(780.5), '1 USD = 780.50 CUP');
  });

  test('unavailable or stale rate is never shown as current', () {
    for (final stale in [false, true]) {
      final snapshot = MarketplacePublicEltoqueRate.parse({
        'available': true,
        'fresh': !stale,
        'rate': 780,
        'base_currency': 'USD',
        'charge_currency': 'CUP',
        'checked_at': stale
          ? DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String()
          : null,
      });
      expect(snapshot!.canDisplay, isFalse);
    }
  });

  test('rejects invalid response and unrelated currency pair', () {
    expect(MarketplacePublicEltoqueRate.parse({'rate': -1}), isNull);
    expect(MarketplacePublicEltoqueRate.parse([]), isNull);
    final wrongPair = MarketplacePublicEltoqueRate.parse({
      'available': true, 'fresh': true, 'rate': 780,
      'base_currency': 'EUR', 'charge_currency': 'CUP',
      'checked_at': now,
    });
    expect(wrongPair!.canDisplay, isFalse);
  });
}
