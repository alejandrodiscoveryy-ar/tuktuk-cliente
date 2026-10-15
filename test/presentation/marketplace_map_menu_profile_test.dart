import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la contratación mantiene mapa y panel de estados en una vista', () {
    final code = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    expect(code, contains('MarketplaceVectorMap('));
    expect(code, contains('DraggableScrollableSheet('));
    expect(code, contains('Widget _floatingBookingPanel()'));
    expect(code, contains('Widget _destinationSearchPrompt()'));
    expect(code, contains('onPointTap: _selectingOrigin == null'));
    expect(code, contains('route?.routePoints'));
    expect(code, contains('publishJob('));
    expect(code, contains('saveActiveJobId('));
  });

  test('menú contiene únicamente accesos operativos', () {
    final code = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    expect(code, contains('Future<void> _openCustomerMenu()'));
    expect(code, contains("'Perfil'"));
    expect(code, contains("'Historial'"));
    expect(code, isNot(contains("'Billetera'")));
    expect(code, isNot(contains("'Referidos'")));
  });

  test('editar perfil conserva widget del mapa en el árbol', () {
    final code = File(
      'lib/presentation/marketplace_customer.dart',
    ).readAsStringSync();
    expect(
      code,
      contains('if (_editingExistingSession) _editCustomerScreen()'),
    );
    expect(code, contains('Widget _editCustomerScreen() => Positioned.fill('));
    expect(code, contains('Guardar datos'));
    expect(code, contains('Volver al mapa'));
    expect(
      code,
      isNot(
        contains('if (_editingExistingSession) return _editCustomerScreen()'),
      ),
    );
  });
}
