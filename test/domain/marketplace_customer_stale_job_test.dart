import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale customer state recovers safely', () {
    final tracking = File(
      'lib/presentation/marketplace_customer_tracking.dart',
    ).readAsStringSync();

    expect(tracking, contains("contains('CUSTOMER_SESSION_NOT_FOUND')"));
    expect(tracking, contains("contains('CUSTOMER_SESSION_EXPIRED')"));
    expect(tracking, contains("contains('CUSTOMER_SESSION_INVALID')"));
    expect(tracking, contains('await _resetInvalidSession();'));
    expect(tracking, contains('await sessionStore.clear();'));

    expect(tracking, contains("contains('JOB_NOT_FOUND')"));
    expect(tracking, contains("contains('ACCESS_DENIED')"));
    expect(tracking, contains('await _finish();'));
  });
}
