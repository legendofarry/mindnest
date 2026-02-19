import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

Future<void> confirmAndLogout({
  required BuildContext context,
  required WidgetRef ref,
  Duration loadingDuration = const Duration(seconds: 2),
}) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
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
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
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
    );
  }
}

class _LogoutLoadingOverlay extends StatelessWidget {
  const _LogoutLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x96071937),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFCFFFFFF),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 26,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Lottie.asset(
                  'assets/loading/loading.json',
                  repeat: true,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.hourglass_top_rounded,
                      size: 54,
                      color: Color(0xFF0E9B90),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Logging you out...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF071937),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
