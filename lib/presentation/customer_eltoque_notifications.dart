part of '../main.dart';

const _customerRatePushFunction = 'marketplace-customer-rate-push';
const _customerTurnstileSiteKey =
    String.fromEnvironment('CUSTOMER_TURNSTILE_SITE_KEY');

@visibleForTesting
bool customerRatePushNeedsProof({required bool hasExistingDeviceSecret}) =>
    !hasExistingDeviceSecret;
const _customerPushSecretCacheKey = 'customer:eltoque:device_secret';
const _customerPushTokenCacheKey = 'customer:eltoque:fcm_token';

@visibleForTesting
bool customerRatePushCanOptIn({
  required bool supported,
  required bool previouslyDenied,
}) =>
    supported && !previouslyDenied;

@visibleForTesting
String customerRateDeviceSecret(Random random) {
  return List<int>.generate(32, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

class CustomerRatePushClient {
  CustomerRatePushClient(this.supabase);

  final SupabaseClient supabase;

  Box get _store => Hive.box(_metaBox);

  bool get hasSavedSubscription =>
      _store.get(_customerPushSecretCacheKey) is String &&
      _store.get(_customerPushTokenCacheKey) is String;

  Future<bool> isSupported() async {
    if (!kIsWeb) return false; // Web phase only; future APK handled separately.
    try {
      return await FirebaseMessaging.instance.isSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> activate() async {
    if (!kIsWeb) {
      throw StateError(
          'Las notificaciones no están disponibles en este navegador.');
    }
    // The permission request is the FIRST awaited browser operation after the
    // tap. A preflight await can discard the browser's transient user gesture.
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
          'Permiso denegado. Puedes activarlo en los ajustes del navegador.');
    }
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: customerRateFirebaseVapidKey,
      serviceWorkerScriptPath: 'firebase-messaging-sw.js',
    );
    if (token == null || token.isEmpty) {
      throw StateError(
          'No se pudo registrar el dispositivo para recibir avisos.');
    }
    final existingSecret = _store.get(_customerPushSecretCacheKey);
    final secret = existingSecret is String && existingSecret.length == 64
        ? existingSecret
        : customerRateDeviceSecret(Random.secure());
    // Renewals use the saved device secret. New devices require a browser
    // challenge, verified by the Edge Function using a server-only key.
    final proof = !customerRatePushNeedsProof(
            hasExistingDeviceSecret:
                existingSecret is String && existingSecret.length == 64)
        ? null
        : await customerRateTurnstileProof(_customerTurnstileSiteKey);
    final response = await supabase.functions.invoke(
      _customerRatePushFunction,
      body: {
        'action': 'subscribe',
        'token': token,
        'device_secret': secret,
        if (proof != null) 'turnstile_token': proof,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError(
          'No se pudo confirmar la suscripción de este dispositivo.');
    }
    await _store.put(_customerPushSecretCacheKey, secret);
    await _store.put(_customerPushTokenCacheKey, token);
  }

  Future<void> refreshExisting() async {
    if (!hasSavedSubscription || !await isSupported()) return;
    try {
      final freshToken = await FirebaseMessaging.instance.getToken(
        vapidKey: customerRateFirebaseVapidKey,
        serviceWorkerScriptPath: 'firebase-messaging-sw.js',
      );
      if (freshToken == null || freshToken.isEmpty) return;
      final secret = _store.get(_customerPushSecretCacheKey) as String;
      final response = await supabase.functions.invoke(
        _customerRatePushFunction,
        body: {
          'action': 'subscribe',
          'token': freshToken,
          'device_secret': secret
        },
      );
      if (response.data is Map && (response.data as Map)['ok'] == true) {
        await _store.put(_customerPushTokenCacheKey, freshToken);
      }
    } catch (_) {
      // A push registration outage must never affect booking or map screens.
    }
  }

  Future<void> deactivate() async {
    final secret = _store.get(_customerPushSecretCacheKey);
    final token = _store.get(_customerPushTokenCacheKey);
    if (secret is! String || token is! String) return;
    final response = await supabase.functions.invoke(
      _customerRatePushFunction,
      body: {'action': 'unsubscribe', 'token': token, 'device_secret': secret},
    );
    if (response.data is! Map || (response.data as Map)['ok'] != true) {
      throw StateError('No se pudo desactivar la alerta. Intenta nuevamente.');
    }
    await _store.delete(_customerPushTokenCacheKey);
    await _store.delete(_customerPushSecretCacheKey);
    // This device's FCM token is not used by any other Cliente feature yet.
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
