import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';

class CounselorAccessSuspendedScreen extends ConsumerWidget {
  const CounselorAccessSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 1100;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionName = (profile?.institutionName ?? '').trim();

    return MindNestShell(
      maxWidth: isDesktop ? 980 : 760,
      backgroundMode: isDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 20,
        24,
        isDesktop ? 28 : 20,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFD6E6F5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140B1A33),
                  blurRadius: 34,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 34 : 24,
                isDesktop ? 30 : 24,
                isDesktop ? 34 : 24,
                isDesktop ? 30 : 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.pause_circle_filled_rounded,
                          color: Color(0xFFB45309),
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Counselor access suspended',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              institutionName.isEmpty
                                  ? 'You are still signed in, but counselor tools are paused until your institution admin restores access.'
                                  : 'Your access at $institutionName is paused for now. You stay signed in, but counselor tools remain blocked until your institution admin restores access.',
                              style: const TextStyle(
                                color: Color(0xFF5B708A),
                                fontSize: 16,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFFBEB), Color(0xFFFFF7D6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What still works',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'You can still review notifications and wait here for access to be restored. Counseling tools, dashboard actions, live rooms, and bookings stay blocked while the suspension is active.',
                          style: TextStyle(
                            color: Color(0xFF7C5A11),
                            fontSize: 14,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _SuspendedChip(
                        icon: Icons.notifications_active_outlined,
                        label: 'Notifications stay available',
                      ),
                      _SuspendedChip(
                        icon: Icons.lock_outline_rounded,
                        label: 'Counselor tools paused',
                      ),
                      _SuspendedChip(
                        icon: Icons.support_agent_rounded,
                        label: 'Contact your admin',
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _SuspendedActionButton(
                          label: 'Open notifications',
                          icon: Icons.notifications_none_rounded,
                          onPressed: () {
                            context.go(
                              AppRoute.notificationsRoute(
                                returnTo: AppRoute.counselorAccessSuspended,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            confirmAndLogout(context: context, ref: ref);
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            side: const BorderSide(color: Color(0xFFD6E6F5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text(
                            'Sign out',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuspendedChip extends StatelessWidget {
  const _SuspendedChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD6E6F5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0D7FA1)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF34455E),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuspendedActionButton extends StatelessWidget {
  const _SuspendedActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D7FA1), Color(0xFF0E9B90)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330E9B90),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
