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

    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  Widget _routeCard(
    BuildContext context,
    MarketplaceCustomerJob job,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tu solicitud',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Text(
              job.originText ?? 'Origen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.arrow_downward_rounded),
            ),
            Text(
              job.destinationText ?? 'Destino',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              '${job.finalPrice.toStringAsFixed(0)} ${job.currency}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tu transportista',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: _media?.driverPhotoSignedUrl == null
                      ? null
                      : NetworkImage(_media!.driverPhotoSignedUrl!),
                  child: _media?.driverPhotoSignedUrl == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    job.driverDisplayName ?? 'Transportista asignado',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_media?.vehiclePhotoSignedUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _media!.vehiclePhotoSignedUrl!,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(vehicleTitle),
            if (job.vehicleRegistration != null) ...[
              const SizedBox(height: 4),
              Text(
                'Matrícula: ${job.vehicleRegistration}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: kMuted),
              ),
            ],
            if (job.driverWhatsappPhone != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _openWhatsApp(
                  job.driverWhatsappPhone!,
                ),
                icon: const Icon(Icons.chat_outlined),
                label: const Text(
                  'Contactar por WhatsApp',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Tu servicio'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _refreshing ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : job == null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _error ?? 'No pudimos cargar el servicio.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _refresh,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              _statusTitle(job.status),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusDescription(job.status),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: kMuted),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: kDanger,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _routeCard(context, job),
                            const SizedBox(height: 16),
                            if (job.hasAssignedDriver)
                              _driverCard(context, job)
                            else if (!job.isTerminal)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    'Aún estamos buscando un '
                                    'transportista disponible.',
                                  ),
                                ),
                              ),
                            if (job.customerCanCancel) ...[
                              const SizedBox(height: 24),
                              OutlinedButton.icon(
                                onPressed: _cancelling ? null : _cancelJob,
                                icon: const Icon(
                                  Icons.close_rounded,
                                ),
                                label: Text(
                                  _cancelling
                                      ? 'Cancelando...'
                                      : 'Cancelar solicitud',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kDanger,
                                ),
                              ),
                            ],
                            if (job.isTerminal) ...[
                              const SizedBox(height: 24),
                              if (job.status == 'settled')
                                _rating == null
                                    ? FilledButton.icon(
                                        onPressed: () => _openRating(job),
                                        icon: const Icon(Icons.star_outline),
                                        label: const Text(
                                            'Calificar transportista'),
                                      )
                                    : Text(
                                        'Tu calificación: ${_rating!.stars} estrellas',
                                        textAlign: TextAlign.center,
                                      ),
                              if (job.status == 'settled')
                                const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _finish,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    'Volver a servicios',
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 24),
                              Text(
                                'Esta pantalla se actualiza '
                                'automáticamente.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: kMuted),
                              ),
                            ],
                          ],
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
