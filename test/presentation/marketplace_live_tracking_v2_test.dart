import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test(
    'solo la carrera activa puede leer su geometría y se limpia al salir',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tuktuk-live-v2-',
      );
      Hive.init(directory.path);
      final box = await Hive.openBox('live-v2-test');
      final store = MarketplaceCustomerSessionStore(box);
      try {
        const origin = MarketplaceMapPoint(
          label: 'Recogida',
          lat: 23.13,
          lon: -82.36,
        );
        const destination = MarketplaceMapPoint(
          label: 'Destino',
          lat: 23.14,
          lon: -82.34,
        );
        await store.saveActiveJobId('job-a');
        await store.saveActiveJobMap(
          jobId: 'job-a',
          origin: origin,
          destination: destination,
          routePoints: [origin, destination],
          distanceKm: 2.4,
        );
        expect(store.readActiveJobMap('job-b'), isNull);
        final data = store.readActiveJobMap('job-a');
        expect(data, isNotNull);
        expect((data!['route_points'] as List).length, 2);
        await store.clearActiveJobId();
        expect(store.readActiveJobMap('job-a'), isNull);
        expect(store.readActiveJobId(), isNull);
      } finally {
        await box.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('la vista usa estados y mapa, sin GPS ficticio del conductor', () {
    final src = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    expect(src, contains('DraggableScrollableSheet('));
    expect(src, contains('MarketplaceVectorMap('));
    expect(src, contains('readActiveJobMap(widget.jobId)'));
    expect(src, contains('_liveDriverSummary(job)'));
    expect(src, contains('showModalBottomSheet<MarketplaceCustomerRating>'));
    expect(src, contains('getJob('));
    expect(src, contains('cancelJob('));
    expect(src, contains('_finishJob'));
    expect(src, isNot(contains('driverLiveLatitude')));
  });
}
