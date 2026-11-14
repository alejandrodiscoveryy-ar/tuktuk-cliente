part of '../main.dart';

/// Approved personalized landing. Direct address search and optional map picker,
/// and the orange action opens the usual quote/payment flow, never publishes
/// a ride before the customer sees the price and confirms.
class MarketplacePromoEntry extends StatelessWidget {
  const MarketplacePromoEntry({
    required this.profile, required this.origin, required this.destination,
    required this.onOrigin, required this.onDestination, required this.onContinue,
    this.onServiceChanged, required this.serviceCode, required this.mapService,
    required this.onOriginSelected, required this.onDestinationSelected, super.key,
  });
  final MarketplacePromoProfile profile;
  final MarketplaceMapPoint? origin, destination;
  final VoidCallback onOrigin, onDestination, onContinue;
  final ValueChanged<String>? onServiceChanged;
  final String serviceCode;
  final MarketplaceMapService mapService;
  final ValueChanged<MarketplaceMapPoint?> onOriginSelected, onDestinationSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101923),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF141D29),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('TukTuk', style: TextStyle(color: Color(0xFFFB923C), fontSize: 30, fontWeight: FontWeight.w900)),
                  Text('Mi TukTuk', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
                const SizedBox(height: 24),
                Center(child: ClipOval(child: SizedBox(width: 128, height: 128,
                  child: profile.photoUrl == null
                    ? const ColoredBox(color: Color(0xFF1E293B), child: Icon(Icons.person_outline, size: 64, color: Color(0xFF94A3B8)))
                    : Image.network(profile.photoUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1E293B), child: Icon(Icons.person_outline, size: 64, color: Color(0xFF94A3B8))),
                        loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: Color(0xFF1E293B), child: Center(child: CircularProgressIndicator())),
                      ),
                ))),
                const SizedBox(height: 16),
                Text('Viaja con ${profile.name}', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Text([marketplacePassengerVehicleLabel(profile.category), marketplaceServiceLabel(serviceCode), if (profile.city != null) profile.city!].join(' · '),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1))),
                if (profile.verified) ...[
                  const SizedBox(height: 12),
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.verified_user_outlined, color: Color(0xFF86EFAC), size: 20),
                    SizedBox(width: 6),
                    Flexible(child: Text('Conductor verificado', style: TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w700, fontSize: 16))),
                  ]),
                ],
                const SizedBox(height: 22),
                const Divider(color: Color(0xFF475569)),
                const SizedBox(height: 12),
                const Text('¿A dónde vamos hoy?', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
                if (profile.services.length > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 7, runSpacing: 6, alignment: WrapAlignment.center, children: [
                    for (final code in ['passenger', ...profile.services.where((s) => s != 'passenger')].where(profile.services.contains))
                      ChoiceChip(label: Text(marketplaceServiceLabel(code)), selected: serviceCode == code,
                        onSelected: (_) => onServiceChanged?.call(code)),
                  ]),
                ],
                const SizedBox(height: 16),
                _PromoAddressInput(service: mapService, label: 'Punto de recogida', point: origin,
                  color: const Color(0xFF22D3EE), onSelected: onOriginSelected, onMap: onOrigin, allowGps: true),
                const SizedBox(height: 12),
                _PromoAddressInput(service: mapService, label: '¿Cuál es tu destino?', point: destination,
                  proximity: origin, color: const Color(0xFFFB923C), onSelected: onDestinationSelected, onMap: onDestination),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA580C), foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: onContinue,
                  child: const Text('Solicitar transporte', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.people_outline, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Intentaremos localizar primero a ${profile.name}. Si no está disponible, buscaremos otro conductor de TukTuk para ti.',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, fontWeight: FontWeight.w600, height: 1.4))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ),
  );

}

class _PromoAddressInput extends StatefulWidget {
  const _PromoAddressInput({required this.service, required this.label,
    required this.point, required this.color, required this.onSelected,
    required this.onMap, this.proximity, this.allowGps = false});

