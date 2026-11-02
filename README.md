# TUKTUK Cliente

Proyecto Flutter independiente para `/cliente/tuk/` y una futura APK.

La URL y clave publicable de Supabase, además del token público de Mapbox, se reciben mediante `--dart-define`; ningún secreto se almacena en el repositorio.

Identificador Android definitivo aprobado: `com.vrixora.tuktukcliente`. Mantenerlo invariable en Google Play, en nuevas versiones y en actualizaciones.

La identidad Android no implica que la app este lista para subir: faltan firma release privada, comprobaciones de Play Console, permisos y notificaciones nativas.

## Android / Google Play (preparacion)
- **Identificador permanente:** `com.vrixora.tuktukcliente`.
- **API:** `compileSdk = 36`, `targetSdk = 36`.
- **Firma release:** obligatoria en `android/key.properties` (ignorado por Git). NO se aceptan las claves de depuracion.
- **Version inicial:** `1.0.0+1`, subir el `versionCode` en cada actualizacion.
- **Firebase:** registrar una nueva app Android con ese paquete dentro del proyecto Firebase de TUKTUK. Obtener los campos publicos Android y compilarlos con `--dart-define=FIREBASE_ANDROID_API_KEY=...`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_SENDER_ID`, `FIREBASE_ANDROID_PROJECT_ID`. NO reutilizar el appId Web.
- **Notificaciones Android:** permisos y receptor FCM preparados; todavia falta el endpoint autenticado de suscripcion de dispositivos y comprobar entrega real en telefono. No reutilizar el Turnstile exclusivo de Web ni registrar el token sin autorizacion del usuario.
- **Datos publicos:** compilar ademas con `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `MAPBOX_PUBLIC_TOKEN`. Nunca insertar service_role ni llaves privadas en Flutter.
- **Control externo:** confirmar Play Console, Play App Signing, formulario de datos, politica de privacidad y prueba interna antes de publicar.
- **CI:** compila APK Android de depuracion para verificar compatibilidad. NO sustituye AAB release firmado ni pruebas de notificaciones reales.
