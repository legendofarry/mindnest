import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/app/mindnest_app.dart';
import 'package:mindnest/core/firebase/firebase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseInitializer.initialize();
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
