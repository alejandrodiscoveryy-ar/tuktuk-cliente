part of '../main.dart';

/// Public, non-personal market snapshot. Not used to price a ride.
@visibleForTesting
class MarketplacePublicEltoqueRate {
  const MarketplacePublicEltoqueRate({
    required this.rate,
    required this.fresh,
    required this.available,
    required this.baseCurrency,
    required this.chargeCurrency,
    this.previousRate,
    this.checkedAt,
    this.changedAt,
  });

  final double rate;
  final double? previousRate;
  final bool fresh;
  final bool available;
  final String baseCurrency;
  final String chargeCurrency;
  final DateTime? checkedAt;
  final DateTime? changedAt;

  double? get change => previousRate == null ? null : rate - previousRate!;

  bool get canDisplay =>
      fresh &&
      available &&
      rate > 0 &&
      baseCurrency == 'USD' &&
      chargeCurrency == 'CUP' &&
      checkedAt != null &&
      !checkedAt!.isBefore(DateTime.now().toUtc().subtract(
            const Duration(hours: 2),
          ));

  static MarketplacePublicEltoqueRate? parse(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['rate'];
    final current = value is num ? value.toDouble() : double.tryParse('$value');
    if (current == null || !current.isFinite || current <= 0) return null;
    final old = raw['previous_rate'];
    final previous = old == null
        ? null
        : (old is num ? old.toDouble() : double.tryParse('$old'));
    return MarketplacePublicEltoqueRate(
      rate: current,
      previousRate: previous != null && previous.isFinite ? previous : null,
      fresh: raw['fresh'] == true,
      available: raw['available'] == true,
      baseCurrency: '${raw['base_currency'] ?? ''}',
      chargeCurrency: '${raw['charge_currency'] ?? ''}',
      checkedAt: _marketDate(raw['checked_at']),
      changedAt: _marketDate(raw['changed_at']),
    );
  }
}

@visibleForTesting
String marketplaceEltoqueAmount(double amount) {
  if (!amount.isFinite) return '—';
  final decimals = amount == amount.roundToDouble() ? 0 : 2;
  return amount.toStringAsFixed(decimals);
}

@visibleForTesting
String marketplaceEltoqueRateLabel(double value) =>
    '1 USD = ${marketplaceEltoqueAmount(value)} CUP';

class TuktukCustomerHomeWithRate extends StatelessWidget {
  const TuktukCustomerHomeWithRate({required this.client, super.key});
  final SupabaseClient client;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TuktukCustomerEltoqueBanner(client: client),
          Expanded(child: MarketplaceCustomerShell(client: client)),
        ],
      );
}

class TuktukCustomerEltoqueBanner extends StatefulWidget {
  const TuktukCustomerEltoqueBanner({required this.client, super.key});
  final SupabaseClient client;

  @override
  State<TuktukCustomerEltoqueBanner> createState() =>
      _TuktukCustomerEltoqueBannerState();
}

