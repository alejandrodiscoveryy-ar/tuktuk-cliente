part of '../main.dart';

// Solo el error exacto de sesiÃ³n inexistente permite intentar recuperarla.
// Los errores de red, tarifas y operaciones distintas nunca renuevan sesiÃ³n.
@visibleForTesting
bool marketplaceCustomerSessionNotFound(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    return details is Map && details['error'] == 'CUSTOMER_SESSION_NOT_FOUND';
  }
  if (error is StateError) {
    return error.message == 'CUSTOMER_SESSION_NOT_FOUND';
  }
  return false;
}

enum MarketplaceBookingStep { location, origin, destination, quote, confirm }

@visibleForTesting
int marketplacePremiumStepNumber(MarketplaceBookingStep step) => step.index + 2;

@visibleForTesting
String marketplaceServiceLabel(String code) => switch (code) {
  'passenger' => 'Pasajeros',
  'courier' => 'Mensajería',
  'cargo' => 'Carga',
  _ => 'Servicio',
};

@visibleForTesting
const marketplacePassengerVehicleCategories = <String>[
  'motorcycle',
  'bicitaxi',
  'tricycle',
  'light_car',
];

@visibleForTesting
String marketplacePassengerVehicleLabel(String code) => switch (code) {
  'motorcycle' => 'Moto',
  'bicitaxi' => 'Bicitaxi',
  'tricycle' => 'Triciclo',
  'light_car' => 'Auto',
  _ => 'Vehículo',
};

class CustomerBookingFlowController extends ChangeNotifier {
  CustomerBookingFlowController(
    this.mapService,
    this.customerService,
    this.session,
  );

  final MarketplaceMapService mapService;
  final MarketplaceCustomerService customerService;
  MarketplaceCustomerSessionSnapshot session;

  MarketplaceBookingStep step = MarketplaceBookingStep.quote;
  MarketplaceMapPoint? origin;
  MarketplaceMapPoint? destination;
  MarketplaceRouteQuote? route;
  String serviceCode = 'passenger';
  String passengerVehicleCategoryCode = 'motorcycle';
  int passengerCount = 1;
  int stopCount = 0;
  bool urgent = false;
  bool loadHelp = false;
  bool unloadHelp = false;
  double? cargoWeightKg;
  double? cargoVolumeM3;
  DateTime? scheduledFor;
  String note = '';
  bool loading = false;
  String? error;
  String idempotencyKey = _marketplaceUuid();
  String publishIdempotencyKey = _marketplaceUuid();
  int _pricingRevision = 0;

  Map<String, dynamic> get pricing => {
    'passenger_count': passengerCount,
    'stop_count': stopCount,
    'urgent': urgent,
    'load_help': loadHelp,
    'unload_help': unloadHelp,
    'cargo_weight_kg': cargoWeightKg,
    'cargo_volume_m3': cargoVolumeM3,
    'vehicle_category_code': serviceCode == 'passenger'
        ? passengerVehicleCategoryCode
        : null,
  };

  Map<String, dynamic>? get selectedPrice =>
      serviceCode == 'cargo' && cargoWeightKg == null && cargoVolumeM3 == null
      ? null
      : serviceCode == 'passenger'
      ? _passengerCategoryPrice
      : route?.prices[serviceCode] is Map
      ? Map<String, dynamic>.from(route!.prices[serviceCode] as Map)
      : null;

