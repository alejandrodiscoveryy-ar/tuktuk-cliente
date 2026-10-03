import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer identity uses phone and supports optional email', () {
    final service = File(
      'lib/data/marketplace_customer_service.dart',
    ).readAsStringSync();

    final presentation = File(
      'lib/presentation/marketplace_customer.dart',
    ).readAsStringSync();

    expect(service, contains("'target_email': email"));

    expect(service, contains("marketplace_customer_email"));

    expect(presentation, contains("Correo electrónico (opcional)"));

    expect(presentation, contains("String _phoneValue()"));

    expect(presentation, contains("String? _emailValue()"));

    expect(presentation, contains("email: email"));
  });
}
