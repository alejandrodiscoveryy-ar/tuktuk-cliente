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

  test('reapertura recupera GPS historico del servidor sin inventar tiempo real', () {
    final source = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    // El gateway puede devolver una posicion de 60-120 s; ya no se desecha.
    expect(source, contains('gps.isLastKnownUsable &&'));
    expect(source, contains('driverPointStale: gps != null && !gps.isFresh'));
    expect(source, contains('Última ubicación conocida hace'));
    // No persiste GPS exacto en Hive ni lo publica como flota disponible.
    expect(source, isNot(contains('saveDriverGps(')));
  });

  test('ETA se oculta sin GPS reciente y la desconexion mantiene el estado', () {
    final s = File('lib/presentation/marketplace_customer_tracking.dart')
        .readAsStringSync();
    expect(s, contains('pickupArrivalEstimate('));
    expect(s, contains('job.driverLocation?.isFresh != true'));
    expect(s, contains('const Duration(seconds: 45)'));
    expect(s, contains('const Duration(seconds: 65)'));
    expect(s, contains('último estado comprobado'));
    expect(s, contains('_offlineTrackingText()'));
    expect(s, contains('_lastJobConfirmedAt'));
    expect(s, contains('No pudimos actualizar el estado. Revisa tu conexión.'));
  });

  test('ETA vial no da minutos de automovil a bicitaxi o bicicleta', () {
    final source = File('lib/presentation/marketplace_customer_tracking.dart')
        .readAsStringSync();
    expect(source, contains("'light_car', 'motorcycle', 'tricycle', 'van'"));
    expect(source, contains('roadVehicle'));
    expect(source, contains('!roadVehicle'));
    expect(source, contains('Llegada orientativa'));
  });

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
