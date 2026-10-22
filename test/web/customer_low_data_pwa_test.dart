import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PWA and notification worker share one scoped registration', () {
    final index = File('web/index.html').readAsStringSync();
    final worker = File('web/firebase-messaging-sw.js').readAsStringSync();
    expect(index, contains("register('firebase-messaging-sw.js'"));
    expect(index, contains("scope: './'"));
    expect(worker, contains("importScripts('customer-cache-sw.js')"));
    expect(worker, contains('messaging.onBackgroundMessage'));
  });

  test('static cache cannot cache booking API, Mapbox or private sessions', () {
    final cache = File('web/customer-cache-sw.js').readAsStringSync();
    expect(cache, contains('TUKTUK_SCOPE.pathname'));
    expect(cache, contains("request.method !== 'GET'"));
    expect(cache, contains("request.headers.has('authorization')"));
    expect(cache, contains('TUKTUK_STATIC.test(relative)'));
    expect(cache, isNot(contains("cache.addAll(['https://")));
    expect(cache, contains('__TUKTUK_RELEASE__'));
  });

  test('Turnstile loads only on opt-in and tracking stops in background', () {
    final index = File('web/index.html').readAsStringSync();
    final tracking = File('lib/presentation/marketplace_customer_tracking.dart').readAsStringSync();
    expect(index, contains('window.tuktukLoadTurnstile'));
    expect(index, contains('await window.tuktukLoadTurnstile()'));
    expect(index, isNot(contains('<script src="https://challenges.cloudflare.com/turnstile')));
    expect(tracking, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(tracking, contains('AppLifecycleState.hidden'));
    expect(tracking, contains('AppLifecycleState.resumed'));
  });

  test('Cloudflare browser cache rules keep scripts revalidated', () {
    final headers = File('web/_headers').readAsStringSync();
    expect(headers, contains('/cliente/tuk/main.dart.js'));
    expect(headers, contains('max-age=0, must-revalidate'));
    expect(headers, contains('/cliente/tuk/assets/*'));
  });
}
