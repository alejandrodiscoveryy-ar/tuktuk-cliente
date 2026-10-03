import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale customer job returns safely to services', () {
    final tracking =
        File('lib/presentation/marketplace_customer_tracking.dart')
            .readAsStringSync();

    expect(tracking, contains('on FunctionsHttpException catch (error)'));
    expect(tracking, contains("contains('ACCESS_DENIED')"));
    expect(tracking, contains('await _finish();'));
  });
}