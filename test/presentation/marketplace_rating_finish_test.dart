import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';

class _Service extends MarketplaceCustomerService {
  _Service(super.client);
  String status = 'en_route';
  bool offline = false;
  int finishCalls = 0;
  int ratingCalls = 0;
  int historyCalls = 0;
  MarketplaceCustomerRating? rating;
  final keys = <String>[];

  MarketplaceCustomerJob get job => MarketplaceCustomerJob.fromMap({
    'job_id': 'job-test', 'status': status, 'final_price': 100,
    'currency': 'CUP', 'origin_text': 'Origen historial',
    'destination_text': 'Destino historial', 'created_at': '2026-10-08T12:00:00Z',
  });

  @override
  Future<MarketplaceCustomerJob> getJob({required String sessionId,
    required String sessionToken, required String jobId}) async => job;

  @override
  Future<MarketplaceCustomerRating?> getRating({required String sessionId,
    required String sessionToken, required String jobId}) async => rating;

  @override
  Future<List<MarketplaceCustomerJob>> history({required String sessionId,
    required String sessionToken, MarketplaceCustomerJob? before}) async {
    historyCalls++;
    return [job];
  }

  @override
  Future<MarketplaceCustomerFinish> finishJob({required String sessionId,
    required String sessionToken, required String jobId,
    required String idempotencyKey}) async {
    finishCalls++;
    throw StateError('Standalone closure must never be used');
  }

  @override
  Future<MarketplaceCustomerRating> createRating({required String sessionId,
    required String sessionToken, required String jobId, required int stars,
    required String idempotencyKey, String? comment}) async {
    ratingCalls++;
    keys.add(idempotencyKey);
    if (offline) throw const SocketException('offline');
    status = 'settled';
    return rating ??= MarketplaceCustomerRating(jobId: jobId, stars: stars);
  }
}

const _session = MarketplaceCustomerSessionSnapshot(
  sessionId: 'session-test', customerId: 'customer-test', token: 'token-test',
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  late SupabaseClient client;
  late _Service service;
  setUp(() {
    client = SupabaseClient('http://127.0.0.1:1', 'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    service = _Service(client);
  });
  tearDown(() => client.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: MarketplaceCustomerTrackingScreen(
      service: service, session: _session, jobId: 'job-test', onDone: () async {},
    )));
    await _pump(tester);
  }

  testWidgets('customer Finish directly opens rating; abandonment leaves ride open', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Finalizar carrera'), 300);
    await tester.tap(find.text('Finalizar carrera'));
    await _pump(tester);
    expect(find.byType(MarketplaceCustomerRatingScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.finishCalls, 0);
    expect(service.ratingCalls, 0);
    await tester.pageBack();
    await _pump(tester);
    expect(service.status, 'en_route');
    expect(service.rating, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('first customer rating submits once and refreshes settled job', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Finalizar carrera'), 300);
    await tester.tap(find.text('Finalizar carrera'));
    await _pump(tester);
    await tester.tap(find.text('Enviar calificación'));
    await _pump(tester);
    expect(service.ratingCalls, 0);
    await tester.tap(find.byTooltip('5 estrellas'));
    await tester.tap(find.text('Enviar calificación'));
    await _pump(tester);
    expect(service.ratingCalls, 1);
    expect(service.finishCalls, 0);
    expect(service.status, 'settled');
    expect(find.text('Tu calificación: 5 estrellas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offline customer rating retains payload key for retry', (tester) async {
    service.offline = true;
    await open(tester);
    await tester.scrollUntilVisible(find.text('Finalizar carrera'), 300);
    await tester.tap(find.text('Finalizar carrera'));
    await _pump(tester);
    await tester.tap(find.byTooltip('5 estrellas'));
    await tester.tap(find.text('Enviar calificación'));
    await _pump(tester);
    expect(service.status, 'en_route');
    expect(service.rating, isNull);
    service.offline = false;
    await tester.tap(find.text('Enviar calificación'));
    await _pump(tester);
    expect(service.keys.toSet(), hasLength(1));
    expect(service.ratingCalls, 2);
    expect(service.finishCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final actor in ['driver', 'admin']) {
    testWidgets('customer pending rating accessible through history after $actor closure', (tester) async {
      service.status = 'settled';
      await tester.pumpWidget(MaterialApp(home: MarketplaceCustomerBookingFlow(
        service: service, session: _session,
      )));
      await _pump(tester);
      await tester.tap(find.text('Historial'));
      await _pump(tester);
      expect(service.historyCalls, 1);
      await tester.tap(find.text('Origen historial → Destino historial'));
      await _pump(tester);
      await tester.scrollUntilVisible(find.text('Calificar transportista'), 300);
      await tester.tap(find.text('Calificar transportista'));
      await _pump(tester);
      await tester.tap(find.byTooltip('5 estrellas'));
      await tester.tap(find.text('Enviar calificación'));
      await _pump(tester);
      expect(service.ratingCalls, 1);
      expect(service.finishCalls, 0);
      expect(find.text('Tu calificación: 5 estrellas'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
