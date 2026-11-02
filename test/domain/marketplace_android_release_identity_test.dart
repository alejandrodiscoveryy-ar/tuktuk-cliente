import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identidad Android definitiva y permisos basicos de Cliente', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/vrixora/tuktukcliente/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(gradle, contains('applicationId = "com.vrixora.tuktukcliente"'));
    expect(gradle, contains('namespace = "com.vrixora.tuktukcliente"'));
    expect(activity, contains('package com.vrixora.tuktukcliente'));
    expect(manifest, contains('android:label="TUKTUK Cliente"'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')));
    expect(gradle, isNot(contains('applicationId = "com.vrixora.provisional')));
  });
}
