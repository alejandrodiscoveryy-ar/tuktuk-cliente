// Reproduce exactamente el claxon incluido en el paquete Flutter.
// En Android se implementa por canal nativo para evitar nuevas dependencias.
import 'package:flutter/services.dart';

const _arrivalChannel = MethodChannel('tuktuk/customer_arrival_claxon');

Future<bool> playArrivalClaxon() async {
  try {
    return await _arrivalChannel.invokeMethod<bool>('play') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
