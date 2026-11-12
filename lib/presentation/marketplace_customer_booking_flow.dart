part of '../main.dart';

@visibleForTesting
String? marketplaceCustomerPublicSupportNumber(Object? data, String projectId) {
  if (data is! Map || data['project_id'] != projectId) return null;
  final support = data['support'];
  if (support is! Map || support['enabled'] != true) return null;
  final value = support['number'];
  if (value is! String ||
      !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
    return null;
  }
  return value;
}

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

@visibleForTesting
String? marketplaceCustomerPublicLiteNumber(Object? data, String projectId) {
  if (data is! Map || data['project_id'] != projectId) return null;
  final support = data['support'];
  if (support is! Map) return null;
  final enabled = support['lite_enabled'] is bool
      ? support['lite_enabled'] == true
      : support['enabled'] == true;
  if (!enabled || support['lite_open'] == false) return null;
  final phone = support['number'];
  if (phone is! String ||
      !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
    return null;
  }
  return phone;
}

// Numero publico del canal Lite, verificado por Admin; no es una tarifa ni reserva.
// Caduca tras 24 horas si no se consigue consultar la configuracion otra vez.
@visibleForTesting
String? marketplaceCustomerCachedAndroidLiteNumber({
  required Object? number,
  required Object? verifiedAt,
  required DateTime now,
}) {
  if (number is! String ||
      !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(number) ||
      verifiedAt is! String) {
    return null;
  }
  final instant = DateTime.tryParse(verifiedAt)?.toUtc();
  if (instant == null) return null;
  final age = now.toUtc().difference(instant);
  if (age.isNegative || age >= const Duration(hours: 24)) return null;
  return number;
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
      'bicycle' => 'Bicicleta',
      'bicitaxi' => 'Bicitaxi',
      'tricycle' => 'Triciclo',
      'light_car' => 'Auto',
      'van' => 'Furgoneta',
      'truck' => 'Camión',
      'other' => 'Otro',
      _ => 'Vehículo',
    };

@visibleForTesting
const marketplaceCargoCourierVehicleCategories = <String>[
  'light_car',
  'bicitaxi',
  'tricycle',
  'motorcycle',
  'van',
  'truck',
  'other',
];

