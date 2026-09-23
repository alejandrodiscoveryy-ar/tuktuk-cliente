import 'dart:convert';

import 'package:tuktuk_cliente/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final captured = <Map<String, dynamic>>[];

  final mock = MockClient((request) async {
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/functions/v1/marketplace-customer-gateway',
    );

    captured.add(
      Map<String, dynamic>.from(jsonDecode(request.body) as Map),
    );

    return http.Response(
      jsonEncode({
        'data': {
          'job_id': 'job-test',
          'service_request_id': 'request-test',
          'status': 'requested',
          'recommended_price': 500,
          'minimum_price': 100,
          'low_price_warning_threshold': 200,
          'currency': 'CUP',
          'pricing_version': 'test',
          'pricing_breakdown': <String, dynamic>{},
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-publishable-key',
    httpClient: mock,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  testWidgets('selected date reaches mocked gateway through the form',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MarketplaceCustomerTripFormScreen(
          service: MarketplaceCustomerService(client),
          session: const MarketplaceCustomerSessionSnapshot(
            sessionId: 'session-test',
            customerId: 'customer-test',
            token: 'token-test',
          ),
          serviceOption: const MarketplaceCustomerServiceOption(
            code: 'passenger',
            name: 'Pasajeros',
            sortOrder: 0,
            currency: 'CUP',
            pricingVersion: 'test',
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Origen de prueba',
    );

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Destino de prueba',
    );

    final schedule = find.text('Programar fecha y hora (opcional)');
    await tester.ensureVisible(schedule);
    await tester.tap(schedule);
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    final displayed =
        tester.widget<Text>(find.textContaining('Programado:')).data!;

    final quoteButton = find.text('Ver precio recomendado');
    await tester.ensureVisible(quoteButton);
    await tester.tap(quoteButton);
    await tester.pump();

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));

      if (find.byType(MarketplaceCustomerQuoteScreen).evaluate().isNotEmpty ||
          find
              .textContaining('No pudimos calcular el precio')
              .evaluate()
              .isNotEmpty) {
        break;
      }

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    }

    await tester.pump();

    expect(captured, hasLength(1));
    expect(captured.single['operation'], 'create_request');

    final params = Map<String, dynamic>.from(
      captured.single['params'] as Map,
    );

    final scheduled = DateTime.parse(
      params['target_scheduled_for'] as String,
    ).toLocal();

    expect(
      displayed,
      'Programado: ${DateFormat('dd/MM/yyyy HH:mm').format(scheduled)}',
    );
    expect(params['target_origin_text'], 'Origen de prueba');
    expect(params['target_destination_text'], 'Destino de prueba');
    expect(params['target_passenger_count'], 1);
    expect(params['target_idempotency_key'], isNotEmpty);

    expect(
      find.byType(MarketplaceCustomerQuoteScreen),
      findsOneWidget,
    );
    expect(
      find.text(
          'Servicio programado: ${DateFormat('dd/MM/yyyy HH:mm').format(scheduled)}'),
      findsOneWidget,
    );

    mock.close();
  });
}
