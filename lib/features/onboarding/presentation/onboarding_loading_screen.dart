import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';

class OnboardingLoadingScreen extends StatefulWidget {
  const OnboardingLoadingScreen({super.key});

  @override
  State<OnboardingLoadingScreen> createState() =>
      _OnboardingLoadingScreenState();
}

class _OnboardingLoadingScreenState extends State<OnboardingLoadingScreen> {
  static const Duration _holdDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    unawaited(_goNext());
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(_holdDuration);
    if (!mounted) {
      return;
    }
    context.go(AppRoute.home);
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackgroundScaffold(
      maxWidth: 420,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFCFFFFFF),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(compact: true),
            const SizedBox(height: 18),
            SizedBox(
              height: 160,
              width: 160,
              child: Lottie.asset(
                'assets/loading/loading.json',
                repeat: true,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.hourglass_top_rounded,
                    size: 72,
                    color: Color(0xFF0E9B90),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Finalizing your setup...',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF071937),
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'We are preparing your dashboard and reminders.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ],
        ),
      ),
    );
  }
}
