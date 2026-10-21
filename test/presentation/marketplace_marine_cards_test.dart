import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('fichas marinas mantienen el catalogo de Vrixora Admin', () {
    final source = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    expect(source, contains('list_marketplace_published_modalities'));
    expect(source, contains('flow.publishedServices'));
    expect(
      RegExp(r'flow\.categoriesForService\(\s*flow\.serviceCode\s*,?\s*\)')
          .hasMatch(source),
      isTrue,
    );
    expect(source, contains('flow.setServiceVehicleCategory(category)'));
    expect(source, contains('flow.setPassengerVehicleCategory'));
    expect(source, contains('class _MarineVeinsPainter extends CustomPainter'));
    expect(
      source,
      contains('class _MarineCardSurface extends StatelessWidget'),
    );
    expect(source, contains("'Solicitar transporte'"));
  });

  testWidgets('selector conserva precios y permite cambiar vehiculo', (
    tester,
  ) async {
    var selected = 'motorcycle';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MarketplaceCompactVehicleSelector(
              selectedCategory: selected,
              categories: const ['motorcycle', 'tricycle', 'light_car'],
              priceLabel: (category) =>
                  category == 'tricycle' ? '1.800 CUP' : '1.300 CUP',
              onSelected: (category) => refresh(() => selected = category),
            ),
          ),
        ),
      ),
    );
    expect(find.text('1.800 CUP'), findsOneWidget);
    await tester.tap(find.byKey(const Key('vehicle-tricycle')));
    await tester.pumpAndSettle();
    expect(selected, 'tricycle');
    expect(find.text('1.800 CUP'), findsOneWidget);
  });
}
