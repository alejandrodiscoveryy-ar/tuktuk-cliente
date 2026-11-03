import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';

  test('Android Lite solo usa un numero E164 y un canal publicado', () {
    expect(marketplaceCustomerPublicLiteNumber({
      'project_id': projectId,
      'support': {
        'number': '+5350012345',
        'enabled': false,
        'lite_enabled': true,
        'lite_open': true,
      }
    }, projectId), '+5350012345');
    expect(marketplaceCustomerPublicLiteNumber({
      'project_id': projectId,
      'support': {'number': '+5350012345', 'lite_enabled': false, 'enabled': true}
    }, projectId), isNull);
    expect(marketplaceCustomerPublicLiteNumber({
      'project_id': projectId,
      'support': {'number': '+5350012345', 'lite_enabled': true, 'lite_open': false}
    }, projectId), isNull);
    expect(marketplaceCustomerPublicLiteNumber({
      'project_id': 'otro-proyecto',
      'support': {'number': '+5350012345', 'lite_enabled': true}
    }, projectId), isNull);
    expect(marketplaceCustomerPublicLiteNumber({
      'project_id': projectId,
      'support': {'number': '555', 'lite_enabled': true}
    }, projectId), isNull);
  });

  test('Android Lite respeta plataforma y nunca publica solicitud', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart')
        .readAsStringSync();
    expect(source, contains('_openAndroidLiteWhatsApp()'));
    expect(source, contains('defaultTargetPlatform != TargetPlatform.android'));
    expect(source, contains('marketplaceCustomerPublicLiteNumber(data, _liteProjectId)'));
    expect(source, contains('No hay precio ni reserva confirmados.'));
    expect(source, contains('await pendingRoute.timeout(const Duration(seconds: 22))'));
  });

  test('Mapbox aplica estilo unico y restaura capas tras actualizarlo', () {
    final source = File('lib/presentation/marketplace_vector_map.dart')
        .readAsStringSync();
    expect(source, contains('ValueKey<String>(MarketplaceMapService.vectorStyleUri)'));
    expect(source, contains('MarketplaceMapService.publicVisualRevision.addListener'));
    expect(source, contains('MarketplaceMapService.publicVisualRevision.removeListener'));
    expect(source, contains('    _layersReady = false;'));
    expect(source, contains('lineColor: 0xFFFFC400'));
    expect(source, contains('pickup_green.png'));
    expect(source, contains('destination_orange.png'));
  });
}