part of '../main.dart';

/// Dos muestras GPS diferentes, precisas y separadas para evitar falsas llegadas.
/// No cambia el estado del servicio ni publica ubicaciones.
class MarketplaceCustomerArrivalGeofence {
  static const radiusMeters = 90.0;
  static const maxAccuracyMeters = 35.0;
  static const maxFixAge = Duration(seconds: 45);
  static const minimumDwell = Duration(seconds: 12);
  DateTime? _firstInside;
  DateTime? _lastSample;
  int _insideSamples = 0;
  bool _triggered = false;

  bool observe({
    required String status,
    required MarketplaceDriverLiveLocation? location,
    required MarketplaceMapPoint? pickup,
    required DateTime now,
  }) {
    if (_triggered) return false;
    if (!const {'accepted', 'en_route', 'pickup'}.contains(status) ||
        pickup == null ||
        location == null ||
        location.capturedAt == null ||
        location.accuracyM == null ||
        location.accuracyM! < 0 ||
        location.accuracyM! > maxAccuracyMeters) {
      _resetCandidate();
      return false;
    }
    final fixAt = location.capturedAt!;
    final age = now.toUtc().difference(fixAt);
    if (age < const Duration(seconds: -15) || age > maxFixAge) {
      _resetCandidate();
      return false;
    }
    final dLat = (location.latitude - pickup.lat) * pi / 180;
    final dLon = (location.longitude - pickup.lon) * pi / 180;
    final lat1 = pickup.lat * pi / 180;
    final lat2 = location.latitude * pi / 180;
    final a =
        pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
    final distanceMeters = 2 * 6371000.0 * asin(min(1.0, sqrt(max(0.0, a))));
    if (!distanceMeters.isFinite || distanceMeters > radiusMeters) {
      _resetCandidate();
      return false;
    }
    if (_lastSample == fixAt) return false;
    if (_lastSample != null && fixAt.isBefore(_lastSample!)) {
      _resetCandidate();
    }
    _lastSample = fixAt;
    _firstInside ??= fixAt;
    _insideSamples += 1;
    if (_insideSamples >= 2 &&
        fixAt.difference(_firstInside!) >= minimumDwell) {
      _triggered = true;
      return true;
    }
    return false;
  }

  void _resetCandidate() {
    _firstInside = null;
    _lastSample = null;
    _insideSamples = 0;
  }
}
