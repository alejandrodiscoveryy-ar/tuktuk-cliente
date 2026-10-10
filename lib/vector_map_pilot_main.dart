import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart' as customer;

// Entrada INDEPENDIENTE; no altera la navegaciÃ³n de Cliente en producciÃ³n.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    runApp(const _StatusApp(
        'Este piloto necesita la configuraciÃ³n pÃºblica de Supabase para la prueba visual.'));
    return;
  }
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    await customer.MarketplaceMapService.loadPublicConfiguration(
      Supabase.instance.client,
    );
    final token = customer.MarketplaceMapService.publicToken;
    if (!token.startsWith('pk.')) {
      runApp(const _StatusApp('Token pÃºblico de Mapbox no disponible.'));
      return;
    }
    mbx.MapboxOptions.setAccessToken(token);
    runApp(_VectorPilotApp(
      styleUri: customer.MarketplaceMapService.vectorStyleUri,
    ));
  } catch (_) {
    runApp(const _StatusApp('No se pudo obtener la configuraciÃ³n pÃºblica del mapa.'));
  }
}

class _StatusApp extends StatelessWidget {
  const _StatusApp(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: Text(message))),
      );
}

class _VectorPilotApp extends StatelessWidget {
  const _VectorPilotApp({required this.styleUri});
  final String styleUri;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('TUKTUK | Piloto mapa vectorial')),
          body: Column(children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('PRUEBA AISLADA. No permite solicitar carreras.'),
            ),
            Expanded(
              child: mbx.MapWidget(
                styleUri: styleUri,
                viewport: mbx.CameraViewportState(
                  center: mbx.Point(
                    coordinates: mbx.Position(-82.3666, 23.1136),
                  ),
                  zoom: 13,
                  bearing: 0,
                  pitch: 0,
                ),
              ),
            ),
          ]),
        ),
      );
}
