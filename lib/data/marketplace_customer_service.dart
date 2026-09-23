part of '../main.dart';

String marketplaceCustomerSessionToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(
    32,
    (_) => random.nextInt(256),
    growable: false,
  );

  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

class MarketplaceCustomerSession {
  const MarketplaceCustomerSession({
    required this.sessionId,
    required this.customerId,
    this.expiresAt,
    this.serverTime,
  });

  final String sessionId;
  final String customerId;
  final DateTime? expiresAt;
  final DateTime? serverTime;

  factory MarketplaceCustomerSession.fromMap(Map map) =>
      MarketplaceCustomerSession(
        sessionId: _marketText(map['session_id']) ?? '',
        customerId: _marketText(map['customer_id']) ?? '',
        expiresAt: _marketDate(map['expires_at']),
        serverTime: _marketDate(map['server_time']),
      );
}

class MarketplaceCustomerJob {
  const MarketplaceCustomerJob({
    required this.id,
    required this.status,
    required this.finalPrice,
    required this.currency,
    this.serviceCode,
    this.originText,
    this.destinationText,
    this.scheduledFor,
    this.publishedAt,
    this.expiresAt,
    this.createdAt,
    this.driverDisplayName,
    this.driverWhatsappPhone,
    this.driverPhotoAssetId,
    this.vehicleId,
    this.vehicleName,
    this.vehicleCategoryCode,
    this.vehicleBrand,
    this.vehicleModel,
    this.vehicleRegistration,
    this.vehicleMainPhotoAssetId,
  });

  final String id;
  final String status;
  final String? serviceCode;
  final String? originText;
  final String? destinationText;
  final DateTime? scheduledFor;
  final double finalPrice;
  final String currency;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  final String? driverDisplayName;
  final String? driverWhatsappPhone;
  final String? driverPhotoAssetId;

  final String? vehicleId;
  final String? vehicleName;
  final String? vehicleCategoryCode;
  final String? vehicleBrand;
  final String? vehicleModel;
  final String? vehicleRegistration;
  final String? vehicleMainPhotoAssetId;

  bool get hasAssignedDriver => driverDisplayName != null || vehicleId != null;

  bool get customerCanCancel => const {
        'requested',
        'published',
        'accepted',
        'en_route',
        'pickup',
      }.contains(status);

  bool get isTerminal => const {
        'settled',
        'cancelled_by_customer',
        'cancelled_by_driver',
        'expired',
        'incident',
      }.contains(status);

  factory MarketplaceCustomerJob.fromMap(Map map) => MarketplaceCustomerJob(
        id: _marketText(map['job_id'] ?? map['id']) ?? '',
        status: _marketText(map['status']) ?? 'unknown',
        serviceCode: _marketText(map['service_code']),
        originText: _marketText(map['origin_text']),
        destinationText: _marketText(map['destination_text']),
        scheduledFor: _marketDate(map['scheduled_for']),
        finalPrice: _marketNumber(map['final_price']),
        currency: _marketText(map['currency']) ?? 'CUP',
        publishedAt: _marketDate(map['published_at']),
        expiresAt: _marketDate(map['expires_at']),
        createdAt: _marketDate(map['created_at']),
        driverDisplayName: _marketText(map['driver_display_name']),
        driverWhatsappPhone: _marketText(map['driver_whatsapp_phone']),
        driverPhotoAssetId: _marketText(map['driver_photo_asset_id']),
        vehicleId: _marketText(map['vehicle_id']),
        vehicleName: _marketText(map['vehicle_name']),
        vehicleCategoryCode: _marketText(map['vehicle_category_code']),
        vehicleBrand: _marketText(map['vehicle_brand']),
        vehicleModel: _marketText(map['vehicle_model']),
        vehicleRegistration: _marketText(map['vehicle_registration']),
        vehicleMainPhotoAssetId:
            _marketText(map['vehicle_main_photo_asset_id']),
      );
}

class MarketplaceCustomerCancellation {
  const MarketplaceCustomerCancellation({
    required this.jobId,
    required this.status,
    this.serverTime,
  });

  final String jobId;
  final String status;
  final DateTime? serverTime;

  factory MarketplaceCustomerCancellation.fromMap(Map map) =>
      MarketplaceCustomerCancellation(
        jobId: _marketText(map['job_id']) ?? '',
        status: _marketText(map['status']) ?? 'unknown',
        serverTime: _marketDate(map['server_time']),
      );
}

class MarketplaceCustomerRating {
  const MarketplaceCustomerRating({
    required this.jobId,
    required this.stars,
    this.comment,
    this.createdAt,
  });

  final String jobId;
  final int stars;
  final String? comment;
  final DateTime? createdAt;

  factory MarketplaceCustomerRating.fromMap(Map map) =>
      MarketplaceCustomerRating(
        jobId: _marketText(map['job_id']) ?? '',
        stars: _marketNumber(map['stars']).round(),
        comment: _marketText(map['comment']),
        createdAt: _marketDate(map['created_at']),
      );
}

class MarketplaceCustomerJobMedia {
  const MarketplaceCustomerJobMedia({
    this.driverPhotoSignedUrl,
    this.vehiclePhotoSignedUrl,
    this.expiresAt,
  });

  final String? driverPhotoSignedUrl;
  final String? vehiclePhotoSignedUrl;
  final DateTime? expiresAt;

  factory MarketplaceCustomerJobMedia.fromMap(Map map) =>
      MarketplaceCustomerJobMedia(
        driverPhotoSignedUrl: _marketText(map['driver_photo_signed_url']),
        vehiclePhotoSignedUrl: _marketText(map['vehicle_photo_signed_url']),
        expiresAt: _marketDate(map['expires_at']),
      );
}

