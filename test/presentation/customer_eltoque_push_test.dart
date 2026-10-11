import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('renewal sends possession secret without a challenge', () async {
    var challenges = 0;
    Map<String, Object?>? sent;
    await customerRateRegisterDevice(
      token: 'synthetic-token',
      secret: 'synthetic-secret',
      needsProof: false,
      challenge: () async {
        challenges++;
        return 'synthetic-proof';
      },
      invoke: (body) async {
        sent = body;
        return {'ok': true};
      },
    );
    expect(challenges, 0);
    expect(sent?['device_secret'], 'synthetic-secret');
    expect(sent?.containsKey('turnstile_token'), false);
  });

  test(
      'new opt-in includes challenge, expired server record recovers explicitly',
      () async {
    for (final needsProof in [true, false]) {
      var calls = 0;
      var challenges = 0;
      await customerRateRegisterDevice(
        token: 'synthetic-token',
        secret: 'synthetic-secret',
        needsProof: needsProof,
        challenge: () async {
          challenges++;
          return 'synthetic-proof';
        },
        invoke: (body) async {
          calls++;
          if (!needsProof && calls == 1) {
            throw const FunctionException(
                status: 403, details: {'error': 'verification_required'});
          }
          expect(body['turnstile_token'], 'synthetic-proof');
          return {'ok': true};
        },
      );
      expect(challenges, 1);
      expect(calls, needsProof ? 1 : 2);
    }
  });

  test('outage and ownership errors do not trigger challenge or report success',
      () async {
    for (final status in [409, 503]) {
      var challenges = 0;
      await expectLater(
          customerRateRegisterDevice(
            token: 'synthetic-token',
            secret: 'synthetic-secret',
            needsProof: false,
            challenge: () async {
              challenges++;
              return 'synthetic-proof';
            },
            invoke: (_) async => throw FunctionException(
                status: status, details: {'error': 'subscription_unavailable'}),
          ),
          throwsA(isA<FunctionException>()));
      expect(challenges, 0);
    }
  });

  test('device secret uses 32 bytes in hex and differs on new generation', () {
    final first = customerRateDeviceSecret(Random.secure());
    final second = customerRateDeviceSecret(Random.secure());
    expect(first, hasLength(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first), isTrue);
    expect(first, isNot(second));
  });

  test(
      'new subscription requires server-verified antiabuse proof; renewal does not',
      () {
    expect(customerRatePushNeedsProof(hasExistingDeviceSecret: false), isTrue);
    expect(customerRatePushNeedsProof(hasExistingDeviceSecret: true), isFalse);
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
