part of '../main.dart';

enum MarketplaceBookingStep { location, origin, destination, quote, confirm }

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
    return Scaffold(
      appBar: AppBar(title: const Text('Solicita tu transporte')),
      body: SafeArea(
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
      }),
    );
  }

  Widget _locationIntro() => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.my_location,
                    size: 64, color: Colors.tealAccent),
                const SizedBox(height: 20),
                Text('Activa tu ubicación',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                const Text(
                    'Permite que TUKTUK use tu ubicación para detectar tu punto de recogida y ayudarte a solicitar más rápido.'),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () =>
                        flow.setStep(MarketplaceBookingStep.origin),
                    child: const Text('Continuar')),
                TextButton(
                    onPressed: () =>
                        flow.setStep(MarketplaceBookingStep.origin),
                    child: const Text('Elegir ubicación manualmente')),
              ],
            )),
      ));

  Widget _quote() {
    final route = flow.route;
    return Column(children: [
      Expanded(
          child: MarketplaceRouteMap(
              origin: flow.origin,
              destination: flow.destination,
              route: route)),
      Flexible(
          child: SingleChildScrollView(
              child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              '${flow.origin?.label ?? ''} → ${flow.destination?.label ?? ''}'),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: () => flow.setStep(MarketplaceBookingStep.origin),
                child: const Text('Cambiar origen')),
            TextButton(
                onPressed: () =>
                    flow.setStep(MarketplaceBookingStep.destination),
                child: const Text('Cambiar destino')),
          ]),
          if (route != null)
            Text(
                '${route.distanceKm.toStringAsFixed(1)} km · ${(route.durationSeconds / 60).round()} min'),
          if (flow.loading) const LinearProgressIndicator(),
          if (flow.error != null)
            Text(flow.error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          const Text('Elige tu servicio'),
          for (final code in const ['passenger', 'courier', 'cargo'])
            ListTile(
              selected: flow.serviceCode == code,
              onTap: () => flow.setService(code),
              leading: Icon(flow.serviceCode == code
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(switch (code) {
                'passenger' => 'Pasajeros',
                'courier' => 'Mensajería',
                _ => 'Carga'
              }),
              subtitle: Text(_priceLabel(route?.prices[code], code)),
            ),
          if (flow.serviceCode == 'passenger')
            Row(children: [
              const Text('Pasajeros'),
              IconButton(
                  onPressed: flow.passengerCount > 1
                      ? () {
                          flow.passengerCount--;
                          flow.reprice();
                        }
                      : null,
                  icon: const Icon(Icons.remove)),
              Text('${flow.passengerCount}'),
              IconButton(
                  onPressed: () {
                    flow.passengerCount++;
                    flow.reprice();
                  },
                  icon: const Icon(Icons.add)),
            ]),
          if (flow.serviceCode == 'cargo') ...[
            TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Peso en kg'),
                onChanged: (value) {
                  flow.cargoWeightKg = double.tryParse(value);
                  _scheduleReprice();
                }),
            TextField(
                controller: volumeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Volumen en m³'),
                onChanged: (value) {
                  flow.cargoVolumeM3 = double.tryParse(value);
                  _scheduleReprice();
                }),
            SwitchListTile(
                title: const Text('Ayuda para cargar'),
                value: flow.loadHelp,
                onChanged: (value) {
                  flow.loadHelp = value;
                  flow.reprice();
                }),
            SwitchListTile(
                title: const Text('Ayuda para descargar'),
                value: flow.unloadHelp,
                onChanged: (value) {
                  flow.unloadHelp = value;
                  flow.reprice();
                }),
          ],
          Row(children: [
            const Text('Paradas'),
            IconButton(
                onPressed: flow.stopCount > 0
                    ? () {
                        flow.stopCount--;
                        flow.reprice();
                      }
                    : null,
                icon: const Icon(Icons.remove)),
            Text('${flow.stopCount}'),
            IconButton(
                onPressed: flow.stopCount < 20
                    ? () {
                        flow.stopCount++;
                        flow.reprice();
                      }
                    : null,
                icon: const Icon(Icons.add)),
          ]),
          SwitchListTile(
              title: const Text('Urgente'),
              value: flow.urgent,
              onChanged: (value) {
                flow.urgent = value;
                flow.reprice();
              }),
          ListTile(
            title: Text(flow.scheduledFor == null
                ? 'Programar'
                : 'Programado: ${flow.scheduledFor}'),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final day = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                  initialDate: DateTime.now());
              if (day == null || !mounted) return;
              final time = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now());
              if (time == null || !mounted) return;
              setState(() => flow.scheduledFor = DateTime(
                  day.year, day.month, day.day, time.hour, time.minute));
            },
          ),
          TextField(
              controller: noteController,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Nota opcional'),
              onChanged: (value) => flow.note = value),
          FilledButton(
            onPressed:
                route != null && flow.selectedPrice != null && !flow.loading
                    ? () => flow.setStep(MarketplaceBookingStep.confirm)
                    : null,
            child: const Text('Continuar'),
          ),
        ]),
      ))),
    ]);
  }

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
        ? 'Desde 2000 CUP · indica peso o volumen'
        : 'Calculando…';
  }

  void _scheduleReprice() {
    pricingDebounce?.cancel();
    if (flow.route == null) return;
    setState(() => flow.loading = true);
    pricingDebounce = Timer(const Duration(milliseconds: 700), flow.reprice);
  }

  Widget _confirmation() => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Confirma tu solicitud',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Text('Servicio: ${flow.serviceCode}'),
          Text('Origen: ${flow.origin?.label}'),
          Text('Destino: ${flow.destination?.label}'),
          Text('Distancia: ${flow.route?.distanceKm.toStringAsFixed(1)} km'),
          Text(
              'Tiempo estimado: ${((flow.route?.durationSeconds ?? 0) / 60).round()} min'),
          Text('Precio: ${_priceLabel(flow.selectedPrice, flow.serviceCode)}'),
          Text('Pasajeros: ${flow.passengerCount}'),
          Text('Paradas: ${flow.stopCount}'),
          Text('Urgente: ${flow.urgent ? 'Sí' : 'No'}'),
          Text('Programación: ${flow.scheduledFor ?? 'Lo antes posible'}'),
          Text('Nota: ${flow.note.isEmpty ? 'Ninguna' : flow.note}'),
          if (flow.error != null)
            Text(flow.error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: flow.loading ? null : _submit,
              child: const Text('Solicitar transporte')),
          TextButton(
              onPressed: () => flow.setStep(MarketplaceBookingStep.quote),
              child: const Text('Editar solicitud')),
        ]),
      ));

  Future<void> _submit() async {
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
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => MarketplaceCustomerTrackingScreen(
                service: widget.service,
                session: widget.session,
                jobId: publication.jobId,
                onDone: sessionStore.clearActiveJobId,
              )));
    } catch (_) {
      if (mounted) {
        setState(() =>
            flow.error = 'No pudimos crear la solicitud. Inténtalo de nuevo.');
      }
    }
  }
}
