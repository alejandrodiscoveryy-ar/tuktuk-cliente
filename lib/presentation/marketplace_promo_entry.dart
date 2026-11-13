part of '../main.dart';

/// Approved promotional landing: one CTA, real pickup/destination picker,
/// automatic fleet fallback. This screen does not create or publish a job.
class MarketplacePromoEntry extends StatefulWidget {
  const MarketplacePromoEntry({required this.profile, required this.mapService,
    required this.onContinue, super.key});
  final MarketplacePromoProfile profile;
  final MarketplaceMapService mapService;
  final void Function(MarketplaceMapPoint, MarketplaceMapPoint, String) onContinue;

  @override
  State<MarketplacePromoEntry> createState() => _MarketplacePromoEntryState();
}

class _MarketplacePromoEntryState extends State<MarketplacePromoEntry> {
  MarketplaceMapPoint? _origin;
  MarketplaceMapPoint? _destination;
  late String _service = widget.profile.services.first;
  bool _picking = false;

  Future<void> _pick(bool origin) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final point = await Navigator.of(context).push<MarketplaceMapPoint>(
        MaterialPageRoute(builder: (context) => Scaffold(
          appBar: AppBar(title: Text(origin ? 'Punto de recogida' : 'Destino')),
          body: SafeArea(child: MarketplaceLocationPicker(
            service: widget.mapService,
            title: origin ? 'Elige la recogida' : 'Elige el destino',
            origin: origin ? null : _origin,
            onConfirm: (value) => Navigator.of(context).pop(value),
          )),
        )),
      );
      if (!mounted || point == null) return;
      setState(() {
        if (origin) { _origin = point; } else { _destination = point; }
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _point(String label, MarketplaceMapPoint? value, bool origin) =>
      Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _picking ? null : () => _pick(origin),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
            child: Row(children: [
              Icon(Icons.location_on_outlined, color: origin
                  ? const Color(0xFF22D3EE) : const Color(0xFFFB923C)),
              const SizedBox(width: 12),
              Expanded(child: Text(value?.label ?? label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: Color(0xFFCBD5E1)))),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final photo = profile.photoUrl;
    final modality = const {'motorcycle':'Moto','bicitaxi':'Bicitaxi',
      'tricycle':'Triciclo','light_car':'Auto','van':'Furgoneta','truck':'Camión',
      'other':'Otro'}[profile.category] ?? 'Transporte';
    final subtitle = [modality, marketplaceServiceLabel(_service),
      if (profile.location != null) profile.location!].join(' · ');
    return Scaffold(
      backgroundColor: const Color(0xFF0B1017),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF141D29),
              borderRadius: BorderRadius.circular(28)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('TukTuk', style: TextStyle(color: Color(0xFFFB923C),
                  fontSize: 28, fontWeight: FontWeight.w900)),
                Text('Mi TukTuk', style: TextStyle(color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 24),
              Center(child: ClipOval(child: SizedBox(width: 126, height: 126,
                child: photo == null ? const ColoredBox(color: Color(0xFF334155),
                  child: Icon(Icons.person_outline, size: 58, color: Colors.white70))
                  : Image.network(photo, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF334155),
                      child: Icon(Icons.person_outline, size: 58, color: Colors.white70))),
              ))),
              const SizedBox(height: 16),
              Text('Viaja con ${profile.name}', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 10),
              Text(subtitle, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1))),
              if (profile.verified) ...[
                const SizedBox(height: 10),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.verified_user_outlined, color: Color(0xFF86EFAC), size: 19),
                  SizedBox(width: 6),
                  Text('Conductor verificado', style: TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w700)),
                ]),
              ],
              const SizedBox(height: 22),
              const Divider(color: Color(0xFF475569)),
              const SizedBox(height: 16),
              const Text('¿A dónde vamos hoy?', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
              if (profile.services.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _service,
                  decoration: const InputDecoration(labelText: 'Servicio'),
                  items: profile.services.map((code) => DropdownMenuItem(value: code,
                    child: Text(marketplaceServiceLabel(code)))).toList(),
                  onChanged: (value) { if (value != null) setState(() => _service = value); },
                ),
              ],
              const SizedBox(height: 16),
              _point('Punto de recogida', _origin, true),
              const SizedBox(height: 12),
              _point('¿Cuál es tu destino?', _destination, false),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA580C),
                  foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: _origin == null || _destination == null || _picking ? null
                    : () => widget.onContinue(_origin!, _destination!, _service),
                child: const Text('Solicitar transporte', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.people_outline, color: Color(0xFF94A3B8)),
                const SizedBox(width: 10),
                Expanded(child: Text('Intentaremos localizar primero a ${profile.name}. Si no está disponible, buscaremos otro conductor de TukTuk para ti.',
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1), height: 1.4))),
              ]),
            ]),
          ),
        ),
      ))),
    );
  }
}
