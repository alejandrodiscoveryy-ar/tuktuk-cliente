import 'dart:convert';

import 'package:tuktuk_cliente/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('scheduled date reaches the mocked Edge gateway', () async {
    final captured = <Map<String, dynamic>>[];

    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://example.supabase.co/functions/v1/marketplace-customer-gateway',
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

    final service = MarketplaceCustomerService(client);
    final scheduled = DateTime(2026, 10, 20, 11, 30);

    final result = await service.createRequest(
      sessionId: 'session-test',
      sessionToken: 'token-test',
      serviceCode: 'passenger',
      originText: 'Origen de prueba',
      destinationText: 'Destino de prueba',
      scheduledFor: scheduled,
      passengerCount: 1,
      idempotencyKey: 'scheduled-test',
    );

    expect(result.jobId, 'job-test');
    expect(captured, hasLength(1));
    expect(captured.single['operation'], 'create_request');

    final params = Map<String, dynamic>.from(captured.single['params'] as Map);

    expect(
      params['target_scheduled_for'],
      scheduled.toUtc().toIso8601String(),
    );
    expect(params['target_idempotency_key'], 'scheduled-test');
    expect(params['target_session_id'], 'session-test');
    expect(params['target_service_code'], 'passenger');

    await service.createRequest(
      sessionId: 'session-test',
      sessionToken: 'token-test',
      serviceCode: 'passenger',
      originText: 'Origen de prueba',
      destinationText: 'Destino de prueba',
      passengerCount: 1,
      idempotencyKey: 'immediate-test',
    );

    expect(captured, hasLength(2));

    final immediate = Map<String, dynamic>.from(captured.last['params'] as Map);

    expect(immediate['target_scheduled_for'], isNull);
    expect(immediate['target_idempotency_key'], 'immediate-test');

    mock.close();
  });
}
