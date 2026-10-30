import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuracion remota no bloquea el arranque de la app completa', () {
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('Future<void> main() async {');
    final runApp = main.indexOf('runApp(MarketplaceCustomerApp(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(runApp, greaterThan(start));
    final beforeApp = main.substring(start, runApp);
    expect(beforeApp,
        isNot(contains('await MarketplaceMapService.loadPublicConfiguration')));
    expect(beforeApp,
        contains('unawaited(_loadPublicMapConfigurationAfterFirstFrame(client))'));
    expect(main, contains('await MarketplaceMapService.loadPublicConfiguration(client)'));
  });

  test('configuracion de mapa tiene limite y refresca sin borrar la sesion', () {
    final service =
        File('lib/data/marketplace_map_service.dart').readAsStringSync();
    final app =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();
    expect(service, contains('.timeout(const Duration(seconds: 8))'));
    expect(service, contains('publicVisualRevision.value++'));
    expect(app, contains('ValueListenableBuilder<int>'));
    expect(app, contains('home: TuktukCustomerHomeWithRate(client: client)'));
  });
}