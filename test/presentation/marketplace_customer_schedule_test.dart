import 'dart:io';

import 'package:tuktuk_cliente/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('expired pickup date opens the picker at a future time', () {
    final now = DateTime(2026, 9, 17, 15);
    final expired = DateTime(2026, 9, 16, 20);
    final future = DateTime(2026, 9, 18, 10);
    final fallback = now.add(const Duration(minutes: 30));

    expect(marketplaceSchedulePickerInitialDate(now, expired), fallback);
    expect(marketplaceSchedulePickerInitialDate(now, now), fallback);
    expect(marketplaceSchedulePickerInitialDate(now, null), fallback);
    expect(marketplaceSchedulePickerInitialDate(now, future), future);
  });

  testWidgets('customer can schedule and clear pickup time', (tester) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MarketplaceCustomerTripFormScreen(
          service: MarketplaceCustomerService(client),
          session: const MarketplaceCustomerSessionSnapshot(
            sessionId: 'test-session',
            customerId: 'test-customer',
            token: 'test-token',
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

    final schedule = find.text('Programar fecha y hora (opcional)');

    await tester.ensureVisible(schedule);
    await tester.tap(schedule);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Programado:'), findsOneWidget);

    final clear = find.text('Solicitar ahora');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(schedule, findsOneWidget);
    expect(find.textContaining('Programado:'), findsNothing);
  });

  test('scheduled time is included in request and idempotency payload', () {
    final source =
        File('lib/presentation/marketplace_customer.dart').readAsStringSync();

    expect(
      source,
      contains("'scheduled_for': _scheduledFor?.toUtc().toIso8601String()"),
    );
    expect(source, contains('scheduledFor: _scheduledFor,'));
  });
}
