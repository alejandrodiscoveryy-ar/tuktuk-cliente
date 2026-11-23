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

// Only the vehicle modality is published with coarse, anonymous GPS.
// Every feature retains the exact coordinate returned by the gateway.
// When approximate coordinates coincide, compact icons separate only in
// screen pixels around that anchor; no rows, columns or invented GPS.
String marketplaceFleetIconKey(String? category) => switch (category) {
  'light_car' => 'tuktuk-fleet-auto-v2',
  'motorcycle' => 'tuktuk-fleet-moto-v2',
  'tricycle' => 'tuktuk-fleet-triciclo-v2',
  'bicitaxi' => 'tuktuk-fleet-bicitaxi-v2',
  'bicycle' => 'tuktuk-fleet-bici-v2',
  _ => 'tuktuk-fleet-otro-v2',
};

// No city-wide grid or fabricated driver positions.
// Each vehicle keeps the approximate, authenticated server coordinate.
// At the rare exact collision, icons can separate by a few SCREEN pixels
// around that same anchor without altering geographic coordinates.
String marketplaceVectorFleetGeoJson(List<MarketplaceMapPoint> points) {
  final grouped = <String, List<MarketplaceMapPoint>>{};
  for (final point in points) {
    final key =
        '${point.lat.toStringAsFixed(6)}:${point.lon.toStringAsFixed(6)}';
    (grouped[key] ??= <MarketplaceMapPoint>[]).add(point);
  }

  final features = <Map<String, Object>>[];
  for (final group in grouped.values) {
    group.sort((a, b) => marketplaceFleetIconKey(a.category)
        .compareTo(marketplaceFleetIconKey(b.category)));
    for (var i = 0; i < group.length; i++) {
      final point = group[i];
      final angle = 2 * pi * i / group.length + 0.29;
      final radial = group.length == 1 ? 0.0 : min(0.36, 0.24 + group.length * 0.02);
      features.add({
        'type': 'Feature',
        'geometry': <String, Object>{
          'type': 'Point',
          'coordinates': <double>[point.lon, point.lat],
        },
        'properties': <String, Object>{
          'icon': marketplaceFleetIconKey(point.category),
          'offset': <double>[
            radial * cos(angle),
            radial * sin(angle),
          ],
        },
      });
    }
  }
  return jsonEncode({'type': 'FeatureCollection', 'features': features});
}

// Retain the approximate server-provided footprint on weak connections,
 // without continuing to claim that a previously live driver is available.
List<MarketplaceMapPoint> marketplaceFleetAsCoverage(
  List<MarketplaceMapPoint> points,
) => List<MarketplaceMapPoint>.unmodifiable(
  points.map((point) => MarketplaceMapPoint(
    label: '',
    lat: point.lat,
    lon: point.lon,
    source: 'fleet_coverage',
    category: point.category,
  )),
);

