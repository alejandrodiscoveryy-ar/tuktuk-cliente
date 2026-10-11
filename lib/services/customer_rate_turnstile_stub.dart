// Non-Web platforms do not request browser push permission or Turnstile.
Future<String> customerRateTurnstileProof(String siteKey) async =>
    throw UnsupportedError('Turnstile solo esta disponible en la WebApp.');
