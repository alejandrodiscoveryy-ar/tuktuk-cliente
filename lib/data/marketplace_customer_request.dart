part of '../main.dart';

Map<String, dynamic> _marketplaceCustomerMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

bool _marketplaceCustomerBool(Object? value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

class MarketplaceCustomerServiceOption {
  const MarketplaceCustomerServiceOption({
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.currency,
    required this.pricingVersion,
  });

  final String code;
  final String name;
  final int sortOrder;
  final String currency;
  final String pricingVersion;

  factory MarketplaceCustomerServiceOption.fromMap(Map map) =>
      MarketplaceCustomerServiceOption(
        code: _marketText(map['service_code']) ?? '',
        name: _marketText(map['service_name']) ?? '',
        sortOrder: _marketNumber(map['sort_order']).round(),
        currency: _marketText(map['currency']) ?? 'CUP',
        pricingVersion: _marketText(map['pricing_version']) ?? '',
      );
}

class MarketplaceCustomerRequestDraft {
  const MarketplaceCustomerRequestDraft({
    required this.jobId,
    required this.serviceRequestId,
    required this.status,
    required this.recommendedPrice,
    required this.minimumPrice,
    required this.lowPriceWarningThreshold,
    required this.currency,
    required this.pricingVersion,
    required this.pricingBreakdown,
    this.serverTime,
  });

  final String jobId;
  final String serviceRequestId;
  final String status;
  final double recommendedPrice;
  final double minimumPrice;
  final double lowPriceWarningThreshold;
  final String currency;
  final String pricingVersion;
  final Map<String, dynamic> pricingBreakdown;
  final DateTime? serverTime;

  bool requiresWarningFor(double price) => price < lowPriceWarningThreshold;

  bool isBelowMinimum(double price) => price < minimumPrice;

  factory MarketplaceCustomerRequestDraft.fromMap(Map map) =>
      MarketplaceCustomerRequestDraft(
        jobId: _marketText(map['job_id']) ?? '',
        serviceRequestId: _marketText(map['service_request_id']) ?? '',
        status: _marketText(map['status']) ?? 'requested',
        recommendedPrice: _marketNumber(map['recommended_price']),
        minimumPrice: _marketNumber(map['minimum_price']),
        lowPriceWarningThreshold:
            _marketNumber(map['low_price_warning_threshold']),
        currency: _marketText(map['currency']) ?? 'CUP',
        pricingVersion: _marketText(map['pricing_version']) ?? '',
        pricingBreakdown: _marketplaceCustomerMap(map['pricing_breakdown']),
        serverTime: _marketDate(map['server_time']),
      );
}

class MarketplaceCustomerPublication {
  const MarketplaceCustomerPublication({
    required this.jobId,
    required this.status,
    required this.recommendedPrice,
    required this.finalPrice,
    required this.minimumPrice,
    required this.lowPriceWarningThreshold,
    required this.priceWarningRequired,
    required this.priceWarningAcknowledged,
    required this.currency,
    required this.pricingVersion,
    required this.pricingBreakdown,
    this.publishedAt,
    this.expiresAt,
    this.serverTime,
  });

  final String jobId;
  final String status;
  final double recommendedPrice;
  final double finalPrice;
  final double minimumPrice;
  final double lowPriceWarningThreshold;
  final bool priceWarningRequired;
  final bool priceWarningAcknowledged;
  final String currency;
  final String pricingVersion;
  final Map<String, dynamic> pricingBreakdown;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime? serverTime;

  factory MarketplaceCustomerPublication.fromMap(Map map) =>
      MarketplaceCustomerPublication(
        jobId: _marketText(map['job_id']) ?? '',
        status: _marketText(map['status']) ?? 'unknown',
        recommendedPrice: _marketNumber(map['recommended_price']),
        finalPrice: _marketNumber(map['final_price']),
        minimumPrice: _marketNumber(map['minimum_price']),
        lowPriceWarningThreshold:
            _marketNumber(map['low_price_warning_threshold']),
        priceWarningRequired: _marketplaceCustomerBool(
          map['price_warning_required'],
        ),
        priceWarningAcknowledged: _marketplaceCustomerBool(
          map['price_warning_acknowledged'],
        ),
        currency: _marketText(map['currency']) ?? 'CUP',
        pricingVersion: _marketText(map['pricing_version']) ?? '',
        pricingBreakdown: _marketplaceCustomerMap(map['pricing_breakdown']),
        publishedAt: _marketDate(map['published_at']),
        expiresAt: _marketDate(map['expires_at']),
        serverTime: _marketDate(map['server_time']),
      );
}

extension MarketplaceCustomerRequestApi on MarketplaceCustomerService {
  Future<List<Map<String, dynamic>>> _customerMany(
    String operation, [
    Map<String, dynamic>? params,
  ]) async {
    final value = await _gateway(operation, params);

    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  Future<List<MarketplaceCustomerServiceOption>> listCustomerServices() async {
    final rows = await _customerMany(
      'services',
    );

    return rows
        .map(MarketplaceCustomerServiceOption.fromMap)
        .toList(growable: false);
  }

  Future<MarketplaceCustomerRequestDraft> createRequest({
    required String sessionId,
    required String sessionToken,
    required String serviceCode,
    required String originText,
    required String destinationText,
    required String idempotencyKey,
    DateTime? scheduledFor,
    int? passengerCount,
    double? cargoWeightKg,
    double? cargoVolumeM3,
    double? cargoLengthCm,
    double? cargoWidthCm,
    double? cargoHeightCm,
    String? requiredBodyType,
    String? notes,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) =>
      _gatewayOne(
        'create_request',
        {
          'target_session_id': sessionId,
          'target_session_token': sessionToken,
          'target_service_code': serviceCode,
          'target_origin_text': originText,
          'target_destination_text': destinationText,
          'target_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          'target_passenger_count': passengerCount,
          'target_cargo_weight_kg': cargoWeightKg,
          'target_cargo_volume_m3': cargoVolumeM3,
          'target_cargo_length_cm': cargoLengthCm,
          'target_cargo_width_cm': cargoWidthCm,
          'target_cargo_height_cm': cargoHeightCm,
          'target_required_body_type': requiredBodyType,
          'target_notes': notes,
          'target_details': details,
          'target_idempotency_key': idempotencyKey,
        },
      ).then(MarketplaceCustomerRequestDraft.fromMap);

  Future<MarketplaceCustomerPublication> publishJob({
    required String sessionId,
    required String sessionToken,
    required String jobId,
    required double finalPrice,
    required bool priceWarningAcknowledged,
    required String idempotencyKey,
  }) =>
      _gatewayOne(
        'publish',
        {
          'target_session_id': sessionId,
          'target_session_token': sessionToken,
          'target_job_id': jobId,
          'target_final_price': finalPrice,
          'target_price_warning_acknowledged': priceWarningAcknowledged,
          'target_idempotency_key': idempotencyKey,
        },
      ).then(MarketplaceCustomerPublication.fromMap);
}
