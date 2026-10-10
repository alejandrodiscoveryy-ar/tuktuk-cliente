import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart' as customer;

// Prueba AISLADA de mapa, puntos y geometria. No ofrece carreras ni precios.
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

  String _lineData() => jsonEncode({
        'type': 'FeatureCollection',
        'features': _origin == null || _destination == null
            ? <Object>[]
            : <Object>[
                {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [
                        _origin!.coordinates.lng,
                        _origin!.coordinates.lat,
                      ],
                      [
                        _destination!.coordinates.lng,
                        _destination!.coordinates.lat,
                      ],
                    ],
                  },
                  'properties': <String, Object>{},
                },
              ],
      });

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
    map.addInteraction(mbx.TapInteraction.onMap((context) {
      if (!mounted) return;
      setState(() {
        if (_origin == null || _destination != null) {
          _origin = context.point;
          _destination = null;
        } else {
          _destination = context.point;
        }
      });
      unawaited(_refreshGeometry());
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
      if (mounted && _error != null) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo actualizar un marcador o linea.');
      }
    }
  }

  void _clear() {
    setState(() {
      _origin = null;
      _destination = null;
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
                  'Prueba aislada. Toca una vez para origen y otra para destino.',
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
                    if (_destination != null)
                      const Text(
                        'Segmento de prueba: linea recta, NO ruta de calles.',
                        style: TextStyle(color: Color(0xFFFFC400)),
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
