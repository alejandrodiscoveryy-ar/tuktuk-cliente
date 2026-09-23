import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tuktuk_cliente/main.dart';

void main() {
  test('customer session parses server contract', () {
    final session = MarketplaceCustomerSession.fromMap({
      'session_id': 'session-1',
      'customer_id': 'customer-1',
      'expires_at': '2026-10-15T12:00:00Z',
      'server_time': '2026-09-15T12:00:00Z',
    });

    expect(session.sessionId, 'session-1');
    expect(session.customerId, 'customer-1');
    expect(session.expiresAt, isNotNull);
    expect(session.serverTime, isNotNull);
  });

  test('customer job exposes assigned driver only from server data', () {
    final job = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-1',
      'status': 'accepted',
      'service_code': 'passenger',
      'origin_text': 'Origen',
      'destination_text': 'Destino',
      'final_price': 850,
      'currency': 'CUP',
      'driver_display_name': 'Conductor',
      'driver_whatsapp_phone': '+5355555555',
      'driver_photo_asset_id': 'driver-photo',
      'vehicle_id': 'vehicle-1',
      'vehicle_name': 'Mi vehículo',
      'vehicle_category_code': 'tricycle',
      'vehicle_brand': 'Marca',
      'vehicle_model': 'Modelo',
      'vehicle_registration': 'P123456',
      'vehicle_main_photo_asset_id': 'vehicle-photo',
    });

    expect(job.status, 'accepted');
    expect(job.finalPrice, 850);
    expect(job.hasAssignedDriver, isTrue);
    expect(job.driverDisplayName, 'Conductor');
    expect(job.vehicleId, 'vehicle-1');
  });

  test('customer job supports unassigned published state', () {
    final job = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-2',
      'status': 'published',
      'service_code': 'courier',
      'final_price': 500,
      'currency': 'CUP',
    });

    expect(job.hasAssignedDriver, isFalse);
    expect(job.driverDisplayName, isNull);
    expect(job.vehicleId, isNull);
  });

  test('customer job follows customer cancellation state machine', () {
    final published = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-published',
      'status': 'published',
      'final_price': 500,
      'currency': 'CUP',
    });

    final pickup = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-pickup',
      'status': 'pickup',
      'final_price': 500,
      'currency': 'CUP',
    });

    final inProgress = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-progress',
      'status': 'in_progress',
      'final_price': 500,
      'currency': 'CUP',
    });

    final settled = MarketplaceCustomerJob.fromMap({
      'job_id': 'job-settled',
      'status': 'settled',
      'final_price': 500,
      'currency': 'CUP',
    });

    expect(published.customerCanCancel, isTrue);
    expect(pickup.customerCanCancel, isTrue);
    expect(inProgress.customerCanCancel, isFalse);
    expect(settled.customerCanCancel, isFalse);
    expect(settled.isTerminal, isTrue);
    expect(published.isTerminal, isFalse);
  });

  test('customer cancellation parses server response', () {
    final result = MarketplaceCustomerCancellation.fromMap({
      'job_id': 'job-3',
      'status': 'cancelled_by_customer',
      'server_time': '2026-09-15T12:00:00Z',
    });

    expect(result.jobId, 'job-3');
    expect(result.status, 'cancelled_by_customer');
    expect(result.serverTime, isNotNull);
  });

  test('customer session token is secure-shape 64 hex chars', () {
    final first = marketplaceCustomerSessionToken();
    final second = marketplaceCustomerSessionToken();

    expect(first, hasLength(64));
    expect(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(first),
      isTrue,
    );
    expect(first, isNot(second));
  });

  test('customer gateway uses the Edge contract without direct RPCs', () {
    final source = File(
      'lib/data/marketplace_customer_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('marketplace-customer-gateway'),
    );
    expect(
      source,
      contains("'start_session'"),
    );
    expect(
      source,
      contains("'get_job'"),
    );

    expect(source, isNot(contains(".from('jobs')")));
    expect(
      source,
      isNot(contains(".from('service_requests')")),
    );
    expect(source, isNot(contains('service_role')));
    expect(source, isNot(contains('.rpc(')));
  });

  test('customer gateway includes narrow rating and private media contracts',
      () {
    final source =
        File('lib/data/marketplace_customer_service.dart').readAsStringSync();
    expect(source, contains("'create_rating'"));
    expect(source, contains("'get_rating'"));
    expect(source, contains("'media'"));
    expect(source, isNot(contains(".from('marketplace_customer_ratings')")));
  });

  test('tracking refreshes private media only on assignment changes or expiry',
      () {
    final source = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    expect(source, contains('_mediaAssignmentSignature'));
    expect(source, contains('mediaExpiresSoon'));
    expect(source, contains("'stars': _stars"));
    expect(source, contains('_payloadSignature != payloadSignature'));
  });

}
