part of '../main.dart';

class MarketplaceMapPoint {
  const MarketplaceMapPoint(
      {required this.label, required this.lat, required this.lon});

  final String label;
  final double lat;
  final double lon;

  LatLng get latLng => LatLng(lat, lon);
  Map<String, dynamic> toMap() => {'lat': lat, 'lon': lon};

  factory MarketplaceMapPoint.fromMap(Map value) => MarketplaceMapPoint(
        label: value['label']?.toString() ?? 'Ubicación seleccionada',
        lat: (value['lat'] as num).toDouble(),
        lon: (value['lon'] as num).toDouble(),
      );
}

class MarketplaceRouteQuote {
  const MarketplaceRouteQuote({
    required this.distanceKm,
    required this.durationSeconds,
    required this.routePoints,
    required this.routeToken,
    required this.prices,
  });

  final double distanceKm;
  final int durationSeconds;
  final List<MarketplaceMapPoint> routePoints;
  final String routeToken;
  final Map<String, dynamic> prices;

  factory MarketplaceRouteQuote.fromMap(Map value) => MarketplaceRouteQuote(
        distanceKm: (value['distance_km'] as num).toDouble(),
        durationSeconds: (value['duration_seconds'] as num).round(),
        routePoints: (value['route_points'] as List)
            .map((item) => MarketplaceMapPoint.fromMap(item as Map))
            .toList(growable: false),
        routeToken: value['route_token'] as String,
        prices: Map<String, dynamic>.from(value['prices'] as Map),
      );
}

class MarketplaceMapService {
  MarketplaceMapService(this._client);
  final SupabaseClient _client;

  static const publicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  Future<dynamic> _invoke(
      String operation, Map<String, dynamic> arguments) async {
    final response = await _client.functions.invoke(
      'marketplace-map-gateway',
      body: {'operation': operation, ...arguments},
    );
    final body = response.data;
    if (body is! Map || body['error'] != null) {
      throw StateError(
          body is Map ? '${body['error']}' : 'MAP_GATEWAY_INVALID');
    }
    return body['data'];
  }

  Future<List<MarketplaceMapPoint>> search(String query) async {
    final data = await _invoke('geocode', {'query': query});
    return (data as List)
        .map((item) => MarketplaceMapPoint.fromMap(item as Map))
        .toList(growable: false);
  }

  Future<MarketplaceMapPoint> reverse(MarketplaceMapPoint point) async =>
      MarketplaceMapPoint.fromMap(await _invoke('reverse_geocode', {
        'point': point.toMap(),
      }) as Map);

  Future<MarketplaceRouteQuote> route({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required Map<String, dynamic> pricing,
  }) async =>
      MarketplaceRouteQuote.fromMap(await _invoke('route_quote', {
        'origin': origin.toMap(),
        'destination': destination.toMap(),
        'pricing': pricing,
      }) as Map);

  Future<MarketplaceRouteQuote> reprice({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required String routeToken,
    required Map<String, dynamic> pricing,
  }) async =>
      MarketplaceRouteQuote.fromMap(await _invoke('price_quote', {
        'origin': origin.toMap(),
        'destination': destination.toMap(),
        'route_token': routeToken,
        'pricing': pricing,
      }) as Map);

  Future<MarketplaceCustomerRequestDraft> create({
    required MarketplaceMapPoint origin,
    required MarketplaceMapPoint destination,
    required String routeToken,
    required Map<String, dynamic> params,
  }) async {
    final result = await _invoke('create_request', {
      'origin': origin.toMap(),
      'destination': destination.toMap(),
      'route_token': routeToken,
      'params': params,
    });
    return MarketplaceCustomerRequestDraft.fromMap(
        (result as List).first as Map);
  }
}
