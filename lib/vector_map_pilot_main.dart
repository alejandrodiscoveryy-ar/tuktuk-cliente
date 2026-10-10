import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart' as customer;
import 'vector_map_route_geometry.dart';

// Prueba AISLADA de ruta real: no crea solicitudes ni modifica tarifas.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    runApp(const _StatusApp('Falta configuracion publica de Supabase.'));
    return;
  }
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    await customer.MarketplaceMapService.loadPublicConfiguration(
      Supabase.instance.client,
    );
    final token = customer.MarketplaceMapService.publicToken;
    if (!token.startsWith('pk.')) {
      runApp(const _StatusApp('Token publico Mapbox no disponible.'));
      return;
    }
    mbx.MapboxOptions.setAccessToken(token);
    runApp(_VectorPilotApp(
      styleUri: customer.MarketplaceMapService.vectorStyleUri,
    ));
  } catch (_) {
    runApp(const _StatusApp('No se pudo cargar la configuracion publica.'));
  }
}

class _StatusApp extends StatelessWidget {
  const _StatusApp(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: Text(message))),
      );
}

// El SDK v3 no implementa managers de anotaciones en Web.
// Usamos fuentes GeoJSON + capas Circle/Line, compatibles con Web y movil.
class _VectorPilotApp extends StatefulWidget {
  const _VectorPilotApp({required this.styleUri});
  final String styleUri;

  @override
  State<_VectorPilotApp> createState() => _VectorPilotAppState();
}

class _VectorPilotAppState extends State<_VectorPilotApp> {
  static const _originSource = 'tuktuk-pilot-origin';
  static const _destSource = 'tuktuk-pilot-destination';
  static const _lineSource = 'tuktuk-pilot-segment';

  mbx.MapboxMap? _map;
  mbx.Point? _origin;
  mbx.Point? _destination;
  List<customer.MarketplaceMapPoint> _routePoints = const [];
  double? _distanceKm;
  int? _durationSeconds;
  int _selectionRevision = 0;
  bool _loadingRoute = false;
  bool _layersReady = false;
  String? _error;

