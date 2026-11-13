part of '../main.dart';

/// Approved personalized landing. Address selection uses the existing picker,
/// and the orange action opens the usual quote/payment flow, never publishes
/// a ride before the customer sees the price and confirms.
class MarketplacePromoEntry extends StatelessWidget {
  const MarketplacePromoEntry({
    required this.profile, required this.origin, required this.destination,
    required this.onOrigin, required this.onDestination, required this.onContinue,
    this.onServiceChanged, required this.serviceCode, super.key,
  });
  final MarketplacePromoProfile profile;
  final MarketplaceMapPoint? origin, destination;
  final VoidCallback onOrigin, onDestination, onContinue;
  final ValueChanged<String>? onServiceChanged;
  final String serviceCode;

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
                    for (final code in profile.services)
                      ChoiceChip(label: Text(marketplaceServiceLabel(code)), selected: serviceCode == code,
                        onSelected: (_) => onServiceChanged?.call(code)),
                  ]),
                ],
                const SizedBox(height: 16),
                _address('Punto de recogida', origin, const Color(0xFF22D3EE), onOrigin),
                const SizedBox(height: 12),
                _address('¿Cuál es tu destino?', destination, const Color(0xFFFB923C), onDestination),
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

  Widget _address(String placeholder, MarketplaceMapPoint? point, Color color, VoidCallback onTap) => Material(
    color: const Color(0xFF1E293B),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      borderRadius: BorderRadius.circular(15), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        child: Row(children: [
          Icon(Icons.location_on_outlined, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(point?.label ?? placeholder, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 17, fontWeight: FontWeight.w700))),
        ])),
    ),
  );
}
