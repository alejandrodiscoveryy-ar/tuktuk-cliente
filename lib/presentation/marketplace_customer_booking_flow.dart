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

class CustomerBookingFlowController extends ChangeNotifier {
  CustomerBookingFlowController(
      this.mapService, this.customerService, this.session);

  final MarketplaceMapService mapService;
  final MarketplaceCustomerService customerService;
  final MarketplaceCustomerSessionSnapshot session;

  MarketplaceBookingStep step = MarketplaceBookingStep.location;
  MarketplaceMapPoint? origin;
  MarketplaceMapPoint? destination;
  MarketplaceRouteQuote? route;
  String serviceCode = 'passenger';
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
      };

  Map<String, dynamic>? get selectedPrice =>
      serviceCode == 'cargo' && cargoWeightKg == null && cargoVolumeM3 == null
          ? null
          : route?.prices[serviceCode] is Map
              ? Map<String, dynamic>.from(route!.prices[serviceCode] as Map)
              : null;

  void setStep(MarketplaceBookingStep value) {
    step = value;
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

  Future<void> refreshRoute() async {
    final start = origin, end = destination;
    if (start == null || end == null) return;
    final revision = ++_pricingRevision;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await mapService.route(
          origin: start, destination: end, pricing: pricing);
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
  const MarketplaceCustomerBookingFlow(
      {required this.service, required this.session, super.key});
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;

  @override
  State<MarketplaceCustomerBookingFlow> createState() =>
      _MarketplaceCustomerBookingFlowState();
}

class _MarketplaceCustomerBookingFlowState
    extends State<MarketplaceCustomerBookingFlow> {
  late final CustomerBookingFlowController flow;
  final noteController = TextEditingController();
  final weightController = TextEditingController();
  final volumeController = TextEditingController();
  Timer? pricingDebounce;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    flow = CustomerBookingFlowController(
      MarketplaceMapService(widget.service._client),
      widget.service,
      widget.session,
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    flow.removeListener(_changed);
    flow.dispose();
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
              TuktukFlowHeader(step: number),
              Expanded(
                child: switch (step) {
                  MarketplaceBookingStep.location => _locationIntro(),
                  MarketplaceBookingStep.origin => MarketplaceLocationPicker(
                      service: flow.mapService,
                      title: 'Elige el origen',
                      onConfirm: flow.setOrigin,
                    ),
                  MarketplaceBookingStep.destination => MarketplaceLocationPicker(
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

  Widget _locationIntro() => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                Semantics(
                  button: true,
                  label: 'Activar ubicación y continuar',
                  child: Tooltip(
                    message: 'Activar ubicación',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          flow.setStep(MarketplaceBookingStep.origin),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: _TuktukGeoActivationButton(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Activa tu ubicación',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: const Text(
                    'Permite que TUKTUK use tu ubicación para detectar tu punto de recogida y ayudarte a solicitar más rápido.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.45,
                      color: TuktukTheme.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const _BenefitCard(
                  Icons.near_me_rounded,
                  'Encontrar tu origen',
                  'Detectamos tu punto de recogida automáticamente.',
                ),
                const SizedBox(height: 10),
                const _BenefitCard(
                  Icons.alt_route_rounded,
                  'Calcular la ruta',
                  'Te mostramos la mejor ruta disponible al instante.',
                ),
                const SizedBox(height: 10),
                const _BenefitCard(
                  Icons.payments_outlined,
                  'Estimar el precio',
                  'Conocemos la distancia para darte un precio justo.',
                ),
                const SizedBox(height: 24),
                TuktukPrimaryButton(
                  onPressed: () =>
                      flow.setStep(MarketplaceBookingStep.origin),
                  label: 'Continuar',
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () =>
                      flow.setStep(MarketplaceBookingStep.origin),
                  child: const Text(
                    'Elegir ubicación manualmente',
                    style: TextStyle(color: TuktukTheme.muted),
                  ),
                ),
                const TuktukFooterLabel('Permiso de ubicación'),
              ],
            ),
          ),
        ),
      );

  Widget _quote() {
    final route = flow.route;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapHeight =
            (constraints.maxHeight * .39).clamp(225.0, 325.0).toDouble();
        return Column(
          children: [
            SizedBox(
              height: mapHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MarketplaceRouteMap(
                      origin: flow.origin,
                      destination: flow.destination,
                      route: route,
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 12,
                    child: TuktukGlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 28,
                            child: Column(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 13,
                                  color: TuktukTheme.mint,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '⋮',
                                  style: TextStyle(
                                    color: TuktukTheme.muted,
                                    height: .75,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Icon(
                                  Icons.circle,
                                  size: 13,
                                  color: TuktukTheme.danger,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  flow.origin?.label ?? 'Origen',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  flow.destination?.label ?? 'Destino',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Editar ruta',
                            onPressed: () =>
                                flow.setStep(MarketplaceBookingStep.origin),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (route != null)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: TuktukMetricPill(
                        icon: Icons.directions_car_filled_outlined,
                        label:
                            '${route.distanceKm.toStringAsFixed(1)} km · ${(route.durationSeconds / 60).round()} min',
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TuktukSectionSheet(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Elige tu servicio',
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final code in const [
                        'passenger',
                        'courier',
                        'cargo'
                      ])
                        TuktukServiceCard(
                          icon: _serviceIcon(code),
                          title: marketplaceServiceLabel(code),
                          subtitle: _serviceDescription(code),
                          price: _priceLabel(route?.prices[code], code),
                          selected: flow.serviceCode == code,
                          onTap: () => flow.setService(code),
                        ),
                      if (flow.serviceCode == 'passenger')
                        TuktukGlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.groups_2_outlined,
                                color: TuktukTheme.mint,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Pasajeros',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
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
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              IconButton(
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
                      if (flow.serviceCode == 'cargo') ...[
                        const SizedBox(height: 2),
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
                                      ),
                                      onChanged: (value) {
                                        flow.cargoWeightKg =
                                            double.tryParse(value);
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
                                      ),
                                      onChanged: (value) {
                                        flow.cargoVolumeM3 =
                                            double.tryParse(value);
                                        _scheduleReprice();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Ayuda para cargar'),
                                value: flow.loadHelp,
                                onChanged: (value) {
                                  flow.loadHelp = value;
                                  flow.reprice();
                                },
                              ),
                              SwitchListTile(
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
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, inner) {
                          final width = (inner.maxWidth - 24) / 4;
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
                      const SizedBox(height: 12),
                      TuktukPrimaryButton(
                        onPressed: route != null &&
                                flow.selectedPrice != null &&
                                !flow.loading
                            ? () =>
                                flow.setStep(MarketplaceBookingStep.confirm)
                            : null,
                        label: 'Continuar',
                      ),
                      const TuktukFooterLabel('Ruta y precio automático'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _serviceIcon(String code) => switch (code) {
        'passenger' => Icons.directions_car_filled_outlined,
        'courier' => Icons.inventory_2_outlined,
        'cargo' => Icons.local_shipping_outlined,
        _ => Icons.local_taxi_outlined,
      };

  String _serviceDescription(String code) => switch (code) {
        'passenger' => 'Traslado de pasajeros',
        'courier' => 'Documentos y paquetes pequeños',
        'cargo' => 'Bultos y carga ligera',
        _ => '',
      };

  String _priceLabel(Object? value, String code) {
    if (value is Map &&
        code == 'cargo' &&
        flow.cargoWeightKg == null &&
        flow.cargoVolumeM3 == null) {
      return 'Desde ${value['minimum_price']} ${value['currency'] ?? 'CUP'}';
    }
    if (value is Map) {
      return '${value['recommended_price']} ${value['currency'] ?? 'CUP'}';
    }
    return code == 'cargo'
        ? 'Indica peso o volumen'
        : 'Calculando…';
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
      flow.scheduledFor =
          DateTime(day.year, day.month, day.day, time.hour, time.minute);
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

  Widget _confirmation() => LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
          children: [
            const Text(
              'Confirma tu solicitud',
              style: TextStyle(
                fontSize: 33,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa los detalles de tu viaje antes de publicarlo.',
              style: TextStyle(
                color: TuktukTheme.muted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),
            TuktukGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    icon: Icons.alt_route_rounded,
                    label: 'Distancia',
                    value:
                        '${flow.route?.distanceKm.toStringAsFixed(1) ?? '-'} km',
                  ),
                  const Divider(color: TuktukTheme.border, height: 1),
                  TuktukSummaryRow(
                    icon: Icons.schedule_outlined,
                    label: 'Tiempo estimado',
                    value:
                        '${((flow.route?.durationSeconds ?? 0) / 60).round()} min',
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
            const SizedBox(height: 10),
            TuktukGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: LayoutBuilder(
                builder: (context, inner) {
                  final itemWidth = (inner.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: [
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
                          Icons.alt_route_rounded,
                          '${flow.stopCount} parada${flow.stopCount == 1 ? '' : 's'}',
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _MiniFact(
                          Icons.bolt_rounded,
                          'Urgente: ${flow.urgent ? 'Sí' : 'No'}',
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _MiniFact(
                          Icons.calendar_month_outlined,
                          flow.scheduledFor == null
                              ? 'Programado: Ahora'
                              : 'Programado: ${DateFormat('dd/MM HH:mm').format(flow.scheduledFor!)}',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLength: 1000,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Nota para el conductor (opcional)',
                prefixIcon: Icon(Icons.edit_outlined),
                counterText: '',
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
            const SizedBox(height: 12),
            TuktukPrimaryButton(
              onPressed: flow.loading || _publishing ? null : _submit,
              label: _publishing ? 'Publicando...' : 'Solicitar transporte',
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(
                'Al confirmar, tu solicitud se publicará para transportistas disponibles.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TuktukTheme.muted),
              ),
            ),
            TextButton(
              onPressed: _publishing
                  ? null
                  : () => flow.setStep(MarketplaceBookingStep.quote),
              child: const Text(
                'Editar solicitud',
                style: TextStyle(color: TuktukTheme.mint),
              ),
            ),
            const TuktukFooterLabel('Confirmación final'),
          ],
        ),
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
  Widget build(BuildContext context) => TuktukGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Color(0x2035D6A2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: TuktukTheme.mint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TuktukTheme.muted,
                      height: 1.3,
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
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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

class _TuktukGeoActivationButtonState
    extends State<_TuktukGeoActivationButton>
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
        tween: Tween(begin: .96, end: 1.035).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.035, end: .96).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    return SizedBox(
      width: 170,
      height: 170,
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
                width: 166,
                height: 166,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TuktukTheme.gold.withValues(alpha: .06),
                ),
              ),
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 110,
                  height: 110,
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
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TuktukTheme.goldSurface,
                    border: Border.all(
                      color: TuktukTheme.gold,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: TuktukTheme.gold.withValues(alpha: .32),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 72,
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