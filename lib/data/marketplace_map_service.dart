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

String? marketplaceMapboxStylePath(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  const prefix = 'mapbox://styles/';
  final path = text.startsWith(prefix) ? text.substring(prefix.length) : text;
  return RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$').hasMatch(path)
      ? path
      : null;
}


class MarketplaceMapService {
  MarketplaceMapService(this._client);
  final SupabaseClient _client;

  static String _publicToken =
      const String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');
  static String _mapStyle = 'mapbox/dark-v11';
  static int _tileSize = 256;

  static String get publicToken => _publicToken;

  static String get tileUrlTemplate =>
      'https://api.mapbox.com/styles/v1/$_mapStyle/tiles/$_tileSize/{z}/{x}/{y}?access_token=$_publicToken';

  // The administrator can store either owner/style or mapbox://styles/owner/style.
  // This config contains only the public map style and token, never admin layers.
  static bool applyPublicVisualCapability(Map item) {
    if (item['capability'] != 'map_visual' ||
        item['enabled'] != true || item['provider_code'] != 'mapbox') {
      return false;
    }

    final token = item['public_token']?.toString().trim() ?? '';
    if (token.isNotEmpty) _publicToken = token;

    final config = item['config'];
    final fallback = item['public_config'];
    final preferred = config is Map ? config['style'] : null;
    final fallbackStyle = fallback is Map ? fallback['style'] : null;
    final style = marketplaceMapboxStylePath(preferred) ??
        marketplaceMapboxStylePath(fallbackStyle);
    if (style != null) _mapStyle = style;

    final sizeValue = config is Map && config['tile_size'] != null
        ? config['tile_size']
        : fallback is Map ? fallback['tile_size'] : null;
    final size = sizeValue is num
        ? sizeValue.toInt()
        : int.tryParse('$sizeValue');
    if (size == 256 || size == 512) _tileSize = size!;
    return true;
  }


  static Future<void> loadPublicConfiguration(SupabaseClient client) async {
    try {
      final value = await client.rpc(
        'get_public_marketplace_map_capabilities_by_slug',
        params: {
          'target_project_slug': 'tuktuk-control',
        },
      );

      if (value is! Map) return;

      final capabilities = value['capabilities'];
      if (capabilities is! List) return;

      for (final item in capabilities) {
        if (item is Map && applyPublicVisualCapability(item)) break;
      }
    } catch (_) {
      // Si la configuración remota no está disponible, la aplicación
      // continúa funcionando. El mapa utilizará el fallback de compilación
      // si existe; de lo contrario mostrará el estado no configurado.
    }
  }

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
