part of '../main.dart';

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

  MarketplaceBookingStep step = MarketplaceBookingStep.location;
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
        'vehicle_category_code':
            serviceCode == 'passenger' ? passengerVehicleCategoryCode : null,
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
          'target_passenger_count':
              serviceCode == 'passenger' ? passengerCount : null,
          'target_vehicle_category_code':
              serviceCode == 'passenger' ? passengerVehicleCategoryCode : null,
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
    super.key,
  });
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final CustomerBookingFlowController? controller;
  final VoidCallback? onEditCustomer;

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
    noteController.text = flow.note;
    weightController.text = flow.cargoWeightKg?.toString() ?? '';
    volumeController.text = flow.cargoVolumeM3?.toString() ?? '';
    flow.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    flow.removeListener(_changed);
    if (_ownsFlow) flow.dispose();
    noteController.dispose();
    weightController.dispose();
    volumeController.dispose();
    pricingDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = flow.step;
    final number = marketplacePremiumStepNumber(step);
    final showRelief = step == MarketplaceBookingStep.location ||
        step == MarketplaceBookingStep.confirm;
    return Scaffold(
      body: SafeArea(
        child: TuktukHavanaBackdrop(
          showRelief: showRelief,
          child: Column(
            children: [
              TuktukFlowHeader(step: number, onBack: _goBack),
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
        flow.setStep(MarketplaceBookingStep.destination);
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
    final selectedPrice = _priceLabel(flow.selectedPrice, flow.serviceCode);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Elige tu servicio',
                  style: TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selecciona lo que necesitas para este viaje.',
                  style: TextStyle(
                    color: TuktukTheme.muted,
                    fontSize: 15.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _premiumTopServiceCard('passenger')),
                    const SizedBox(width: 8),
                    Expanded(child: _premiumTopServiceCard('courier')),
                    const SizedBox(width: 8),
                    Expanded(child: _premiumTopServiceCard('cargo')),
                  ],
                ),
                if (flow.serviceCode == 'passenger') ...[
                  const SizedBox(height: 20),
                  const Text(
                    '¿Cómo quieres viajar?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, inner) {
                      const gap = 9.0;
                      final width = (inner.maxWidth - gap) / 2;

                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final category
                              in marketplacePassengerVehicleCategories)
                            SizedBox(
                              width: width,
                              child: _premiumPassengerVehicleCard(category),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: TuktukTheme.surface.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TuktukTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.groups_2_outlined,
                          color: TuktukTheme.mint,
                          size: 23,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Pasajeros',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: flow.passengerCount > 1
                              ? () {
                                  flow.passengerCount--;
                                  flow.reprice();
                                }
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text(
                          '${flow.passengerCount}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: flow.passengerCount < 8
                              ? () {
                                  flow.passengerCount++;
                                  flow.reprice();
                                }
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ],
                if (flow.serviceCode == 'cargo') ...[
                  const SizedBox(height: 16),
                  TuktukGlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: weightController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Peso (kg)',
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  flow.cargoWeightKg = double.tryParse(value);
                                  _scheduleReprice();
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: volumeController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Volumen (m³)',
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  flow.cargoVolumeM3 = double.tryParse(value);
                                  _scheduleReprice();
                                },
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ayuda para cargar'),
                          value: flow.loadHelp,
                          onChanged: (value) {
                            flow.loadHelp = value;
                            flow.reprice();
                          },
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ayuda para descargar'),
                          value: flow.unloadHelp,
                          onChanged: (value) {
                            flow.unloadHelp = value;
                            flow.reprice();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, inner) {
                    final width = (inner.maxWidth - 8) / 2;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: width,
                          child: TuktukActionChip(
                            label: flow.stopCount == 0
                                ? 'Paradas'
                                : 'Paradas ${flow.stopCount}',
                            icon: Icons.location_on_outlined,
                            onTap: _showStopsSheet,
                            active: flow.stopCount > 0,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TuktukActionChip(
                            label: 'Urgente',
                            icon: Icons.bolt_rounded,
                            onTap: () {
                              flow.urgent = !flow.urgent;
                              flow.reprice();
                            },
                            active: flow.urgent,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TuktukActionChip(
                            label: flow.scheduledFor == null
                                ? 'Programar'
                                : 'Programado',
                            icon: Icons.calendar_month_outlined,
                            onTap: _pickSchedule,
                            active: flow.scheduledFor != null,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TuktukActionChip(
                            label: flow.note.trim().isEmpty
                                ? 'Nota'
                                : 'Nota añadida',
                            icon: Icons.notes_outlined,
                            onTap: _showNoteSheet,
                            active: flow.note.trim().isNotEmpty,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (flow.loading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                if (flow.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    flow.error!,
                    style: const TextStyle(color: TuktukTheme.danger),
                  ),
                ],
                if (route != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: TuktukTheme.surface.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: TuktukTheme.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 25,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: TuktukTheme.mint,
                                  ),
                                  Text(
                                    '⋮',
                                    style: TextStyle(
                                      color: TuktukTheme.muted,
                                      height: .7,
                                    ),
                                  ),
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: TuktukTheme.gold,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    flow.origin?.label ?? 'Origen',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    flow.destination?.label ?? 'Destino',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar ruta',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  flow.setStep(MarketplaceBookingStep.origin),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: TuktukTheme.mint,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: TuktukTheme.border, height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'Distancia',
                                    style: TextStyle(
                                      color: TuktukTheme.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${route.distanceKm.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'Tiempo',
                                    style: TextStyle(
                                      color: TuktukTheme.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${(route.durationSeconds / 60).round()} min',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'Estimado',
                                    style: TextStyle(
                                      color: TuktukTheme.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    selectedPrice,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TuktukTheme.gold,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 210,
                      child: MarketplaceRouteMap(
                        origin: flow.origin,
                        destination: flow.destination,
                        route: route,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: TuktukPrimaryButton(
            onPressed:
                route != null && flow.selectedPrice != null && !flow.loading
                    ? () => flow.setStep(MarketplaceBookingStep.confirm)
                    : null,
            label: 'Continuar',
          ),
        ),
      ],
    );
  }

  Widget _premiumPassengerVehicleCard(String category) {
    final selected = flow.passengerVehicleCategoryCode == category;

    final price = _priceLabel(_passengerPrice(category), 'passenger');

    final icon = switch (category) {
      'motorcycle' => Icons.two_wheeler_rounded,
      'bicitaxi' => Icons.pedal_bike_rounded,
      'tricycle' => Icons.electric_rickshaw_rounded,
      'light_car' => Icons.directions_car_filled_outlined,
      _ => Icons.local_taxi_outlined,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => flow.setPassengerVehicleCategory(category),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 92,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? TuktukTheme.gold.withValues(alpha: .10)
                : TuktukTheme.surface.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? TuktukTheme.gold.withValues(alpha: .82)
                  : TuktukTheme.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: selected
                      ? TuktukTheme.gold.withValues(alpha: .13)
                      : TuktukTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected ? TuktukTheme.gold : TuktukTheme.mint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marketplacePassengerVehicleLabel(category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? TuktukTheme.gold : TuktukTheme.muted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: TuktukTheme.gold,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumTopServiceCard(String code) {
    final selected = flow.serviceCode == code;

    final secondaryText = code == 'passenger'
        ? 'Elige modalidad'
        : _priceLabel(flow.route?.prices[code], code);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => flow.setService(code),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? TuktukTheme.gold.withValues(alpha: .10)
                : TuktukTheme.surface.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? TuktukTheme.gold.withValues(alpha: .82)
                  : TuktukTheme.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? TuktukTheme.gold.withValues(alpha: .14)
                          : TuktukTheme.mint.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _serviceIcon(code),
                      color: selected ? TuktukTheme.gold : TuktukTheme.mint,
                      size: 21,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? TuktukTheme.gold : TuktukTheme.border,
                    size: 19,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                marketplaceServiceLabel(code),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                secondaryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? TuktukTheme.gold : TuktukTheme.muted,
                  fontSize: 12.3,
                  fontWeight: FontWeight.w700,
                ),
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
                        iconColor: TuktukTheme.gold,
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
    try {
      final draft = await flow.submit();
      final publication = await widget.service.publishJob(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        jobId: draft.jobId,
        finalPrice: draft.recommendedPrice,
        priceWarningAcknowledged: true,
        idempotencyKey: flow.publishIdempotencyKey,
      );
      if (!mounted) return;
      final sessionStore = MarketplaceCustomerSessionStore(Hive.box(_metaBox));
      await sessionStore.saveActiveJobId(publication.jobId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MarketplaceCustomerTrackingScreen(
            service: widget.service,
            session: widget.session,
            jobId: publication.jobId,
            onDone: sessionStore.clearActiveJobId,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _publishing = false;
          flow.error = 'No pudimos crear la solicitud. Inténtalo de nuevo.';
        });
      }
    }
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
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
