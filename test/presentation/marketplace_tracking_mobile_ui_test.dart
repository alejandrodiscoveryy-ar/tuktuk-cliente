import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu de cliente sin circulo amarillo y rayas verdes', () {
    final source = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    final menu = source
        .split('Widget _bookingHeader()')
        .last
        .split('Future<void> _openCustomerMenu()')
        .first;
    expect(menu, contains('backgroundColor: TuktukTheme.background'));
    expect(menu, contains('foregroundColor: Colors.white'));
    expect(menu, contains('BorderSide(color: TuktukTheme.gold'));
    expect(menu, isNot(contains('IconButton.filledTonal(')));
  });

  test('seguimiento reserva mapa y fija botones sin tapar atribucion', () {
    final source = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    expect(source, contains('FractionallySizedBox('));
    expect(source, contains('heightFactor: .61'));
    expect(source, contains('initialChildSize: .41'));
    expect(source, contains('minChildSize: .41'));
    expect(source, contains('_trackingActionFooter(job)'));
    expect(source, contains('Solicitar otro transporte'));
    expect(source, contains('Cancelar solicitud'));
    expect(source, isNot(contains('driverLiveLatitude')));
  });

  test('calificacion utilizable sin pantalla vacia ni boton al fondo', () {
    final source = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    final form = source
        .split('class _MarketplaceCustomerRatingScreenState')
        .last;
    expect(form, contains('Size.fromHeight(54)'));
    expect(form, contains('WrapAlignment.spaceEvenly'));
    expect(form, isNot(contains('const Spacer()')));
  });
}
