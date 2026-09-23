part of '../main.dart';

class MarketplaceLocationPicker extends StatefulWidget {
  const MarketplaceLocationPicker({
    required this.service,
    required this.title,
    required this.onConfirm,
    this.origin,
    super.key,
  });

  final MarketplaceMapService service;
  final String title;
  final MarketplaceMapPoint? origin;
  final ValueChanged<MarketplaceMapPoint> onConfirm;

  @override
  State<MarketplaceLocationPicker> createState() =>
      _MarketplaceLocationPickerState();
}

class _MarketplaceLocationPickerState extends State<MarketplaceLocationPicker> {
  final controller = MapController();
  final searchController = TextEditingController();
  Timer? debounce;
  Timer? reverseDebounce;
  MarketplaceMapPoint? selected;
  List<MarketplaceMapPoint> results = const [];
  String? message;
  bool busy = false;

  @override
  void dispose() {
    debounce?.cancel();
    reverseDebounce?.cancel();
    searchController.dispose();
    controller.dispose();
    super.dispose();
  }

  void search(String value) {
    debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => results = const []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final found = await widget.service.search(value.trim());
        if (mounted && searchController.text.trim() == value.trim()) {
          setState(() {
            results = found;
            message = null;
          });
        }
      } catch (_) {
        if (mounted) setState(() => message = 'No pudimos buscar ese lugar.');
      }
    });
  }

  Future<void> select(LatLng position) async {
    setState(() {
      selected = MarketplaceMapPoint(
          label: 'Ubicación seleccionada',
          lat: position.latitude,
          lon: position.longitude);
      results = const [];
      busy = true;
    });
    try {
      final point = await widget.service.reverse(selected!);
      if (mounted) setState(() => selected = point);
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'No pudimos obtener la dirección. Puedes continuar con el punto elegido.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> usePosition() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('LOCATION_DISABLED');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('LOCATION_DENIED');
      }
      final position = await Geolocator.getCurrentPosition();
      controller.move(LatLng(position.latitude, position.longitude), 15);
      await select(LatLng(position.latitude, position.longitude));
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Ubicación no disponible. Busca un lugar o toca el mapa para elegirlo manualmente.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const token = MarketplaceMapService.publicToken;
    final center = widget.origin?.latLng ?? const LatLng(23.1136, -82.3666);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.origin != null)
                Text('Origen: ${widget.origin!.label}'),
              TextField(
                  controller: searchController,
                  onChanged: search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar dirección o lugar',
                  )),
              if (results.isNotEmpty)
                SizedBox(
                    height: 160,
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(results[index].label),
                        onTap: () {
                          final point = results[index];
                          controller.move(point.latLng, 15);
                          setState(() {
                            selected = point;
                            results = const [];
                            searchController.text = point.label;
                          });
                        },
                      ),
                    )),
            ],
          )),
      Expanded(
          child: Stack(children: [
        if (token.isEmpty)
          const Center(
              child: Text(
                  'Configura MAPBOX_PUBLIC_TOKEN para mostrar el mapa. Puedes buscar lugares arriba.'))
        else
          FlutterMap(
            mapController: controller,
            options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
                onTap: (_, point) => select(point),
                onPositionChanged: (camera, hasGesture) {
                  if (!hasGesture) return;
                  reverseDebounce?.cancel();
                  setState(() => selected = MarketplaceMapPoint(
                        label: 'Ubicación seleccionada',
                        lat: camera.center.latitude,
                        lon: camera.center.longitude,
                      ));
                  reverseDebounce =
                      Timer(const Duration(milliseconds: 700), () {
                    if (selected != null) select(selected!.latLng);
                  });
                }),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token=$token',
                userAgentPackageName: 'com.vrixora.tuktuk',
              ),
              if (selected != null)
                MarkerLayer(markers: [
                  Marker(
                    point: selected!.latLng,
                    width: 50,
                    height: 50,
                    child: Icon(Icons.location_pin,
                        size: 44,
                        color: widget.origin == null
                            ? Colors.tealAccent
                            : Colors.redAccent),
                  )
                ]),
              marketplaceMapAttribution(selected?.latLng ?? center),
            ],
          ),
      ])),
      if (message != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
      Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (widget.origin == null)
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: busy ? null : usePosition,
                icon: const Icon(Icons.my_location),
                label: const Text('Usar mi ubicación'),
              )),
            if (widget.origin == null) const SizedBox(width: 8),
            Expanded(
                child: FilledButton(
              onPressed: selected == null || busy
                  ? null
                  : () => widget.onConfirm(selected!),
              child: Text(widget.origin == null
                  ? 'Confirmar origen'
                  : 'Confirmar destino'),
            )),
          ])),
    ]);
  }
}

class MarketplaceRouteMap extends StatelessWidget {
  const MarketplaceRouteMap(
      {required this.origin,
      required this.destination,
      required this.route,
      super.key});
  final MarketplaceMapPoint? origin;
  final MarketplaceMapPoint? destination;
  final MarketplaceRouteQuote? route;

  @override
  Widget build(BuildContext context) {
    const token = MarketplaceMapService.publicToken;
    if (token.isEmpty) return const Center(child: Text('Mapa no configurado'));
    return FlutterMap(
      options: MapOptions(
          initialCenter: origin?.latLng ?? const LatLng(23.1136, -82.3666),
          initialZoom: 12),
      children: [
        TileLayer(
            urlTemplate:
                'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token=$token',
            userAgentPackageName: 'com.vrixora.tuktuk'),
        if (route != null)
          PolylineLayer(polylines: [
            Polyline(
              points: route!.routePoints
                  .map((point) => point.latLng)
                  .toList(growable: false),
              color: Colors.tealAccent,
              strokeWidth: 5,
            )
          ]),
        MarkerLayer(markers: [
          if (origin != null)
            Marker(
                point: origin!.latLng,
                child: const Icon(Icons.location_pin,
                    color: Colors.tealAccent, size: 40)),
          if (destination != null)
            Marker(
                point: destination!.latLng,
                child: const Icon(Icons.location_pin,
                    color: Colors.redAccent, size: 40)),
        ]),
        marketplaceMapAttribution(
            origin?.latLng ?? const LatLng(23.1136, -82.3666)),
      ],
    );
  }
}

Widget marketplaceMapAttribution(LatLng point) => RichAttributionWidget(
      attributions: [
        LogoSourceAttribution(
          Image.network(
            'https://cdn.prod.website-files.com/6050a76fa6a633d5d54ae714/657a891ba7274ba4f8b3a168_img-main-logo.png',
            fit: BoxFit.contain,
          ),
          height: 30,
          tooltip: 'Mapbox',
          onTap: () => launchUrl(Uri.parse('https://www.mapbox.com/')),
        ),
        TextSourceAttribution('Mapbox',
            onTap: () =>
                launchUrl(Uri.parse('https://www.mapbox.com/about/maps'))),
        TextSourceAttribution('OpenStreetMap',
            onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'))),
        TextSourceAttribution('Mejorar este mapa',
            prependCopyright: false,
            onTap: () => launchUrl(Uri.parse(
                'https://apps.mapbox.com/feedback/#/${point.longitude}/${point.latitude}/12'))),
      ],
    );
