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
