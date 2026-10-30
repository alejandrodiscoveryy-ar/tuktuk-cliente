import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'services/customer_arrival_sound_stub.dart'
    if (dart.library.html) 'services/customer_arrival_sound_web.dart'
    as customer_arrival_sound;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/customer_rate_firebase_options.dart';
import 'services/customer_rate_turnstile_stub.dart'
    if (dart.library.js_interop) 'services/customer_rate_turnstile_web.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

part 'data/marketplace_customer_service.dart';
part 'data/marketplace_customer_request.dart';
part 'data/marketplace_map_service.dart';
part 'presentation/marketplace_customer.dart';
part 'presentation/marketplace_customer_booking_flow.dart';
part 'presentation/marketplace_customer_tracking.dart';
part 'domain/marketplace_customer_arrival_geofence.dart';
part 'presentation/marketplace_location_picker.dart';
part 'presentation/marketplace_vector_map.dart';
part 'presentation/tuktuk_ui.dart';
part 'presentation/customer_eltoque_banner.dart';
part 'presentation/customer_eltoque_notifications.dart';

const _metaBox = 'marketplace_customer_meta';
const kPrimary = Color(0xFF2DD4A3);
const kTertiary = Color(0xFFFFC400);
const kMuted = Color(0xFF93A2B5);
const kDanger = Color(0xFFFB7185);
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<bool> customerFirebaseReady = Future<bool>.value(false);

Future<void> _initializeCustomerFirebaseAfterFirstFrame(
    Completer<bool> ready) async {
  try {
    await Firebase.initializeApp(options: customerRateFirebaseWebOptions);
    ready.complete(true);
  } catch (_) {
    // Las alertas son opcionales y nunca bloquean el transporte.
    ready.complete(false);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(_metaBox);
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    runApp(const _ConfigurationRequiredApp());
    return;
  }
  await Supabase.initialize(
      url: _supabaseUrl, publishableKey: _supabasePublishableKey);

  final client = Supabase.instance.client;
  // El token publico de compilacion permite mostrar el mapa de inmediato.
  if (MarketplaceMapService.publicToken.startsWith('pk.')) {
    mbx.MapboxOptions.setAccessToken(MarketplaceMapService.publicToken);
  }
  if (kIsWeb) {
    final ready = Completer<bool>();
    customerFirebaseReady = ready.future;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeCustomerFirebaseAfterFirstFrame(ready));
      unawaited(_loadPublicMapConfigurationAfterFirstFrame(client));
    });
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPublicMapConfigurationAfterFirstFrame(client));
    });
  }
  // Ni mapas remotos ni Firebase bloquean la primera pantalla utilizable.
  runApp(MarketplaceCustomerApp(client: client));
}

Future<void> _loadPublicMapConfigurationAfterFirstFrame(
    SupabaseClient client) async {
  await MarketplaceMapService.loadPublicConfiguration(client);
  if (MarketplaceMapService.publicToken.startsWith('pk.')) {
    try {
      mbx.MapboxOptions.setAccessToken(MarketplaceMapService.publicToken);
    } catch (_) {
      // El mapa remoto es opcional; nunca bloquear el transporte.
    }
  }
}

double _marketNumber(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
DateTime? _marketDate(Object? value) =>
    value == null ? null : DateTime.tryParse('$value')?.toUtc();
String? _marketText(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}

@visibleForTesting
bool isMarketplaceCustomerEntryUri(Uri uri) =>
    uri.queryParameters['mode'] == 'customer' ||
    uri.path == '/cliente/tuk' ||
    uri.path == '/cliente/tuk/';

ThemeData buildAppTheme(Brightness brightness) => ThemeData(
      colorScheme: const ColorScheme.dark(
          primary: kPrimary,
          secondary: kTertiary,
          surface: Color(0xFF16202D),
          error: kDanger),
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: TuktukTheme.background,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      inputDecorationTheme: TuktukTheme.inputDecoration,
    );

class _ConfigurationRequiredApp extends StatelessWidget {
  const _ConfigurationRequiredApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TUKTUK Cliente',
        theme: buildAppTheme(Brightness.dark),
        home: const Scaffold(
            body: Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'La aplicación requiere configuración segura para conectarse.',
                        textAlign: TextAlign.center)))),
      );
}