class MarketplaceCustomerSessionSnapshot {
  const MarketplaceCustomerSessionSnapshot({
    required this.sessionId,
    required this.customerId,
    required this.token,
    this.expiresAt,
  });

  final String sessionId;
  final String customerId;
  final String token;
  final DateTime? expiresAt;
}

class MarketplaceCustomerSessionStore {
  MarketplaceCustomerSessionStore(this._box);

  final Box _box;

  static const _sessionIdKey = 'marketplace_customer_session_id';
  static const _customerIdKey = 'marketplace_customer_customer_id';
  static const _tokenKey = 'marketplace_customer_session_token';
  static const _expiresAtKey = 'marketplace_customer_session_expires_at';
  static const _activeJobIdKey = 'marketplace_customer_active_job_id';

  MarketplaceCustomerSessionSnapshot? read() {
    final sessionId = _marketText(_box.get(_sessionIdKey));
    final customerId = _marketText(_box.get(_customerIdKey));
    final token = _marketText(_box.get(_tokenKey));

    if (sessionId == null || customerId == null || token == null) {
      return null;
    }

    return MarketplaceCustomerSessionSnapshot(
      sessionId: sessionId,
      customerId: customerId,
      token: token,
      expiresAt: _marketDate(_box.get(_expiresAtKey)),
    );
  }

  Future<void> save({
    required MarketplaceCustomerSession session,
    required String token,
  }) async {
    await _box.putAll({
      _sessionIdKey: session.sessionId,
      _customerIdKey: session.customerId,
      _tokenKey: token,
      _expiresAtKey: session.expiresAt?.toIso8601String(),
    });
  }

  String? readActiveJobId() => _marketText(_box.get(_activeJobIdKey));

  Future<void> saveActiveJobId(String jobId) async {
    await _box.put(_activeJobIdKey, jobId);
  }

  Future<void> clearActiveJobId() async {
    await _box.delete(_activeJobIdKey);
  }

  Future<void> clear() async {
    await _box.deleteAll([
      _sessionIdKey,
      _customerIdKey,
      _tokenKey,
      _expiresAtKey,
      _activeJobIdKey,
    ]);
  }
}

class MarketplaceCustomerService {
  MarketplaceCustomerService(this._client);

  final SupabaseClient _client;

  Future<dynamic> _gateway(String operation,
      [Map<String, dynamic>? params]) async {
    final response = await _client.functions.invoke(
      'marketplace-customer-gateway',
      body: {
        'operation': operation,
        'params': params ?? const <String, dynamic>{}
      },
    );
    final value = response.data;
    if (value is Map && value['error'] != null) {
      throw StateError(value['error'].toString());
    }
    return value is Map ? value['data'] : null;
  }

  Future<Map<String, dynamic>> _gatewayOne(
    String operation, [
    Map<String, dynamic>? params,
  ]) async {
    final value = await _gateway(operation, params);
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return <String, dynamic>{};
  }

  Future<MarketplaceCustomerSession> startSession({
    required String displayName,
    required String whatsappPhone,
    required String sessionToken,
    required String idempotencyKey,
  }) =>
      _gatewayOne(
        'start_session',
        {
          'target_display_name': displayName,
          'target_whatsapp_phone': whatsappPhone,
          'target_session_token': sessionToken,
          'target_idempotency_key': idempotencyKey,
        },
      ).then(MarketplaceCustomerSession.fromMap);

  Future<MarketplaceCustomerJob> getJob({
    required String sessionId,
    required String sessionToken,
    required String jobId,
  }) =>
      _gatewayOne(
        'get_job',
        {
          'target_session_id': sessionId,
          'target_session_token': sessionToken,
          'target_job_id': jobId,
        },
      ).then(MarketplaceCustomerJob.fromMap);

  Future<MarketplaceCustomerCancellation> cancelJob({
    required String sessionId,
    required String sessionToken,
    required String jobId,
    required String reason,
    required String idempotencyKey,
  }) =>
      _gatewayOne(
        'cancel',
        {
          'target_session_id': sessionId,
          'target_session_token': sessionToken,
          'target_job_id': jobId,
          'target_reason': reason,
          'target_idempotency_key': idempotencyKey,
        },
      ).then(MarketplaceCustomerCancellation.fromMap);

  Future<MarketplaceCustomerRating?> getRating({
    required String sessionId,
    required String sessionToken,
    required String jobId,
  }) async {
    final value = await _gateway('get_rating', {
      'target_session_id': sessionId,
      'target_session_token': sessionToken,
      'target_job_id': jobId,
    });
    if (value is List && value.isNotEmpty && value.first is Map) {
      return MarketplaceCustomerRating.fromMap(value.first as Map);
    }
    return null;
  }

  Future<MarketplaceCustomerRating> createRating({
    required String sessionId,
    required String sessionToken,
    required String jobId,
    required int stars,
    required String idempotencyKey,
    String? comment,
  }) =>
      _gatewayOne('create_rating', {
        'target_session_id': sessionId,
        'target_session_token': sessionToken,
        'target_job_id': jobId,
        'target_stars': stars,
        'target_comment': comment,
        'target_idempotency_key': idempotencyKey,
      }).then(MarketplaceCustomerRating.fromMap);

  Future<MarketplaceCustomerJobMedia> getJobMedia({
    required String sessionId,
    required String sessionToken,
    required String jobId,
  }) =>
      _gatewayOne('media', {
        'target_session_id': sessionId,
        'target_session_token': sessionToken,
        'target_job_id': jobId,
      }).then(MarketplaceCustomerJobMedia.fromMap);
}
