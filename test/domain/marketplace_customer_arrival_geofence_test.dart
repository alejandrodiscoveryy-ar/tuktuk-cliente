import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 15);
  const pickup =
      MarketplaceMapPoint(label: 'Recogida', lat: 23.1300, lon: -82.3600);
  MarketplaceDriverLiveLocation position({
    required DateTime at,
    double lat = 23.1300,
    double accuracy = 12,
  }) =>
      MarketplaceDriverLiveLocation(
        latitude: lat,
        longitude: -82.3600,
        capturedAt: at,
        accuracyM: accuracy,
      );

  test('la misma lectura GPS no puede disparar dos muestras', () {
    final detector = MarketplaceCustomerArrivalGeofence();
    final fix = position(at: now.subtract(const Duration(seconds: 15)));
    expect(
        detector.observe(
            status: 'en_route', location: fix, pickup: pickup, now: now),
        false);
    expect(
        detector.observe(
            status: 'en_route', location: fix, pickup: pickup, now: now),
        false);
  });

  test('dos posiciones distintas separadas activan solo una alerta', () {
    final detector = MarketplaceCustomerArrivalGeofence();
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now.subtract(const Duration(seconds: 25))),
          pickup: pickup,
          now: now,
        ),
        false);
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now.subtract(const Duration(seconds: 10))),
          pickup: pickup,
          now: now,
        ),
        true);
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now),
          pickup: pickup,
          now: now,
        ),
        false);
  });

  test('no se notifica con GPS inexacto, lejano o durante el servicio', () {
    final detector = MarketplaceCustomerArrivalGeofence();
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now, accuracy: 95),
          pickup: pickup,
          now: now,
        ),
        false);
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now, lat: 23.135),
          pickup: pickup,
          now: now,
        ),
        false);
    expect(
        detector.observe(
          status: 'in_progress',
          location: position(at: now),
          pickup: pickup,
          now: now,
        ),
        false);
    expect(
        detector.observe(
          status: 'en_route',
          location: position(at: now.subtract(const Duration(minutes: 2))),
          pickup: pickup,
          now: now,
        ),
        false);
  });

  test('una salida del perimetro reinicia la confirmacion', () {
    final detector = MarketplaceCustomerArrivalGeofence();
    expect(
        detector.observe(
            status: 'accepted',
            location: position(at: now.subtract(const Duration(seconds: 40))),
            pickup: pickup,
            now: now),
        false);
    expect(
        detector.observe(
            status: 'accepted',
            location: position(
                at: now.subtract(const Duration(seconds: 25)), lat: 23.135),
            pickup: pickup,
            now: now),
        false);
    expect(
        detector.observe(
            status: 'accepted',
            location: position(at: now.subtract(const Duration(seconds: 15))),
            pickup: pickup,
            now: now),
        false);
    expect(
        detector.observe(
            status: 'accepted',
            location: position(at: now),
            pickup: pickup,
            now: now),
        true);
  });
}
