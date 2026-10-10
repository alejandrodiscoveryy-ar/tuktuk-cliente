part of '../main.dart';

// Shared vector renderer for the real customer booking flow.
// Only public map configuration and data for this booking are rendered.
String marketplaceVectorPointGeoJson(MarketplaceMapPoint? point) => jsonEncode({
  'type': 'FeatureCollection',
  'features': point == null
      ? <Object>[]
      : <Object>[
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [point.lon, point.lat],
            },
            'properties': <String, Object>{},
          },
        ],
});

String marketplaceVectorLineGeoJson(List<MarketplaceMapPoint> points) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'features': points.length < 2
          ? <Object>[]
          : <Object>[
              {
                'type': 'Feature',
                'geometry': {
                  'type': 'LineString',
                  'coordinates': points
                      .map((point) => <double>[point.lon, point.lat])
                      .toList(growable: false),
                },
                'properties': <String, Object>{},
              },
            ],
    });

class MarketplaceVectorMap extends StatefulWidget {
  const MarketplaceVectorMap({
    required this.initialCenter,
    required this.initialZoom,
    this.requestedCenter,
    this.markerPoint,
    this.markerIsDestination = false,
    this.originPoint,
    this.destinationPoint,
    this.routePoints = const <MarketplaceMapPoint>[],
    this.onPointTap,
    this.onCenterMoved,
    super.key,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final ValueNotifier<LatLng?>? requestedCenter;
  final MarketplaceMapPoint? markerPoint;
  final bool markerIsDestination;
  final MarketplaceMapPoint? originPoint;
  final MarketplaceMapPoint? destinationPoint;
  final List<MarketplaceMapPoint> routePoints;
  final ValueChanged<LatLng>? onPointTap;
  final ValueChanged<LatLng>? onCenterMoved;

  @override
  State<MarketplaceVectorMap> createState() => _MarketplaceVectorMapState();
}

class _MarketplaceVectorMapState extends State<MarketplaceVectorMap> {
  static const _sourceOrigin = 'tuktuk-client-vector-origin';
  static const _sourceDestination = 'tuktuk-client-vector-destination';
  static const _sourceRoute = 'tuktuk-client-vector-route';

  mbx.MapboxMap? _map;
  bool _layersReady = false;
  String? _loadError;
  LatLng? _lastCenter;
  LatLng? _programmaticTarget;

  @override
  void initState() {
    super.initState();
    _lastCenter = widget.initialCenter;
    widget.requestedCenter?.addListener(_centerRequested);
  }

  @override
  void didUpdateWidget(covariant MarketplaceVectorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedCenter != widget.requestedCenter) {
      oldWidget.requestedCenter?.removeListener(_centerRequested);
      widget.requestedCenter?.addListener(_centerRequested);
    }
    if (oldWidget.markerPoint != widget.markerPoint ||
        oldWidget.markerIsDestination != widget.markerIsDestination ||
        oldWidget.originPoint != widget.originPoint ||
        oldWidget.destinationPoint != widget.destinationPoint ||
        oldWidget.routePoints != widget.routePoints) {
      unawaited(_refreshGeometry());
    }
  }

  @override
  void dispose() {
    widget.requestedCenter?.removeListener(_centerRequested);
    _map = null;
    super.dispose();
  }

  MarketplaceMapPoint? get _origin =>
      widget.onPointTap != null &&
          widget.markerPoint != null &&
          !widget.markerIsDestination
      ? widget.markerPoint
      : widget.originPoint;

  MarketplaceMapPoint? get _destination =>
      widget.onPointTap != null &&
          widget.markerPoint != null &&
          widget.markerIsDestination
      ? widget.markerPoint
      : widget.destinationPoint;

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
    map.addInteraction(
      mbx.TapInteraction.onMap((context) {
        if (!mounted || widget.onPointTap == null) return;
        widget.onPointTap!(
          LatLng(
            context.point.coordinates.lat.toDouble(),
            context.point.coordinates.lng.toDouble(),
          ),
        );
      }),
    );
    unawaited(
      map.scaleBar.updateSettings(mbx.ScaleBarSettings(enabled: false)),
    );
    _centerRequested();
  }

  void _centerRequested() {
    final position = widget.requestedCenter?.value;
    final map = _map;
    if (position == null || map == null) return;
    _programmaticTarget = position;
    _lastCenter = position;
    unawaited(
      map.setCamera(
        mbx.CameraOptions(
          center: mbx.Point(
            coordinates: mbx.Position(position.longitude, position.latitude),
          ),
          zoom: 15,
        ),
      ),
    );
  }

