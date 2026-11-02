import 'package:firebase_core/firebase_core.dart';

// Public Firebase web configuration already used by TUKTUK Conductor.
// Do not store a service account, private VAPID key, or API secrets here.
const customerRateFirebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyAVDRuwMJZStQGCqHRGMuoNydCbG3JeUIo',
  authDomain: 'tuktuk-control-9e74c.firebaseapp.com',
  projectId: 'tuktuk-control-9e74c',
  storageBucket: 'tuktuk-control-9e74c.firebasestorage.app',
  messagingSenderId: '835856456604',
  appId: '1:835856456604:web:f9ce95c62e04f050fec659',
);

const customerRateFirebaseVapidKey =
    'BF-az4NW8nREYEw-RvnBOfQ2wrJGttOjBhR_PD0SKWEKDHWqWvFBLdmka5e_0d-_Mptdrpxxfy1aF-FFPQpvfEE';

// La app Android de TUKTUK Cliente debe darse de alta en el proyecto Firebase.
// Son identificadores publicos de Firebase, no secretos. Nunca reutilizar el
// appId de Web como si fuera Android. Si faltan, el transporte sigue activo
// pero los avisos nativos quedan deshabilitados.
FirebaseOptions? get customerRateFirebaseAndroidOptionsOrNull {
  const apiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  const sender = String.fromEnvironment('FIREBASE_ANDROID_SENDER_ID');
  const project = String.fromEnvironment('FIREBASE_ANDROID_PROJECT_ID');
  if (apiKey.isEmpty || appId.isEmpty || sender.isEmpty || project.isEmpty) {
    return null;
  }
  return const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: sender,
    projectId: project,
  );
}