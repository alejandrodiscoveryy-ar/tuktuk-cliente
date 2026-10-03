import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale customer job returns safely to services', () {
    final service = File(
      'lib/data/marketplace_customer_service.dart',
    ).readAsStringSync();

    final tracking = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();

    expect(service, contains('on FunctionException catch (error)'));
    expect(service, contains("details['error']"));
    expect(tracking, contains("value.contains('ACCESS_DENIED')"));
    expect(tracking, contains('await _finish();'));
  });
}
