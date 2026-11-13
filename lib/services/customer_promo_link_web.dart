// Keep all unrelated query parameters and the current route.
import 'dart:html' as html;

void clearCustomerPromoLink() {
  try {
    final uri = Uri.base;
    if (!uri.queryParameters.containsKey('conductor')) return;
    final params = Map<String, String>.from(uri.queryParameters)..remove('conductor');
    final clean = uri.replace(queryParameters: params);
    html.window.history.replaceState(null, '', clean.toString());
  } catch (_) {
    // Optional URL cleanup must not block a confirmed ride.
  }
}
