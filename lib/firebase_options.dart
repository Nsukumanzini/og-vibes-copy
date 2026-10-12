import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase configuration for the Android and Web apps registered in
/// `og-vibes-1f15c`. Web values are supplied as public build-time defines so
/// they can also be reused by the messaging service worker during deployment.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError(
      'Firebase is currently configured for Android and Web only.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
    appId: '1:949237855418:web:0ffd60fff20fbf95fa3e83',
    messagingSenderId: '949237855418',
    projectId: 'og-vibes-1f15c',
    authDomain: 'og-vibes-1f15c.firebaseapp.com',
    storageBucket: 'og-vibes-1f15c.firebasestorage.app',
    measurementId: String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID'),
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDcbLLOdJEfNgslQn8TuW1vFe3sYNpgMUI',
    appId: '1:949237855418:android:6bab423046285b31fa3e83',
    messagingSenderId: '949237855418',
    projectId: 'og-vibes-1f15c',
    storageBucket: 'og-vibes-1f15c.firebasestorage.app',
  );

  static bool get webIsConfigured =>
      web.apiKey.isNotEmpty && web.appId.isNotEmpty;
}
