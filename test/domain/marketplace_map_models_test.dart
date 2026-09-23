import 'package:tuktuk_cliente/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map point parses latitude and longitude without swapping', () {
    final point = app.MarketplaceMapPoint.fromMap({
      'label': 'La Habana',
      'lat': 23.1136,
      'lon': -82.3666,
    });
    expect(point.lat, 23.1136);
    expect(point.lon, -82.3666);
    expect(point.latLng.latitude, 23.1136);
    expect(point.latLng.longitude, -82.3666);
  });

  test('route quote parses verified route and price snapshots', () {
    final quote = app.MarketplaceRouteQuote.fromMap({
      'distance_km': 9,
      'duration_seconds': 1200,
      'route_token': 'signed',
      'route_points': [
        {'lat': 23.1, 'lon': -82.3},
        {'lat': 23.2, 'lon': -82.4},
      ],
      'prices': {
        'passenger': {'recommended_price': 3900, 'currency': 'CUP'},
      },
    });
    expect(quote.distanceKm, 9);
    expect(quote.durationSeconds, 1200);
    expect(quote.routePoints[0].lat, 23.1);
    expect(quote.routePoints[0].lon, -82.3);
    expect(quote.prices['passenger']['recommended_price'], 3900);
  });
}
