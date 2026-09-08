// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_WEB_API_KEY',
    appId: '1:265155033945:web:87b10e00993670c2922a48',
    messagingSenderId: '265155033945',
    projectId: 'pengaduansekolah-eb875',
    authDomain: 'pengaduansekolah-eb875.firebaseapp.com',
    storageBucket: 'pengaduansekolah-eb875.firebasestorage.app',
    measurementId: 'G-WN6RZCQHEL',
  );
}
