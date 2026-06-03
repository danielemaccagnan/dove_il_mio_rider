import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

/// Configurazione Firebase per iOS, identica ai valori di GoogleService-Info.plist
/// (progetto trova-il-mio-rider, lo stesso di Android -> dati condivisi).
///
/// Perché serve: il plist non è incluso nel bundle Xcode dell'app, quindi
/// `Firebase.initializeApp()` senza opzioni fallisce su iOS con
/// "[core/no-app] No Firebase App". Passando le opzioni esplicitamente,
/// Firebase si inizializza senza dipendere dal file nativo.
const FirebaseOptions iosFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBXN7M9CWUWZAxrj9ftNlE-5-kmYMbqpjA',
  appId: '1:706727634459:ios:83a0fb3126e31523303abe',
  messagingSenderId: '706727634459',
  projectId: 'trova-il-mio-rider',
  storageBucket: 'trova-il-mio-rider.firebasestorage.app',
  iosBundleId: 'com.example.doveIlMioRider',
);

/// Inizializza Firebase in modo cross-platform.
/// - iOS: usa le opzioni esplicite qui sopra (il plist non è nel bundle).
/// - Android (e tutto il resto): comportamento INVARIATO, usa
///   `Firebase.initializeApp()` che legge google-services.json.
Future<void> initFirebaseCrossPlatform() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await Firebase.initializeApp(options: iosFirebaseOptions);
  } else {
    await Firebase.initializeApp();
  }
}
