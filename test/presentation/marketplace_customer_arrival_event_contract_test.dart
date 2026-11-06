import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('El cliente oye el aviso cuando servidor indica pickup', () {
    final tracking = File('lib/presentation/marketplace_customer_tracking.dart').readAsStringSync();
    expect(tracking, contains("final arrived = job.status == 'pickup';"));
    expect(tracking, isNot(contains('_arrivalGeofence.observe')));
    expect(tracking, contains('_arrivalNotified = true'));
    expect(tracking, contains('playArrivalClaxon()'));
  });
  test('Si el navegador bloquea el sonido, aparece reproduccion manual', () {
    final tracking = File('lib/presentation/marketplace_customer_tracking.dart').readAsStringSync();
    expect(tracking, contains('Escuchar claxon de llegada'));
    expect(tracking, contains("if (const {'accepted', 'en_route', 'pickup'}"));
    expect(tracking, contains('playArrivalClaxon()'));
  });
  test('Android usa el claxon original empaquetado, no beep generico', () {
    final main = File('lib/main.dart').readAsStringSync();
    final kotlin = File('android/app/src/main/kotlin/com/vrixora/tuktukcliente/MainActivity.kt').readAsStringSync();
    expect(main, contains("dart.library.io) 'services/customer_arrival_sound_mobile.dart'"));
    expect(kotlin, contains('assets/sounds/tuktuk-car-double-horn.wav'));
    expect(kotlin, contains('MethodChannel('));
  });
}
