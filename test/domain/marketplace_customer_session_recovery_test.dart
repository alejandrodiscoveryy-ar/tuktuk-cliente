import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('identifica únicamente el error de sesión perdida', () {
    expect(
      marketplaceCustomerSessionNotFound(
        const FunctionException(
          status: 400,
          details: {'error': 'CUSTOMER_SESSION_NOT_FOUND'},
        ),
      ),
      isTrue,
    );
    expect(
      marketplaceCustomerSessionNotFound(
        const FunctionException(
          status: 400,
          details: {'error': 'ROUTE_TOKEN_EXPIRED'},
        ),
      ),
      isFalse,
    );
    expect(
      marketplaceCustomerSessionNotFound(
        const FunctionException(status: 503, details: 'network issue'),
      ),
      isFalse,
    );
    expect(
      marketplaceCustomerSessionNotFound(
        StateError('CUSTOMER_SESSION_NOT_FOUND'),
      ),
      isTrue,
    );
  });
}
