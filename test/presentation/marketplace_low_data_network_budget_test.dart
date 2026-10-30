import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tasa opcional no compite con el primer frame ni con viajes', () {
    final source = File('lib/presentation/customer_eltoque_banner.dart')
        .readAsStringSync();
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source, contains('_initialRateTimer = Timer(const Duration(seconds: 3)'));
    expect(source, contains('.timeout(const Duration(seconds: 10))'));
    expect(source, contains('if (_loading || !_appVisible) return;'));
    expect(source, contains('_initialRateTimer?.cancel();'));
    expect(source, contains('const Duration(minutes: 5)'));
    expect(source, contains('FirebaseMessaging.onMessage.listen'));
  });

  test('catalogo publicado solo consulta servidor con tiempo acotado', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart')
        .readAsStringSync();
    expect(source, contains('if (_loadingPublishedModalities) return;'));
    expect(source, contains('_loadingPublishedModalities = true;'));
    expect(source, contains('_loadingPublishedModalities = false;'));
    expect(source, contains("'list_marketplace_published_modalities'"));
    expect(source, contains('.timeout(const Duration(seconds: 18))'));
    expect(source, contains('publicationReady = false;'));
    expect(source, contains('publicationReady = true;'));
    expect(source, contains('No podemos comprobar las modalidades disponibles. Reintenta.'));
    // Nunca suplanta un catalogo no verificado con opciones supuestas.
    expect(source, isNot(contains('publicationReady = true; // fallback')));
  });
}