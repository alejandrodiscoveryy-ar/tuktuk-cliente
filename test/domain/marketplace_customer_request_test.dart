import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tuktuk_cliente/main.dart';

void main() {
  test('customer service option parses pricing contract', () {
    final service = MarketplaceCustomerServiceOption.fromMap({
      'service_code': 'passenger',
      'service_name': 'Pasajeros',
      'sort_order': 10,
      'currency': 'CUP',
      'pricing_version': 'passenger-v1',
    });

    expect(service.code, 'passenger');
    expect(service.name, 'Pasajeros');
    expect(service.sortOrder, 10);
    expect(service.currency, 'CUP');
    expect(service.pricingVersion, 'passenger-v1');
  });

  test('customer request draft parses quote snapshot', () {
    final draft = MarketplaceCustomerRequestDraft.fromMap({
      'job_id': 'job-1',
      'service_request_id': 'request-1',
      'status': 'requested',
      'recommended_price': 1000,
      'minimum_price': 500,
      'low_price_warning_threshold': 800,
      'currency': 'CUP',
      'pricing_version': 'passenger-v1',
      'pricing_breakdown': {
        'base_price': 500,
        'recommended_price': 1000,
      },
      'server_time': '2026-09-16T01:00:00Z',
    });

    expect(draft.jobId, 'job-1');
    expect(draft.serviceRequestId, 'request-1');
    expect(draft.recommendedPrice, 1000);
    expect(draft.isBelowMinimum(499), isTrue);
    expect(draft.requiresWarningFor(700), isTrue);
    expect(draft.requiresWarningFor(850), isFalse);
    expect(draft.pricingBreakdown['base_price'], 500);
  });

  test('customer publication parses frozen price state', () {
    final publication = MarketplaceCustomerPublication.fromMap({
      'job_id': 'job-2',
      'status': 'published',
      'recommended_price': 1000,
      'final_price': 750,
      'minimum_price': 500,
      'low_price_warning_threshold': 800,
      'price_warning_required': true,
      'price_warning_acknowledged': true,
      'currency': 'CUP',
      'pricing_version': 'passenger-v1',
      'pricing_breakdown': {
        'recommended_price': 1000,
      },
      'published_at': '2026-09-16T01:00:00Z',
      'expires_at': '2026-09-16T02:00:00Z',
      'server_time': '2026-09-16T01:00:00Z',
    });

    expect(publication.status, 'published');
    expect(publication.finalPrice, 750);
    expect(publication.priceWarningRequired, isTrue);
    expect(
      publication.priceWarningAcknowledged,
      isTrue,
    );
    expect(publication.publishedAt, isNotNull);
    expect(publication.expiresAt, isNotNull);
  });

  test('customer request layer uses only Edge gateway operations', () {
    final source = File(
      'lib/data/marketplace_customer_request.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("'services'"),
    );
    expect(
      source,
      contains("'create_request'"),
    );
    expect(
      source,
      contains("'publish'"),
    );

    expect(source, isNot(contains(".from('jobs')")));
    expect(
      source,
      isNot(contains(".from('service_requests')")),
    );
    expect(
      source,
      isNot(contains(".from('marketplace_pricing_rules')")),
    );
    expect(source, isNot(contains('service_role')));
    expect(source, isNot(contains('.rpc(')));
  });
}