  final MarketplaceMapService service;
  final String label;
  final MarketplaceMapPoint? point, proximity;
  final Color color;
  final ValueChanged<MarketplaceMapPoint?> onSelected;
  final VoidCallback onMap;
  final bool allowGps;

  @override
  State<_PromoAddressInput> createState() => _PromoAddressInputState();
}

class _PromoAddressInputState extends State<_PromoAddressInput> {
  late final TextEditingController _controller;
  Timer? _debounce;
  int _revision = 0;
  bool _busy = false;
  String? _message;
  List<MarketplaceMapPoint> _results = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.point?.label ?? '');
  }

  @override
  void didUpdateWidget(covariant _PromoAddressInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final point = widget.point;
    if (point != null && point != oldWidget.point) {
      _debounce?.cancel();
      _revision++;
      _controller.text = point.label;
      _results = const [];
      _busy = false;
      _message = null;
    }
  }

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final revision = ++_revision;
    final query = value.trim();
    if (widget.point != null) widget.onSelected(null);
    setState(() {
      _results = const [];
      _message = null;
      _busy = query.length >= 3;
    });
    if (query.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final results = await widget.service.search(query, proximity: widget.proximity)
            .timeout(const Duration(seconds: 12));
        if (!mounted || revision != _revision) return;
        setState(() {
          _results = results.take(5).toList(growable: false);
          _message = results.isEmpty ? 'No encontramos esa dirección. Prueba otra búsqueda o usa el mapa.' : null;
          _busy = false;
        });
      } catch (_) {
        if (!mounted || revision != _revision) return;
        setState(() {
          _message = 'No pudimos buscar esa dirección. Intenta de nuevo o usa el mapa.';
          _busy = false;
        });
      }
    });
  }

  void _choose(MarketplaceMapPoint point) {
    _revision++;
    _debounce?.cancel();
    _controller.text = point.label;
    setState(() {
      _results = const [];
      _busy = false;
      _message = null;
    });
    widget.onSelected(point);
  }

  Future<void> _useGps() async {
    _debounce?.cancel();
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _results = const [];
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('LOCATION_DISABLED');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('LOCATION_DENIED');
      }
      if (!mounted || revision != _revision) return;
      final position = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15));
      if (!mounted || revision != _revision) return;
      final gps = MarketplaceMapPoint(label: 'Mi ubicación actual', lat: position.latitude, lon: position.longitude);
      var point = gps;
      try {
        final address = await widget.service.reverse(gps).timeout(const Duration(seconds: 6));
        // Keep the actual GPS coordinates, not a potentially shifted geocoder result.
        point = MarketplaceMapPoint(label: address.label, lat: gps.lat, lon: gps.lon);
      } catch (_) {
        // Valid GPS coordinates remain usable if reverse geocoding is unavailable.
      }
      if (!mounted || revision != _revision) return;
      _choose(point);
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _busy = false;
        _message = 'No pudimos obtener tu ubicación. Escribe tu dirección o usa el mapa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _controller,
        onChanged: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'Escribe una dirección',
          prefixIcon: Icon(Icons.location_on_outlined, color: widget.color),
          suffixIcon: widget.point != null ? Icon(Icons.check_circle_outline, color: widget.color) : null,
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      Wrap(spacing: 8, children: [
        if (widget.allowGps)
          TextButton.icon(onPressed: _busy ? null : () => unawaited(_useGps()),
            icon: const Icon(Icons.my_location), label: const Text('Usar mi ubicación GPS')),
        TextButton.icon(onPressed: () {
          _revision++;
          _debounce?.cancel();
          setState(() { _busy = false; _results = const []; _message = null; });
          widget.onMap();
        }, icon: const Icon(Icons.map_outlined), label: Text(widget.allowGps ? 'Origen en el mapa' : 'Destino en el mapa')),
      ]),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_message!,
          style: const TextStyle(color: Color(0xFFCBD5E1)))),
      for (final result in _results)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.place_outlined, color: widget.color),
          title: Text(result.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _choose(result),
        ),
    ],
  );
}