  String _pointData(mbx.Point? point) => jsonEncode({
        'type': 'FeatureCollection',
        'features': point == null
            ? <Object>[]
            : <Object>[
                {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [
                      point.coordinates.lng,
                      point.coordinates.lat,
                    ],
                  },
                  'properties': <String, Object>{},
                },
              ],
      });

  String _lineData() => pilotRouteGeoJson(_routePoints);

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
    map.addInteraction(mbx.TapInteraction.onMap((context) {
      if (!mounted) return;
      final revision = ++_selectionRevision;
      setState(() {
        if (_origin == null || _destination != null) {
          _origin = context.point;
          _destination = null;
        } else {
          _destination = context.point;
        }
        _routePoints = const [];
        _distanceKm = null;
        _durationSeconds = null;
        _loadingRoute = _destination != null;
        _error = null;
      });
      unawaited(_refreshGeometry());
      if (_destination != null) unawaited(_loadRealRoute(revision));
    }));
    unawaited(
        map.scaleBar.updateSettings(mbx.ScaleBarSettings(enabled: false)));
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || _layersReady) return;
    try {
      await map.addSource(mbx.GeoJsonSource(
        id: _originSource,
        data: _pointData(_origin),
      ));
      await map.addSource(mbx.GeoJsonSource(
        id: _destSource,
        data: _pointData(_destination),
      ));
      await map.addSource(mbx.GeoJsonSource(
        id: _lineSource,
        data: _lineData(),
      ));
      await map.addLayer(mbx.LineLayer(
        id: 'tuktuk-pilot-line-layer',
        sourceId: _lineSource,
        lineColor: 0xFF26D1AA,
        lineWidth: 5,
        slot: 'top',
      ));
      await map.addLayer(mbx.CircleLayer(
        id: 'tuktuk-pilot-origin-layer',
        sourceId: _originSource,
        circleColor: 0xFF26D1AA,
        circleRadius: 11,
        circleStrokeColor: 0xFF07121C,
        circleStrokeWidth: 3,
        slot: 'top',
      ));
      await map.addLayer(mbx.CircleLayer(
        id: 'tuktuk-pilot-destination-layer',
        sourceId: _destSource,
        circleColor: 0xFFE5A951,
        circleRadius: 11,
        circleStrokeColor: 0xFF07121C,
        circleStrokeWidth: 3,
        slot: 'top',
      ));
      if (!mounted) return;
      setState(() {
        _layersReady = true;
        _error = null;
      });
      await _refreshGeometry();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudieron dibujar las capas del piloto.');
      }
    }
  }

  Future<void> _updateSource(String id, String data) async {
    final source = await _map?.getSource(id);
    if (source is! mbx.GeoJsonSource) {
      throw StateError('Fuente GeoJSON no disponible: $id');
    }
    await source.updateGeoJSON(data);
  }

  Future<void> _refreshGeometry() async {
    if (!_layersReady || _map == null) return;
    try {
      await _updateSource(_originSource, _pointData(_origin));
      await _updateSource(_destSource, _pointData(_destination));
      await _updateSource(_lineSource, _lineData());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo actualizar un marcador o linea.');
      }
    }
  }

  Future<void> _loadRealRoute(int revision) async {
    final start = _origin;
    final end = _destination;
    if (start == null || end == null) return;
    try {
      // Mismo contrato y pasarela que la reserva de Cliente. Esta prueba
      // calcula un presupuesto pero NO crea ni publica solicitudes de viaje.
      final quote = await customer.MarketplaceMapService(
        Supabase.instance.client,
      ).route(
        origin: customer.MarketplaceMapPoint(
          label: 'Origen de prueba',
          lat: start.coordinates.lat.toDouble(),
          lon: start.coordinates.lng.toDouble(),
        ),
        destination: customer.MarketplaceMapPoint(
          label: 'Destino de prueba',
          lat: end.coordinates.lat.toDouble(),
          lon: end.coordinates.lng.toDouble(),
        ),
        pricing: const {
          'passenger_count': 1,
          'stop_count': 0,
          'urgent': false,
          'load_help': false,
          'unload_help': false,
          'cargo_weight_kg': null,
          'cargo_volume_m3': null,
          'vehicle_category_code': 'motorcycle',
        },
      );
      if (!mounted || revision != _selectionRevision) return;
      if (quote.routePoints.length < 2) {
        throw const FormatException('Ruta sin geometria suficiente');
      }
      setState(() {
        _routePoints = quote.routePoints;
        _distanceKm = quote.distanceKm;
        _durationSeconds = quote.durationSeconds;
        _loadingRoute = false;
        _error = null;
      });
      unawaited(_refreshGeometry());
    } catch (_) {
      if (!mounted || revision != _selectionRevision) return;
      setState(() {
        _routePoints = const [];
        _loadingRoute = false;
        _error = 'No pudimos calcular el recorrido real por calles.';
      });
      // Nunca sustituir una ruta fallida por la antigua linea recta.
      unawaited(_refreshGeometry());
    }
  }

  void _clear() {
    ++_selectionRevision;
    setState(() {
      _origin = null;
      _destination = null;
      _routePoints = const [];
      _distanceKm = null;
      _durationSeconds = null;
      _loadingRoute = false;
      _error = null;
    });
    unawaited(_refreshGeometry());
  }

  String _format(mbx.Point? point) => point == null
      ? 'Sin seleccionar'
      : '${point.coordinates.lat.toStringAsFixed(5)}, '
          '${point.coordinates.lng.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          appBar:
              AppBar(title: const Text('TUKTUK | Mapa vectorial interactivo')),
          body: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Prueba de rutas reales. Toca una vez para origen y otra para destino.',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: mbx.MapWidget(
                  styleUri: widget.styleUri,
                  onMapCreated: _onMapCreated,
                  onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
                  viewport: mbx.CameraViewportState(
                    center: mbx.Point(
                      coordinates: mbx.Position(-82.3666, 23.1136),
                    ),
                    zoom: 13,
                    bearing: 0,
                    pitch: 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Origen: ${_format(_origin)}'),
                    Text('Destino: ${_format(_destination)}'),
                    if (_loadingRoute)
                      const Text('Calculando recorrido real por calles...'),
                    if (_routePoints.length >= 2 &&
                        _distanceKm != null &&
                        _durationSeconds != null)
                      Text(
                        'Recorrido real: ${_distanceKm!.toStringAsFixed(2)} km, '
                        '${(_durationSeconds! / 60).round()} min estimados.',
                        style: const TextStyle(color: Color(0xFF26D1AA)),
                      ),
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(color: Colors.redAccent)),
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Elegir otros puntos'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