  Map<String, dynamic>? get _passengerCategoryPrice {
    final byCategory = route?.prices['passenger_by_category'];
    if (byCategory is! Map ||
        byCategory[passengerVehicleCategoryCode] is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(
      byCategory[passengerVehicleCategoryCode] as Map,
    );
  }

  void setStep(MarketplaceBookingStep value) {
    step = value;
    notifyListeners();
  }

  void replaceSession(MarketplaceCustomerSessionSnapshot value) {
    session = value;
    notifyListeners();
  }

  void setOrigin(MarketplaceMapPoint value) {
    _pricingRevision++;
    origin = value;
    route = null;
    destination = null;
    step = MarketplaceBookingStep.destination;
    notifyListeners();
  }

  // En la pantalla principal cambiar el origen no debe borrar el destino.
  void setPickupForQuote(MarketplaceMapPoint value) {
    _pricingRevision++;
    origin = value;
    route = null;
    error = null;
    step = MarketplaceBookingStep.quote;
    notifyListeners();
    if (destination != null) {
      unawaited(refreshRoute());
    }
  }

  void setDestination(MarketplaceMapPoint value) {
    _pricingRevision++;
    destination = value;
    route = null;
    step = MarketplaceBookingStep.quote;
    notifyListeners();
    refreshRoute();
  }

  void setService(String value) {
    serviceCode = value;
    notifyListeners();
  }

  void setPassengerVehicleCategory(String value) {
    if (!marketplacePassengerVehicleCategories.contains(value) ||
        passengerVehicleCategoryCode == value) {
      return;
    }
    passengerVehicleCategoryCode = value;
    // La moto solo permite un pasajero; otras capacidades se validan en servidor.
    if (value == 'motorcycle' && passengerCount > 1) {
      passengerCount = 1;
    }
    notifyListeners();
    reprice();
  }

  Future<void> refreshRoute() async {
    final start = origin, end = destination;
    if (start == null || end == null) return;
    final revision = ++_pricingRevision;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await mapService.route(
        origin: start,
        destination: end,
        pricing: pricing,
      );
      if (revision == _pricingRevision) route = result;
    } catch (_) {
      error =
          'No pudimos calcular la ruta. Comprueba tu conexión e inténtalo de nuevo.';
    } finally {
      if (revision == _pricingRevision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> reprice() async {
    final start = origin, end = destination, previous = route;
    if (start == null || end == null || previous == null) return;
    final revision = ++_pricingRevision;
    loading = true;
    notifyListeners();
    try {
      final updated = await mapService.reprice(
        origin: start,
        destination: end,
        routeToken: previous.routeToken,
        pricing: pricing,
      );
      if (revision != _pricingRevision) return;
      route = MarketplaceRouteQuote(
        distanceKm: previous.distanceKm,
        durationSeconds: previous.durationSeconds,
        routePoints: previous.routePoints,
        routeToken: previous.routeToken,
        prices: updated.prices,
      );
      error = null;
    } catch (cause) {
      if (cause.toString().contains('ROUTE_TOKEN_EXPIRED')) {
        loading = false;
        await refreshRoute();
        return;
      }
      error = 'No pudimos actualizar el precio.';
    } finally {
      if (revision == _pricingRevision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<MarketplaceCustomerRequestDraft> submit() async {
    final start = origin, end = destination, current = route;
    if (start == null ||
        end == null ||
        current == null ||
        selectedPrice == null) {
      throw StateError('BOOKING_INCOMPLETE');
    }
    loading = true;
    notifyListeners();
    try {
      return await mapService.create(
        origin: start,
        destination: end,
        routeToken: current.routeToken,
        params: {
          'target_session_id': session.sessionId,
          'target_session_token': session.token,
          'target_service_code': serviceCode,
          'target_origin_text': start.label,
          'target_destination_text': end.label,
          'target_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          'target_passenger_count': serviceCode == 'passenger'
              ? passengerCount
              : null,
          'target_vehicle_category_code': serviceCode == 'passenger'
              ? passengerVehicleCategoryCode
              : null,
          'target_cargo_weight_kg': cargoWeightKg,
          'target_cargo_volume_m3': cargoVolumeM3,
          'target_cargo_length_cm': null,
          'target_cargo_width_cm': null,
          'target_cargo_height_cm': null,
          'target_required_body_type': null,
          'target_notes': note,
          'target_details': {
            'stop_count': stopCount,
            'urgent': urgent,
            'load_help': loadHelp,
            'unload_help': unloadHelp,
          },
          'target_idempotency_key': idempotencyKey,
        },
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

class MarketplaceCustomerBookingFlow extends StatefulWidget {
  const MarketplaceCustomerBookingFlow({
    required this.service,
    required this.session,
    this.controller,
    this.onEditCustomer,
    this.onSessionInvalid,
    super.key,
  });
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final CustomerBookingFlowController? controller;
  final VoidCallback? onEditCustomer;
  final Future<bool> Function()? onSessionInvalid;

  @override
  State<MarketplaceCustomerBookingFlow> createState() =>
      _MarketplaceCustomerBookingFlowState();
}

class _MarketplaceCustomerBookingFlowState
    extends State<MarketplaceCustomerBookingFlow> {
  late final CustomerBookingFlowController flow;
  bool _ownsFlow = false;
  final noteController = TextEditingController();
  final weightController = TextEditingController();
  final volumeController = TextEditingController();
  Timer? pricingDebounce;
  bool _publishing = false;
  bool _tryingAutoPickup = false;
  final ValueNotifier<LatLng?> _mapCenter = ValueNotifier<LatLng?>(null);
  final TextEditingController _placeSearch = TextEditingController();
  Timer? _searchDebounce;
  bool? _selectingOrigin;
  bool _searchingPlaces = false;
  bool _resolvingMapPoint = false;
  String? _placeMessage;
  List<MarketplaceMapPoint> _placeResults = const <MarketplaceMapPoint>[];
  MarketplaceRouteQuote? _lastRoute;

  @override
  void initState() {
    super.initState();
    flow =
        widget.controller ??
        CustomerBookingFlowController(
          MarketplaceMapService(widget.service._client),
          widget.service,
          widget.session,
        );
    _ownsFlow = widget.controller == null;
    noteController.text = flow.note;
    weightController.text = flow.cargoWeightKg?.toString() ?? '';
    volumeController.text = flow.cargoVolumeM3?.toString() ?? '';
    flow.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          flow.step == MarketplaceBookingStep.quote &&
          flow.origin == null) {
        unawaited(_autoLocatePickup());
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    final route = flow.route;
    if (route != null && !identical(route, _lastRoute)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusRoute();
      });
    }
    _lastRoute = route;
    setState(() {});
  }

  @override
  void dispose() {
    flow.removeListener(_changed);
    if (_ownsFlow) flow.dispose();
    noteController.dispose();
    weightController.dispose();
    volumeController.dispose();
    pricingDebounce?.cancel();
    _searchDebounce?.cancel();
    _mapCenter.dispose();
    _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = flow.step;
    final number = marketplacePremiumStepNumber(step);
    final showRelief =
        step == MarketplaceBookingStep.location ||
        step == MarketplaceBookingStep.confirm;
    if (step == MarketplaceBookingStep.quote) {
      return Scaffold(body: _quote());
    }
    return Scaffold(
      body: SafeArea(
        child: TuktukHavanaBackdrop(
          showRelief: showRelief,
          child: Column(
            children: [
              if (step == MarketplaceBookingStep.quote)
                _bookingHeader()
              else
                TuktukFlowHeader(step: number, onBack: _goBack),
              if (step == MarketplaceBookingStep.location)
                TextButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('Historial'),
                ),
              Expanded(
                child: switch (step) {
                  MarketplaceBookingStep.location => _locationIntro(),
                  MarketplaceBookingStep.origin => MarketplaceLocationPicker(
                    service: flow.mapService,
                    title: 'Elige el origen',
                    onConfirm: flow.setOrigin,
                  ),
                  MarketplaceBookingStep.destination =>
                    MarketplaceLocationPicker(
                      service: flow.mapService,
                      title: 'Elige el destino',
                      origin: flow.origin,
                      onConfirm: flow.setDestination,
                    ),
                  MarketplaceBookingStep.quote => _quote(),
                  MarketplaceBookingStep.confirm => _confirmation(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
    child: Row(
      children: [
        const _TuktukBrandLockup(width: 126),
        const Spacer(),
        IconButton(
          tooltip: 'Abrir menú',
          onPressed: _openCustomerMenu,
          style: IconButton.styleFrom(
            backgroundColor: TuktukTheme.background,
            foregroundColor: Colors.white,
            side: const BorderSide(color: TuktukTheme.gold, width: 1.3),
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: const Icon(Icons.menu_rounded, size: 26),
        ),
      ],
    ),
  );

  Future<void> _openCustomerMenu() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.fromLTRB(
          18,
          MediaQuery.paddingOf(dialogContext).top + 75,
          18,
          16,
        ),
        backgroundColor: TuktukTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: TuktukTheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Menú TukTuk',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _customerMenuItem(
                      Icons.person_outline_rounded,
                      'Perfil',
                      () {
                        Navigator.of(dialogContext).pop();
                        widget.onEditCustomer?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _customerMenuItem(
                      Icons.history_rounded,
                      'Historial',
                      () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_openHistory());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customerMenuItem(IconData icon, String title, VoidCallback onTap) =>
      Material(
        color: TuktukTheme.surface.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: TuktukTheme.mint, size: 29),
                const SizedBox(height: 9),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
  Future<void> _selectPoint({required bool origin}) async {
    if (!origin && flow.origin == null) return;
    _searchDebounce?.cancel();
    _placeSearch.clear();
    setState(() {
      _selectingOrigin = origin;
      _placeResults = const <MarketplaceMapPoint>[];
      _placeMessage = null;
    });
  }

  void _cancelPlaceSelection() {
    _searchDebounce?.cancel();
    _placeSearch.clear();
    setState(() {
      _selectingOrigin = null;
      _placeResults = const <MarketplaceMapPoint>[];
      _placeMessage = null;
      _searchingPlaces = false;
    });
  }

  void _searchPlaces(String text) {
    _searchDebounce?.cancel();
    final query = text.trim();
    setState(() {
      _placeResults = const <MarketplaceMapPoint>[];
      _placeMessage = null;
      _searchingPlaces = query.length >= 3;
    });
    if (query.length < 3) return;
    _searchDebounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final found = await flow.mapService.search(query);
        if (!mounted ||
            _selectingOrigin == null ||
            _placeSearch.text.trim() != query) {
          return;
        }
        setState(() {
          _placeResults = found;
          _searchingPlaces = false;
          if (found.isEmpty) {
            _placeMessage = 'Sin resultados. Puedes tocar el mapa.';
          }
        });
      } catch (_) {
        if (mounted && _placeSearch.text.trim() == query) {
          setState(() {
            _searchingPlaces = false;
            _placeMessage = 'No se pudo buscar. Toca el mapa para elegir.';
          });
        }
      }
    });
  }

  void _commitPlace(MarketplaceMapPoint point, bool origin) {
    if (origin) {
      flow.setPickupForQuote(point);
    } else {
      flow.setDestination(point);
    }
    _cancelPlaceSelection();
    // Mismo mapa y misma vista. El cambio solo recoloca su camara.
    _mapCenter.value = point.latLng;
  }

  Future<void> _pickMapPoint(LatLng coordinates) async {
    final selectingOrigin = _selectingOrigin;
    if (selectingOrigin == null || _resolvingMapPoint) return;
    setState(() => _resolvingMapPoint = true);
    var point = MarketplaceMapPoint(
      label: 'Punto marcado en el mapa',
      lat: coordinates.latitude,
      lon: coordinates.longitude,
    );
    try {
      point = await flow.mapService.reverse(point);
    } catch (_) {
      // Si falla el nombre de la calle, las coordenadas siguen siendo validas.
    } finally {
      if (mounted) setState(() => _resolvingMapPoint = false);
    }
    if (!mounted || _selectingOrigin != selectingOrigin) return;
    _commitPlace(point, selectingOrigin);
  }

  double get _mapRequestedZoom {
    final distance = flow.route?.distanceKm;
    if (distance == null) return 14.5;
    if (distance <= 2) return 14.2;
    if (distance <= 6) return 12.6;
    if (distance <= 12) return 11.8;
    if (distance <= 22) return 11;
    return 10;
  }

  void _focusRoute() {
    final a = flow.origin;
    final b = flow.destination;
    if (a == null || b == null || !mounted) {
      return;
    }
    _mapCenter.value = LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);
  } // Se intenta una sola vez al abrir. Si GPS o permisos fallan, la entrada

  // manual sigue disponible. Nunca sustituye una recogida elegida por el usuario.
  Future<void> _autoLocatePickup() async {
    if (_tryingAutoPickup || flow.origin != null) return;
    _tryingAutoPickup = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || flow.origin != null) return;
      var point = MarketplaceMapPoint(
        label: 'Mi ubicación actual',
        lat: position.latitude,
        lon: position.longitude,
      );
      try {
        point = await flow.mapService.reverse(point);
      } catch (_) {
        // Conservamos coordenadas validas si la direccion no se resuelve.
      }
      if (mounted && flow.origin == null) {
        flow.setPickupForQuote(point);
        _mapCenter.value = point.latLng;
      }
    } catch (_) {
      // La ubicacion no debe impedir contratar manualmente.
    } finally {
      _tryingAutoPickup = false;
    }
  }

  Future<void> _openHistory() async {
    final job = await showModalBottomSheet<MarketplaceCustomerJob>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MarketplaceCustomerHistory(
        service: widget.service,
        session: widget.session,
      ),
    );
    if (job == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MarketplaceCustomerTrackingScreen(
          service: widget.service,
          session: widget.session,
          jobId: job.id,
          onDone: () async {},
        ),
      ),
    );
  }

  void _goBack() {
    switch (flow.step) {
      case MarketplaceBookingStep.location:
        widget.onEditCustomer?.call();
        break;
      case MarketplaceBookingStep.origin:
        flow.setStep(MarketplaceBookingStep.location);
        break;
      case MarketplaceBookingStep.destination:
        flow.setStep(MarketplaceBookingStep.origin);
        break;
      case MarketplaceBookingStep.quote:
        widget.onEditCustomer?.call();
        break;
      case MarketplaceBookingStep.confirm:
        flow.setStep(MarketplaceBookingStep.quote);
        break;
    }
  }

  Widget _locationIntro() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 2),
            Semantics(
              button: true,
              label: 'Activar ubicación y continuar',
              child: Tooltip(
                message: 'Activar ubicación',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => flow.setStep(MarketplaceBookingStep.origin),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: _TuktukGeoActivationButton(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Activa tu ubicación',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1.04,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: const Text(
                'Usaremos tu ubicación para encontrar el punto de recogida y calcular tu viaje.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.4,
                  color: TuktukTheme.muted,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _BenefitCard(
              Icons.near_me_rounded,
              'Tu punto de recogida',
              'Ubicamos dónde comienza tu viaje.',
            ),
            const SizedBox(height: 6),
            const _BenefitCard(
              Icons.alt_route_rounded,
              'La mejor ruta',
              'Calculamos el recorrido disponible.',
            ),
            const SizedBox(height: 6),
            const _BenefitCard(
              Icons.payments_outlined,
              'Precio estimado',
              'Usamos la distancia para calcularlo.',
            ),
            const SizedBox(height: 20),
            TuktukPrimaryButton(
              onPressed: () => flow.setStep(MarketplaceBookingStep.origin),
              label: 'Continuar',
            ),
          ],
        ),
      ),
    ),
  );
  Widget _quote() {
    final route = flow.route;
    final origin = flow.origin;
    final destination = flow.destination;
    final center = origin?.latLng ?? const LatLng(23.1136, -82.3666);
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: MarketplaceMapService.publicToken.isEmpty
                ? const ColoredBox(
                    color: TuktukTheme.background,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'Mapa temporalmente no disponible. Puedes buscar una direccion.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                : MarketplaceVectorMap(
                    initialCenter: center,
                    initialZoom: 13.2,
                    requestedCenter: _mapCenter,
                    requestedZoom: _mapRequestedZoom,
                    originPoint: origin,
                    destinationPoint: destination,
                    routePoints:
                        route?.routePoints ?? const <MarketplaceMapPoint>[],
                    onPointTap: _selectingOrigin == null ? null : _pickMapPoint,
                  ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0xD908141B), Color(0x0008141B)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 4,
            child: _floatingOriginDestination(),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * .78,
            child: _floatingBookingPanel(),
          ),
        ],
      ),
    );
  }

  Widget _floatingOriginDestination() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        decoration: BoxDecoration(
          color: TuktukTheme.background.withValues(alpha: .77),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TuktukTheme.border),
        ),
        child: _bookingHeader(),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: TuktukTheme.background.withValues(alpha: .80),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: TuktukTheme.border),
        ),
        child: Column(
          children: [
            _floatingLocationRow(
              icon: Icons.my_location_rounded,
              color: TuktukTheme.mint,
              label: 'Recogida',
              value:
                  flow.origin?.label ??
                  'Detectando ubicación o toca para elegir',
              onTap: () => _selectPoint(origin: true),
              tooltip: 'Cambiar recogida',
            ),
            if (flow.destination != null || _selectingOrigin == false) ...[
              const Divider(color: TuktukTheme.border, height: 1),
              _floatingLocationRow(
                icon: Icons.location_on_rounded,
                color: TuktukTheme.gold,
                label: 'Destino',
                value: flow.destination?.label ?? 'Marcar destino',
                onTap: flow.origin == null
                    ? null
                    : () => _selectPoint(origin: false),
                tooltip: 'Elegir destino',
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _floatingLocationRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback? onTap,
    required String tooltip,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: TuktukTheme.muted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: tooltip,
            child: Icon(
              Icons.edit_location_alt_outlined,
              color: onTap == null ? TuktukTheme.muted : color,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _floatingBookingPanel() => DraggableScrollableSheet(
    key: ValueKey<String>(
      _selectingOrigin != null
          ? 'elegir-punto'
          : flow.origin == null
          ? 'recogida'
          : flow.destination == null
          ? 'destino'
          : 'cotizacion',
    ),
    expand: false,
    initialChildSize: flow.destination == null ? .36 : .58,
    minChildSize: .26,
    maxChildSize: .96,
    snap: true,
    snapSizes: const [.58],
    builder: (context, scroller) => Container(
      decoration: BoxDecoration(
        color: TuktukTheme.background.withValues(alpha: .72),
        border: Border.all(color: TuktukTheme.border),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
        boxShadow: const [BoxShadow(color: Color(0x64000000), blurRadius: 22)],
      ),
      child: ListView(
        controller: scroller,
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: TuktukTheme.border,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectingOrigin != null)
            _floatingPlaceSelection()
          else if (flow.origin == null)
            _floatingNextAction(
              'Tu punto de recogida',
              'Detectamos tu ubicación. Si no aparece, selecciona un punto.',
              'Elegir recogida',
              () => _selectPoint(origin: true),
            )
          else if (flow.destination == null)
            _destinationSearchPrompt()
          else
            _floatingQuoteOptions(),
        ],
      ),
    ),
  );

  Widget _destinationSearchPrompt() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '¿A dónde vamos?',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 12),
      Material(
        color: TuktukTheme.surface.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectPoint(origin: false),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: TuktukTheme.gold),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Buscar dirección o marcar en el mapa',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  Widget _floatingNextAction(
    String title,
    String detail,
    String action,
    VoidCallback callback,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 5),
      Text(detail, style: const TextStyle(color: TuktukTheme.muted)),
      const SizedBox(height: 12),
      TuktukPrimaryButton(onPressed: callback, label: action),
    ],
  );

  Widget _floatingPlaceSelection() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _selectingOrigin! ? 'Elegir recogida' : 'Elegir destino',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            onPressed: _cancelPlaceSelection,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cerrar búsqueda',
          ),
        ],
      ),
      const Text(
        'Busca una dirección o toca directamente el mapa.',
        style: TextStyle(color: TuktukTheme.muted),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _placeSearch,
        autofocus: true,
        onChanged: _searchPlaces,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Dirección o lugar',
          isDense: true,
        ),
      ),
      if (_resolvingMapPoint || _searchingPlaces)
        const Padding(
          padding: EdgeInsets.all(7),
          child: LinearProgressIndicator(),
        ),
      if (_placeMessage != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _placeMessage!,
            style: const TextStyle(color: TuktukTheme.muted),
          ),
        ),
      if (_placeResults.isNotEmpty)
        SizedBox(
          height: 130,
          child: ListView.builder(
            itemCount: _placeResults.length,
            itemBuilder: (context, index) {
              final point = _placeResults[index];
              return ListTile(
                dense: true,
                leading: const Icon(
                  Icons.place_outlined,
                  color: TuktukTheme.mint,
                ),
                title: Text(
                  point.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  final origin = _selectingOrigin;
                  if (origin != null) _commitPlace(point, origin);
                },
              );
            },
          ),
        ),
    ],
  );

  Widget _floatingQuoteOptions() {
    final route = flow.route;
    final price = _priceLabel(flow.selectedPrice, flow.serviceCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pide tu transporte',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            if (route != null)
              Text(
                '${route.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: TuktukTheme.mint,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            for (final code in const ['passenger', 'courier', 'cargo']) ...[
              if (code != 'passenger') const SizedBox(width: 7),
              Expanded(child: _floatingServiceChoice(code)),
            ],
          ],
        ),
        if (flow.serviceCode == 'passenger') ...[
          const SizedBox(height: 9),
          MarketplaceCompactVehicleSelector(
            selectedCategory: flow.passengerVehicleCategoryCode,
            priceLabel: (category) =>
                _priceLabel(_passengerPrice(category), 'passenger'),
            onSelected: flow.setPassengerVehicleCategory,
          ),
        ],
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _openFloatingOptions,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Más opciones'),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 2),
          ),
        ),
        if (flow.loading) const LinearProgressIndicator(),
        if (flow.error != null)
          Text(flow.error!, style: const TextStyle(color: TuktukTheme.danger)),
        if (flow.serviceCode == 'cargo' && flow.selectedPrice == null)
          const Text(
            'Indica peso o volumen en Más opciones para cotizar.',
            style: TextStyle(color: TuktukTheme.muted),
          ),
        const SizedBox(height: 5),
        Text(
          'Estimado: $price',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: TuktukTheme.gold,
          ),
        ),
        const SizedBox(height: 7),
        TuktukPrimaryButton(
          onPressed:
              route != null &&
                  flow.selectedPrice != null &&
                  !flow.loading &&
                  !_publishing
              ? _submit
              : null,
          label: _publishing ? 'Publicando...' : 'Solicitar transporte',
        ),
      ],
    );
  }

  Widget _floatingServiceChoice(String code) {
    final selected = flow.serviceCode == code;
    return InkWell(
      onTap: () => flow.setService(code),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? TuktukTheme.gold.withValues(alpha: .17)
              : TuktukTheme.surface.withValues(alpha: .60),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? TuktukTheme.gold : TuktukTheme.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _serviceIcon(code),
              size: 22,
              color: selected ? TuktukTheme.gold : TuktukTheme.mint,
            ),
            const SizedBox(height: 4),
            Text(
              marketplaceServiceLabel(code),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFloatingOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: TuktukTheme.background,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .63,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(19, 5, 19, 26),
            children: [
              const Text(
                'Opciones del servicio',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              if (flow.serviceCode == 'passenger')
                Row(
                  children: [
                    const Expanded(child: Text('Pasajeros')),
                    IconButton(
                      onPressed: flow.passengerCount > 1
                          ? () {
                              flow.passengerCount--;
                              flow.reprice();
                              refreshSheet(() {});
                            }
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '${flow.passengerCount}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                    ),
                    IconButton(
                      onPressed:
                          flow.passengerCount <
                              (flow.passengerVehicleCategoryCode == 'motorcycle'
                                  ? 1
                                  : 8)
                          ? () {
                              flow.passengerCount++;
                              flow.reprice();
                              refreshSheet(() {});
                            }
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              if (flow.serviceCode == 'cargo') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Peso (kg)'),
                  onChanged: (value) {
                    flow.cargoWeightKg = double.tryParse(value);
                    _scheduleReprice();
                  },
                ),
                TextField(
                  controller: volumeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Volumen (m³)'),
                  onChanged: (value) {
                    flow.cargoVolumeM3 = double.tryParse(value);
                    _scheduleReprice();
                  },
                ),
                SwitchListTile(
                  title: const Text('Ayuda para cargar'),
                  value: flow.loadHelp,
                  onChanged: (value) {
                    flow.loadHelp = value;
                    flow.reprice();
                    refreshSheet(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Ayuda para descargar'),
                  value: flow.unloadHelp,
                  onChanged: (value) {
                    flow.unloadHelp = value;
                    flow.reprice();
                    refreshSheet(() {});
                  },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.alt_route_rounded),
                title: const Text('Paradas adicionales'),
                subtitle: Text('${flow.stopCount}'),
                onTap: () async {
                  await _showStopsSheet();
                  if (sheetContext.mounted) refreshSheet(() {});
                },
              ),
              SwitchListTile(
                title: const Text('Servicio urgente'),
                value: flow.urgent,
                onChanged: (value) {
                  flow.urgent = value;
                  flow.reprice();
                  refreshSheet(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Programar servicio'),
                subtitle: Text(
                  flow.scheduledFor == null
                      ? 'Ahora'
                      : DateFormat('dd/MM HH:mm').format(flow.scheduledFor!),
                ),
                onTap: () async {
                  await _pickSchedule();
                  if (sheetContext.mounted) refreshSheet(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Nota para el conductor'),
                subtitle: Text(
                  flow.note.isEmpty ? 'Sin nota' : flow.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  await _showNoteSheet();
                  if (sheetContext.mounted) refreshSheet(() {});
                },
              ),
              const SizedBox(height: 16),
              TuktukPrimaryButton(
                label: 'Listo',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _serviceIcon(String code) => switch (code) {
    'passenger' => Icons.directions_car_filled_outlined,
    'courier' => Icons.inventory_2_outlined,
    'cargo' => Icons.local_shipping_outlined,
    _ => Icons.local_taxi_outlined,
  };

  String _formatPriceAmount(Object? value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');

    if (number == null) {
      return value?.toString() ?? '-';
    }

    final digits = number.round().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }

    return buffer.toString();
  }

  String _priceLabel(Object? value, String code) {
    if (value is Map &&
        code == 'cargo' &&
        flow.cargoWeightKg == null &&
        flow.cargoVolumeM3 == null) {
      return 'Desde ${_formatPriceAmount(value['minimum_price'])} '
          '${value['currency'] ?? 'CUP'}';
    }

    if (value is Map) {
      return '${_formatPriceAmount(value['recommended_price'])} '
          '${value['currency'] ?? 'CUP'}';
    }

    return code == 'cargo' ? 'Indica peso o volumen' : 'Calculando…';
  }

  Object? _passengerPrice(String category) {
    final prices = flow.route?.prices['passenger_by_category'];
    return prices is Map ? prices[category] : null;
  }

  Future<void> _showStopsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: TuktukTheme.background,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paradas adicionales',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: flow.stopCount > 0
                          ? () {
                              flow.stopCount--;
                              setSheetState(() {});
                              flow.reprice();
                            }
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Text(
                        '${flow.stopCount}',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: flow.stopCount < 20
                          ? () {
                              flow.stopCount++;
                              setSheetState(() {});
                              flow.reprice();
                            }
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TuktukPrimaryButton(
                  label: 'Listo',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickSchedule() async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDate: flow.scheduledFor ?? DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: flow.scheduledFor == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(flow.scheduledFor!),
    );
    if (time == null || !mounted) return;
    setState(() {
      flow.scheduledFor = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _showNoteSheet() async {
    noteController.text = flow.note;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TuktukTheme.background,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nota para el conductor',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              maxLength: 1000,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Escribe una indicación opcional',
              ),
              onChanged: (value) => flow.note = value,
            ),
            const SizedBox(height: 8),
            TuktukPrimaryButton(
              label: 'Guardar nota',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _confirmation() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          children: [
            const Text(
              'Confirma tu solicitud',
              style: TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Revisa lo esencial antes de solicitar tu transporte.',
              style: TextStyle(
                color: TuktukTheme.muted,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            TuktukGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Column(
                children: [
                  TuktukSummaryRow(
                    icon: _serviceIcon(flow.serviceCode),
                    label: 'Servicio',
                    value: marketplaceServiceLabel(flow.serviceCode),
                  ),
                  const Divider(color: TuktukTheme.border, height: 1),
                  TuktukSummaryRow(
                    icon: Icons.location_on_outlined,
                    label: 'Origen',
                    value: flow.origin?.label ?? '',
                  ),
                  const Divider(color: TuktukTheme.border, height: 1),
                  TuktukSummaryRow(
                    icon: Icons.flag_outlined,
                    label: 'Destino',
                    value: flow.destination?.label ?? '',
                    iconColor: TuktukTheme.gold,
                  ),
                  const Divider(color: TuktukTheme.border, height: 1),
                  TuktukSummaryRow(
                    icon: Icons.payments_outlined,
                    label: 'Precio estimado',
                    value: _priceLabel(flow.selectedPrice, flow.serviceCode),
                    iconColor: TuktukTheme.gold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, inner) {
                final itemWidth = (inner.maxWidth - 14) / 2;

                return Wrap(
                  spacing: 14,
                  runSpacing: 13,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.alt_route_rounded,
                        '${flow.route?.distanceKm.toStringAsFixed(1) ?? '-'} km',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.schedule_outlined,
                        '${((flow.route?.durationSeconds ?? 0) / 60).round()} min',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.groups_2_outlined,
                        flow.serviceCode == 'passenger'
                            ? '${flow.passengerCount} pasajero${flow.passengerCount == 1 ? '' : 's'}'
                            : marketplaceServiceLabel(flow.serviceCode),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.location_on_outlined,
                        '${flow.stopCount} parada${flow.stopCount == 1 ? '' : 's'}',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.bolt_rounded,
                        flow.urgent ? 'Servicio urgente' : 'Sin urgencia',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MiniFact(
                        Icons.calendar_month_outlined,
                        flow.scheduledFor == null
                            ? 'Ahora'
                            : DateFormat(
                                'dd/MM HH:mm',
                              ).format(flow.scheduledFor!),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLength: 1000,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Nota para el conductor (opcional)',
                prefixIcon: Icon(Icons.edit_outlined),
                counterText: '',
                isDense: true,
              ),
              onChanged: (value) => flow.note = value,
            ),
            if (flow.error != null) ...[
              const SizedBox(height: 10),
              Text(
                flow.error!,
                style: const TextStyle(color: TuktukTheme.danger),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _publishing
                      ? null
                      : () => flow.setStep(MarketplaceBookingStep.quote),
                  style: TextButton.styleFrom(
                    foregroundColor: TuktukTheme.mint,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  label: const Text(
                    'Editar solicitud',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _publishing ? null : widget.onEditCustomer,
                  style: TextButton.styleFrom(
                    foregroundColor: TuktukTheme.muted,
                  ),
                  icon: const Icon(Icons.person_outline_rounded, size: 19),
                  label: const Text(
                    'Editar tus datos',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: TuktukPrimaryButton(
          onPressed: flow.loading || _publishing ? null : _submit,
          label: _publishing ? 'Publicando...' : 'Solicitar transporte',
        ),
      ),
    ],
  );
  void _scheduleReprice() {
    pricingDebounce?.cancel();
    if (flow.route == null) return;
    setState(() => flow.loading = true);
    pricingDebounce = Timer(const Duration(milliseconds: 700), flow.reprice);
  }

  Future<void> _submit() async {
    if (_publishing || flow.loading) return;
    setState(() => _publishing = true);
    var requestCreated = false;
    try {
      final draft = await flow.submit();
      requestCreated = true;
      final publication = await widget.service.publishJob(
        sessionId: flow.session.sessionId,
        sessionToken: flow.session.token,
        jobId: draft.jobId,
        finalPrice: draft.recommendedPrice,
        priceWarningAcknowledged: true,
        idempotencyKey: flow.publishIdempotencyKey,
      );
      if (!mounted) return;
      final sessionStore = MarketplaceCustomerSessionStore(Hive.box(_metaBox));
      await sessionStore.saveActiveJobId(publication.jobId);
      try {
        // Caché local, no consulta la ubicación de ningún conductor.
        final quote = flow.route;
        if (flow.origin != null && flow.destination != null && quote != null) {
          await sessionStore.saveActiveJobMap(
            jobId: publication.jobId,
            origin: flow.origin!,
            destination: flow.destination!,
            routePoints: quote.routePoints,
            distanceKm: quote.distanceKm,
          );
        }
      } catch (_) {
        // La carrera publicada NO puede fallar por una caché visual opcional.
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MarketplaceCustomerTrackingScreen(
            service: widget.service,
            session: flow.session,
            jobId: publication.jobId,
            onDone: sessionStore.clearActiveJobId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (!requestCreated &&
          marketplaceCustomerSessionNotFound(error) &&
          widget.onSessionInvalid != null) {
        bool renewed = false;
        try {
          renewed = await widget.onSessionInvalid!();
        } catch (_) {
          renewed = false;
        }
        if (!mounted) return;
        setState(() {
          _publishing = false;
          flow.error = renewed
              ? 'La sesión fue renovada. Revisa la ruta y pulsa Solicitar transporte otra vez.'
              : 'Tu sesión no pudo renovarse. Comprueba tu conexión y vuelve a intentarlo.';
        });
        return;
      }
      setState(() {
        _publishing = false;
        flow.error = 'No pudimos crear la solicitud. Inténtalo de nuevo.';
      });
    }
  }
}

// Selector de cuatro vehiculos visible sin scroll horizontal.
// Unicamente recibe precios calculados por el gateway existente.
class MarketplaceCompactVehicleSelector extends StatelessWidget {
  const MarketplaceCompactVehicleSelector({
    required this.selectedCategory,
    required this.priceLabel,
    required this.onSelected,
    super.key,
  });

  final String selectedCategory;
  final String Function(String category) priceLabel;
  final ValueChanged<String> onSelected;

  IconData _icon(String category) => switch (category) {
    'motorcycle' => Icons.two_wheeler_rounded,
    'bicitaxi' => Icons.pedal_bike_rounded,
    'tricycle' => Icons.electric_rickshaw_rounded,
    'light_car' => Icons.directions_car_filled_outlined,
    _ => Icons.local_taxi_outlined,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // En telefonos normales los cuatro se ven a la vez; en anchos
      // realmente estrechos se organizan en una cuadricula 2 x 2.
      final columns = constraints.maxWidth < 335 ? 2 : 4;
      const gap = 6.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

      return Wrap(
        key: const Key('compact-vehicle-layout'),
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final category in marketplacePassengerVehicleCategories)
            SizedBox(width: width, child: _tile(category)),
        ],
      );
    },
  );

  Widget _tile(String category) {
    final selected = selectedCategory == category;
    final price = priceLabel(category);
    final title = marketplacePassengerVehicleLabel(category);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. Precio $price',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('vehicle-$category'),
          onTap: () => onSelected(category),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? TuktukTheme.gold.withValues(alpha: .17)
                  : TuktukTheme.surface.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? TuktukTheme.gold : TuktukTheme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(
                  _icon(category),
                  size: 20,
                  color: selected ? TuktukTheme.gold : TuktukTheme.mint,
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                SizedBox(
                  height: 15,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      price,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: selected ? TuktukTheme.gold : TuktukTheme.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard(this.icon, this.title, this.detail);

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: TuktukTheme.mint.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: TuktukTheme.mint, size: 22),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  color: TuktukTheme.muted,
                  fontSize: 13.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniFact extends StatelessWidget {
  const _MiniFact(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: TuktukTheme.mint, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

class _TuktukGeoActivationButton extends StatefulWidget {
  const _TuktukGeoActivationButton();

  @override
  State<_TuktukGeoActivationButton> createState() =>
      _TuktukGeoActivationButtonState();
}

class _TuktukGeoActivationButtonState extends State<_TuktukGeoActivationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();

    _breath = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: .96,
          end: 1.035,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.035,
          end: .96,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = reduceMotion ? 0.0 : _controller.value;
          final ringScale = 1.0 + (progress * .42);
          final ringOpacity = reduceMotion ? .24 : (1 - progress) * .48;

          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TuktukTheme.gold.withValues(alpha: .06),
                ),
              ),
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: TuktukTheme.gold.withValues(alpha: ringOpacity),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: reduceMotion ? 1 : _breath.value,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TuktukTheme.goldSurface,
                    border: Border.all(color: TuktukTheme.gold, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: TuktukTheme.gold.withValues(alpha: .32),
                        blurRadius: 22,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 52,
                    color: TuktukTheme.background,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