  Future<void> _onMapIdle() async {
    final map = _map;
    if (map == null || !_layersReady || widget.onCenterMoved == null) return;
    try {
      final camera = await map.getCameraState();
      if (!mounted || map != _map) return;
      final position = LatLng(
        camera.center.coordinates.lat.toDouble(),
        camera.center.coordinates.lng.toDouble(),
      );
      bool close(LatLng a, LatLng b) =>
          (a.latitude - b.latitude).abs() < 0.00002 &&
          (a.longitude - b.longitude).abs() < 0.00002;
      final expected = _programmaticTarget;
      if (expected != null && close(expected, position)) {
        _programmaticTarget = null;
        _lastCenter = position;
        return;
      }
      final last = _lastCenter;
      if (last != null && close(last, position)) return;
      _lastCenter = position;
      widget.onCenterMoved?.call(position);
    } catch (_) {
      // The map may be tearing down during a navigation transition.
    }
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || _layersReady) return;
    try {
      await map.addSource(
        mbx.GeoJsonSource(
          id: _sourceOrigin,
          data: marketplaceVectorPointGeoJson(_origin),
        ),
      );
      await map.addSource(
        mbx.GeoJsonSource(
          id: _sourceDestination,
          data: marketplaceVectorPointGeoJson(_destination),
        ),
      );
      await map.addSource(
        mbx.GeoJsonSource(
          id: _sourceRoute,
          data: marketplaceVectorLineGeoJson(widget.routePoints),
        ),
      );
      await map.addLayer(
        mbx.LineLayer(
          id: 'tuktuk-client-route-outline',
          sourceId: _sourceRoute,
          lineColor: 0xFF06131A,
          lineWidth: 10,
          slot: 'top',
        ),
      );
      await map.addLayer(
        mbx.LineLayer(
          id: 'tuktuk-client-route-line',
          sourceId: _sourceRoute,
          lineColor: 0xFFFFC400,
          lineWidth: 6,
          slot: 'top',
        ),
      );
      // Iconos premium propios, anclados al punto exacto del mapa.
      // Primero registramos ambos PNG en el estilo Mapbox Web/Android/iOS.
      final assets = DefaultAssetBundle.of(context);
      final pickup = await assets.load('assets/map_markers/pickup_green.png');
      final destination = await assets.load(
        'assets/map_markers/destination_red.png',
      );
      if (!mounted || map != _map) return;
      await map.addImage(
        'tuktuk-client-pickup-green-v7',
        2.0,
        mbx.StyleImage.bytes(
          pickup.buffer.asUint8List(pickup.offsetInBytes, pickup.lengthInBytes),
        ),
      );
      await map.addImage(
        'tuktuk-client-destination-red-v7',
        2.0,
        mbx.StyleImage.bytes(
          destination.buffer.asUint8List(
            destination.offsetInBytes,
            destination.lengthInBytes,
          ),
        ),
      );
      await map.addLayer(
        mbx.SymbolLayer(
          id: 'tuktuk-client-origin-point',
          sourceId: _sourceOrigin,
          iconImage: 'tuktuk-client-pickup-green-v7',
          iconAnchor: mbx.IconAnchor.BOTTOM,
          iconSize: 1.0,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          slot: 'top',
        ),
      );
      await map.addLayer(
        mbx.SymbolLayer(
          id: 'tuktuk-client-destination-point',
          sourceId: _sourceDestination,
          iconImage: 'tuktuk-client-destination-red-v7',
          iconAnchor: mbx.IconAnchor.BOTTOM,
          iconSize: 1.0,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          slot: 'top',
        ),
      );
      if (!mounted || map != _map) return;
      setState(() {
        _layersReady = true;
        _loadError = null;
      });
      await _refreshGeometry();
    } catch (_) {
      if (mounted && map == _map) {
        setState(() => _loadError = 'No se pudo dibujar el mapa.');
      }
    }
  }

  Future<void> _updateSource(String id, String data) async {
    final source = await _map?.getSource(id);
    if (source is! mbx.GeoJsonSource) {
      throw StateError('Map source unavailable: $id');
    }
    await source.updateGeoJSON(data);
  }

  Future<void> _refreshGeometry() async {
    if (!_layersReady || _map == null) return;
    try {
      await _updateSource(
        _sourceOrigin,
        marketplaceVectorPointGeoJson(_origin),
      );
      await _updateSource(
        _sourceDestination,
        marketplaceVectorPointGeoJson(_destination),
      );
      await _updateSource(
        _sourceRoute,
        marketplaceVectorLineGeoJson(widget.routePoints),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'No se pudo actualizar la ruta.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MarketplaceMapService.publicToken.startsWith('pk.')) {
      return const Center(child: Text('Mapa vectorial no configurado.'));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        mbx.MapWidget(
          styleUri: MarketplaceMapService.vectorStyleUri,
          viewport: mbx.CameraViewportState(
            center: mbx.Point(
              coordinates: mbx.Position(
                widget.initialCenter.longitude,
                widget.initialCenter.latitude,
              ),
            ),
            zoom: widget.initialZoom,
            bearing: 0,
            pitch: 0,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
          onMapIdleListener: (_) => unawaited(_onMapIdle()),
          onMapLoadErrorListener: (_) {
            if (mounted) {
              setState(() => _loadError = 'El mapa no pudo cargar.');
            }
          },
        ),
        if (_loadError != null)
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE5222732),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