class _TuktukCustomerEltoqueBannerState
    extends State<TuktukCustomerEltoqueBanner> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  Timer? _initialRateTimer;
  bool _appVisible = true;
  StreamSubscription<RemoteMessage>? _pushMessages;
  late final CustomerRatePushClient _pushClient;
  bool _pushEnabled = false;
  bool _pushReady = false;
  bool _pushInitUnavailable = false;
  bool _pushBusy = false;
  String? _pushError;
  MarketplacePublicEltoqueRate? _snapshot;
  bool _loading = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushClient = CustomerRatePushClient(widget.client);
    _pushEnabled = _pushClient.hasSavedSubscription;
    if (kIsWeb) unawaited(_enablePushWhenReady());
    // La tasa es solo informativa: no competir con la carga de carreras.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialRateTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) unawaited(_refresh());
      });
    });
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _enablePushWhenReady() async {
    final ready = await customerFirebaseReady;
    if (!mounted) return;
    if (!ready) {
      setState(() => _pushInitUnavailable = true);
      return;
    }

    setState(() => _pushReady = true);
    if (_pushEnabled) unawaited(_pushClient.refreshExisting());

    try {
      _pushMessages = FirebaseMessaging.onMessage.listen((message) {
        if (message.data['kind'] != 'customer_exchange_rate_update') return;
        unawaited(_refresh());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'elTOQUE: la tasa ha cambiado. Consulta la franja superior.'),
          ));
        }
      });
    } catch (_) {
      // Los avisos opcionales no afectan viajes, mapas ni tarifas.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    if (_appVisible) {
      _initialRateTimer?.cancel();
      _initialRateTimer = null;
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _initialRateTimer?.cancel();
    _refreshTimer?.cancel();
    _pushMessages?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _toggleAlerts() async {
    if (_pushBusy) return;
    setState(() {
      _pushBusy = true;
      _pushError = null;
    });
    try {
      if (_pushEnabled) {
        await _pushClient.deactivate();
      } else {
        await _pushClient.activate();
      }
      if (!mounted) return;
      setState(() => _pushEnabled = _pushClient.hasSavedSubscription);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pushError =
          'No se pudieron cambiar las alertas. Comprueba los permisos o intenta luego.');
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading || !_appVisible) return;
    _loading = true;
    try {
      final raw = await widget.client
          .rpc('marketplace_public_eltoque_rate')
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _snapshot = MarketplacePublicEltoqueRate.parse(raw));
    } catch (_) {
      if (!mounted) return;
      setState(() => _snapshot = null);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = _snapshot;
    final valid = rate?.canDisplay ?? false;
    final delta = valid ? rate!.change : null;
    final directionColor = delta == null || delta == 0
        ? TuktukTheme.muted
        : delta > 0
            ? TuktukTheme.mint
            : TuktukTheme.danger;
    final marker = delta == null || delta == 0
        ? '—'
        : delta > 0
            ? '↑'
            : '↓';
    final directionText = delta == null || delta == 0
        ? ''
        : ' $marker${marketplaceEltoqueAmount(delta.abs())}';
    final text = valid
        ? marketplaceEltoqueRateLabel(rate!.rate)
        : 'Tasa no disponible';

    return Material(
      color: const Color(0xFF101A21),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const Key('eltoque-banner-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_exchange_rounded,
                          size: 17, color: TuktukTheme.gold),
                      const SizedBox(width: 7),
                      const Text('elTOQUE',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: TuktukTheme.gold)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: TuktukTheme.text)),
                      ),
                      if (valid && delta != null && delta != 0)
                        Text(directionText,
                            style: TextStyle(
                                color: directionColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      const SizedBox(width: 5),
                      Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: TuktukTheme.muted),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valid
                        ? 'Fuente: elTOQUE. Valor referencial. '
                            'Última consulta: ${DateFormat("dd/MM HH:mm").format(rate!.checkedAt!.toLocal())}.'
                        : 'No hay una tasa reciente verificada. Intenta más tarde.',
                    style: const TextStyle(
                        fontSize: 11.5, color: TuktukTheme.muted),
                  ),
                ),
              ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: _pushBusy || (!_pushReady && !_pushEnabled) ? null : _toggleAlerts,
                      icon: Icon(_pushEnabled
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined),
                      label: Text(_pushBusy
                          ? 'Comprobando...'
                          : _pushEnabled
                              ? 'Desactivar alertas'
                              : _pushInitUnavailable
                                  ? 'Alertas no disponibles'
                                  : !_pushReady
                                      ? 'Preparando alertas...'
                                      : 'Activar alertas gratuitas'),
                    ),
                    if (_pushError != null)
                      Text(_pushError!,
                          style: const TextStyle(
                              fontSize: 12, color: TuktukTheme.danger)),
                    if (!_pushEnabled)
                      const Text(
                          'Recibe un aviso cuando cambie la tasa. '
                          'Sin cuenta, sin pagos y solo con tu permiso.',
                          style: TextStyle(
                              fontSize: 11.5, color: TuktukTheme.muted)),
                  ],
                ),
              ),
            const Divider(height: 1, color: TuktukTheme.border),
          ],
        ),
      ),
    );
  }
}
