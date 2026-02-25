import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class DesktopPrimaryShell extends ConsumerWidget {
  const DesktopPrimaryShell({super.key, required this.child});

  static const _openProfileQueryKey = 'openProfile';
  static const _profileOpenTokenQueryKey = 'profileOpenTs';

  final Widget child;

  bool _canAccessLive(UserProfile profile) {
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.counselor;
  }

  void _openProfileFromHeader(BuildContext context) {
    final uri = Uri(
      path: AppRoute.home,
      queryParameters: <String, String>{
        _openProfileQueryKey: '1',
        _profileOpenTokenQueryKey: DateTime.now().microsecondsSinceEpoch
            .toString(),
      },
    );
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    if (!isDesktop) {
      return child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final hasInstitution = (profile?.institutionId ?? '').isNotEmpty;
    final canAccessLive = profile != null && _canAccessLive(profile);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF15A39A), Color(0xFF0E9B90)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.psychology_alt_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'MindNest',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF071937),
                fontSize: 20,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: hasInstitution
                ? () => context.go(AppRoute.notifications)
                : null,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Profile',
            onPressed: profile == null
                ? null
                : () => _openProfileFromHeader(context),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B1220), Color(0xFF0E1A2E)]
                : const [Color(0xFFF4F7FB), Color(0xFFF1F5F9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: kToolbarHeight + 6),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1260),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 240,
                            child: DesktopSectionNav(
                              hasInstitution: hasInstitution,
                              canAccessLive: canAccessLive,
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
