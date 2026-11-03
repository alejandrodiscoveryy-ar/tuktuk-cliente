import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android: el banner de elTOQUE no duplica el margen superior', () {
    final banner = File('lib/presentation/customer_eltoque_banner.dart')
        .readAsStringSync();
    expect(banner, contains('TuktukCustomerEltoqueBanner(client: client)'));
    expect(banner, contains('MediaQuery.removePadding('));
    expect(banner, contains(
      'removeTop: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,'));
    expect(banner, contains('child: MarketplaceCustomerShell(client: client)'));
    expect(banner, contains('child: SafeArea('));
  });
}
