import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('componentes visuales de reserva permanecen en la misma biblioteca Dart', () {
    final entrypoint = File('lib/main.dart').readAsStringSync();
    final booking = File(
      'lib/presentation/marketplace_customer_booking_flow.dart',
    ).readAsStringSync();
    final primitives = File(
      'lib/presentation/marketplace_booking_visual_primitives.dart',
    ).readAsStringSync();

    expect(entrypoint, contains("part 'presentation/marketplace_customer_booking_flow.dart';"));
    expect(entrypoint, contains("part 'presentation/marketplace_booking_visual_primitives.dart';"));
    expect(primitives, startsWith("part of '../main.dart';"));

    for (final widget in [
      '_MarineCardSurface',
      '_MarineVeinsPainter',
      '_BenefitCard',
      '_MiniFact',
    ]) {
      expect(primitives, contains('class $widget extends'));
      expect(booking, isNot(contains('class $widget extends')));
    }
    expect(booking, contains('class MarketplaceCustomerBookingFlow extends StatefulWidget'));
    expect(booking, contains('class _TuktukGeoActivationButton extends StatefulWidget'));
  });
}
