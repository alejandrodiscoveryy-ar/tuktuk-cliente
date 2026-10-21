import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  final prices = <String, String>{
    'motorcycle': '1.600 CUP',
    'bicitaxi': '800 CUP',
    'tricycle': '2.700 CUP',
    'light_car': '3.500 CUP',
  };

  Widget preview(
    double width,
    ValueChanged<String> select, {
    String selected = 'motorcycle',
    List<String> categories = marketplacePassengerVehicleCategories,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: MarketplaceCompactVehicleSelector(
            selectedCategory: selected,
            categories: categories,
            priceLabel: (category) => prices[category]!,
            onSelected: select,
          ),
        ),
      ),
    ),
  );

  testWidgets('cuatro modalidades visibles y completas en telefono normal', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(preview(350, (value) => chosen = value));
    expect(find.byKey(const Key('vehicle-motorcycle')), findsOneWidget);
    expect(find.byKey(const Key('vehicle-bicitaxi')), findsOneWidget);
    expect(find.byKey(const Key('vehicle-tricycle')), findsOneWidget);
    expect(find.byKey(const Key('vehicle-light_car')), findsOneWidget);
    expect(find.text('1.600 CUP'), findsOneWidget);
    expect(find.text('2.700 CUP'), findsOneWidget);
    expect(find.text('3.500 CUP'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('vehicle-motorcycle'))).dy,
      tester.getTopLeft(find.byKey(const Key('vehicle-light_car'))).dy,
    );
    await tester.tap(find.byKey(const Key('vehicle-tricycle')));
    await tester.pump();
    expect(chosen, 'tricycle');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no muestra Bicitaxi cuando el administrador no lo publica', (tester) async {
    await tester.pumpWidget(preview(350, (_) {}, categories: const ['motorcycle', 'tricycle', 'light_car']));
    expect(find.byKey(const Key('vehicle-bicitaxi')), findsNothing);
    expect(find.byKey(const Key('vehicle-tricycle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Carga y Mensajeria usan la categoria publicada en el precio y solicitud', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    expect(source, contains("'service_code': serviceCode"));
    expect(source, contains("'vehicle_category_code': selectedVehicleCategoryCode"));
    expect(source, contains("'target_vehicle_category_code': selectedVehicleCategoryCode"));
    expect(source, contains('publishedCategoriesByService'));
    expect(source, contains('onSelected: (_) => flow.setServiceVehicleCategory(category)'));
  });

  testWidgets('ancho pequeno adapta a 2 x 2 sin ocultar vehiculos', (
    tester,
  ) async {
    await tester.pumpWidget(preview(285, (_) {}));
    expect(find.byKey(const Key('vehicle-light_car')), findsOneWidget);
    final motoY = tester
        .getTopLeft(find.byKey(const Key('vehicle-motorcycle')))
        .dy;
    final biciY = tester
        .getTopLeft(find.byKey(const Key('vehicle-bicitaxi')))
        .dy;
    final triY = tester
        .getTopLeft(find.byKey(const Key('vehicle-tricycle')))
        .dy;
    expect(motoY, biciY);
    expect(triY, greaterThan(motoY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('se conserva seleccion dorada al cambiar de modalidad', (
    tester,
  ) async {
    await tester.pumpWidget(preview(350, (_) {}, selected: 'motorcycle'));
    await tester.pumpWidget(preview(350, (_) {}, selected: 'tricycle'));
    expect(find.text('2.700 CUP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('contratacion sigue usando precio del servidor y un solo CTA', () {
    final source = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("_priceLabel(_passengerPrice(category), 'passenger')"),
    );
    expect(source, contains('onSelected: flow.setPassengerVehicleCategory'));
    expect(source, contains('publishJob('));
    expect(source, contains('Solicitar transporte'));
    expect(source, isNot(contains('width: 158')));
    expect(source, isNot(contains('height: 94')));
  });
}
