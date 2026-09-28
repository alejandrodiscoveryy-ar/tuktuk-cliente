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
  bool tilesFailed = false;
  bool busy = false;
  bool searchOpen = false;

  @override
  void initState() {
    super.initState();

    // Solo para el origen. Al entrar al Paso 3 desde «Activa tu ubicación»,
    // intentamos localizar al cliente automáticamente.
    if (widget.origin == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoLocateOrigin();
      });
    }
  }

  Future<void> _autoLocateOrigin() async {
    if (busy || selected != null) return;
    await usePosition();
  }

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
        lon: position.longitude,
      );
      results = const [];
      busy = true;
    });
    try {
      final point = await widget.service.reverse(selected!);
      if (mounted) setState(() => selected = point);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'No pudimos obtener la dirección. Puedes continuar con el punto elegido.',
        );
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
      final point = LatLng(position.latitude, position.longitude);

      // El mapa puede estar terminando de montarse en el primer frame.
      // Programamos el centrado para el frame siguiente, pero seleccionamos
      // el punto de inmediato para no añadir otro paso al flujo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          controller.move(point, 15);
        } catch (_) {
          // Si el controlador todavía no está listo, el punto seleccionado
          // sigue siendo válido y el usuario puede ajustar el pin.
        }
      });

      await select(point);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Ubicación no disponible. Busca un lugar o toca el mapa para elegirlo manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = MarketplaceMapService.publicToken;
    final center = widget.origin?.latLng ?? const LatLng(23.1136, -82.3666);
    final destination = widget.origin != null;

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: token.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Configura MAPBOX_PUBLIC_TOKEN para mostrar el mapa. Puedes buscar lugares y elegir un punto manualmente.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : FlutterMap(
                    mapController: controller,
                    options: MapOptions(
                      backgroundColor: TuktukTheme.background,
                      initialCenter: center,
                      initialZoom: destination ? 13 : 12,
                      onTap: (_, point) => select(point),
                      onPositionChanged: (camera, hasGesture) {
                        if (!hasGesture) return;

                        reverseDebounce?.cancel();

                        setState(
                          () => selected = MarketplaceMapPoint(
                            label: 'Ubicación seleccionada',
                            lat: camera.center.latitude,
                            lon: camera.center.longitude,
                          ),
                        );

                        reverseDebounce = Timer(
                          const Duration(milliseconds: 700),
                          () {
                            if (selected != null) {
                              select(selected!.latLng);
                            }
                          },
                        );
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: MarketplaceMapService.tileUrlTemplate,
                        userAgentPackageName: 'com.vrixora.tuktuk',
                        errorTileCallback: (_, __, ___) {
                          if (mounted && !tilesFailed) {
                            setState(() => tilesFailed = true);
                          }
                        },
                      ),
                      if (selected != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: selected!.latLng,
                              width: 64,
                              height: 64,
                              child: _PremiumMapPin(destination: destination),
                            ),
                          ],
                        ),
                      marketplaceMapAttribution(selected?.latLng ?? center),
                    ],
                  ),
          ),
          if (token.isNotEmpty)
            const Positioned.fill(child: TuktukMapLoadingOverlay()),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      TuktukTheme.background.withValues(alpha: .42),
                      Colors.transparent,
                    ],
                    stops: const [0, .22],
                  ),
                ),
              ),
            ),
          ),
          if (!destination)
            Positioned(
              left: 14,
              right: 14,
              top: 10,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEB121A20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: TuktukTheme.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 16,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: TuktukTheme.mint,
                          size: 25,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Punto de recogida',
                                style: TextStyle(
                                  color: TuktukTheme.muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selected?.label ?? 'Elige el origen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Buscar dirección',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => searchOpen = !searchOpen);
                          },
                          icon: const Icon(
                            Icons.search_rounded,
                            color: TuktukTheme.mint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (searchOpen) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar dirección o lugar',
                      ),
                    ),
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 170),
                        decoration: BoxDecoration(
                          color: TuktukTheme.surfaceStrong,
                          border: Border.all(color: TuktukTheme.border),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) => ListTile(
                            dense: true,
                            title: Text(results[index].label),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _chooseSearchResult(results[index]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          if (destination)
            Positioned(
              left: 14,
              right: 14,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xEB121A20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: TuktukTheme.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 16,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          Icon(Icons.circle, size: 11, color: TuktukTheme.mint),
                          Text(
                            '⋮',
                            style: TextStyle(
                              color: TuktukTheme.muted,
                              height: .7,
                            ),
                          ),
                          Icon(Icons.circle, size: 11, color: TuktukTheme.gold),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.origin?.label ?? 'Origen',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: TuktukTheme.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            selected?.label ?? 'Selecciona tu destino',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: selected == null
                                  ? TuktukTheme.muted
                                  : TuktukTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!destination)
            Positioned(
              left: 14,
              right: 14,
              bottom: 10,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TuktukMapButton(
                          label: 'Centrar en mí',
                          icon: Icons.my_location_rounded,
                          onPressed: busy ? null : usePosition,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TuktukMapButton(
                          label: 'Mover pin',
                          icon: Icons.location_on_rounded,
                          onPressed: () {
                            setState(
                              () => message =
                                  'Mueve el mapa o toca un punto para ajustar el origen.',
                            );
                          },
                          active: selected != null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE8121A20),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TuktukTheme.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected == null
                              ? Icons.touch_app_outlined
                              : Icons.check_circle_outline_rounded,
                          color: TuktukTheme.mint,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selected?.label ??
                                'Toca el mapa o usa tu ubicación actual.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: TuktukTheme.muted,
                              fontSize: 13.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TuktukTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (tilesFailed) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'El mapa no pudo cargar todas las teselas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: TuktukTheme.gold, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TuktukPrimaryButton(
                    onPressed: selected == null || busy
                        ? null
                        : () => widget.onConfirm(selected!),
                    label: 'Confirmar origen',
                  ),
                ],
              ),
            ),
          if (destination)
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .48,
                ),
                child: TuktukSectionSheet(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '¿A dónde vas?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: searchController,
                          onChanged: search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.location_on_outlined),
                            suffixIcon: Icon(
                              Icons.search_rounded,
                              color: TuktukTheme.gold,
                            ),
                            hintText: 'Buscar destino',
                            isDense: true,
                          ),
                        ),
                        if (results.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 138),
                            decoration: BoxDecoration(
                              color: TuktukTheme.surfaceStrong,
                              border: Border.all(color: TuktukTheme.border),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) => ListTile(
                                dense: true,
                                title: Text(results[index].label),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () =>
                                    _chooseSearchResult(results[index]),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        const Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              color: TuktukTheme.mint,
                              size: 20,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'También puedes mover el mapa y elegir el punto exacto.',
                                style: TextStyle(
                                  color: TuktukTheme.muted,
                                  fontSize: 12.8,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            message!,
                            style: const TextStyle(
                              color: TuktukTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (tilesFailed) ...[
                          const SizedBox(height: 7),
                          const Text(
                            'El mapa no pudo cargar todas las teselas.',
                            style: TextStyle(
                              color: TuktukTheme.gold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TuktukPrimaryButton(
                          onPressed: selected == null || busy
                              ? null
                              : () => widget.onConfirm(selected!),
                          label: 'Confirmar destino',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _chooseSearchResult(MarketplaceMapPoint point) {
    controller.move(point.latLng, 15);
    setState(() {
      selected = point;
      results = const [];
      searchController.text = point.label;
      searchOpen = false;
      message = null;
    });
  }
}

class _PremiumMapPin extends StatelessWidget {
  const _PremiumMapPin({required this.destination});
  final bool destination;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: (destination ? TuktukTheme.danger : TuktukTheme.mint)
                  .withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            Icons.location_on_rounded,
            color: destination ? TuktukTheme.danger : TuktukTheme.mint,
            size: 48,
          ),
        ],
      );
}

class MarketplaceRouteMap extends StatelessWidget {
  const MarketplaceRouteMap({
    required this.origin,
    required this.destination,
    required this.route,
    super.key,
  });

  final MarketplaceMapPoint? origin;
  final MarketplaceMapPoint? destination;
  final MarketplaceRouteQuote? route;

  @override
  Widget build(BuildContext context) {
    final token = MarketplaceMapService.publicToken;
    if (token.isEmpty) {
      return const Center(child: Text('Mapa no configurado'));
    }

    final center = origin != null && destination != null
        ? LatLng(
            (origin!.lat + destination!.lat) / 2,
            (origin!.lon + destination!.lon) / 2,
          )
        : origin?.latLng ?? const LatLng(23.1136, -82.3666);
    final distance = route?.distanceKm ?? 0;
    final zoom = distance <= 3
        ? 13.2
        : distance <= 8
            ? 12.2
            : distance <= 18
                ? 11.4
                : 10.7;

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            backgroundColor: TuktukTheme.background,
            initialCenter: center,
            initialZoom: zoom,
          ),
          children: [
            TileLayer(
              urlTemplate: MarketplaceMapService.tileUrlTemplate,
              userAgentPackageName: 'com.vrixora.tuktuk',
            ),
            if (route != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route!.routePoints
                        .map((point) => point.latLng)
                        .toList(growable: false),
                    color: TuktukTheme.mint,
                    strokeWidth: 6,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (origin != null)
                  Marker(
                    point: origin!.latLng,
                    width: 52,
                    height: 52,
                    child: const _PremiumMapPin(destination: false),
                  ),
                if (destination != null)
                  Marker(
                    point: destination!.latLng,
                    width: 52,
                    height: 52,
                    child: const _PremiumMapPin(destination: true),
                  ),
              ],
            ),
            marketplaceMapAttribution(
              origin?.latLng ?? const LatLng(23.1136, -82.3666),
            ),
          ],
        ),
        const TuktukMapLoadingOverlay(),
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
          height: 26,
          tooltip: 'Mapbox',
          onTap: () => launchUrl(Uri.parse('https://www.mapbox.com/')),
        ),
        TextSourceAttribution(
          'Mapbox',
          onTap: () =>
              launchUrl(Uri.parse('https://www.mapbox.com/about/maps')),
        ),
        TextSourceAttribution(
          'OpenStreetMap',
          onTap: () =>
              launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
        ),
        TextSourceAttribution(
          'Mejorar este mapa',
          prependCopyright: false,
          onTap: () => launchUrl(
            Uri.parse(
              'https://apps.mapbox.com/feedback/#/${point.longitude}/${point.latitude}/12',
            ),
          ),
        ),
      ],
    );
