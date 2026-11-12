import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  testWidgets('ambos metodos son visibles, excluyentes y tactiles en movil estrecho',
      (tester) async {
    String value = 'cash';
    bool enabled = true;
    int changes = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: StatefulBuilder(builder: (context, setState) {
              update = setState;
              return MarketplaceRidePaymentSelector(
                value: value,
                enabled: enabled,
                onChanged: (next) => setState(() {
                  value = next;
                  changes++;
                }),
              );
            }),
          ),
        ),
      ),
    ));
    final cash = find.byKey(const ValueKey('booking-ride-payment-cash'));
    final transfer = find.byKey(const ValueKey('booking-ride-payment-transfer'));
    Color? background(Finder finder) =>
        tester.widget<OutlinedButton>(finder).style!.backgroundColor!.resolve({});
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
    expect(tester.getSize(cash).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(transfer).height, greaterThanOrEqualTo(44));
    expect(background(cash), TuktukTheme.mint);
    expect(background(transfer), TuktukTheme.surfaceStrong);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(transfer);
    await tester.pumpAndSettle();
    expect(value, 'transfer');
    expect(background(transfer), TuktukTheme.mint);
    expect(background(cash), TuktukTheme.surfaceStrong);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(changes, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(cash);
    await tester.pumpAndSettle();
    expect(value, 'cash');
    expect(changes, 2);
    update(() => enabled = false);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(transfer).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(cash).onPressed, isNull);
    expect(value, 'cash');
    expect(tester.takeException(), isNull);
  });

  test('la ficha reserva espacio para el selector y conserva la altura sin cotizacion', () {
    for (final height in [480.0, 640.0, 800.0, 1100.0]) {
      final min = marketplaceBookingPanelMinFraction(height, hasQuoteFooter: true);
      expect(min, greaterThanOrEqualTo(.26));
      expect(min, lessThanOrEqualTo(.90));
      expect(height * .78 * min, greaterThanOrEqualTo(247.9));
      expect(marketplaceBookingPanelMinFraction(height, hasQuoteFooter: false), .26);
    }
  });
}
