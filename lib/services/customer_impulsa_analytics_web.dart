import 'dart:js_interop';

@JS('tuktukImpulsaTrack')
external void _track(JSString event, JSNumber? price, JSString? reason);

/// Optional browser analytics bridge. It never blocks price, checkout, or rides.
void track(String event, {double? priceCup, String? reason}) {
  try {
    _track(event.toJS, priceCup?.toJS, reason?.toJS);
  } catch (_) {
    // Tracking must be strictly best effort, including when HTML lacks the bridge.
  }
}
