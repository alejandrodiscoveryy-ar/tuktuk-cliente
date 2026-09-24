import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
part 'presentation/marketplace_location_picker.dart';
part 'presentation/tuktuk_ui.dart';

const _metaBox = 'marketplace_customer_meta';
const kPrimary = Color(0xFF2DD4A3);
const kTertiary = Color(0xFFFFC400);
const kMuted = Color(0xFF93A2B5);
const kDanger = Color(0xFFFB7185);
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

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
  runApp(MarketplaceCustomerApp(client: Supabase.instance.client));
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
