import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/app/mindnest_app.dart';
import 'package:mindnest/core/firebase/firebase_initializer.dart';
import 'package:mindnest/features/auth/data/auth_session_manager.dart';
import 'package:mindnest/features/notifications/data/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseInitializer.initialize();
    await AuthSessionManager.enforceStartupPolicy(FirebaseAuth.instance);
    try {
      await PushNotificationService.bootstrap();
    } catch (_) {
      // Keep app startup resilient even if notification setup fails.
    }
  } catch (error) {
    runApp(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Firebase initialization failed.\n\n$error\n\n'
                  'Run flutterfire configure and verify platform config files.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  runApp(const ProviderScope(child: MindNestApp()));
}
