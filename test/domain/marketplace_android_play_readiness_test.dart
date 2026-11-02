import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Play: API36, firma privada sin fallback debug', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(gradle, contains('applicationId = "com.vrixora.tuktukcliente"'));
    expect(gradle, contains('compileSdk = 36'));
    expect(gradle, contains('targetSdk = 36'));
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('releaseBuildRequested && !uploadSigningReady'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')));
    expect(pubspec, contains('version: 1.0.0+1'));
  });

  test('Android FCM: opciones Android distintas de Web, sin bypass Turnstile', () {
    final opts = File('lib/services/customer_rate_firebase_options.dart')
        .readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final subscriptions = File('lib/presentation/customer_eltoque_notifications.dart')
        .readAsStringSync();
    expect(opts, contains('customerRateFirebaseAndroidOptionsOrNull'));
    expect(opts, contains('FIREBASE_ANDROID_APP_ID'));
    expect(main, contains('_customerAndroidBackgroundMessage'));
    expect(main, contains('FirebaseMessaging.onBackgroundMessage('));
    expect(main, contains('FirebaseAppCheck.instance.activate('));
    expect(subscriptions, contains('defaultTargetPlatform != TargetPlatform.android'));
    expect(subscriptions, contains("proofKey: kIsWeb ? 'turnstile_token' : 'app_check_token'"));
    expect(subscriptions, contains('customerRateTurnstileProof('));
  });
}
