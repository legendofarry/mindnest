import 'dart:ui';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

Future<void> confirmAndLogout({
  required BuildContext context,
  required WidgetRef ref,
  Duration loadingDuration = const Duration(seconds: 2),
}) async {
  final isWindowsDesktop =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (isWindowsDesktop) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!context.mounted) {
      return;
    }
  }

  final shouldLogout = await showDialog<bool>(
    context: context,
    barrierDismissible: !isWindowsDesktop,
    builder: (dialogContext) => const _LogoutConfirmDialog(),
  );

  if (shouldLogout != true || !context.mounted) {
    return;
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(builder: (_) => const _LogoutLoadingOverlay());
  overlay.insert(entry);

  try {
    await Future<void>.delayed(loadingDuration);
    await ref.read(authRepositoryProvider).signOut();
    await syncAuthSessionState(ref);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    showModernBannerFromSnackBar(
      context,
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  } finally {
    entry.remove();
  }
}

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 34, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A0F172A),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    'Log out now?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF071937),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will be signed out of your MindNest session. You can log in again anytime.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E728D),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Log Out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: -32,
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E9B90), Color(0xFF15AFA3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x400E9B90),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.self_improvement_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutLoadingOverlay extends StatelessWidget {
  const _LogoutLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xD8071937), Color(0xE6113657)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            top: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3315AFA3), Color(0x0015AFA3)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -140,
            bottom: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x333B82F6), Color(0x003B82F6)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        height: 260,
                        child: Lottie.asset(
                          'assets/loading/loading.json',
                          repeat: true,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.hourglass_top_rounded,
                              size: 120,
                              color: Color(0xFF7DD3FC),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Logging you out...',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Please wait while MindNest closes your session safely.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFFD6E3F5),
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
