import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

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

  test('cotizacion reserva espacio inicial para modalidades y pago', () {
    for (final height in [480.0, 640.0, 760.0, 800.0, 1100.0]) {
      final preferred = height < 760 ? .82 : .72;
      final min = marketplaceBookingPanelMinFraction(height, hasQuoteFooter: true);
      final initial = marketplaceQuoteInitialFraction(height, preferred: preferred, minimum: min);
      expect(initial, greaterThanOrEqualTo(preferred));
      expect(initial, greaterThanOrEqualTo(min));
      expect(initial, lessThanOrEqualTo(.94));
      if (height >= 640) {
        expect(height * .78 * initial, greaterThanOrEqualTo(459.9));
      } else {
        expect(initial, preferred);
      }
    }
  });

  test('distancia arriba y selector de servicios horizontal sin titulo redundante', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final locations = source.split('Widget _floatingOriginDestination()').last.split('Widget _floatingBookingPanel()').first;
    final options = source.split('Widget _floatingQuoteOptions()').last.split('Future<void> _openFloatingOptions()').first;
    expect(locations, contains('distanceLabel: flow.route == null'));
    expect(locations, contains('flow.route!.distanceKm.toStringAsFixed(1)'));
    expect(options, isNot(contains('Pide tu transporte')));
    expect(options, contains('MarketplaceCompactVehicleSelector('));
    expect(options, contains('BoxConstraints(minHeight: 32)'));
    expect(options, contains('child: Row('));
    expect(options, contains('FittedBox('));
  });

  test('panel compacto y CTA fijo se conservan', () {
    final source = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    expect(source, contains('initialChildSize: _initialBookingPanelFraction()'));
    expect(source, contains('if (flow.destination == null) return .36;'));
    expect(source, contains("MediaQuery.sizeOf(context).height < 760 ? .82 : .72"));
    expect(source, contains('return marketplaceQuoteInitialFraction('));
    expect(source, contains('minChildSize: _minBookingPanelFraction'));
    expect(source, contains('snapSizes: const [.56, .72, .82]'));
    expect(source, contains('.where((size) => size > _minBookingPanelFraction)'));
    expect(source, contains('Widget _quoteStickyFooter()'));
    expect(source, contains('NotificationListener<DraggableScrollableNotification>'));
    expect(File('lib/presentation/marketplace_booking_visual_primitives.dart').readAsStringSync(), contains('class _MarineCardSurface'));
  });
}
