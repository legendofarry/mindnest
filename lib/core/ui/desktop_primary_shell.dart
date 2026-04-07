import 'dart:async';

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

  String? _normalizedPrimaryWorkspaceRoute(String? rawRoute) {
    final normalized = (rawRoute ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return null;
    }
    switch (uri.path) {
      case AppRoute.home:
      case AppRoute.counselorDirectory:
      case AppRoute.counselorProfile:
      case AppRoute.studentAppointments:
      case AppRoute.sessionDetails:
      case AppRoute.carePlan:
      case AppRoute.liveHub:
      case AppRoute.notifications:
      case AppRoute.privacyControls:
        return uri.toString();
      default:
        return null;
    }
  }

  void _showNotificationsUnavailable(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!dialogContext.mounted) {
            return;
          }
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
    final currentUri = GoRouterState.of(context).uri;
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
    final firstName = _firstNameForProfile(profile);
    final notificationsActive = matchedLocation == AppRoute.notifications;
    final profileActive = matchedLocation == AppRoute.privacyControls;
    final notificationsReturnTo =
        _normalizedPrimaryWorkspaceRoute(
          currentUri.queryParameters[AppRoute.returnToQuery],
        ) ??
        AppRoute.home;
    final overlayAnchorRoute =
        _normalizedPrimaryWorkspaceRoute(currentUri.toString()) ??
        AppRoute.home;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF071120)
          : const Color(0xFFF4F7FB),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 22, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 296,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: DesktopSectionNav(
                      hasInstitution: hasInstitution,
                      canAccessLive: canAccessLive,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 0, 16),
                        child: _PrimaryWorkspaceHeader(
                          firstName: firstName,
                          unreadCount: unreadCount,
                          notificationsActive: notificationsActive,
                          profileActive: profileActive,
                          onNotifications: hasInstitution
                              ? () {
                                  if (notificationsActive) {
                                    context.go(notificationsReturnTo);
                                    return;
                                  }
                                  context.go(
                                    AppRoute.notificationsRoute(
                                      returnTo: overlayAnchorRoute,
                                    ),
                                  );
                                }
                              : () => _showNotificationsUnavailable(context),
                          onProfile: profile == null
                              ? null
                              : () {
                                  if (matchedLocation == AppRoute.home) {
                                    ref
                                            .read(
                                              desktopProfileOpenRequestProvider
                                                  .notifier,
                                            )
                                            .state =
                                        DateTime.now().microsecondsSinceEpoch;
                                    return;
                                  }
                                  _openProfileFromHeader(context);
                                },
                          isDark: isDark,
                        ),
                      ),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _firstNameForProfile(UserProfile? profile) {
  final rawName = profile?.name.trim() ?? '';
  if (rawName.isNotEmpty) {
    return rawName.split(RegExp(r'\s+')).first;
  }
  final email = profile?.email.trim() ?? '';
  if (email.contains('@')) {
    return email.split('@').first;
  }
  return 'there';
}

class _PrimaryWorkspaceHeader extends StatefulWidget {
  const _PrimaryWorkspaceHeader({
    required this.firstName,
    required this.unreadCount,
    required this.notificationsActive,
    required this.profileActive,
    required this.onNotifications,
    required this.onProfile,
    required this.isDark,
  });

  final String firstName;
  final int unreadCount;
  final bool notificationsActive;
  final bool profileActive;
  final VoidCallback onNotifications;
  final VoidCallback? onProfile;
  final bool isDark;

  @override
  State<_PrimaryWorkspaceHeader> createState() =>
      _PrimaryWorkspaceHeaderState();
}

class _PrimaryWorkspaceHeaderState extends State<_PrimaryWorkspaceHeader>
    with WidgetsBindingObserver {
  late _GreetingPeriod _greetingPeriod = _currentGreetingPeriod();
  Timer? _greetingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleGreetingRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _greetingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshGreetingPeriod();
    }
  }

  void _refreshGreetingPeriod() {
    final nextPeriod = _currentGreetingPeriod();
    if (mounted && nextPeriod != _greetingPeriod) {
      setState(() => _greetingPeriod = nextPeriod);
    }
    _scheduleGreetingRefresh();
  }

  void _scheduleGreetingRefresh() {
    _greetingTimer?.cancel();
    final now = DateTime.now();
    final nextBoundary = _nextGreetingBoundary(now);
    final delay = nextBoundary.difference(now);
    _greetingTimer = Timer(
      delay.isNegative ? Duration.zero : delay + const Duration(seconds: 1),
      _refreshGreetingPeriod,
    );
  }

  String get _greetingLabel {
    switch (_greetingPeriod) {
      case _GreetingPeriod.morning:
        return 'Good morning';
      case _GreetingPeriod.afternoon:
        return 'Good afternoon';
      case _GreetingPeriod.evening:
        return 'Good evening';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$_greetingLabel, ${widget.firstName}',
                    style: const TextStyle(
                      color: Color(0xFF1E2432),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Here's your wellness overview for today.",
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderActionButton(
              tooltip: 'Notifications',
              active: widget.notificationsActive,
              onPressed: widget.onNotifications,
              child: _HeaderBellIcon(
                unreadCount: widget.unreadCount,
                active: widget.notificationsActive,
              ),
            ),
            const SizedBox(width: 8),
            _HeaderActionButton(
              tooltip: 'Profile',
              active: widget.profileActive,
              onPressed: widget.onProfile,
              child: Icon(
                Icons.person_outline_rounded,
                color: widget.profileActive
                    ? const Color(0xFF0B2442)
                    : (widget.isDark
                          ? const Color(0xFFD6E3F5)
                          : const Color(0xFF16324F)),
              ),
            ),
            const SizedBox(width: 10),
            const WindowsDesktopWindowControls(),
          ],
        ),
      ],
    );
  }
}

enum _GreetingPeriod { morning, afternoon, evening }

_GreetingPeriod _currentGreetingPeriod([DateTime? now]) {
  final current = now ?? DateTime.now();
  final hour = current.hour;
  if (hour < 12) {
    return _GreetingPeriod.morning;
  }
  if (hour < 18) {
    return _GreetingPeriod.afternoon;
  }
  return _GreetingPeriod.evening;
}

DateTime _nextGreetingBoundary(DateTime now) {
  if (now.hour < 12) {
    return DateTime(now.year, now.month, now.day, 12);
  }
  if (now.hour < 18) {
    return DateTime(now.year, now.month, now.day, 18);
  }
  return DateTime(now.year, now.month, now.day + 1);
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
