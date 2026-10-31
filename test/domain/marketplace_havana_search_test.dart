import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart' as app;

void main() {
  test('POI interpreta categoria distancia y origen sin perder coordenadas', () {
    final result = app.MarketplaceMapPoint.fromMap({
      'label': 'Hospital Calixto García',
      'category': 'hospital',
      'source': 'openstreetmap',
      'distance_km': 4.6,
      'lat': 23.13,
      'lon': -82.38,
    });
    expect(result.category,'hospital');
    expect(result.distanceKm,4.6);
    expect(result.source,'openstreetmap');
    expect(result.latLng.latitude,23.13);
    expect(result.toMap(), {'lat': 23.13,'lon': -82.38});
  });

  test('las direcciones antiguas siguen compatibles', () {
    final result = app.MarketplaceMapPoint.fromMap({
      'label': 'Calle 23, Vedado',
      'lat': 23.1,
      'lon': -82.4,
    });
    expect(result.category,isNull);
    expect(result.distanceKm,isNull);
    expect(result.label,'Calle 23, Vedado');
  });
}