class MarketplaceVectorMap extends StatefulWidget {
  const MarketplaceVectorMap({
    required this.initialCenter,
    required this.initialZoom,
    this.requestedCenter,
    this.requestedZoom,
    this.ornamentBottomInset,
    this.markerPoint,
    this.markerIsDestination = false,
    this.driverPoint,
    this.driverPointStale = false,
    this.loadFleetPoints,
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
  final double? requestedZoom;
  final ValueNotifier<double>? ornamentBottomInset;
  final MarketplaceMapPoint? markerPoint;
  final bool markerIsDestination;
  final MarketplaceMapPoint? driverPoint;
  final bool driverPointStale;
  final Future<List<MarketplaceMapPoint>> Function()? loadFleetPoints;
  final MarketplaceMapPoint? originPoint;
  final MarketplaceMapPoint? destinationPoint;
  final List<MarketplaceMapPoint> routePoints;
  final ValueChanged<LatLng>? onPointTap;
  final ValueChanged<LatLng>? onCenterMoved;

  @override
  State<MarketplaceVectorMap> createState() => _MarketplaceVectorMapState();
}

class _MarketplaceVectorMapState extends State<MarketplaceVectorMap>
    with WidgetsBindingObserver {
  static const _sourceOrigin = 'tuktuk-client-vector-origin';
  static const _sourceDestination = 'tuktuk-client-vector-destination';
  static const _sourceDriver = 'tuktuk-client-vector-driver';
  static const _sourceDriverStale = 'tuktuk-client-vector-driver-stale';
  static const _sourceRoute = 'tuktuk-client-vector-route';
  static const _sourceFleet = 'tuktuk-client-vector-working-fleet';
  static const _sourceCoverage = 'tuktuk-client-vector-fleet-coverage';
  Timer? _fleetTimer;
  bool _fleetRequestPending = false;
  bool _fleetForeground = true;
  List<MarketplaceMapPoint> _fleetPoints = const [];

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
    widget.ornamentBottomInset?.addListener(_updateOrnaments);
    MarketplaceMapService.publicVisualRevision.addListener(_visualStyleChanged);
    WidgetsBinding.instance.addObserver(this);
    _fleetForeground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _startFleetPolling();
  }

  @override
  void didUpdateWidget(covariant MarketplaceVectorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedCenter != widget.requestedCenter) {
      oldWidget.requestedCenter?.removeListener(_centerRequested);
      widget.requestedCenter?.addListener(_centerRequested);
    }
    if (oldWidget.ornamentBottomInset != widget.ornamentBottomInset) {
      oldWidget.ornamentBottomInset?.removeListener(_updateOrnaments);
      widget.ornamentBottomInset?.addListener(_updateOrnaments);
      _updateOrnaments();
    }
    if (oldWidget.markerPoint != widget.markerPoint ||
        oldWidget.markerIsDestination != widget.markerIsDestination ||
        oldWidget.originPoint != widget.originPoint ||
        oldWidget.destinationPoint != widget.destinationPoint ||
        oldWidget.routePoints != widget.routePoints) {
      unawaited(_refreshGeometry());
    }
    if (oldWidget.driverPoint != widget.driverPoint ||
        oldWidget.driverPointStale != widget.driverPointStale) {
      unawaited(_refreshDriverPoint());
    }
    if ((oldWidget.loadFleetPoints == null) != (widget.loadFleetPoints == null)) {
      _fleetTimer?.cancel();
      _fleetTimer = null;
      if (widget.loadFleetPoints == null) {
        _fleetPoints = const [];
        unawaited(_refreshFleetSource());
      } else {
        _startFleetPolling();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fleetForeground = state == AppLifecycleState.resumed;
    if (_fleetForeground) {
      _startFleetPolling();
    } else {
      _fleetTimer?.cancel();
      _fleetTimer = null;
      // Keep only an anonymous coverage footprint while inactive; never
      // retain a stale live-availability assertion.
      _fleetPoints = marketplaceFleetAsCoverage(_fleetPoints);
      unawaited(_refreshFleetSource());
    }
  }

  void _startFleetPolling() {
    if (!_fleetForeground || widget.loadFleetPoints == null || _fleetTimer != null) return;
    unawaited(_loadFleet());
    _fleetTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_loadFleet());
    });
  }

  Future<void> _loadFleet() async {
    final loader = widget.loadFleetPoints;
    if (!mounted || !_fleetForeground || loader == null || _fleetRequestPending) return;
    _fleetRequestPending = true;
    try {
      final points = await loader().timeout(const Duration(seconds: 12));
      if (!mounted || widget.loadFleetPoints == null) return;
      // Preserve both anonymous layers; availability is always explicit.
      _fleetPoints = points;
      await _refreshFleetSource();
    } catch (_) {
      // Poor connectivity must not erase known coverage, but it must
      // immediately downgrade any old live signal to coverage.
      if (mounted && widget.loadFleetPoints != null) {
        _fleetPoints = marketplaceFleetAsCoverage(_fleetPoints);
        await _refreshFleetSource();
      }
    } finally {
      _fleetRequestPending = false;
    }
  }

  Future<void> _refreshFleetSource() async {
    if (!_layersReady || _map == null) return;
    try {
      await _updateSource(_sourceCoverage, marketplaceVectorFleetGeoJson(
        _fleetPoints.where((point) => point.source != 'fleet_live').toList(),
      ));
      await _updateSource(_sourceFleet, marketplaceVectorFleetGeoJson(
        _fleetPoints.where((point) => point.source == 'fleet_live').toList(),
      ));
    } catch (_) {
      // Map/style can be disposed while the snapshot is in flight.
    }
  }

  @override
  void dispose() {
    _fleetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.requestedCenter?.removeListener(_centerRequested);
    widget.ornamentBottomInset?.removeListener(_updateOrnaments);
    MarketplaceMapService.publicVisualRevision.removeListener(_visualStyleChanged);
    _map = null;
    super.dispose();
  }

  MarketplaceMapPoint? get _origin => widget.onPointTap != null &&
          widget.markerPoint != null &&
          !widget.markerIsDestination
      ? widget.markerPoint
      : widget.originPoint;

  MarketplaceMapPoint? get _destination => widget.onPointTap != null &&
          widget.markerPoint != null &&
          widget.markerIsDestination
      ? widget.markerPoint
      : widget.destinationPoint;

  void _visualStyleChanged() {
    if (mounted) setState(() {});
  }

  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
    _layersReady = false;
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
    _updateOrnaments();
  }

  void _updateOrnaments() {
    final map = _map;
    if (map == null) return;
    final height = MediaQuery.sizeOf(context).height;
    final inset = (widget.ornamentBottomInset?.value ?? 0)
        .clamp(0.0, max(0.0, height - 72))
        .toDouble();
    // Creditos siempre visibles en el mapa libre, nunca debajo del CTA.
    unawaited(map.logo.updateSettings(
      mbx.LogoSettings(marginBottom: inset + 10, marginLeft: 8),
    ));
    unawaited(map.attribution.updateSettings(
      mbx.AttributionSettings(marginBottom: inset + 10, marginRight: 8),
    ));
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
          zoom: widget.requestedZoom ?? 15,
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

  // Compact illustrations drawn with stable Canvas paths, never font glyphs.
  // No large colored tiles: the vehicle silhouette itself is the marker.
  // The driver location still comes only from the coarse gateway GeoJSON.
  Future<void> _registerFleetIcons(mbx.MapboxMap map) async {
    const width = 96;
    const height = 72;
    const ink = Color(0xFF071725);
    const light = Color(0xFFF4FAFF);
    final variants = <(String, Color)>[
      ('auto', const Color(0xFF5DBDFA)),
      ('moto', const Color(0xFFE6BD58)),
      ('triciclo', const Color(0xFFFF9849)),
      ('bicitaxi', const Color(0xFF63DBB0)),
      ('bici', const Color(0xFFB7A3F8)),
      ('otro', const Color(0xFFB5C7D2)),
    ];

    for (final (name, color) in variants) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final fill = Paint()..color = color;
      final darkFill = Paint()..color = ink;
      final glass = Paint()..color = const Color(0xFFE0F4FF);
      final rim = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;

      void shell(ui.Path path) {
        canvas.drawPath(path, rim);
        canvas.drawPath(path, fill);
      }

      void stroke(List<Offset> points, {double thickness = 6, Color? tone}) {
        final p = Paint()
          ..color = ink
          ..strokeWidth = thickness + 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final main = Paint()
          ..color = tone ?? color
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, p);
        canvas.drawPath(path, main);
      }

      void wheel(double x, double y, double radius) {
        canvas.drawCircle(Offset(x, y), radius + 2, darkFill);
        canvas.drawCircle(Offset(x, y), radius - 2, Paint()..color = light);
        canvas.drawCircle(Offset(x, y), max(2, radius * .32), darkFill);
      }

      switch (name) {
        case 'auto':
          shell(ui.Path()
            ..moveTo(8, 42)
            ..lineTo(21, 40)
            ..lineTo(31, 27)
            ..quadraticBezierTo(34, 23, 40, 23)
            ..lineTo(62, 23)
            ..quadraticBezierTo(68, 23, 71, 28)
            ..lineTo(79, 39)
            ..lineTo(87, 43)
            ..lineTo(87, 53)
            ..lineTo(9, 53)
            ..close());
          canvas.drawPath(ui.Path()
            ..moveTo(35, 29)
            ..lineTo(46, 29)
            ..lineTo(46, 40)
            ..lineTo(26, 40)
            ..close(), glass);
          canvas.drawPath(ui.Path()
            ..moveTo(50, 29)
            ..lineTo(63, 29)
            ..lineTo(72, 40)
            ..lineTo(50, 40)
            ..close(), glass);
          wheel(25, 54, 9);
          wheel(72, 54, 9);
        case 'moto':
          wheel(20, 54, 12);
          wheel(77, 54, 12);
          stroke([const Offset(20, 54), const Offset(39, 38),
            const Offset(54, 54), const Offset(20, 54)], thickness: 5);
          stroke([const Offset(39, 38), const Offset(65, 38),
            const Offset(77, 54)], thickness: 5);
          stroke([const Offset(65, 38), const Offset(69, 26),
            const Offset(78, 26)], thickness: 4);
          stroke([const Offset(31, 31), const Offset(51, 31)], thickness: 7);
          canvas.drawCircle(const Offset(55, 48), 7, darkFill);
          canvas.drawCircle(const Offset(55, 48), 4, fill);
        case 'triciclo':
          // Three distinct wheels, a closed passenger cabin and a motor nose.
          shell(ui.Path()
            ..moveTo(11, 44)
            ..lineTo(14, 25)
            ..quadraticBezierTo(19, 18, 29, 18)
            ..lineTo(53, 18)
            ..quadraticBezierTo(63, 18, 66, 27)
            ..lineTo(70, 43)
            ..lineTo(83, 46)
            ..lineTo(86, 54)
            ..lineTo(10, 54)
            ..close());
          canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(25, 24, 32, 20),
              const Radius.circular(4)), glass);
          stroke([const Offset(41, 25), const Offset(41, 43)],
            thickness: 2.5, tone: ink);
          canvas.drawCircle(const Offset(77, 43), 3, glass);
          wheel(21, 55, 8);
          wheel(44, 55, 8);
          wheel(78, 55, 8);
        case 'bicitaxi':
          // Passenger canopy behind a visibly open bicycle cockpit.
          shell(ui.Path()
            ..moveTo(9, 46)
            ..lineTo(12, 25)
            ..quadraticBezierTo(17, 17, 24, 17)
            ..lineTo(45, 17)
            ..quadraticBezierTo(52, 17, 56, 25)
            ..lineTo(56, 46)
            ..close());
          canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(20, 25, 26, 15),
              const Radius.circular(3)), glass);
          stroke([const Offset(56, 40), const Offset(69, 33),
            const Offset(78, 53), const Offset(58, 53)], thickness: 4);
          stroke([const Offset(67, 31), const Offset(76, 29)], thickness: 3);
          wheel(20, 54, 9);
          wheel(45, 54, 9);
          wheel(79, 54, 10);
        case 'bici':
          wheel(18, 54, 13);
          wheel(79, 54, 13);
          stroke([const Offset(18, 54), const Offset(37, 34),
            const Offset(54, 54), const Offset(18, 54)], thickness: 4);
          stroke([const Offset(37, 34), const Offset(71, 34),
            const Offset(79, 54), const Offset(54, 54)], thickness: 4);
          stroke([const Offset(31, 30), const Offset(44, 30)], thickness: 3);
          stroke([const Offset(70, 34), const Offset(72, 25),
            const Offset(81, 25)], thickness: 3);
        default:
          shell(ui.Path()
            ..moveTo(13, 47)
            ..lineTo(24, 34)
            ..lineTo(71, 34)
            ..lineTo(84, 47)
            ..lineTo(84, 54)
            ..lineTo(13, 54)
            ..close());
          wheel(25, 54, 9);
          wheel(70, 54, 9);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (png == null) throw StateError('FLEET_ICON_RENDER_FAILED');
      if (!mounted || _map != map) return;
      await map.addImage(
        'tuktuk-fleet-$name-v2',
        3.0,
        mbx.StyleImage.bytes(png.buffer.asUint8List(
          png.offsetInBytes,
          png.lengthInBytes,
        )),
      );
    }
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || _layersReady) return;
    try {
      final assets = DefaultAssetBundle.of(context);
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
      await map.addSource(
        mbx.GeoJsonSource(
          id: _sourceDriver,
          data: marketplaceVectorPointGeoJson(
            widget.driverPointStale ? null : widget.driverPoint,
          ),
        ),
      );
      await map.addSource(
        mbx.GeoJsonSource(
          id: _sourceDriverStale,
          data: marketplaceVectorPointGeoJson(
            widget.driverPointStale ? widget.driverPoint : null,
          ),
        ),
      );
      await _registerFleetIcons(map);
      if (!mounted || _map != map) return;
      // Coverage remains subdued. Each vehicle keeps its own icon at the
      // gateway coordinate; multiple vehicles use screen-space fan offsets.
      await map.addSource(mbx.GeoJsonSource(
        id: _sourceCoverage,
        data: marketplaceVectorFleetGeoJson(
          _fleetPoints.where((point) => point.source != 'fleet_live').toList(),
        ),
      ));
      await map.addLayer(mbx.SymbolLayer(
        id: 'tuktuk-client-fleet-vehicle-coverage',
        sourceId: _sourceCoverage,
        iconImageExpression: const ['get', 'icon'],
        iconOffsetExpression: const ['array', 'number', 2, ['get', 'offset']],
        iconSize: 0.92,
        iconOpacity: 0.82,
        iconEmissiveStrength: 1.0,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        slot: 'top',
      ));
      // Only truly available vehicles receive full-opacity markers.
      await map.addSource(mbx.GeoJsonSource(
        id: _sourceFleet,
        data: marketplaceVectorFleetGeoJson(
          _fleetPoints.where((point) => point.source == 'fleet_live').toList(),
        ),
      ));
      await map.addLayer(mbx.SymbolLayer(
        id: 'tuktuk-client-fleet-vehicle-live',
        sourceId: _sourceFleet,
        iconImageExpression: const ['get', 'icon'],
        iconOffsetExpression: const ['array', 'number', 2, ['get', 'offset']],
        iconSize: 1.00,
        iconOpacity: 1.0,
        iconEmissiveStrength: 1.0,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        slot: 'top',
      ));
      // La geometria vial verificada se representa siempre en dorado.
      // Sin slot: sobre el mapa base dark-v11 y estilos privados por igual.
      // Aura tenue + trazo opaco: contraste legible sin tapar las calles.
      await map.addLayer(
        mbx.LineLayer(
          id: 'tuktuk-client-route-glow',
          sourceId: _sourceRoute,
          lineColor: 0xFFFFC400,
          lineOpacity: 0.30,
          lineWidth: 15,
          lineBlur: 1.2,
          lineCap: mbx.LineCap.ROUND,
          lineJoin: mbx.LineJoin.ROUND,
        ),
      );
      await map.addLayer(
        mbx.LineLayer(
          id: 'tuktuk-client-route-line',
          sourceId: _sourceRoute,
          lineColor: 0xFFFFC400,
          lineOpacity: 1.0,
          lineWidth: 8,
          lineCap: mbx.LineCap.ROUND,
          lineJoin: mbx.LineJoin.ROUND,
        ),
      );
      // Iconos premium propios, anclados al punto exacto del mapa.
      // Primero registramos ambos PNG en el estilo Mapbox Web/Android/iOS.
      final pickup = await assets.load('assets/map_markers/pickup_green.png');
      final destination = await assets.load(
        'assets/map_markers/destination_orange.png',
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
        'tuktuk-client-destination-orange-v8',
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
          iconImage: 'tuktuk-client-destination-orange-v8',
          iconAnchor: mbx.IconAnchor.BOTTOM,
          iconSize: 1.0,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          slot: 'top',
        ),
      );
      await map.addLayer(
        mbx.CircleLayer(
          id: 'tuktuk-client-driver-live-position',
          sourceId: _sourceDriver,
          circleColor: 0xFF28C7FF,
          circleRadius: 10,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ),
      );
      // Gris = ultima ubicacion comprobada; no aparentar GPS en vivo.
      await map.addLayer(
        mbx.CircleLayer(
          id: 'tuktuk-client-driver-last-known-position',
          sourceId: _sourceDriverStale,
          circleColor: 0xFF81909A,
          circleRadius: 10,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2,
        ),
      );
      if (!mounted || map != _map) return;
      setState(() {
        _layersReady = true;
        _loadError = null;
      });
      await _refreshGeometry();
      await _refreshDriverPoint();
      await _refreshFleetSource();
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

  Future<void> _refreshDriverPoint() async {
    if (!_layersReady || _map == null) return;
    try {
      // Actualización ligera, sin recrear mapa, estilo ni ruta.
      await _updateSource(
        _sourceDriver,
        marketplaceVectorPointGeoJson(
          widget.driverPointStale ? null : widget.driverPoint,
        ),
      );
      await _updateSource(
        _sourceDriverStale,
        marketplaceVectorPointGeoJson(
          widget.driverPointStale ? widget.driverPoint : null,
        ),
      );
    } catch (_) {
      // Si falla la actualización GPS, preservar el mapa de la carrera.
    }
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
          key: ValueKey<String>(MarketplaceMapService.vectorStyleUri),
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
          onStyleLoadedListener: (_) {
            _updateOrnaments();
            unawaited(_onStyleLoaded());
          },
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
