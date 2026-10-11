import 'dart:js_interop';

@JS('tuktukCustomerTurnstileProof')
external JSPromise<JSString> _turnstileProof(JSString siteKey);

Future<String> customerRateTurnstileProof(String siteKey) async {
  if (siteKey.trim().isEmpty) {
    throw StateError(
        'Las alertas se activaran cuando se configure la verificacion.');
  }
  return (await _turnstileProof(siteKey.toJS).toDart).toDart;
}
