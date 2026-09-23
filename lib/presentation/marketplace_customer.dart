part of '../main.dart';

class MarketplaceCustomerApp extends StatelessWidget {
  const MarketplaceCustomerApp({
    required this.client,
    super.key,
  });

  final SupabaseClient client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TUKTUK',
      theme: buildAppTheme(Brightness.dark),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: MarketplaceCustomerShell(
        client: client,
      ),
    );
  }
}

class MarketplaceCustomerShell extends StatefulWidget {
  const MarketplaceCustomerShell({
    required this.client,
    super.key,
  });

  final SupabaseClient client;

  @override
  State<MarketplaceCustomerShell> createState() =>
      _MarketplaceCustomerShellState();
}

class _MarketplaceCustomerShellState extends State<MarketplaceCustomerShell> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _whatsappController = TextEditingController();

  late final MarketplaceCustomerService _service;
  late final MarketplaceCustomerSessionStore _sessionStore;
  late final String _sessionToken;
  late final String _startIdempotencyKey;

  MarketplaceCustomerSessionSnapshot? _existingSession;
  String? _activeJobId;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _service = MarketplaceCustomerService(widget.client);
    _sessionStore = MarketplaceCustomerSessionStore(Hive.box(_metaBox));

    final saved = _sessionStore.read();
    final expiresAt = saved?.expiresAt;

    if (saved != null &&
        (expiresAt == null || expiresAt.isAfter(DateTime.now().toUtc()))) {
      _existingSession = saved;
      _activeJobId = _sessionStore.readActiveJobId();
    } else if (saved != null) {
      _sessionStore.clear();
    }

    _sessionToken = marketplaceCustomerSessionToken();
    _startIdempotencyKey = _marketplaceUuid();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Escribe tu nombre.';
    }
    if (text.length > 120) {
      return 'El nombre es demasiado largo.';
    }
    return null;
  }

  String? _validateWhatsapp(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Escribe tu número de WhatsApp.';
    }

    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(text)) {
      return 'Usa formato internacional, por ejemplo +5355555555.';
    }

    return null;
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = await _service.startSession(
        displayName: _nameController.text.trim(),
        whatsappPhone: _whatsappController.text.trim(),
        sessionToken: _sessionToken,
        idempotencyKey: _startIdempotencyKey,
      );

      final snapshot = MarketplaceCustomerSessionSnapshot(
        sessionId: session.sessionId,
        customerId: session.customerId,
        token: _sessionToken,
        expiresAt: session.expiresAt,
      );

      await _sessionStore.save(
        session: session,
        token: _sessionToken,
      );

      if (!mounted) return;

      setState(() {
        _existingSession = snapshot;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos iniciar la solicitud. Revisa tu conexión e inténtalo otra vez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _clearActiveJob() async {
    await _sessionStore.clearActiveJobId();

    if (!mounted) return;

    setState(() {
      _activeJobId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final existingSession = _existingSession;

    if (existingSession != null) {
      final activeJobId = _activeJobId;

      if (activeJobId != null) {
        return MarketplaceCustomerTrackingScreen(
          service: _service,
          session: existingSession,
          jobId: activeJobId,
          onDone: _clearActiveJob,
        );
      }

      return MarketplaceCustomerBookingFlow(
        service: _service,
        session: existingSession,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.local_taxi_rounded,
                      size: 56,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '¿Cómo quieres que te llamemos?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Conecta con un transportista disponible desde TUKTUK.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: kMuted),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.name,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _whatsappController,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [
                        AutofillHints.telephoneNumber,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp',
                        hintText: '+5355555555',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                      validator: _validateWhatsapp,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Usaremos este número únicamente como contacto operativo del servicio.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kMuted),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: kDanger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _continue,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continuar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceCustomerRequestScreen extends StatefulWidget {
  const MarketplaceCustomerRequestScreen({
    required this.service,
    required this.session,
    super.key,
  });

  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;

  @override
  State<MarketplaceCustomerRequestScreen> createState() =>
      _MarketplaceCustomerRequestScreenState();
}

class _MarketplaceCustomerRequestScreenState
    extends State<MarketplaceCustomerRequestScreen> {
  List<MarketplaceCustomerServiceOption> _services =
      const <MarketplaceCustomerServiceOption>[];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final services = await widget.service.listCustomerServices();

      if (!mounted) return;

      setState(() {
        _services = services;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'No pudimos cargar los servicios disponibles.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva solicitud'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _services.isEmpty
                          ? const Center(
                              child: Text(
                                'Todavía no hay servicios disponibles.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: _services.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final service = _services[index];

                                return Card(
                                  child: ListTile(
                                    title: Text(service.name),
                                    subtitle: Text(
                                      'Precio calculado en ${service.currency}',
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              MarketplaceCustomerTripFormScreen(
                                            service: widget.service,
                                            session: widget.session,
                                            serviceOption: service,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceCustomerTripFormScreen extends StatefulWidget {
  const MarketplaceCustomerTripFormScreen({
    required this.service,
    required this.session,
    required this.serviceOption,
    super.key,
  });

  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final MarketplaceCustomerServiceOption serviceOption;

  @override
  State<MarketplaceCustomerTripFormScreen> createState() =>
      _MarketplaceCustomerTripFormScreenState();
}

class _MarketplaceCustomerTripFormScreenState
    extends State<MarketplaceCustomerTripFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _passengerController = TextEditingController(text: '1');

  final _cargoWeightController = TextEditingController();
  final _cargoVolumeController = TextEditingController();

  final _distanceController = TextEditingController();
  final _stopCountController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  DateTime? _scheduledFor;
  bool _urgent = false;
  bool _loadHelp = false;
  bool _unloadHelp = false;
  bool _loading = false;

  String? _error;
  String? _requestIdempotencyKey;
  String? _requestPayloadSignature;

  bool get _needsPassengers =>
      widget.serviceOption.code == 'passenger' ||
      widget.serviceOption.code == 'tourism';

  bool get _isCargo => widget.serviceOption.code == 'cargo';

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _passengerController.dispose();
    _cargoWeightController.dispose();
    _cargoVolumeController.dispose();
    _distanceController.dispose();
    _stopCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _requiredLocation(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Este campo es obligatorio.';
    }

    if (text.length > 240) {
      return 'Máximo 240 caracteres.';
    }

    return null;
  }

  int? _positiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  double? _positiveDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  double? _optionalPositiveDouble(String value) {
    if (value.trim().isEmpty) return null;
    return _positiveDouble(value);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final initial = marketplaceSchedulePickerInitialDate(now, _scheduledFor);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );

    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (!mounted || time == null) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (!selected.isAfter(DateTime.now())) {
      setState(() {
        _error = 'Selecciona una fecha y hora futuras.';
      });
      return;
    }

    setState(() {
      _scheduledFor = selected;
      _error = null;
    });
  }

  Future<void> _requestQuote() async {
    if (!_formKey.currentState!.validate()) return;

    if (_scheduledFor != null && !_scheduledFor!.isAfter(DateTime.now())) {
      setState(() {
        _error = 'La fecha programada ya vencio. Selecciona otra.';
      });
      return;
    }

    final passengerCount =
        _needsPassengers ? _positiveInt(_passengerController.text) : null;

    if (_needsPassengers && passengerCount == null) {
      setState(() {
        _error = 'Indica una cantidad válida de pasajeros.';
      });
      return;
    }

    final cargoWeight = _optionalPositiveDouble(_cargoWeightController.text);
    final cargoVolume = _optionalPositiveDouble(_cargoVolumeController.text);

    if (_isCargo && cargoWeight == null && cargoVolume == null) {
      setState(() {
        _error = 'Para carga indica al menos el peso o el volumen aproximado.';
      });
      return;
    }

    final distance = _optionalPositiveDouble(_distanceController.text);

    if (_distanceController.text.trim().isNotEmpty && distance == null) {
      setState(() {
        _error = 'La distancia debe ser mayor que cero.';
      });
      return;
    }

    final stopText = _stopCountController.text.trim();
    final stopCount = stopText.isEmpty ? 0 : int.tryParse(stopText);

    if (stopCount == null || stopCount < 0 || stopCount > 20) {
      setState(() {
        _error = 'Las paradas adicionales deben estar entre 0 y 20.';
      });
      return;
    }

    final notes = _notesController.text.trim();

    if (notes.length > 1000) {
      setState(() {
        _error = 'Las notas no pueden superar 1000 caracteres.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = <String, dynamic>{
        'distance_source': distance == null ? 'unavailable' : 'manual',
        'stop_count': stopCount,
        'urgent': _urgent,
        'load_help': _isCargo && _loadHelp,
        'unload_help': _isCargo && _unloadHelp,
      };

      if (distance != null) {
        details['estimated_distance_km'] = distance;
      }

      final payloadSignature = jsonEncode({
        'service_code': widget.serviceOption.code,
        'origin_text': _originController.text.trim(),
        'destination_text': _destinationController.text.trim(),
        'scheduled_for': _scheduledFor?.toUtc().toIso8601String(),
        'passenger_count': passengerCount,
        'cargo_weight_kg': cargoWeight,
        'cargo_volume_m3': cargoVolume,
        'notes': notes.isEmpty ? null : notes,
        'details': details,
      });

      if (_requestPayloadSignature != payloadSignature ||
          _requestIdempotencyKey == null) {
        _requestPayloadSignature = payloadSignature;
        _requestIdempotencyKey = _marketplaceUuid();
      }

      final draft = await widget.service.createRequest(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        serviceCode: widget.serviceOption.code,
        originText: _originController.text.trim(),
        destinationText: _destinationController.text.trim(),
        scheduledFor: _scheduledFor,
        passengerCount: passengerCount,
        cargoWeightKg: cargoWeight,
        cargoVolumeM3: cargoVolume,
        notes: notes.isEmpty ? null : notes,
        details: details,
        idempotencyKey: _requestIdempotencyKey!,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MarketplaceCustomerQuoteScreen(
            service: widget.service,
            session: widget.session,
            serviceOption: widget.serviceOption,
            draft: draft,
            scheduledFor: _scheduledFor,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos calcular el precio. Revisa los datos e inténtalo otra vez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceOption.name),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Qué necesitas?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _originController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Origen',
                        prefixIcon: Icon(Icons.trip_origin_rounded),
                      ),
                      validator: _requiredLocation,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _destinationController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Destino',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      validator: _requiredLocation,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickSchedule,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _scheduledFor == null
                            ? 'Programar fecha y hora (opcional)'
                            : 'Programado: ${DateFormat('dd/MM/yyyy HH:mm').format(_scheduledFor!)}',
                      ),
                    ),
                    if (_scheduledFor != null)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _scheduledFor = null;
                                  _error = null;
                                });
                              },
                        child: const Text('Solicitar ahora'),
                      ),
                    if (_needsPassengers) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passengerController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad de pasajeros',
                          prefixIcon: Icon(Icons.groups_outlined),
                        ),
                      ),
                    ],
                    if (_isCargo) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cargoWeightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Peso aproximado (kg)',
                          prefixIcon: Icon(Icons.scale_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cargoVolumeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Volumen aproximado (m³)',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _distanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Distancia aproximada en km (opcional)',
                        prefixIcon: Icon(Icons.route_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _stopCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Paradas adicionales',
                        prefixIcon: Icon(Icons.add_location_alt_outlined),
                      ),
                    ),
                    if (_isCargo) ...[
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Necesito ayuda para cargar',
                        ),
                        value: _loadHelp,
                        onChanged: (value) {
                          setState(() {
                            _loadHelp = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Necesito ayuda para descargar',
                        ),
                        value: _unloadHelp,
                        onChanged: (value) {
                          setState(() {
                            _unloadHelp = value;
                          });
                        },
                      ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Servicio urgente'),
                      value: _urgent,
                      onChanged: (value) {
                        setState(() {
                          _urgent = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Notas (opcional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: kDanger),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _requestQuote,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Ver precio recomendado',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceCustomerQuoteScreen extends StatefulWidget {
  const MarketplaceCustomerQuoteScreen({
    required this.service,
    required this.session,
    required this.serviceOption,
    required this.draft,
    this.scheduledFor,
    super.key,
  });

  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final MarketplaceCustomerServiceOption serviceOption;
  final MarketplaceCustomerRequestDraft draft;
  final DateTime? scheduledFor;

  @override
  State<MarketplaceCustomerQuoteScreen> createState() =>
      _MarketplaceCustomerQuoteScreenState();
}

class _MarketplaceCustomerQuoteScreenState
    extends State<MarketplaceCustomerQuoteScreen> {
  late final TextEditingController _priceController;

  bool _warningAcknowledged = false;
  bool _publishing = false;

  String? _error;
  String? _publishIdempotencyKey;
  String? _publishPayloadSignature;

  MarketplaceCustomerRequestDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();

    _priceController = TextEditingController(
      text: _priceInput(draft.recommendedPrice),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  String _priceInput(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  double? _currentPrice() {
    final text = _priceController.text.trim().replaceAll(',', '.');

    final value = double.tryParse(text);

    if (value == null || value <= 0) {
      return null;
    }

    return (value * 100).round() / 100;
  }

  String _publicationError(Object error) {
    final value = error.toString();

    if (value.contains('PRICE_QUOTE_STALE')) {
      return 'La tarifa cambió desde que calculamos el precio. '
          'Regresa y vuelve a calcular la solicitud.';
    }

    if (value.contains('FINAL_PRICE_BELOW_MINIMUM')) {
      return 'El precio está por debajo del mínimo permitido.';
    }

    if (value.contains(
      'PRICE_WARNING_ACKNOWLEDGEMENT_REQUIRED',
    )) {
      return 'Debes confirmar la advertencia de precio bajo.';
    }

    if (value.contains('JOB_NOT_REQUESTED')) {
      return 'Esta solicitud ya fue publicada o ya no puede publicarse.';
    }

    if (value.contains('SCHEDULED_TIME_EXPIRED')) {
      return 'La hora programada ya venció. '
          'Regresa y actualiza la solicitud.';
    }

    return 'No pudimos publicar la solicitud. '
        'Revisa tu conexión e inténtalo otra vez.';
  }

  void _useRecommendedPrice() {
    setState(() {
      _priceController.text = _priceInput(draft.recommendedPrice);
      _warningAcknowledged = false;
      _error = null;
    });
  }

  Future<void> _publish() async {
    final price = _currentPrice();

    if (price == null) {
      setState(() {
        _error = 'Escribe un precio válido.';
      });
      return;
    }

    if (draft.isBelowMinimum(price)) {
      setState(() {
        _error = 'El mínimo permitido es '
            '${draft.minimumPrice.toStringAsFixed(0)} '
            '${draft.currency}.';
      });
      return;
    }

    final warningRequired = draft.requiresWarningFor(price);

    if (warningRequired && !_warningAcknowledged) {
      setState(() {
        _error = 'Confirma la advertencia antes de publicar.';
      });
      return;
    }

    final warningAck = warningRequired && _warningAcknowledged;

    final payloadSignature = jsonEncode({
      'job_id': draft.jobId,
      'final_price': price,
      'price_warning_acknowledged': warningAck,
    });

    if (_publishPayloadSignature != payloadSignature ||
        _publishIdempotencyKey == null) {
      _publishPayloadSignature = payloadSignature;
      _publishIdempotencyKey = _marketplaceUuid();
    }

    setState(() {
      _publishing = true;
      _error = null;
    });

    try {
      final publication = await widget.service.publishJob(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        jobId: draft.jobId,
        finalPrice: price,
        priceWarningAcknowledged: warningAck,
        idempotencyKey: _publishIdempotencyKey!,
      );

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
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _publicationError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _currentPrice();
    final belowMinimum = price != null && draft.isBelowMinimum(price);
    final warningRequired = price != null && draft.requiresWarningFor(price);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Precio y publicación'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.serviceOption.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.scheduledFor == null
                        ? 'Solicitud inmediata'
                        : 'Servicio programado: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.scheduledFor!)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            'Precio recomendado',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${draft.recommendedPrice.toStringAsFixed(0)} '
                            '${draft.currency}',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Puedes aceptarlo, aumentarlo o reducirlo '
                            'antes de publicar.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: kMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      setState(() {
                        _warningAcknowledged = false;
                        _error = null;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Tu precio',
                      suffixText: draft.currency,
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _publishing ? null : _useRecommendedPrice,
                    child: const Text(
                      'Usar precio recomendado',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mínimo permitido: '
                    '${draft.minimumPrice.toStringAsFixed(0)} '
                    '${draft.currency}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: belowMinimum ? kDanger : kMuted,
                        ),
                  ),
                  if (warningRequired && !belowMinimum) ...[
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: kTertiary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Este precio está por debajo '
                                    'del nivel recomendado. '
                                    'Puede reducir la probabilidad '
                                    'de que un transportista acepte '
                                    'la solicitud.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'Entiendo y quiero publicar '
                                'con este precio.',
                              ),
                              value: _warningAcknowledged,
                              onChanged: _publishing
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _warningAcknowledged = value ?? false;
                                        _error = null;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: kDanger),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _publishing ? null : _publish,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                      child: _publishing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Publicar solicitud',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'El pago se realiza directamente al '
                    'transportista. TUKTUK no cobra el viaje '
                    'al cliente.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: kMuted),
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

DateTime marketplaceSchedulePickerInitialDate(
  DateTime now,
  DateTime? scheduledFor,
) {
  if (scheduledFor != null && scheduledFor.isAfter(now)) {
    return scheduledFor;
  }

  return now.add(const Duration(minutes: 30));
}

String _marketplaceUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  );

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');

  final value = bytes.map(hex).join();

  return '${value.substring(0, 8)}-'
      '${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-'
      '${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
