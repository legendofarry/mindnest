import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/app/mindnest_app.dart';
import 'package:mindnest/core/firebase/firebase_initializer.dart';
import 'package:mindnest/features/auth/data/auth_session_manager.dart';
import 'package:mindnest/features/notifications/data/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyFullscreenMode();

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

  runApp(
    const ProviderScope(child: _FullscreenModeEnforcer(child: MindNestApp())),
  );
}

Future<void> _applyFullscreenMode() async {
  if (kIsWeb) {
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [],
    );
  }
}

class _FullscreenModeEnforcer extends StatefulWidget {
  const _FullscreenModeEnforcer({required this.child});

  final Widget child;

  @override
  State<_FullscreenModeEnforcer> createState() =>
      _FullscreenModeEnforcerState();
}

class _FullscreenModeEnforcerState extends State<_FullscreenModeEnforcer>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleApply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleApply(const Duration(milliseconds: 120));
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleApply(const Duration(milliseconds: 120));
  }

  void _scheduleApply([Duration delay = Duration.zero]) {
    unawaited(
      Future<void>.delayed(delay, () async {
        if (!mounted) {
          return;
        }
        await _applyFullscreenMode();
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
