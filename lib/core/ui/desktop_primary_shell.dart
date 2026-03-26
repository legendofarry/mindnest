import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_profile_open_signal.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';

class DesktopPrimaryShell extends ConsumerWidget {
  const DesktopPrimaryShell({
    super.key,
    required this.child,
    required this.matchedLocation,
  });

  static const _openProfileQueryKey = 'openProfile';
  static const _profileOpenTokenQueryKey = 'profileOpenTs';

  final Widget child;
  final String matchedLocation;

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

  void _showNotificationsUnavailable(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Notifications unavailable'),
          content: const Text(
            'An institution is '
            'required for the full experience.',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    if (!isDesktop) {
      return child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final bypassShellForCounselorDirectory =
        matchedLocation == AppRoute.counselorDirectory &&
        profile?.role == UserRole.counselor;
    if (bypassShellForCounselorDirectory) {
      return child;
    }

    final hasInstitution = (profile?.institutionId ?? '').isNotEmpty;
    final canAccessLive = profile != null && _canAccessLive(profile);
    final unreadCount = hasInstitution && profile != null
        ? (ref.watch(unreadNotificationCountProvider(profile.id)).valueOrNull ??
              0)
        : 0;
    final notificationsActive = matchedLocation == AppRoute.notifications;
    final profileActive = matchedLocation == AppRoute.privacyControls;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF071120)
          : const Color(0xFFF4F7FB),
      appBar: AppBar(
        toolbarHeight: 82,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleSpacing: 24,
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'MindNest',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF071937),
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Student Workspace',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF8FA4C2)
                        : const Color(0xFF62748B),
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _HeaderActionButton(
            tooltip: 'Notifications',
            active: notificationsActive,
            onPressed: hasInstitution
                ? () => context.go(AppRoute.notifications)
                : () => _showNotificationsUnavailable(context),
            child: _HeaderBellIcon(
              unreadCount: unreadCount,
              active: notificationsActive,
            ),
          ),
          const SizedBox(width: 8),
          _HeaderActionButton(
            tooltip: 'Profile',
            active: profileActive,
            onPressed: profile == null
                ? null
                : () {
                    if (matchedLocation == AppRoute.home) {
                      ref
                              .read(desktopProfileOpenRequestProvider.notifier)
                              .state =
                          DateTime.now().microsecondsSinceEpoch;
                      return;
                    }
                    _openProfileFromHeader(context);
                  },
            child: Icon(
              Icons.person_outline_rounded,
              color: profileActive
                  ? const Color(0xFF0B2442)
                  : (isDark
                        ? const Color(0xFFD6E3F5)
                        : const Color(0xFF16324F)),
            ),
          ),
          const SizedBox(width: 10),
          const WindowsDesktopWindowControls(),
          const SizedBox(width: 24),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF081423) : const Color(0xFFF4F7FB),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF18273B)
                    : const Color(0xFFD8E2EE),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF071120), Color(0xFF0B182A)]
                : const [Color(0xFFF4F7FB), Color(0xFFEFF4F9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 0, 20),
                child: SizedBox(
                  width: 272,
                  child: DesktopSectionNav(
                    hasInstitution: hasInstitution,
                    canAccessLive: canAccessLive,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 24, 24),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBellIcon extends StatelessWidget {
  const _HeaderBellIcon({required this.unreadCount, required this.active});

  final int unreadCount;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          color: active
              ? const Color(0xFF0B2442)
              : (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFD6E3F5)
                    : const Color(0xFF16324F)),
        ),
        if (unreadCount > 0)
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFBEEBF2)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF69CBD7)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFD3DFEC)),
          ),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x1E15A39A),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: IconButton(onPressed: onPressed, icon: child),
      ),
    );
  }
}
