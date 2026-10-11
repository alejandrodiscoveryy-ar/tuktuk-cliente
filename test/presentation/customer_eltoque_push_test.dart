import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('device secret uses 32 bytes in hex and differs on new generation', () {
    final first = customerRateDeviceSecret(Random.secure());
    final second = customerRateDeviceSecret(Random.secure());
    expect(first, hasLength(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first), isTrue);
    expect(first, isNot(second));
  });

  test('push opt-in honors capabilities and denied permission', () {
    expect(customerRatePushCanOptIn(supported: true, previouslyDenied: false),
        true);
    expect(customerRatePushCanOptIn(supported: false, previouslyDenied: false),
        false);
    expect(customerRatePushCanOptIn(supported: true, previouslyDenied: true),
        false);
  });
}
