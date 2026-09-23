import 'package:tuktuk_cliente/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('/cliente/tuk selecciona la WebApp de clientes', () {
    expect(
      isMarketplaceCustomerEntryUri(
        Uri.parse('https://www.vrixora.com/cliente/tuk'),
      ),
      isTrue,
    );
  });

  test('/cliente/tuk/ selecciona la WebApp de clientes', () {
    expect(
      isMarketplaceCustomerEntryUri(
        Uri.parse('https://www.vrixora.com/cliente/tuk/'),
      ),
      isTrue,
    );
  });

  test('/tuktuk/app/ conserva la experiencia de prestadores', () {
    expect(
      isMarketplaceCustomerEntryUri(
        Uri.parse('https://www.vrixora.com/tuktuk/app/'),
      ),
      isFalse,
    );
  });

  test('mode=customer continúa siendo compatible', () {
    expect(
      isMarketplaceCustomerEntryUri(
        Uri.parse('https://www.vrixora.com/tuktuk/app/?mode=customer'),
      ),
      isTrue,
    );
  });
}
