import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tarifas reales por categoria y sin revelar solo la seleccionada', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    expect(source, contains('vehiclePriceForCard(category)'));
    expect(source, contains('mapService.reprice('));
    expect(source, contains("'vehicle_category_code': category"));
    expect(source, contains('loadCategoryComparisons()'));
    expect(source, isNot(contains('selected && flow.selectedPrice != null')));
  });

  test('Mapbox conserva sus creditos por encima de la ficha', () {
    final source = File('lib/presentation/marketplace_vector_map.dart').readAsStringSync();
    expect(source, contains('map.logo.updateSettings('));
    expect(source, contains('map.attribution.updateSettings('));
    expect(source, contains('marginBottom: inset + 10'));
    expect(source, isNot(contains('LogoSettings(enabled: false)')));
  });

  test('Mapbox tiene margen inicial aun sin arrastrar la ficha', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final map = File('lib/presentation/marketplace_vector_map.dart').readAsStringSync();
    expect(source, contains('void _syncInitialMapboxCredits()'));
    expect(source, contains('_syncInitialMapboxCredits();'));
    expect(source, contains('_bookingPanelHeight = viewportHeight * .78 * panelFraction;'));
    expect(source, contains('_refreshMapOrnaments();'));
    expect(map, contains('onStyleLoadedListener: (_) {'));
    expect(map, contains('_updateOrnaments();'));
  });

  test('panel compacto y CTA fijo se conservan', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    expect(source, contains('initialChildSize: flow.destination == null ? .36 : .56'));
    expect(source, contains('Widget _quoteStickyFooter()'));
    expect(source, contains('NotificationListener<DraggableScrollableNotification>'));
    expect(source, contains('class _MarineCardSurface'));
  });
}
