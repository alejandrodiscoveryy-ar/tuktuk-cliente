part of '../main.dart';

class MarketplaceCustomerTrackingScreen extends StatefulWidget {
  const MarketplaceCustomerTrackingScreen({
    required this.service,
    required this.session,
    required this.jobId,
    required this.onDone,
    super.key,
  });

  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final String jobId;
  final Future<void> Function() onDone;

  @override
  State<MarketplaceCustomerTrackingScreen> createState() =>
      _MarketplaceCustomerTrackingScreenState();
}

class _MarketplaceCustomerTrackingScreenState
    extends State<MarketplaceCustomerTrackingScreen> {
  Timer? _pollTimer;

  MarketplaceCustomerJob? _job;
  MarketplaceCustomerJobMedia? _media;
  MarketplaceCustomerRating? _rating;
  String? _mediaAssignmentSignature;

  bool _loading = true;
  bool _refreshing = false;
  bool _cancelling = false;

  String? _error;
  String? _cancelPayloadSignature;
  String? _cancelIdempotencyKey;

  @override
  void initState() {
    super.initState();

    _refresh();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;

    _refreshing = true;

    try {
      final job = await widget.service.getJob(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        jobId: widget.jobId,
      );

      if (!mounted) return;

      setState(() {
        _job = job;
        _error = null;
      });

      final mediaSignature =
          '${job.driverPhotoAssetId ?? ''}:${job.vehicleMainPhotoAssetId ?? ''}';
      final mediaExpiresSoon = _media?.expiresAt == null ||
          _media!.expiresAt!.isBefore(
            DateTime.now().toUtc().add(const Duration(minutes: 2)),
          );
      if (job.hasAssignedDriver &&
          (_mediaAssignmentSignature != mediaSignature || mediaExpiresSoon)) {
        try {
          final media = await widget.service.getJobMedia(
            sessionId: widget.session.sessionId,
            sessionToken: widget.session.token,
            jobId: widget.jobId,
          );
          if (mounted) {
            setState(() {
              _media = media;
              _mediaAssignmentSignature = mediaSignature;
            });
          }
        } catch (_) {
          // Private media is optional UI enrichment; the server remains the
          // privacy boundary and the card retains its visual fallback.
        }
      }
      if (job.status == 'settled') {
        final rating = await widget.service.getRating(
          sessionId: widget.session.sessionId,
          sessionToken: widget.session.token,
          jobId: widget.jobId,
        );
        if (mounted) setState(() => _rating = rating);
      }

      if (job.isTerminal) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No pudimos actualizar el estado. Revisa tu conexión.';
      });
    } finally {
      _refreshing = false;

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _statusTitle(String status) => switch (status) {
        'requested' => 'Preparando solicitud',
        'published' => 'Buscando transportista',
        'accepted' => 'Transportista asignado',
        'en_route' => 'El transportista va hacia ti',
        'pickup' => 'Transportista en el punto de recogida',
        'in_progress' => 'Servicio en curso',
        'completed' => 'Servicio completado',
        'settled' => 'Servicio finalizado',
        'cancelled_by_customer' => 'Solicitud cancelada',
        'cancelled_by_driver' => 'Cancelada por el transportista',
        'expired' => 'La solicitud expiró',
        'incident' => 'Servicio en revisión',
        _ => 'Estado del servicio',
      };

  String _statusDescription(String status) => switch (status) {
        'published' =>
          'Tu solicitud está visible para los transportistas compatibles.',
        'accepted' =>
          'Un transportista aceptó tu solicitud. Ya puedes ver sus datos.',
        'en_route' => 'Tu transportista se dirige al punto de recogida.',
        'pickup' => 'El transportista indicó que llegó al punto de recogida.',
        'in_progress' => 'El servicio ya comenzó.',
        'completed' => 'El transportista marcó el servicio como completado.',
        'settled' => 'El servicio quedó cerrado correctamente.',
        'cancelled_by_customer' => 'Cancelaste esta solicitud.',
        'cancelled_by_driver' => 'El transportista canceló el servicio.',
        'expired' => 'Ningún transportista aceptó antes del vencimiento.',
        'incident' => 'El servicio requiere revisión.',
        _ => 'El estado se actualizará automáticamente.',
      };

  Future<String?> _askCancellationReason() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: TextField(
          controller: controller,
          maxLength: 240,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Indica brevemente el motivo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Confirmar cancelación'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _cancelJob() async {
    final job = _job;

    if (job == null || !job.customerCanCancel) return;

    final reason = await _askCancellationReason();

    if (!mounted || reason == null) return;

    if (reason.isEmpty) {
      setState(() {
        _error = 'Debes indicar el motivo de la cancelación.';
      });
      return;
    }

    final payloadSignature = jsonEncode({
      'job_id': job.id,
      'reason': reason,
    });

    if (_cancelPayloadSignature != payloadSignature ||
        _cancelIdempotencyKey == null) {
      _cancelPayloadSignature = payloadSignature;
      _cancelIdempotencyKey = _marketplaceUuid();
    }

    setState(() {
      _cancelling = true;
      _error = null;
    });

    try {
      await widget.service.cancelJob(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        jobId: job.id,
        reason: reason,
        idempotencyKey: _cancelIdempotencyKey!,
      );

      await _refresh();
    } catch (error) {
      if (!mounted) return;

      final value = error.toString();

      setState(() {
        _error = value.contains(
          'CUSTOMER_CANCELLATION_REQUIRES_SUPPORT',
        )
            ? 'Este servicio ya no puede cancelarse directamente.'
            : 'No pudimos cancelar la solicitud. Inténtalo otra vez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return;

    final uri = Uri.parse('https://wa.me/$digits');
    final opened = await launchUrl(uri);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos abrir WhatsApp.',
          ),
        ),
      );
    }
  }

  Future<void> _finish() async {
    await widget.onDone();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => MarketplaceCustomerShell(
          client: widget.service._client,
        ),
      ),
      (route) => false,
    );
  }

  Widget _routeCard(
    BuildContext context,
    MarketplaceCustomerJob job,
  ) {
    final service = marketplaceServiceLabel(job.serviceCode ?? '');
    return TuktukGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        children: [
          TuktukSummaryRow(
            icon: Icons.local_taxi_outlined,
            label: 'Servicio',
            value: service.isEmpty ? 'Servicio solicitado' : service,
          ),
          const Divider(color: TuktukTheme.border, height: 1),
          TuktukSummaryRow(
            icon: Icons.location_on_outlined,
            label: 'Origen',
            value: job.originText ?? 'Origen',
          ),
          const Divider(color: TuktukTheme.border, height: 1),
          TuktukSummaryRow(
            icon: Icons.flag_outlined,
            label: 'Destino',
            value: job.destinationText ?? 'Destino',
            iconColor: TuktukTheme.gold,
          ),
          const Divider(color: TuktukTheme.border, height: 1),
          TuktukSummaryRow(
            icon: Icons.payments_outlined,
            label: 'Precio',
            value: '${job.finalPrice.toStringAsFixed(0)} ${job.currency}',
            iconColor: TuktukTheme.gold,
          ),
          const Divider(color: TuktukTheme.border, height: 1),
          TuktukSummaryRow(
            icon: Icons.radar_rounded,
            label: 'Estado',
            value: _statusTitle(job.status),
          ),
        ],
      ),
    );
  }

  Widget _driverCard(
    BuildContext context,
    MarketplaceCustomerJob job,
  ) {
    final vehicleParts = <String?>[
      job.vehicleBrand,
      job.vehicleModel,
    ]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);

    final vehicleTitle = vehicleParts.isNotEmpty
        ? vehicleParts.join(' ')
        : job.vehicleName ?? 'Vehículo asignado';

    return TuktukGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tu transportista',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFF18312D),
                backgroundImage: _media?.driverPhotoSignedUrl == null
                    ? null
                    : NetworkImage(_media!.driverPhotoSignedUrl!),
                child: _media?.driverPhotoSignedUrl == null
                    ? const Icon(
                        Icons.person_outline,
                        color: TuktukTheme.mint,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.driverDisplayName ?? 'Transportista asignado',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vehicleTitle,
                      style: const TextStyle(color: TuktukTheme.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_media?.vehiclePhotoSignedUrl != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                _media!.vehiclePhotoSignedUrl!,
                height: 128,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (job.vehicleRegistration != null) ...[
            const SizedBox(height: 10),
            Text(
              'Matrícula: ${job.vehicleRegistration}',
              style: const TextStyle(color: TuktukTheme.muted),
            ),
          ],
          if (job.driverWhatsappPhone != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _openWhatsApp(job.driverWhatsappPhone!),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Contactar por WhatsApp'),
            ),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
        'published' => Icons.radar_rounded,
        'accepted' => Icons.person_pin_circle_outlined,
        'en_route' => Icons.directions_car_filled_outlined,
        'pickup' => Icons.location_on_outlined,
        'in_progress' => Icons.alt_route_rounded,
        'completed' || 'settled' => Icons.check_circle_outline_rounded,
        'cancelled_by_customer' ||
        'cancelled_by_driver' =>
          Icons.cancel_outlined,
        'expired' => Icons.timer_off_outlined,
        'incident' => Icons.warning_amber_rounded,
        _ => Icons.local_taxi_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final job = _job;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TuktukTheme.background,
        body: TuktukHavanaBackdrop(
          showLighthouse: false,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    TuktukBrandHeader(
                      trailing: IconButton(
                        tooltip: 'Actualizar',
                        onPressed: _refreshing ? null : _refresh,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : job == null
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Center(
                                    child: TuktukGlassCard(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _error ??
                                                'No pudimos cargar el servicio.',
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 16),
                                          TuktukPrimaryButton(
                                            onPressed: _refresh,
                                            label: 'Reintentar',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    6,
                                    20,
                                    26,
                                  ),
                                  children: [
                                    Text(
                                      _statusTitle(job.status),
                                      style: const TextStyle(
                                        fontSize: 34,
                                        height: 1.05,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _statusDescription(job.status),
                                      style: const TextStyle(
                                        color: TuktukTheme.muted,
                                        fontSize: 17,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: SizedBox(
                                        height: 250,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.asset(
                                              'assets/branding/tuktuk_havana_morro_tracking.png',
                                              fit: BoxFit.cover,
                                              alignment: Alignment.center,
                                            ),
                                            const DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Color(0x14000000),
                                                    Color(0x6E061118),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Align(
                                              alignment: Alignment.bottomCenter,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 18,
                                                ),
                                                child: TuktukStatusOrb(
                                                  icon: _statusIcon(job.status),
                                                  active: !job.isTerminal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: TuktukTheme.danger,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    _routeCard(context, job),
                                    const SizedBox(height: 12),
                                    if (job.hasAssignedDriver)
                                      _driverCard(context, job)
                                    else if (!job.isTerminal)
                                      const TuktukGlassCard(
                                        padding: EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              color: TuktukTheme.mint,
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Seguimos buscando un transportista disponible.',
                                                style: TextStyle(
                                                  color: TuktukTheme.text,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (job.customerCanCancel) ...[
                                      const SizedBox(height: 16),
                                      OutlinedButton.icon(
                                        onPressed:
                                            _cancelling ? null : _cancelJob,
                                        icon: const Icon(Icons.close_rounded),
                                        label: Text(
                                          _cancelling
                                              ? 'Cancelando...'
                                              : 'Cancelar solicitud',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: TuktukTheme.danger,
                                          side: const BorderSide(
                                            color: TuktukTheme.danger,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (job.isTerminal) ...[
                                      const SizedBox(height: 16),
                                      if (job.status == 'settled')
                                        _rating == null
                                            ? TuktukPrimaryButton(
                                                onPressed: () =>
                                                    _openRating(job),
                                                label:
                                                    'Calificar transportista',
                                                icon: Icons.star_outline,
                                              )
                                            : Text(
                                                'Tu calificación: ${_rating!.stars} estrellas',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: TuktukTheme.muted,
                                                ),
                                              ),
                                      if (job.status == 'settled')
                                        const SizedBox(height: 10),
                                      TuktukPrimaryButton(
                                        onPressed: _finish,
                                        label: 'Volver a servicios',
                                      ),
                                    ],
                                  ],
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

  Future<void> _openRating(MarketplaceCustomerJob job) async {
    final rating = await Navigator.of(context).push<MarketplaceCustomerRating>(
      MaterialPageRoute(
        builder: (_) => MarketplaceCustomerRatingScreen(
          service: widget.service,
          session: widget.session,
          jobId: job.id,
        ),
      ),
    );
    if (rating != null && mounted) setState(() => _rating = rating);
  }
}

class MarketplaceCustomerRatingScreen extends StatefulWidget {
  const MarketplaceCustomerRatingScreen(
      {required this.service,
      required this.session,
      required this.jobId,
      super.key});
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final String jobId;
  @override
  State<MarketplaceCustomerRatingScreen> createState() =>
      _MarketplaceCustomerRatingScreenState();
}

class _MarketplaceCustomerRatingScreenState
    extends State<MarketplaceCustomerRatingScreen> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _sending = false;
  String? _error;
  String? _idempotencyKey;
  String? _payloadSignature;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars < 1 || _stars > 5) {
      setState(() => _error = 'Selecciona entre 1 y 5 estrellas.');
      return;
    }
    final comment = _comment.text.trim();
    final payloadSignature = jsonEncode({
      'job_id': widget.jobId,
      'stars': _stars,
      'comment': comment,
    });
    if (_payloadSignature != payloadSignature || _idempotencyKey == null) {
      _payloadSignature = payloadSignature;
      _idempotencyKey = _marketplaceUuid();
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final rating = await widget.service.createRating(
          sessionId: widget.session.sessionId,
          sessionToken: widget.session.token,
          jobId: widget.jobId,
          stars: _stars,
          comment: comment.isEmpty ? null : comment,
          idempotencyKey: _idempotencyKey!);
      if (mounted) Navigator.of(context).pop(rating);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No pudimos guardar tu calificación. Inténtalo otra vez.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Calificar transportista')),
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('¿Cómo fue tu experiencia?'),
                    const SizedBox(height: 16),
                    Wrap(
                        children: List.generate(
                            5,
                            (index) => IconButton(
                                onPressed: _sending
                                    ? null
                                    : () => setState(() => _stars = index + 1),
                                icon: Icon(
                                    index < _stars
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: kTertiary),
                                tooltip: '${index + 1} estrellas'))),
                    TextField(
                        controller: _comment,
                        maxLength: 1000,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: 'Comentario (opcional)')),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: kDanger)),
                    const Spacer(),
                    FilledButton(
                        onPressed: _sending ? null : _submit,
                        child: Text(
                            _sending ? 'Enviando...' : 'Enviar calificación'))
                  ]))));
}
