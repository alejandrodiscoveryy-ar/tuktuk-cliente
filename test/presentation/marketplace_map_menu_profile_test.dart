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
    expect(code, contains('onPointTap: flow.origin == null && _selectingOrigin == null'));
    expect(code, contains('route?.routePoints'));
    expect(code, contains('publishJob('));
    expect(code, contains('saveActiveJobId('));
  });

  test('menu 3x2 conserva accesos operativos y funciones proximas desactivadas', () {
    final code = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    final start = code.indexOf('  Future<void> _openCustomerMenu() async {');
    final finish = code.indexOf('  Future<void> _showCustomerMenuDetail(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(finish, greaterThan(start));
    final menu = code.substring(start, finish);
    for (final label in ['Perfil', 'Historial', 'Billetera', 'Referidos', 'Ajustes', 'Ayuda']) {
      expect(menu, contains("'$label'"));
    }
    expect(menu, contains('widget.onEditCustomer?.call()'));
    expect(menu, contains('unawaited(_openHistory())'));
    expect(menu, contains("Icons.wallet_outlined, 'Billetera', null, comingSoon: true,"));
    expect(menu, contains("Icons.card_giftcard_rounded, 'Referidos', null,"));
    expect(RegExp(r'comingSoon:\s*true').allMatches(menu).length, 2);
    expect(code, contains('onTap: comingSoon ? null : onTap'));
    expect(code, contains("Text('Próximamente'"));
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
