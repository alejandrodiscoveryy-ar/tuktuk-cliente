import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
  final valid = {
    'project_id': projectId,
    'support': {'enabled': true, 'number': '+5355555555'},
  };

  test('el soporte utiliza solo el numero publico activo del proyecto', () {
    expect(marketplaceCustomerPublicSupportNumber(valid, projectId),
        '+5355555555');
    expect(marketplaceCustomerPublicSupportNumber({
      ...valid, 'project_id': 'otro-proyecto',
    }, projectId), isNull);
    expect(marketplaceCustomerPublicSupportNumber({
      ...valid, 'support': {'enabled': false, 'number': '+5355555555'},
    }, projectId), isNull);
    expect(marketplaceCustomerPublicSupportNumber({
      ...valid, 'support': {'enabled': true, 'number': '5355555555'},
    }, projectId), isNull);
    expect(marketplaceCustomerPublicSupportNumber(null, projectId), isNull);
  });

  test('los seis accesos conservan funciones correctas', () {
    final source = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    for (final label in ['Perfil', 'Historial', 'Billetera',
      'Referidos', 'Ajustes', 'Ayuda']) {
      expect(source, contains("'$label'"));
    }
    expect(source, contains("'get_public_whatsapp_settings'"));
    expect(source, contains('launchUrl(uri, mode: LaunchMode.externalApplication)'));
    expect(source, contains('onTap: comingSoon ? null : onTap'));
    expect(source, contains("'Billetera', null, comingSoon: true"));
    expect(source, contains("'Referidos', null,"));
    expect(source, contains('TuktukCustomerMenuGlyphPainter(title, tint)'));
  });

  testWidgets('cuatro iconos vectoriales se dibujan sin fuentes externas',
      (tester) async {
    for (final kind in ['Billetera', 'Referidos', 'Ajustes', 'Ayuda']) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: CustomPaint(
            size: const Size(28, 28),
            painter: TuktukCustomerMenuGlyphPainter(kind, Colors.green),
          )),
        ),
      ));
      expect(tester.takeException(), isNull, reason: kind);
    }
  });
}