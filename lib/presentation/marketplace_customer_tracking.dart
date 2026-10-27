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
    extends State<MarketplaceCustomerTrackingScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  final MarketplaceCustomerArrivalGeofence _arrivalGeofence =
      MarketplaceCustomerArrivalGeofence();
  bool _arrivalNotified = false;
  String get _arrivalNoticeKey => 'arrival_notified_${widget.jobId}';

  MarketplaceCustomerJob? _job;
  MarketplaceCustomerJobMedia? _media;
  MarketplaceCustomerRating? _rating;
  String? _mediaAssignmentSignature;

  bool _loading = true;
  bool _refreshing = false;
  bool _cancelling = false;
  bool _finishing = false;
  final ValueNotifier<double> _trackingMapInset = ValueNotifier<double>(0);
  final ValueNotifier<LatLng?> _driverCameraTarget =
      ValueNotifier<LatLng?>(null);
  bool _followDriver = true;
  DateTime? _lastDriverPositionTime;
  double _trackingSheetFraction = .32;

  String? _error;
  String? _cancelPayloadSignature;
  String? _cancelIdempotencyKey;

  @override
  void initState() {
    super.initState();

    try {
      _arrivalNotified = Hive.box(_metaBox).get(_arrivalNoticeKey) == true;
    } catch (_) {
      _arrivalNotified = false;
    }
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_job?.isTerminal == true) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _refresh();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _trackingMapInset.dispose();
    _driverCameraTarget.dispose();
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
      _observeArrival(job);
      _updateDriverCamera(job);

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
    } on FunctionsHttpException catch (error) {
      final details = error.details;
      final detailText = details is Map && details['error'] != null
          ? details['error'].toString()
          : details?.toString();

      final invalidSession =
          detailText?.contains('CUSTOMER_SESSION_NOT_FOUND') == true ||
              detailText?.contains('CUSTOMER_SESSION_EXPIRED') == true ||
              detailText?.contains('CUSTOMER_SESSION_INVALID') == true;

      if (invalidSession) {
        _pollTimer?.cancel();
        await _resetInvalidSession();
        return;
      }

      final staleJob = detailText?.contains('ACCESS_DENIED') == true ||
          detailText?.contains('JOB_NOT_FOUND') == true;

      if (staleJob) {
        _pollTimer?.cancel();
        await _finish();
        return;
      }

      if (!mounted) return;

      setState(() {
        _error = 'No pudimos actualizar el estado. Revisa tu conexión.';
      });
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

  void _updateDriverCamera(MarketplaceCustomerJob job) {
    if (!_followDriver) return;
    final gps = job.driverLocation;
    if (gps == null || !gps.isFresh || gps.capturedAt == null) return;
    if (_lastDriverPositionTime == gps.capturedAt) return;
    _lastDriverPositionTime = gps.capturedAt;
    _driverCameraTarget.value = LatLng(gps.latitude, gps.longitude);
  }

  void _recenterOnDriver() {
    final gps = _job?.driverLocation;
    if (gps == null || !gps.isFresh) return;
    setState(() => _followDriver = true);
    _lastDriverPositionTime = gps.capturedAt;
    _driverCameraTarget.value = LatLng(gps.latitude, gps.longitude);
  }

  void _onCustomerMapMoved(LatLng center) {
    if (!mounted || !_followDriver) return;
    setState(() => _followDriver = false);
  }

  MarketplaceMapPoint? _pickupForArrival() {
    try {
      final route = MarketplaceCustomerSessionStore(
        Hive.box(_metaBox),
      ).readActiveJobMap(widget.jobId);
      final origin = route?['origin'];
      if (origin is Map) {
        return MarketplaceMapPoint.fromMap(Map<String, dynamic>.from(origin));
      }
    } catch (_) {
      // Nunca inferir una recogida sin coordenadas verificadas.
    }
    return null;
  }

  Future<void> _playArrivalSound() async {
    await customer_arrival_sound.playArrivalClaxon();
  }

  void _observeArrival(MarketplaceCustomerJob job) {
    if (_arrivalNotified) return;
    final arrived = _arrivalGeofence.observe(
      status: job.status,
      location: job.driverLocation,
      pickup: _pickupForArrival(),
      now: DateTime.now().toUtc(),
    );
    if (!arrived || !mounted) return;
    setState(() => _arrivalNotified = true);
    try {
      unawaited(Hive.box(_metaBox).put(_arrivalNoticeKey, true));
    } catch (_) {
      // El aviso visible permanece aunque falle la persistencia local.
    }
    unawaited(_playArrivalSound());
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

  Future<void> _finishJob() async {
    final job = _job;

    if (job == null || !job.customerCanFinish || _finishing || _cancelling) {
      return;
    }

    setState(() => _finishing = true);
    try {
      await _openRating(job);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
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

    final payloadSignature = jsonEncode({'job_id': job.id, 'reason': reason});

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
        _error = value.contains('CUSTOMER_CANCELLATION_REQUIRES_SUPPORT')
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
        const SnackBar(content: Text('No pudimos abrir WhatsApp.')),
      );
    }
  }

  void _returnToCustomerShell() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) =>
            MarketplaceCustomerShell(client: widget.service._client),
      ),
      (route) => false,
    );
  }

  Future<void> _resetInvalidSession() async {
    final sessionStore = MarketplaceCustomerSessionStore(Hive.box(_metaBox));

    await sessionStore.clear();

    if (!mounted) return;

    _returnToCustomerShell();
  }

  Future<void> _finish() async {
    await widget.onDone();

    if (!mounted) return;

    _returnToCustomerShell();
  }

  Widget _routeCard(BuildContext context, MarketplaceCustomerJob job) {
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

  Widget _driverCard(BuildContext context, MarketplaceCustomerJob job) {
    final vehicleParts = <String?>[job.vehicleBrand, job.vehicleModel]
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
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
                    ? const Icon(Icons.person_outline, color: TuktukTheme.mint)
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

  Widget _liveMap() {
    Map<String, dynamic>? stored;
    try {
      stored = MarketplaceCustomerSessionStore(
        Hive.box(_metaBox),
      ).readActiveJobMap(widget.jobId);
    } catch (_) {
      // La vista también debe funcionar si el almacenamiento local no carga.
    }
    if (stored != null && MarketplaceMapService.publicToken.startsWith('pk.')) {
      try {
        final origin = MarketplaceMapPoint.fromMap(
          Map<String, dynamic>.from(stored['origin'] as Map),
        );
        final destination = MarketplaceMapPoint.fromMap(
          Map<String, dynamic>.from(stored['destination'] as Map),
        );
        final rawPoints = stored['route_points'];
        final points = rawPoints is List
            ? rawPoints
                .whereType<Map>()
                .map((point) => MarketplaceMapPoint.fromMap(point))
                .toList(growable: false)
            : <MarketplaceMapPoint>[];
        final gps = _job?.driverLocation;
        final driverPoint = gps != null && gps.isFresh
            ? MarketplaceMapPoint(
                label: 'Conductor',
                lat: gps.latitude,
                lon: gps.longitude,
              )
            : null;
        final distance = (stored['distance_km'] as num?)?.toDouble() ?? 0;
        // El mapa de seguimiento ocupa la zona visible superior, no la
        // pantalla completa bajo la ficha. Adaptar el zoom a esa altura.
        final zoom = distance <= 3
            ? 12.3
            : distance <= 8
                ? 11.3
                : 10.3;
        return MarketplaceVectorMap(
          initialCenter: LatLng(
            (origin.lat + destination.lat) / 2,
            (origin.lon + destination.lon) / 2,
          ),
          initialZoom: zoom,
          ornamentBottomInset: _trackingMapInset,
          requestedCenter: _driverCameraTarget,
          requestedZoom: 14.0,
          onCenterMoved: _onCustomerMapMoved,
          driverPoint: driverPoint,
          originPoint: origin,
          destinationPoint: destination,
          routePoints: points,
        );
      } catch (_) {
        // Si la caché no es válida, nunca inventar coordenadas.
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/branding/tuktuk_havana_morro_tracking.png',
          fit: BoxFit.cover,
        ),
        const DecoratedBox(decoration: BoxDecoration(color: Color(0x7B050B10))),
        const Align(
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'El mapa de esta carrera no está disponible en este dispositivo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _liveDriverSummary(MarketplaceCustomerJob job) {
    final vehicleParts = <String?>[
      job.vehicleBrand,
      job.vehicleModel,
    ].whereType<String>().where((text) => text.trim().isNotEmpty).toList();
    final vehicleName = vehicleParts.isNotEmpty
        ? vehicleParts.join(' ')
        : (job.vehicleName ?? 'Vehículo asignado');
    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: TuktukTheme.backgroundSoft,
              backgroundImage: _media?.driverPhotoSignedUrl == null
                  ? null
                  : NetworkImage(_media!.driverPhotoSignedUrl!),
              child: _media?.driverPhotoSignedUrl == null
                  ? const Icon(
                      Icons.person_outline_rounded,
                      color: TuktukTheme.mint,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.driverDisplayName ?? 'Transportista asignado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    job.vehicleRegistration == null
                        ? vehicleName
                        : '$vehicleName · ${job.vehicleRegistration}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TuktukTheme.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (_media?.vehiclePhotoSignedUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _media!.vehiclePhotoSignedUrl!,
                  width: 56,
                  height: 43,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 56),
                ),
              ),
          ],
        ),
        if (job.driverWhatsappPhone != null) ...[
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openWhatsApp(job.driverWhatsappPhone!),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('Contactar por WhatsApp'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _trackingActionFooter(MarketplaceCustomerJob job) {
    final settled = job.status == 'settled';
    final pendingRating = settled && _rating == null;
    final canFinish = job.customerCanFinish;
    // La interfaz usa exactamente los estados cancelables aprobados.
    final canCancel = job.customerCanCancel;
    if (!canFinish && !canCancel && !job.isTerminal && !pendingRating) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(17, 10, 17, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF018333C), Color(0xF5081720)],
        ),
        border: Border(top: BorderSide(color: Color(0x8866A5AB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canFinish)
            TuktukPrimaryButton(
              onPressed: _finishing || _cancelling ? null : _finishJob,
              label: _finishing ? 'Finalizando...' : 'Finalizar carrera',
              icon: Icons.check_circle_outline_rounded,
            ),
          if (pendingRating)
            TuktukPrimaryButton(
              onPressed: _finishing ? null : () => _openRating(job),
              label: 'Calificar transportista',
              icon: Icons.star_outline_rounded,
            ),
          if (job.isTerminal && !pendingRating)
            TuktukPrimaryButton(
              onPressed: _finish,
              label: 'Solicitar otro transporte',
              icon: Icons.arrow_forward_rounded,
            ),
          if (pendingRating)
            TextButton(
              onPressed: _finish,
              child: const Text('Solicitar otro transporte'),
            ),
          if (canCancel)
            TextButton.icon(
              onPressed: _cancelling || _finishing ? null : _cancelJob,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(_cancelling ? 'Cancelando...' : 'Cancelar solicitud'),
              style: TextButton.styleFrom(
                foregroundColor: TuktukTheme.danger,
                minimumSize: const Size.fromHeight(42),
              ),
            ),
        ],
      ),
    );
  }

  Widget _liveSheet(MarketplaceCustomerJob job, ScrollController scroller) {
    final terminal = job.isTerminal;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE8173742), Color(0xEC081720)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: TuktukTheme.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroller,
                padding: const EdgeInsets.fromLTRB(17, 10, 17, 18),
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: TuktukTheme.border,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        _statusIcon(job.status),
                        color: terminal ? TuktukTheme.gold : TuktukTheme.mint,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _statusTitle(job.status),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _statusDescription(job.status),
                    style: const TextStyle(
                      color: TuktukTheme.muted,
                      fontSize: 13,
                    ),
                  ),
                  if (job.hasAssignedDriver &&
                      const {'accepted', 'en_route', 'pickup', 'in_progress'}
                          .contains(job.status)) ...[
                    const SizedBox(height: 6),
                    Text(
                      job.driverLocation?.isFresh == true
                          ? 'Ubicación del conductor actualizada'
                          : 'Ubicación del conductor temporalmente no disponible',
                      style: const TextStyle(
                          color: TuktukTheme.muted, fontSize: 12),
                    ),
                  ],
                  if (_arrivalNotified &&
                      const {'accepted', 'en_route', 'pickup'}
                          .contains(job.status)) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF174A43),
                        border: Border.all(color: TuktukTheme.mint, width: 1.3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.notifications_active_rounded,
                              color: TuktukTheme.mint, size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Tu conductor está cerca',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900)),
                                SizedBox(height: 4),
                                Text(
                                    'El GPS lo sitúa en la zona de recogida. '
                                    'Comprueba el vehículo y contacta si es necesario.',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!_arrivalNotified &&
                      const {'accepted', 'en_route', 'pickup'}
                          .contains(job.status)) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => unawaited(_playArrivalSound()),
                        icon: const Icon(Icons.volume_up_rounded, size: 18),
                        label: const Text('Activar y probar claxon'),
                      ),
                    ),
                  ],
                  if (job.status == 'published' ||
                      job.status == 'requested') ...[
                    const SizedBox(height: 11),
                    const LinearProgressIndicator(
                      minHeight: 3,
                      color: TuktukTheme.mint,
                      backgroundColor: TuktukTheme.border,
                    ),
                  ],
                  if (job.hasAssignedDriver) ...[
                    const SizedBox(height: 12),
                    _liveDriverSummary(job),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.flag_outlined,
                        size: 19,
                        color: TuktukTheme.gold,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          job.destinationText ?? 'Destino',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${job.finalPrice.toStringAsFixed(0)} ${job.currency}',
                        style: const TextStyle(
                          color: TuktukTheme.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: TuktukTheme.danger),
                    ),
                  ],
                  if (job.status == 'settled' && _rating != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Tu calificación: ${_rating!.stars} estrellas',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Detalles del servicio',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      _routeCard(context, job),
                      if (job.hasAssignedDriver) ...[
                        const SizedBox(height: 10),
                        _driverCard(context, job),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            _trackingActionFooter(job),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final searching = job?.status == 'published' || job?.status == 'requested';
    final assigned = job != null &&
        const {'accepted', 'en_route', 'pickup'}.contains(job.status);
    final initialSheetSize = searching
        ? .32
        : assigned
            ? .37
            : .40;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TuktukTheme.background,
        body: SafeArea(
          child: Stack(
            children: [
              // El mapa ocupa todo el fondo; la ficha flota sobre el.
              // Nunca recortar el mapa a la altura de la ficha.
              Positioned.fill(child: _liveMap()),
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Color(0x52050B10), Color(0x00050B10)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TuktukBrandHeader(
                  trailing: IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _refreshing ? null : _refresh,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (job?.hasAssignedDriver == true &&
                  job?.driverLocation?.isFresh == true)
                Positioned(
                  top: 76,
                  right: 12,
                  child: Material(
                    color: TuktukTheme.backgroundSoft,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: TextButton.icon(
                      onPressed: _recenterOnDriver,
                      icon: Icon(
                        _followDriver ? Icons.gps_fixed : Icons.my_location,
                        size: 18,
                      ),
                      label: Text(
                        _followDriver
                            ? 'Siguiendo conductor'
                            : 'Seguir conductor',
                      ),
                    ),
                  ),
                ),
              if (job == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: TuktukGlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_loading)
                            const CircularProgressIndicator()
                          else
                            Text(_error ?? 'No pudimos cargar el servicio.'),
                          const SizedBox(height: 12),
                          TuktukPrimaryButton(
                            onPressed: _refreshing ? null : _refresh,
                            label: 'Reintentar',
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Align(
                  alignment: Alignment.bottomCenter,
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notice) {
                      _trackingSheetFraction = notice.extent;
                      final height =
                          MediaQuery.sizeOf(context).height * notice.extent;
                      if ((_trackingMapInset.value - height).abs() > 2) {
                        _trackingMapInset.value = height;
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      key: ValueKey<String>(job.status),
                      initialChildSize: initialSheetSize,
                      minChildSize: initialSheetSize,
                      maxChildSize: .82,
                      expand: false,
                      snap: true,
                      snapSizes: const [.82],
                      builder: (context, scroller) => _liveSheet(job, scroller),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRating(MarketplaceCustomerJob job) async {
    // La ficha y el mapa permanecen en la misma pantalla.
    // Los creditos Mapbox se mantienen en la parte libre del mapa.
    final height = MediaQuery.sizeOf(context).height;
    _trackingMapInset.value = height * .68;
    MarketplaceCustomerRating? rating;
    try {
      rating = await showModalBottomSheet<MarketplaceCustomerRating>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final viewport = MediaQuery.sizeOf(sheetContext).height;
          final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
          final allowedHeight =
              (viewport - keyboard - 12).clamp(0.0, viewport).toDouble();
          final contentHeight =
              (viewport * .66).clamp(0.0, allowedHeight).toDouble();
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              height: contentHeight,
              child: MarketplaceCustomerRatingScreen(
                service: widget.service,
                session: widget.session,
                jobId: job.id,
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) _trackingMapInset.value = height * _trackingSheetFraction;
    }
    if (rating != null && mounted) {
      setState(() => _rating = rating);
      await _refresh();
    }
  }
}

class MarketplaceCustomerRatingScreen extends StatefulWidget {
  const MarketplaceCustomerRatingScreen({
    required this.service,
    required this.session,
    required this.jobId,
    super.key,
  });
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;
  final String jobId;
  @override
  State<MarketplaceCustomerRatingScreen> createState() =>
      _MarketplaceCustomerRatingScreenState();
}

class MarketplaceCustomerHistory extends StatefulWidget {
  const MarketplaceCustomerHistory({
    required this.service,
    required this.session,
    super.key,
  });
  final MarketplaceCustomerService service;
  final MarketplaceCustomerSessionSnapshot session;

  @override
  State<MarketplaceCustomerHistory> createState() =>
      _MarketplaceCustomerHistoryState();
}

class _MarketplaceCustomerHistoryState
    extends State<MarketplaceCustomerHistory> {
  final _jobs = <MarketplaceCustomerJob>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.history(
        sessionId: widget.session.sessionId,
        sessionToken: widget.session.token,
        before: _jobs.isEmpty ? null : _jobs.last,
      );
      if (!mounted) return;
      setState(() {
        final ids = _jobs.map((j) => j.id).toSet();
        _jobs.addAll(page.where((j) => ids.add(j.id)));
        _hasMore = page.length == 50;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos cargar el historial. Reintenta.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Historial',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar historial',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final job in _jobs)
                ListTile(
                  title: Text(
                    '${job.originText ?? 'Origen'} → ${job.destinationText ?? 'Destino'}',
                  ),
                  subtitle: Text('${job.finalPrice} ${job.currency}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(job),
                ),
              if (_error != null) Text(_error!),
              if (!_loading && _jobs.isEmpty && _error == null)
                const Text('Todavía no tienes carreras finalizadas.'),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_hasMore && !_loading)
                TextButton(
                  onPressed: _loadMore,
                  child: Text(
                    _error == null ? 'Cargar más historial' : 'Reintentar',
                  ),
                ),
            ],
          ),
        ),
      );
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
        idempotencyKey: _idempotencyKey!,
      );
      if (mounted) Navigator.of(context).pop(rating);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No pudimos guardar tu calificación. Inténtalo otra vez.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
          border: Border.all(color: TuktukTheme.border),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF01A3D45), Color(0xFA071722)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Align(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TuktukTheme.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: TuktukTheme.gold),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Calificar transportista',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar calificación',
                      onPressed:
                          _sending ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                  children: [
                    const Text(
                      '¿Cómo fue tu experiencia?',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tu valoración ayuda a mejorar el servicio.',
                      style: TextStyle(color: TuktukTheme.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceEvenly,
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
                            size: 38,
                            color: TuktukTheme.gold,
                          ),
                          tooltip: '${index + 1} estrellas',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _comment,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Comentario (opcional)',
                        hintText: 'Cuéntanos cómo fue tu viaje',
                      ),
                    ),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: kDanger)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 9, 18, 14),
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: TuktukTheme.gold,
                    foregroundColor: TuktukTheme.background,
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  child: Text(_sending ? 'Enviando...' : 'Enviar calificación'),
                ),
              ),
            ],
          ),
        ),
      );
}