@visibleForTesting
const marketplaceCourierVehicleCategories = <String>[
  'bicycle',
  ...marketplaceCargoCourierVehicleCategories,
];

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
  String _ridePaymentMethod = 'cash';
  bool _ridePaymentMethodLocked = false;
  String get ridePaymentMethod => _ridePaymentMethod;
  bool get ridePaymentMethodLocked => _ridePaymentMethodLocked;
  bool loading = false;
  String? error;
  String idempotencyKey = _marketplaceUuid();
  String publishIdempotencyKey = _marketplaceUuid();
  int _pricingRevision = 0;
  List<String> publishedPassengerCategories =
      marketplacePassengerVehicleCategories;
  Map<String, List<String>> publishedCategoriesByService = const {};
  List<String> publishedServices = const ['passenger', 'courier', 'cargo'];
  bool publicationReady = false;
  bool _loadingPublishedModalities = false;
  String cargoVehicleCategoryCode = 'light_car';
  String courierVehicleCategoryCode = 'motorcycle';

  String get selectedVehicleCategoryCode => switch (serviceCode) {
        'passenger' => passengerVehicleCategoryCode,
        'cargo' => cargoVehicleCategoryCode,
        'courier' => courierVehicleCategoryCode,
        _ => '',
      };
  List<String> categoriesForService(String service) =>
      publishedCategoriesByService[service] ?? const [];

  final Map<String, Object> _categoryQuoteCache = <String, Object>{};
  String? _categoryQuoteSignature;
  int _categoryQuoteRequestId = 0;

  String get _priceComparisonKey => jsonEncode(<String, Object?>{
    'route_token': route?.routeToken,
    'service': serviceCode,
    'distance_km': route?.distanceKm,
    'stop_count': stopCount,
    'urgent': urgent,
    'load_help': loadHelp,
    'unload_help': unloadHelp,
    'cargo_weight_kg': cargoWeightKg,
    'cargo_volume_m3': cargoVolumeM3,
    'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
  });

  Object? vehiclePriceForCard(String category) {
    if (route == null || !publicationReady ||
        !categoriesForService(serviceCode).contains(category)) {
      return null;
    }
    if (serviceCode == 'passenger') {
      final passenger = route!.prices['passenger_by_category'];
      return passenger is Map ? passenger[category] : null;
    }
    if (serviceCode == 'cargo' && cargoWeightKg == null && cargoVolumeM3 == null) {
      return null;
    }
    if (category == selectedVehicleCategoryCode) return selectedPrice;
    if (_categoryQuoteSignature != _priceComparisonKey) return null;
    return _categoryQuoteCache[category];
  }

  // Solo el gateway autorizado calcula importes: no hay precios inventados.
  // Una peticion cada vez para evitar rafagas; los resultados caducos se descartan.
  Future<void> loadCategoryComparisons() async {
    final start = origin;
    final end = destination;
    final snapshot = route;
    final currentService = serviceCode;
    final generation = ++_categoryQuoteRequestId;
    if (start == null || end == null || snapshot == null ||
        !publicationReady || currentService == 'passenger' ||
        (currentService == 'cargo' && cargoWeightKg == null && cargoVolumeM3 == null)) {
      _categoryQuoteCache.clear();
      _categoryQuoteSignature = null;
      return;
    }
    final signature = _priceComparisonKey;
    if (_categoryQuoteSignature != signature) {
      _categoryQuoteSignature = signature;
      _categoryQuoteCache.clear();
    }
    final parameters = Map<String, dynamic>.from(pricing);
    for (final category in categoriesForService(currentService)) {
      if (generation != _categoryQuoteRequestId || _priceComparisonKey != signature) {
        return;
      }
      if (category == selectedVehicleCategoryCode ||
          _categoryQuoteCache.containsKey(category)) {
        continue;
      }
      try {
        final quote = await mapService.reprice(
          origin: start,
          destination: end,
          routeToken: snapshot.routeToken,
          pricing: <String, dynamic>{...parameters, 'vehicle_category_code': category},
        );
        if (generation != _categoryQuoteRequestId || _priceComparisonKey != signature) {
        return;
      }
        final result = quote.prices[currentService];
        if (result is Map) {
          _categoryQuoteCache[category] = Map<String, dynamic>.from(result);
          notifyListeners();
        }
      } catch (_) {
        // Sin tarifa del servidor no mostramos un importe supuesto.
      }
    }
  }

  Future<void> loadPublishedModalities() async {
    // Consulta solo de lectura; una sola llamada activa evita rafagas.
    if (_loadingPublishedModalities) return;
    _loadingPublishedModalities = true;
    publicationReady = false;
    notifyListeners();
    try {
      final response = await Supabase.instance.client.rpc(
        'list_marketplace_published_modalities',
        params: {'target_project_slug': 'tuktuk-control'},
      ).timeout(const Duration(seconds: 18));
      if (response is! List) throw StateError('MODALITY_CATALOG_INVALID');
      final pairs = response.whereType<Map>().toList();
      final categoriesByService = <String, List<String>>{
        for (final service in const ['passenger', 'courier', 'cargo'])
          service: (service == 'passenger'
                  ? marketplacePassengerVehicleCategories
                  : service == 'courier'
                      ? marketplaceCourierVehicleCategories
                      : marketplaceCargoCourierVehicleCategories)
              .where(
                (category) => pairs.any(
                  (r) =>
                      r['service_code'] == service &&
                      r['vehicle_category_code'] == category,
                ),
              )
              .toList(growable: false),
      };
      final services = const ['passenger', 'courier', 'cargo']
          .where((service) => categoriesByService[service]!.isNotEmpty)
          .toList(growable: false);
      final prevService = serviceCode,
          prevCategory = selectedVehicleCategoryCode;
      publishedCategoriesByService = categoriesByService;
      publishedPassengerCategories = categoriesByService['passenger']!;
      publishedServices = services;
      if (!services.contains(serviceCode) && services.isNotEmpty) {
        serviceCode = services.first;
      }
      if (!publishedPassengerCategories.contains(
            passengerVehicleCategoryCode,
          ) &&
          publishedPassengerCategories.isNotEmpty) {
        passengerVehicleCategoryCode = publishedPassengerCategories.first;
      }
      final cargo = categoriesByService['cargo']!;
      if (!cargo.contains(cargoVehicleCategoryCode) && cargo.isNotEmpty) {
        cargoVehicleCategoryCode = cargo.first;
      }
      final courier = categoriesByService['courier']!;
      if (!courier.contains(courierVehicleCategoryCode) && courier.isNotEmpty) {
        courierVehicleCategoryCode = courier.first;
      }
      publicationReady = true;
      error = services.isEmpty
          ? 'No hay modalidades publicadas en este momento.'
          : null;
      notifyListeners();
      if (origin != null &&
          destination != null &&
          (prevService != serviceCode ||
              prevCategory != selectedVehicleCategoryCode)) {
        await refreshRoute();
      }
    } catch (_) {
      publicationReady = false;
      publishedCategoriesByService = const {};
      publishedPassengerCategories = const [];
      publishedServices = const [];
      error = 'No podemos comprobar las modalidades disponibles. Reintenta.';
      notifyListeners();
    } finally {
      _loadingPublishedModalities = false;
    }
  }

  Map<String, dynamic> get pricing => {
        'service_code': serviceCode,
        'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
        'passenger_count': passengerCount,
        'stop_count': stopCount,
        'urgent': urgent,
        'load_help': loadHelp,
        'unload_help': unloadHelp,
        'cargo_weight_kg': cargoWeightKg,
        'cargo_volume_m3': cargoVolumeM3,
        'vehicle_category_code': selectedVehicleCategoryCode,
      };

  Map<String, dynamic>? get selectedPrice => !publicationReady ||
          !publishedServices.contains(serviceCode) ||
          !categoriesForService(
            serviceCode,
          ).contains(selectedVehicleCategoryCode)
      ? null
      : serviceCode == 'cargo' && cargoWeightKg == null && cargoVolumeM3 == null
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

  // No recalcular tarifas por la forma de pago. Un intento de publicación
  // conserva su elección para no cambiar el contenido de una solicitud
  // idempotente cuando la respuesta de red se pierde.
  void setRidePaymentMethod(String value) {
    if (loading || _ridePaymentMethodLocked || value == _ridePaymentMethod ||
        !const ['cash', 'transfer'].contains(value)) return;
    _ridePaymentMethod = value;
    idempotencyKey = _marketplaceUuid();
    publishIdempotencyKey = _marketplaceUuid();
    notifyListeners();
  }

  void resetToStart() {
    // Abandonar un borrador no crea ni cancela ninguna carrera real.
    _pricingRevision++;
    _categoryQuoteRequestId++;
    _categoryQuoteCache.clear();
    _categoryQuoteSignature = null;
    origin = null;
    destination = null;
    route = null;
    scheduledFor = null;
    passengerCount = 1;
    stopCount = 0;
    urgent = false;
    loadHelp = false;
    unloadHelp = false;
    cargoWeightKg = null;
    cargoVolumeM3 = null;
    note = '';
    _ridePaymentMethod = 'cash';
    _ridePaymentMethodLocked = false;
    error = null;
    idempotencyKey = _marketplaceUuid();
    publishIdempotencyKey = _marketplaceUuid();
    step = MarketplaceBookingStep.quote;
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
    if (!publicationReady ||
        !publishedServices.contains(value) ||
        value == serviceCode) {
      return;
    }
    serviceCode = value;
    notifyListeners();
    unawaited(reprice());
  }

  void setServiceVehicleCategory(String value) {
    if (!publicationReady ||
        !categoriesForService(serviceCode).contains(value) ||
        value == selectedVehicleCategoryCode) {
      return;
    }
    if (serviceCode == 'passenger') {
      setPassengerVehicleCategory(value);
      return;
    }
    if (serviceCode == 'cargo') {
      cargoVehicleCategoryCode = value;
    }
    if (serviceCode == 'courier') {
      courierVehicleCategoryCode = value;
    }
    notifyListeners();
    unawaited(reprice());
  }

  void setPassengerVehicleCategory(String value) {
    if (!publicationReady ||
        !publishedPassengerCategories.contains(value) ||
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
      final pendingRoute = mapService.route(
        origin: start,
        destination: end,
        pricing: pricing,
      );
      final result = kIsWeb
          ? await pendingRoute
          : await pendingRoute.timeout(const Duration(seconds: 22));
      if (revision == _pricingRevision) {
        route = result;
        unawaited(loadCategoryComparisons());
      }
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
      final pendingPrice = mapService.reprice(
        origin: start,
        destination: end,
        routeToken: previous.routeToken,
        pricing: pricing,
      );
      final updated = kIsWeb
          ? await pendingPrice
          : await pendingPrice.timeout(const Duration(seconds: 22));
      if (revision != _pricingRevision) return;
      route = MarketplaceRouteQuote(
        distanceKm: previous.distanceKm,
        durationSeconds: previous.durationSeconds,
        routePoints: previous.routePoints,
        routeToken: previous.routeToken,
        prices: updated.prices,
      );
      error = null;
      unawaited(loadCategoryComparisons());
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
    if (!publicationReady ||
        !publishedServices.contains(serviceCode) ||
        !categoriesForService(
          serviceCode,
        ).contains(selectedVehicleCategoryCode)) {
      throw StateError('MODALITY_NOT_PUBLISHED');
    }
    if (start == null ||
        end == null ||
        current == null ||
        selectedPrice == null) {
      throw StateError('BOOKING_INCOMPLETE');
    }
    _ridePaymentMethodLocked = true;
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
          'target_passenger_count':
              serviceCode == 'passenger' ? passengerCount : null,
          'target_vehicle_category_code': selectedVehicleCategoryCode,
          'target_cargo_weight_kg': cargoWeightKg,
          'target_cargo_volume_m3': cargoVolumeM3,
          'target_cargo_length_cm': null,
          'target_cargo_width_cm': null,
          'target_cargo_height_cm': null,
          'target_required_body_type': null,
          'target_notes': note,
          'target_details': {
            'ride_payment_method': _ridePaymentMethod,
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

/// Dos formas de pago excluyentes, visibles sin abrir otro menú.
class MarketplaceRidePaymentSelector extends StatelessWidget {
  const MarketplaceRidePaymentSelector({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  Widget _option(String code, String label, IconData icon) {
    final selected = value == code;
    final foreground = selected ? TuktukTheme.background : TuktukTheme.text;
    final background = selected ? TuktukTheme.mint : TuktukTheme.surfaceStrong;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          key: ValueKey('booking-ride-payment-$code'),
          onPressed: enabled ? () => onChanged(code) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: background,
            disabledForegroundColor: foreground.withValues(alpha: .75),
            disabledBackgroundColor: background.withValues(alpha: .65),
            side: BorderSide(
              color: selected ? TuktukTheme.mint : TuktukTheme.border,
              width: selected ? 1.6 : 1,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? Icons.check_circle_rounded : icon, size: 18),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
        key: const ValueKey('booking-ride-payment-method'),
        children: [
          _option('cash', 'Efectivo', Icons.payments_outlined),
          const SizedBox(width: 8),
          _option('transfer', 'Transferencia', Icons.account_balance_outlined),
        ],
      );
}

/// Reserva espacio al pie fijo incluso al arrastrar la ficha hacia abajo.
/// La ficha de elección de puntos mantiene su altura compacta original.
@visibleForTesting
double marketplaceBookingPanelMinFraction(double viewportHeight,
    {required bool hasQuoteFooter}) {
  if (!hasQuoteFooter) return .26;
  return (248 / (max(viewportHeight, 1.0) * .78)).clamp(.26, .90).toDouble();
}

/// Reserve room for the payment footer and two vehicle rows on mobile.
/// Very short viewports retain the draggable, scrolling sheet.
@visibleForTesting
double marketplaceQuoteInitialFraction(double viewportHeight,
    {required double preferred, required double minimum}) {
  final contentFraction = (460 / (max(viewportHeight, 1.0) * .78))
      .clamp(.26, .94).toDouble();
  return max(max(preferred, minimum), contentFraction);
}

class MarketplaceCustomerBookingFlow extends StatefulWidget {
  const MarketplaceCustomerBookingFlow({
    required this.service,
    required this.session,
    this.controller,
    this.onEditCustomer,
    this.profileEditorOpen = false,
    this.onSessionInvalid,
    super.key,
  });
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final CustomerBookingFlowController? controller;
  final VoidCallback? onEditCustomer;
  final bool profileEditorOpen;
  final Future<bool> Function()? onSessionInvalid;

  @override
  State<MarketplaceCustomerBookingFlow> createState() =>
      _MarketplaceCustomerBookingFlowState();
}

class _MarketplaceCustomerBookingFlowState
    extends State<MarketplaceCustomerBookingFlow> with WidgetsBindingObserver {
  late final CustomerBookingFlowController flow;
  bool _ownsFlow = false;
  final noteController = TextEditingController();
  final weightController = TextEditingController();
  final volumeController = TextEditingController();
  Timer? pricingDebounce;
  bool _publishing = false;
  bool _tryingAutoPickup = false;
  bool _locatingPickup = false;
  int _pickupLocationRevision = 0;
  bool _bookingResetRequested = false;
  final ValueNotifier<LatLng?> _mapCenter = ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> _mapPanelInset = ValueNotifier<double>(0);
  String? _mapPanelLayoutKey;
  double _bookingPanelHeight = 0;
  bool _historyOpen = false;
  final TextEditingController _placeSearch = TextEditingController();
  Timer? _searchDebounce;
  bool? _selectingOrigin;
  bool _searchingPlaces = false;
  bool _resolvingMapPoint = false;
  String? _placeMessage;
  List<MarketplaceMapPoint> _placeResults = const <MarketplaceMapPoint>[];
  MarketplaceRouteQuote? _lastRoute;
  static const _liteProjectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
  static const _litePhoneKey = 'tuktuk_android_lite_phone_v1';
  static const _liteVerifiedKey = 'tuktuk_android_lite_verified_at_v1';
  Timer? _liteRefreshTimer;
  Future<void>? _liteRefreshInFlight;
  DateTime? _liteLastAttempt;
  bool _liteInForeground = true;

  @override
  void initState() {
    super.initState();
    flow = widget.controller ??
        CustomerBookingFlowController(
          MarketplaceMapService(widget.service._client),
          widget.service,
          widget.session,
        );
    _ownsFlow = widget.controller == null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_refreshAndroidLiteNumber(force: true));
      // Si la conexion vuelve mientras la app esta abierta, se reintenta
      // como maximo en los siguientes 15 minutos; nunca se mantiene un polling
      // activo en segundo plano.
      _liteRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
        if (mounted && _liteInForeground) {
          unawaited(_refreshAndroidLiteNumber());
        }
      });
    }
    unawaited(flow.loadPublishedModalities());
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

  @override
  void didUpdateWidget(covariant MarketplaceCustomerBookingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileEditorOpen != widget.profileEditorOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshMapOrnaments();
      });
    }
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _liteRefreshTimer?.cancel();
    flow.removeListener(_changed);
    if (_ownsFlow) flow.dispose();
    noteController.dispose();
    weightController.dispose();
    volumeController.dispose();
    pricingDebounce?.cancel();
    _searchDebounce?.cancel();
    _mapCenter.dispose();
    _mapPanelInset.dispose();
    _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = flow.step;
    final number = marketplacePremiumStepNumber(step);
    final showRelief = step == MarketplaceBookingStep.location ||
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
            if (flow.origin != null || flow.destination != null || _selectingOrigin != null)
              IconButton(
                tooltip: 'Volver al inicio',
                onPressed: _publishing ? null : _returnToStart,
                icon: const Icon(Icons.home_outlined, size: 25),
              ),
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

  void _returnToStart() {
    if (_publishing) return;
    _pickupLocationRevision++;
    _bookingResetRequested = true;
    pricingDebounce?.cancel();
    _searchDebounce?.cancel();
    _placeSearch.clear();
    noteController.clear();
    weightController.clear();
    volumeController.clear();
    _selectingOrigin = null;
    _placeResults = const <MarketplaceMapPoint>[];
    _placeMessage = null;
    _searchingPlaces = false;
    _mapPanelLayoutKey = null;
    flow.resetToStart();
    _mapCenter.value = const LatLng(23.1136, -82.3666);
  }

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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Menú TukTuk',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _customerMenuItem(
                    Icons.person_outline_rounded, 'Perfil', () {
                      Navigator.of(dialogContext).pop();
                      widget.onEditCustomer?.call();
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _customerMenuItem(
                    Icons.history_rounded, 'Historial', () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_openHistory());
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _customerMenuItem(
                    Icons.wallet_outlined, 'Billetera', null, comingSoon: true,
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _customerMenuItem(
                    Icons.card_giftcard_rounded, 'Referidos', null,
                    comingSoon: true,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _customerMenuItem(
                    Icons.settings_outlined, 'Ajustes', () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_showCustomerMenuDetail(
                        'Ajustes',
                        'Para gestionar permisos de ubicación y notificaciones, utiliza los ajustes del navegador o del teléfono.',
                      ));
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _customerMenuItem(
                    Icons.support_agent_rounded, 'Ayuda', () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_openCustomerSupportWhatsApp());
                    },
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomerSupportWhatsApp() async {
    // Mismo numero publico que TukTuk Lite, siempre gestionado desde Admin.
    const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
    try {
      final data = await widget.service._client.rpc(
        'get_public_whatsapp_settings',
        params: {'target_project_id': projectId},
      ).timeout(const Duration(seconds: 8));
      final phone = marketplaceCustomerPublicSupportNumber(data, projectId);
      if (!mounted) return;
      if (phone == null) {
        _customerSupportMessage('El soporte no esta disponible ahora. Intenta mas tarde.');
        return;
      }
      final uri = Uri.https(
        'wa.me',
        '/${phone.substring(1)}',
        {'text': 'Hola, necesito ayuda con TukTuk Cliente.'},
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _customerSupportMessage('No se pudo abrir WhatsApp. Comprueba tu conexion.');
      }
    } catch (_) {
      _customerSupportMessage('No se pudo consultar el soporte. Revisa tu conexion.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _liteInForeground = state == AppLifecycleState.resumed;
    if (_liteInForeground && mounted && !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_refreshAndroidLiteNumber(force: true));
    }
  }

  Future<void> _refreshAndroidLiteNumber({bool force = false}) async {
    if (!mounted || kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) return;
    final running = _liteRefreshInFlight;
    if (running != null) {
      await running;
      return;
    }
    final now = DateTime.now().toUtc();
    final last = _liteLastAttempt;
    final minimum = force
        ? const Duration(seconds: 30)
        : const Duration(minutes: 15);
    if (last != null && now.difference(last) < minimum) return;
    _liteLastAttempt = now;
    final request = _fetchAndroidLiteNumberFromAdmin();
    _liteRefreshInFlight = request;
    try {
      await request;
    } finally {
      if (identical(_liteRefreshInFlight, request)) {
        _liteRefreshInFlight = null;
      }
    }
  }

  Future<void> _fetchAndroidLiteNumberFromAdmin() async {
    try {
      final data = await widget.service._client.rpc(
        'get_public_whatsapp_settings',
        params: {'target_project_id': _liteProjectId},
      ).timeout(const Duration(seconds: 8));
      // Respuesta malformada o de otro proyecto: no actualizar el cache.
      if (data is! Map || data['project_id'] != _liteProjectId) return;
      final phone = marketplaceCustomerPublicLiteNumber(data, _liteProjectId);
      final cache = Hive.box(_metaBox);
      if (phone == null) {
        // Si Administracion cierra Lite, invalidar inmediatamente el cache.
        await cache.delete(_litePhoneKey);
        await cache.delete(_liteVerifiedKey);
      } else {
        await cache.putAll({
          _litePhoneKey: phone,
          _liteVerifiedKey: DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (_) {
      // Fallo de red: conservar solo un numero previamente validado,
      // que caducara en 24 horas. No inventar ni fijar numeros manuales.
    }
  }

  Future<String?> _androidLitePhoneForContact() async {
    await _refreshAndroidLiteNumber(force: true);
    try {
      final cache = Hive.box(_metaBox);
      return marketplaceCustomerCachedAndroidLiteNumber(
        number: cache.get(_litePhoneKey),
        verifiedAt: cache.get(_liteVerifiedKey),
        now: DateTime.now().toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAndroidLiteWhatsApp() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final origin = flow.origin;
    final destination = flow.destination;
    if (origin == null || destination == null) {
      _customerSupportMessage('Indica origen y destino antes de continuar.');
      return;
    }
    try {
      final phone = await _androidLitePhoneForContact();
      if (!mounted) return;
      if (phone == null) {
        _customerSupportMessage(
          'No hay un numero Lite autorizado y verificado en las ultimas 24 horas. '
          'Revisa la conexion y vuelve a intentar.',
        );
        return;
      }
      final message = <String>[
        'TukTuk Cliente | SOLICITUD ALTERNATIVA',
        'Servicio: ${flow.serviceCode}',
        if (flow.session.displayName?.trim().isNotEmpty == true)
          'Cliente: ${flow.session.displayName!.trim()}',
        if (flow.session.whatsappPhone?.trim().isNotEmpty == true)
          'Telefono: ${flow.session.whatsappPhone!.trim()}',
        'Recogida: ${origin.label}',
        'GPS recogida: https://www.google.com/maps?q=${origin.lat},${origin.lon}',
        'Destino: ${destination.label}',
        'Canal: Android Lite por WhatsApp',
        'Pendiente de respuesta humana.',
        'No hay precio ni reserva confirmados.',
      ].join('\n');
      final uri = Uri.https(
        'wa.me',
        '/${phone.substring(1)}',
        {'text': message},
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _customerSupportMessage('No se pudo abrir WhatsApp. Reintenta.');
      }
    } catch (_) {
      _customerSupportMessage(
        'No se pudo consultar el canal Lite. Comprueba tu conexion.',
      );
    }
  }

  Widget _androidWeakConnectionFallback() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android ||
        flow.origin == null || flow.destination == null) {
      return const SizedBox.shrink();
    }
    final missingQuote = flow.publicationReady &&
        flow.serviceCode == 'passenger' && flow.route != null &&
        flow.selectedPrice == null && !flow.loading;
    if (flow.error == null && !missingQuote) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TuktukTheme.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TuktukTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'No se pudo completar la cotizacion',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Reintenta con conexion estable o solicita asistencia por WhatsApp. '
            'El canal Lite no confirma un viaje ni un precio automaticamente.',
            style: TextStyle(fontSize: 12, color: TuktukTheme.muted),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: flow.loading ? null : () {
                  if (flow.publicationReady) {
                    unawaited(flow.refreshRoute());
                  } else {
                    unawaited(flow.loadPublishedModalities());
                  }
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_openAndroidLiteWhatsApp()),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Alternativa WhatsApp'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _customerSupportMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showCustomerMenuDetail(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: TuktukTheme.background,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _customerMenuGlyph(IconData icon, String title, bool comingSoon) {
    final tint = comingSoon
        ? TuktukTheme.mint.withValues(alpha: .82)
        : TuktukTheme.mint;
    if (title == 'Perfil' || title == 'Historial') {
      return Icon(icon, color: tint, size: 28);
    }
    // Los otros cuatro iconos se pintan como vectores: no dependen
    // de MaterialIcons.otf que puede quedar en cache en WebApp.
    return CustomPaint(
      size: const Size(28, 28),
      painter: TuktukCustomerMenuGlyphPainter(title, tint),
    );
  }

  Widget _customerMenuItem(
    IconData icon,
    String title,
    VoidCallback? onTap, {
    bool comingSoon = false,
  }) => Material(
        color: TuktukTheme.surface.withValues(alpha: comingSoon ? .55 : .78),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: comingSoon ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _customerMenuGlyph(icon, title, comingSoon),
                const SizedBox(height: 7),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: comingSoon
                          ? Colors.white.withValues(alpha: .68)
                          : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 13,
                  child: comingSoon
                      ? Text('Próximamente',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white.withValues(alpha: .68),
                          ))
                      : title == 'Ayuda'
                          ? const Text('WhatsApp',
                              style: TextStyle(
                                fontSize: 9, color: TuktukTheme.mint,
                              ))
                          : null,
                ),
              ],
            ),
          ),
        ),
      );
  Future<void> _selectPoint({required bool origin}) async {
    if (!origin && flow.origin == null) return;
    if (origin) _pickupLocationRevision++;
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
        final center = _mapCenter.value;
        final near = flow.origin ?? (center == null
            ? null
            : MarketplaceMapPoint(
                label: 'Centro del mapa',
                lat: center.latitude,
                lon: center.longitude,
              ));
        final found = await flow.mapService.search(query, proximity: near);
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
      _pickupLocationRevision++;
      flow.setPickupForQuote(point);
    } else {
      flow.setDestination(point);
    }
    _cancelPlaceSelection();
    // Mismo mapa y misma vista. El cambio solo recoloca su camara.
    _mapCenter.value = point.latLng;
  }

  Future<void> _pickMapPoint(LatLng coordinates) async {
    // Con la recogida conocida, un toque normal marca o cambia el destino.
    // El modo explicito de edicion de recogida mantiene prioridad.
    final selectingOrigin = _selectingOrigin ?? (flow.origin == null ? null : false);
    if (selectingOrigin == null || _resolvingMapPoint) return;
    final pickupRevisionAtTap = _pickupLocationRevision;
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
    if (!mounted || (_selectingOrigin ?? (flow.origin == null ? null : false)) != selectingOrigin) return;
    if (selectingOrigin && pickupRevisionAtTap != _pickupLocationRevision) return;
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
    final latitude = (a.lat + b.lat) / 2;
    final longitude = (a.lon + b.lon) / 2;
    final zoom = _mapRequestedZoom;
    final degreesPerPixel = 360.0 * cos(latitude * pi / 180.0) /
        (512.0 * pow(2.0, zoom).toDouble());
    final screen = MediaQuery.sizeOf(context);
    final visualOffset = (screen.height * .13).clamp(45.0, 165.0);
    // Desplaza los puntos al espacio libre entre encabezado y ficha inferior.
    _mapCenter.value = LatLng(latitude - degreesPerPixel * visualOffset, longitude);
  } // Se intenta una sola vez al abrir. Si GPS o permisos fallan, la entrada

  // manual sigue disponible. Nunca sustituye una recogida elegida por el usuario.
  // Recupera la recogida con un toque. Mantiene el destino y nunca publica.
  // Un cambio posterior de origen invalida la peticion GPS anterior.
  Future<void> _restoreGpsPickup() async {
    if (_locatingPickup || _publishing) return;
    final revision = ++_pickupLocationRevision;
    setState(() => _locatingPickup = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showPickupGpsMessage('Activa la ubicación del teléfono para volver a tu posición.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showPickupGpsMessage('Permite el acceso a la ubicación para recuperar tu recogida.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || revision != _pickupLocationRevision || _publishing) return;
      var point = MarketplaceMapPoint(
        label: 'Mi ubicación actual',
        lat: position.latitude,
        lon: position.longitude,
      );
      try {
        point = await flow.mapService.reverse(point);
      } catch (_) {
        // El nombre de la calle es opcional; conservamos las coordenadas GPS.
      }
      if (!mounted || revision != _pickupLocationRevision || _publishing) return;
      _commitPlace(point, true);
    } catch (_) {
      if (mounted && revision == _pickupLocationRevision) {
        _showPickupGpsMessage('No pudimos obtener tu ubicación. Puedes elegir la recogida en el mapa.');
      }
    } finally {
      if (mounted) setState(() => _locatingPickup = false);
    }
  }

  void _showPickupGpsMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  Future<void> _autoLocatePickup() async {
    if (_tryingAutoPickup || _locatingPickup || flow.origin != null) return;
    final revision = _pickupLocationRevision;
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
      if (!mounted || flow.origin != null || _bookingResetRequested ||
          _locatingPickup || revision != _pickupLocationRevision) return;
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
      if (mounted && flow.origin == null && !_bookingResetRequested &&
          !_locatingPickup && revision == _pickupLocationRevision) {
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
    _historyOpen = true;
    _refreshMapOrnaments();

    MarketplaceCustomerJob? job;

    try {
      job = await showModalBottomSheet<MarketplaceCustomerJob>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TuktukTheme.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        builder: (_) => MarketplaceCustomerHistory(
          service: widget.service,
          session: widget.session,
        ),
      );
    } finally {
      _historyOpen = false;
      if (mounted) _refreshMapOrnaments();
    }

    if (job == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MarketplaceCustomerTrackingScreen(
          service: widget.service,
          session: widget.session,
          jobId: job!.id,
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
  void _refreshMapOrnaments() {
    final height = MediaQuery.sizeOf(context).height;
    final covered = widget.profileEditorOpen || _historyOpen;
    final raised = (height * .82)
        .clamp(0.0, max(0.0, height - 72))
        .toDouble();

    final inset = covered
        ? max(_bookingPanelHeight, raised)
        : _bookingPanelHeight;

    if ((_mapPanelInset.value - inset).abs() > 2) {
      _mapPanelInset.value = inset;
    }
  }

  // Abre suficiente espacio para las cuatro fichas en dos filas.
  bool get _hasQuoteFooter =>
      flow.origin != null && flow.destination != null && _selectingOrigin == null;

  double get _minBookingPanelFraction => marketplaceBookingPanelMinFraction(
        MediaQuery.sizeOf(context).height,
        hasQuoteFooter: _hasQuoteFooter,
      );

  double _initialBookingPanelFraction() {
    if (flow.destination == null) return .36;
    final preferred = flow.serviceCode != 'passenger' || !flow.publicationReady
        ? .56
        : MediaQuery.sizeOf(context).height < 760 ? .82 : .72;
    if (!_hasQuoteFooter) return max(preferred, _minBookingPanelFraction);
    return marketplaceQuoteInitialFraction(
      MediaQuery.sizeOf(context).height,
      preferred: preferred,
      minimum: _minBookingPanelFraction,
    );
  }

  void _syncInitialMapboxCredits() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelFraction = _initialBookingPanelFraction();
    final layoutKey = '${viewportHeight.round()}:$panelFraction';

    if (_mapPanelLayoutKey != layoutKey) {
      _mapPanelLayoutKey = layoutKey;
      _bookingPanelHeight = viewportHeight * .78 * panelFraction;
    }

    _refreshMapOrnaments();
  }

  Widget _quote() {
    final route = flow.route;
    final origin = flow.origin;
    final destination = flow.destination;
    final center = origin?.latLng ?? const LatLng(23.1136, -82.3666);
    _syncInitialMapboxCredits();
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
                    ornamentBottomInset: _mapPanelInset,
                    originPoint: origin,
                    destinationPoint: destination,
                    routePoints:
                        route?.routePoints ?? const <MarketplaceMapPoint>[],
                    onPointTap: flow.origin == null && _selectingOrigin == null ? null : _pickMapPoint,
                  ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x1208141B), Color(0x0008141B)],
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
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notice) {
                final height = MediaQuery.sizeOf(context).height * .78 * notice.extent;
                _bookingPanelHeight = height;
                _refreshMapOrnaments();
                return false;
              },
              child: _floatingBookingPanel(),
            ),
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
                  value: flow.origin?.label ??
                      'Detectando ubicación o toca para elegir',
                  onTap: () => _selectPoint(origin: true),
                  tooltip: 'Cambiar recogida',
                  showRestoreGps: true,
                  restoringGps: _locatingPickup,
                  onRestoreGps: _locatingPickup || _publishing
                      ? null
                      : () => unawaited(_restoreGpsPickup()),
                ),
                if (flow.destination != null || _selectingOrigin == false) ...[
                  const Divider(color: TuktukTheme.border, height: 1),
                  _floatingLocationRow(
                    icon: Icons.location_on_rounded,
                    color: TuktukTheme.destinationOrange,
                    label: 'Destino',
                    value: flow.destination?.label ?? 'Marcar destino',
                    distanceLabel: flow.route == null
                        ? null
                        : '${flow.route!.distanceKm.toStringAsFixed(1)} km',
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
    String? distanceLabel,
    bool showRestoreGps = false,
    bool restoringGps = false,
    VoidCallback? onRestoreGps,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (showRestoreGps)
                IconButton(
                  tooltip: 'Volver a mi ubicación',
                  onPressed: onRestoreGps,
                  color: color,
                  iconSize: 23,
                  visualDensity: VisualDensity.compact,
                  icon: restoringGps
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon),
                )
              else
                Icon(icon, color: color, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: TuktukTheme.muted,
                            ),
                          ),
                        ),
                        if (distanceLabel != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              distanceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: TuktukTheme.mint,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
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
                      : 'cotizacion-${flow.serviceCode}-${flow.publicationReady}',
        ),
        expand: false,
        initialChildSize: _initialBookingPanelFraction(),
        minChildSize: _minBookingPanelFraction,
        maxChildSize: .96,
        snap: true,
        snapSizes: const [.56, .72, .82]
            .where((size) => size > _minBookingPanelFraction).toList(),
        builder: (context, scroller) => Container(
          decoration: BoxDecoration(
                        gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xD80F2831), Color(0xDC081720)],
            ),
            border: Border.all(color: TuktukTheme.border),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
            boxShadow: const [
              BoxShadow(color: Color(0x64000000), blurRadius: 22)
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
            controller: scroller,
            padding: EdgeInsets.fromLTRB(15, 10, 15, _hasQuoteFooter ? 8 : 20),
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
              SizedBox(height: _hasQuoteFooter ? 6 : 12),
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
              if (flow.origin != null && flow.destination != null && _selectingOrigin == null)
                _quoteStickyFooter(),
            ],
          ),
        ),
      );

  Widget _ridePaymentSelector() => MarketplaceRidePaymentSelector(
        value: flow.ridePaymentMethod,
        enabled: !_publishing && !flow.loading && !flow.ridePaymentMethodLocked,
        onChanged: flow.setRidePaymentMethod,
      );

  Widget _quoteStickyFooter() {
    final price = _priceLabel(flow.selectedPrice, flow.serviceCode);
    final enabled = flow.route != null && flow.selectedPrice != null &&
        !flow.loading && !_publishing;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF018333C), Color(0xF5081720)],
        ),
        border: Border(top: BorderSide(color: Color(0x8866A5AB))),
      ),
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                flex: 4,
                child: Text('Forma de pago', style: TextStyle(
                    color: TuktukTheme.text, fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text.rich(TextSpan(
                    text: 'Estimado  ',
                    style: const TextStyle(color: TuktukTheme.muted,
                        fontSize: 12, fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(text: price, style: const TextStyle(color: TuktukTheme.gold,
                          fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ridePaymentSelector(),
          const SizedBox(height: 7),
          TuktukPrimaryButton(
            onPressed: enabled ? _submit : null,
            label: _publishing ? 'Publicando...' : 'Solicitar transporte',
          ),
          TextButton.icon(
            onPressed: _publishing ? null : _returnToStart,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Volver al inicio'),
          ),
        ],
      ),
    );
  }
  Widget _destinationSearchPrompt() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '¿A dónde vamos?',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text('Toca el mapa para indicar tu destino.',
              style: TextStyle(fontSize: 13, color: TuktukTheme.muted)),
          const SizedBox(height: 10),
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
  ) =>
      Column(
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
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900),
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
                    subtitle: Text([
                      if (point.category != null) point.category!,
                      if (point.distanceKm != null)
                        '${point.distanceKm!.toStringAsFixed(1)} km',
                      if (point.source == 'openstreetmap')
                        '© OpenStreetMap contributors',
                    ].join(' · '), maxLines: 2),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final code in flow.publishedServices) ...[
              if (code != 'passenger') const SizedBox(width: 7),
              Expanded(child: _floatingServiceChoice(code)),
            ],
          ],
        ),
        if (!flow.publicationReady)
          TextButton(
            onPressed: () => unawaited(flow.loadPublishedModalities()),
            child: const Text('Reintentar cargar modalidades'),
          ),
        if (flow.publicationReady && flow.serviceCode == 'passenger') ...[
          const SizedBox(height: 9),
          MarketplaceCompactVehicleSelector(
            selectedCategory: flow.passengerVehicleCategoryCode,
            categories: flow.publishedPassengerCategories,
            priceLabel: (category) =>
                _priceLabel(_passengerPrice(category), 'passenger'),
            onSelected: flow.setPassengerVehicleCategory,
          ),
        ],
        if (flow.publicationReady && flow.serviceCode != 'passenger') ...[
          const SizedBox(height: 9),
          const Text(
            'Tipo de vehículo',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          MarketplaceCompactVehicleSelector(
            selectedCategory: flow.selectedVehicleCategoryCode,
            categories: flow.categoriesForService(flow.serviceCode),
            priceLabel: (category) => _priceLabel(
              flow.vehiclePriceForCard(category),
              flow.serviceCode,
            ),
            onSelected: flow.setServiceVehicleCategory,
            wrapPriceLabel: flow.serviceCode == 'cargo',
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
        _androidWeakConnectionFallback(),
        if (flow.serviceCode == 'cargo' && flow.selectedPrice == null)
          const Text(
            'Indica peso o volumen en Más opciones para cotizar.',
            style: TextStyle(color: TuktukTheme.muted),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _floatingServiceChoice(String code) {
    final selected = flow.serviceCode == code;
    return InkWell(
      onTap: () => flow.setService(code),
      borderRadius: BorderRadius.circular(14),
      child: _MarineCardSurface(
        selected: selected,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _serviceIcon(code),
                    size: 18,
                    color: selected ? TuktukTheme.gold : TuktukTheme.mint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    marketplaceServiceLabel(code),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                      onPressed: flow.passengerCount <
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
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
                        iconColor: TuktukTheme.destinationOrange,
                      ),
                      const Divider(color: TuktukTheme.border, height: 1),
                      TuktukSummaryRow(
                        icon: Icons.payments_outlined,
                        label: 'Precio estimado',
                        value:
                            _priceLabel(flow.selectedPrice, flow.serviceCode),
                        iconColor: TuktukTheme.gold,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TuktukGlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Forma de pago',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      _ridePaymentSelector(),
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
      Map<String, dynamic>? transitionMap;
      try {
        // Respaldo en memoria: mantiene el mapa al pasar a la busqueda,
        // aun si la persistencia local falla. No incluye datos del conductor.
        final quote = flow.route;
        if (flow.origin != null && flow.destination != null && quote != null) {
          transitionMap = <String, dynamic>{
            'job_id': publication.jobId,
            'origin': flow.origin!.toMap(),
            'destination': flow.destination!.toMap(),
            'distance_km': quote.distanceKm,
            'route_points': quote.routePoints
                .map((point) => point.toMap())
                .toList(growable: false),
          };
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
            initialMapData: transitionMap,
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

@visibleForTesting
Color marketplaceVehicleAccent(String category) => switch (category) {
      'motorcycle' => const Color(0xFFE5A84E),
      'bicitaxi' => const Color(0xFF63D7AF),
      'tricycle' => const Color(0xFF60BDD0),
      'light_car' => const Color(0xFFA9A3E0),
      _ => TuktukTheme.mint,
    };

// Selector compartido de vehiculos, sin scroll horizontal.
// Unicamente recibe precios calculados por el gateway existente.
class MarketplaceCompactVehicleSelector extends StatelessWidget {
  const MarketplaceCompactVehicleSelector({
    required this.selectedCategory,
    this.categories = marketplacePassengerVehicleCategories,
    required this.priceLabel,
    required this.onSelected,
    this.wrapPriceLabel = false,
    super.key,
  });

  final String selectedCategory;
  final List<String> categories;
  final String Function(String category) priceLabel;
  final ValueChanged<String> onSelected;
  final bool wrapPriceLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (categories.isEmpty) return const SizedBox.shrink();
          // Dos columnas en telefonos y cuatro cuando hay espacio suficiente.
          final columns = constraints.maxWidth < 540 ? 2 : 4;
          const gap = 8.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            key: const Key('compact-vehicle-layout'),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final category in categories)
                SizedBox(width: width, child: _tile(category)),
            ],
          );
        },
      );

  Widget _tile(String category) {
    final selected = selectedCategory == category;
    final accent = marketplaceVehicleAccent(category);
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: _MarineCardSurface(
              selected: selected,
              tint: accent,
              radius: 15,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _marineVehicleIcon(category),
                    size: 22,
                    color: selected
                        ? Color.lerp(accent, Colors.white, .22)!
                        : accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (wrapPriceLabel)
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? accent
                                  : Color.lerp(TuktukTheme.muted, accent, .60)!,
                            ),
                          )
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              price,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? accent
                                    : Color.lerp(TuktukTheme.muted, accent, .60)!,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _marineVehicleIcon(String category) => switch (category) {
      'motorcycle' => Icons.two_wheeler_rounded,
      'bicycle' => Icons.pedal_bike_rounded,
      'bicitaxi' => Icons.pedal_bike_rounded,
      'tricycle' => Icons.electric_rickshaw_rounded,
      'light_car' => Icons.directions_car_filled_outlined,
      'van' => Icons.airport_shuttle_rounded,
      'truck' => Icons.local_shipping_outlined,
      _ => Icons.directions_car_outlined,
    };

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
// Iconos ligeros de cliente. No dependen de la fuente Material Icons ni
// descargan SVG, paquetes o imagenes de terceros.
@visibleForTesting
class TuktukCustomerMenuGlyphPainter extends CustomPainter {
  TuktukCustomerMenuGlyphPainter(this.kind, this.tint);
  final String kind;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final pen = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tint;
    switch (kind) {
      case 'Billetera':
        canvas.drawRRect(
          RRect.fromLTRBR(3, 8, 29, 26, const Radius.circular(4)), pen);
        canvas.drawLine(const Offset(4, 13), const Offset(25, 13), pen);
        canvas.drawRRect(
          RRect.fromLTRBR(20, 16, 29, 23, const Radius.circular(2)), pen);
        canvas.drawCircle(const Offset(23.5, 19.5), 1, fill);
      case 'Referidos':
        canvas.drawCircle(const Offset(12, 10), 4, pen);
        canvas.drawCircle(const Offset(23, 12), 3, pen);
        canvas.drawPath(ui.Path()
          ..moveTo(3, 25)
          ..quadraticBezierTo(3, 16, 12, 16)
          ..quadraticBezierTo(21, 16, 21, 25), pen);
        canvas.drawPath(ui.Path()
          ..moveTo(23, 18)
          ..quadraticBezierTo(29, 18, 29, 25), pen);
      case 'Ajustes':
        canvas.drawCircle(const Offset(16, 16), 9.0, pen);
        canvas.drawCircle(const Offset(16, 16), 3.5, pen);
        for (var index = 0; index < 8; index++) {
          final angle = index * pi / 4;
          canvas.drawLine(
            Offset(16 + cos(angle) * 10, 16 + sin(angle) * 10),
            Offset(16 + cos(angle) * 13, 16 + sin(angle) * 13),
            pen,
          );
        }
      case 'Ayuda':
        canvas.drawPath(ui.Path()
          ..moveTo(5, 18)
          ..quadraticBezierTo(5, 5, 16, 5)
          ..quadraticBezierTo(27, 5, 27, 18), pen);
        canvas.drawRRect(
          RRect.fromLTRBR(4, 16, 9, 24, const Radius.circular(2)), pen);
        canvas.drawRRect(
          RRect.fromLTRBR(23, 16, 28, 24, const Radius.circular(2)), pen);
        canvas.drawPath(ui.Path()
          ..moveTo(27, 24)
          ..quadraticBezierTo(27, 28, 21, 28), pen);
        canvas.drawCircle(const Offset(20, 28), 1.2, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TuktukCustomerMenuGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.tint != tint;
}
