import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('only an ongoing ride is eligible for customer finish', () {
    MarketplaceCustomerJob job(String status) =>
        MarketplaceCustomerJob.fromMap({
          'job_id': 'job-test',
          'status': status,
          'final_price': 100,
          'currency': 'CUP',
        });

    expect(job('published').customerCanFinish, isFalse);
    expect(job('accepted').customerCanFinish, isFalse);
    expect(job('en_route').customerCanFinish, isTrue);
    expect(job('pickup').customerCanFinish, isTrue);
    expect(job('in_progress').customerCanFinish, isTrue);
    expect(job('settled').customerCanFinish, isFalse);
    expect(job('incident').customerCanFinish, isFalse);
  });

  test('customer finish uses the authenticated session gateway', () async {
    final calls = <Map<String, dynamic>>[];

    final mock = MockClient((request) async {
      calls.add(
        Map<String, dynamic>.from(jsonDecode(request.body) as Map),
      );

      return http.Response(
        jsonEncode({
          'data': [
            {
              'job_id': 'job-test',
              'status': 'settled',
              'server_time': '2026-10-08T12:00:00Z',
            },
          ],
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

    final result = await MarketplaceCustomerService(client).finishJob(
      sessionId: 'session-test',
      sessionToken: 'token-test',
      jobId: 'job-test',
      idempotencyKey: 'key-test',
    );

    expect(result.jobId, 'job-test');
    expect(result.status, 'settled');
    expect(result.serverTime, isNotNull);

    expect(calls, hasLength(1));
    expect(calls.single['operation'], 'finish');

    final params = Map<String, dynamic>.from(
      calls.single['params'] as Map,
    );

    expect(params['target_session_id'], 'session-test');
    expect(params['target_session_token'], 'token-test');
    expect(params['target_job_id'], 'job-test');
    expect(params['target_idempotency_key'], 'key-test');

    client.dispose();
    mock.close();
  });

  test('customer history uses session ownership and a bounded creation cursor', () async {
    final calls = <Map<String, dynamic>>[];
    final mock = MockClient((request) async {
      calls.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      return http.Response(jsonEncode({'data': [{
        'job_id': 'old-job', 'status': 'settled', 'final_price': 100,
        'currency': 'CUP', 'created_at': '2026-09-01T00:00:00Z',
      }]}), 200, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('http://127.0.0.1:1', 'test-key',
      httpClient: mock, authOptions: const AuthClientOptions(autoRefreshToken: false));
    final service = MarketplaceCustomerService(client);
    final first = await service.history(sessionId: 'session-test', sessionToken: 'token-test');
    await service.history(sessionId: 'session-test', sessionToken: 'token-test', before: first.single);
    expect(calls.map((c) => c['operation']), everyElement('history'));
    final params = calls.last['params'] as Map;
    expect(params['target_limit'], 50);
    expect(params['target_session_id'], 'session-test');
    expect(params['target_session_token'], 'token-test');
    expect(params['target_before_job_id'], 'old-job');
    expect(DateTime.parse(params['target_before_created_at'] as String), first.single.createdAt);
    client.dispose();
    mock.close();
  });
}
