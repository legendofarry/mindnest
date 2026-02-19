import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mindnest/firebase_options.dart';

class FirebaseInitializer {
  static bool _emulatorsConfigured = false;

  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _configureEmulatorsIfNeeded();
  }

  static Future<void> _configureEmulatorsIfNeeded() async {
    const useEmulators = bool.fromEnvironment(
      'USE_FIREBASE_EMULATORS',
      defaultValue: false,
    );
    if (!useEmulators || _emulatorsConfigured) {
      return;
    }

    final host = _resolveEmulatorHost();
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    _emulatorsConfigured = true;
  }

  static String _resolveEmulatorHost() {
    if (kIsWeb) {
      return 'localhost';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return 'localhost';
  }
}
