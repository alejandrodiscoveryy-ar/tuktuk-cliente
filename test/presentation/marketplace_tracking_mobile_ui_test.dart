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
    expect(source, contains('Positioned.fill(child: _liveMap())'));
    expect(source, contains('initialChildSize: initialSheetSize'));
    expect(source, contains('NotificationListener<DraggableScrollableNotification>'));
    expect(source, contains('ornamentBottomInset: _trackingMapInset'));
    expect(source, contains('_trackingMapInset.value = height * .68'));
    expect(source, contains('_trackingActionFooter(job)'));
    expect(source, contains('Solicitar otro transporte'));
    expect(source, contains('Cancelar solicitud'));
    expect(source, isNot(contains('driverLiveLatitude')));
  });

  test('reserva y seguimiento mantienen el mismo filtro de luz', () {
    final booking = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    final tracking = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    const overlay = 'colors: [Color(0x1208141B), Color(0x0008141B)]';
    expect(booking, contains(overlay));
    expect(tracking, contains(overlay));
    expect(tracking, isNot(contains('Color(0x52050B10)')));
    // El estilo vectorial permanece compartido; solo se adapta el zoom.
    final map = File(
      'lib/presentation/marketplace_vector_map.dart',
    ).readAsStringSync();
    expect(map, contains('styleUri: MarketplaceMapService.vectorStyleUri'));
    expect(booking, contains('MarketplaceVectorMap('));
    expect(tracking, contains('MarketplaceVectorMap('));
  });

  test('seguimiento recibe respaldo de ruta sin duplicar datos remotos', () {
    final booking = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    final tracking = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();
    expect(booking, contains('initialMapData: transitionMap'));
    expect(booking, contains("'job_id': publication.jobId"));
    expect(booking, contains('saveActiveJobMap('));
    expect(tracking, contains('final Map<String, dynamic>? initialMapData;'));
    expect(tracking, contains('widget.initialMapData,'));
    expect(tracking, contains("mapData['job_id'] != widget.jobId"));
    expect(tracking, contains('Map<String, dynamic>.from(mapData'));
    expect(tracking, contains('Probar la siguiente fuente'));
    expect(tracking, contains('route = MarketplaceCustomerSessionStore('));
    expect(tracking, contains('El mapa de esta carrera no está disponible'));
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
