library firebase_core;

class FirebaseOptions {
  final String apiKey;
  final String appId;
  final String? messagingSenderId;
  final String projectId;
  final String? authDomain;
  final String? storageBucket;
  final String? measurementId;

  const FirebaseOptions({
    required this.apiKey,
    required this.appId,
    this.messagingSenderId,
    required this.projectId,
    this.authDomain,
    this.storageBucket,
    this.measurementId,
  });
}

class Firebase {
  static final List<FirebaseApp> apps = <FirebaseApp>[];

  static Future<FirebaseApp> initializeApp({FirebaseOptions? options}) async {
    final app = FirebaseApp();
    apps.add(app);
    return app;
  }
}

class FirebaseApp {}
