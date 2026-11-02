import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'premium pickup/destination markers are distinct valid PNG assets',
    () async {
      final pickup = await rootBundle.load(
        'assets/map_markers/pickup_green.png',
      );
      final destination = await rootBundle.load(
        'assets/map_markers/destination_orange.png',
      );
      const magic = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      for (final icon in [pickup, destination]) {
        final bytes = icon.buffer.asUint8List(
          icon.offsetInBytes,
          icon.lengthInBytes,
        );
        expect(bytes.length, greaterThan(2000));
        expect(bytes.sublist(0, 8), magic);
        expect(icon.getUint32(16), 112);
        expect(icon.getUint32(20), 144);
      }
      expect(
        pickup.buffer.asUint8List(),
        isNot(equals(destination.buffer.asUint8List())),
      );
    },
  );
  test('destination orange is used in map, booking and tracking', () {
    final theme = File('lib/presentation/tuktuk_ui.dart').readAsStringSync();
    final vector = File('lib/presentation/marketplace_vector_map.dart').readAsStringSync();
    final booking = File('lib/presentation/marketplace_customer_booking_flow.dart').readAsStringSync();
    final tracking = File('lib/presentation/marketplace_customer_tracking.dart').readAsStringSync();
    expect(theme, contains('destinationOrange = Color(0xFFFF963E)'));
    expect(vector, contains('destination_orange.png'));
    expect(vector, contains('tuktuk-client-destination-orange-v8'));
    expect(vector, contains('lineColor: 0xFFFFC400'));
    expect(booking, contains('color: TuktukTheme.destinationOrange'));
    expect(booking, contains('iconColor: TuktukTheme.destinationOrange'));
    expect(tracking, contains('iconColor: TuktukTheme.destinationOrange'));
    expect(tracking, contains('color: TuktukTheme.destinationOrange'));
  });

}
