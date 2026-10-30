import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final quote = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
  final tracking = File('lib/presentation/marketplace_customer_tracking.dart').readAsStringSync();

  test('recogida automatica permite marcar directamente destino en mapa', () {
    expect(quote, contains('onPointTap: flow.origin == null && _selectingOrigin == null'));
    expect(quote, contains('final selectingOrigin = _selectingOrigin ?? (flow.origin == null ? null : false)'));
    expect(quote, contains('flow.setDestination(point)'));
    expect(quote, contains('flow.setPickupForQuote(point)'));
  });

  test('boton y precio persistentes fuera de la lista desplazable', () {
    expect(quote, contains('Widget _quoteStickyFooter()'));
    expect(quote, contains('if (flow.origin != null && flow.destination != null && _selectingOrigin == null)'));
    expect(quote, contains('child: ListView('));
    expect(quote, contains('label: _publishing ? \'Publicando...\' : \'Solicitar transporte\''));
  });

  test('tarjetas marinas uniformes y capa de seguimiento translucida', () {
    expect(quote, contains('final columns = constraints.maxWidth < 540 ? 2 : 4;'));
    expect(quote, contains('Color marketplaceVehicleAccent(String category)'));
    expect(quote, contains('tint: accent,'));
    expect(quote, contains('final columns = available.maxWidth < 280 ? 2 : 3;'));
    expect(quote, contains('class _MarineCardSurface extends StatelessWidget'));
    expect(tracking, contains('Color(0xE8173742)'));
    expect(quote, contains('visualOffset'));
  });
}