import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/no_scrollbar_scroll_behavior.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/presentation/notification_center_screen.dart';
import 'package:mindnest/features/counselor/presentation/counselor_profile_settings_screen.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

enum CounselorWorkspaceNavSection {
  dashboard,
  sessions,
  live,
  availability,
  counselors,
}

class CounselorWorkspaceRouteShell extends ConsumerWidget {
  const CounselorWorkspaceRouteShell({
    super.key,
    required this.state,
    required this.child,
  });

  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.role != UserRole.counselor) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Center(
          child: Text(
            'This workspace is available only for counselors.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final unreadCount =
        ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
    final showCounselorDirectory =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile.institutionId ?? ''),
            )
            .valueOrNull
            ?.directoryEnabled ??
        false;
    final shell = _routeShellForState(state);
    final notificationsReturnTo =
        _normalizedCounselorWorkspaceRoute(
          state.uri.queryParameters[AppRoute.returnToQuery],
        ) ??
        AppRoute.counselorDashboard;
    final profileReturnTo =
        _normalizedCounselorWorkspaceRoute(
          state.uri.queryParameters[AppRoute.returnToQuery],
        ) ??
        (state.matchedLocation == AppRoute.counselorPrivacyControls
            ? AppRoute.counselorSettings
            : AppRoute.counselorDashboard);
    final overlayAnchorRoute = switch (state.matchedLocation) {
      AppRoute.counselorNotifications => notificationsReturnTo,
      AppRoute.counselorSettings => profileReturnTo,
      _ => state.matchedLocation,
    };

    if (state.matchedLocation == AppRoute.counselorNotifications ||
        state.matchedLocation == AppRoute.counselorSettings ||
        state.matchedLocation == AppRoute.counselorPrivacyControls) {
      return child;
    }

    return ScrollConfiguration(
      behavior: const NoScrollbarScrollBehavior(),
      child: CounselorWorkspaceScaffold(
        profile: profile,
        activeSection: shell.section,
        showCounselorDirectory: showCounselorDirectory,
        unreadNotifications: unreadCount,
        title: shell.title,
        subtitle: shell.subtitle,
        childHandlesOwnScroll: shell.childHandlesOwnScroll,
        onSelectSection: (section) {
          switch (section) {
            case CounselorWorkspaceNavSection.dashboard:
              context.go(AppRoute.counselorDashboard);
            case CounselorWorkspaceNavSection.sessions:
              context.go(AppRoute.counselorAppointments);
            case CounselorWorkspaceNavSection.live:
              context.go(AppRoute.counselorLiveHub);
            case CounselorWorkspaceNavSection.availability:
              context.go(AppRoute.counselorAvailability);
            case CounselorWorkspaceNavSection.counselors:
              context.go(AppRoute.counselorDirectory);
          }
        },
        onNotifications: () {
          if (state.matchedLocation == AppRoute.counselorNotifications) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(notificationsReturnTo);
            }
            return;
          }
          _openCounselorNotificationsOverlay(context);
        },
        onProfile: () {
          _openCounselorProfileOverlay(
            context,
            returnToRoute: overlayAnchorRoute,
          );
        },
        onLogout: () => confirmAndLogout(context: context, ref: ref),
        notificationsHighlighted: shell.notificationsHighlighted,
        profileHighlighted: shell.profileHighlighted,
        child: child,
      ),
    );
  }
}

Future<void> _openCounselorNotificationsOverlay(BuildContext context) async {
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: AppRoute.counselorNotifications),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const NotificationCenterScreen(embeddedInCounselorShell: true);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            );
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    ),
  );
}

Future<void> _openCounselorProfileOverlay(
  BuildContext context, {
  String? returnToRoute,
}) async {
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: AppRoute.counselorSettings),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return CounselorProfileSettingsScreen(
          embeddedInCounselorShell: true,
          returnToRoute: returnToRoute,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            );
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    ),
  );
}

class _CounselorRouteShellConfig {
  const _CounselorRouteShellConfig({
    required this.section,
    required this.title,
    required this.subtitle,
    this.notificationsHighlighted = false,
    this.profileHighlighted = false,
    this.childHandlesOwnScroll = false,
  });

  final CounselorWorkspaceNavSection section;
  final String title;
  final String subtitle;
  final bool notificationsHighlighted;
  final bool profileHighlighted;
  final bool childHandlesOwnScroll;
}

_CounselorRouteShellConfig _routeShellForState(GoRouterState state) {
  if (state.matchedLocation == AppRoute.counselorNotifications) {
    final returnTo =
        _normalizedCounselorWorkspaceRoute(
          state.uri.queryParameters[AppRoute.returnToQuery],
        ) ??
        AppRoute.counselorDashboard;
    final anchorShell = _routeShellForLocation(returnTo);
    return _CounselorRouteShellConfig(
      section: anchorShell.section,
      title: 'Notifications',
      subtitle:
          'Track booking updates, reminders, and action-required alerts without leaving the counselor workspace.',
      notificationsHighlighted: true,
      childHandlesOwnScroll: true,
    );
  }
  if (state.matchedLocation == AppRoute.counselorSettings) {
    final returnTo =
        _normalizedCounselorWorkspaceRoute(
          state.uri.queryParameters[AppRoute.returnToQuery],
        ) ??
        AppRoute.counselorDashboard;
    final anchorShell = _routeShellForLocation(returnTo);
    return _CounselorRouteShellConfig(
      section: anchorShell.section,
      title: 'Profile Settings',
      subtitle:
          'Manage the professional profile students see, tune booking rules, and update counselor account controls from one workspace.',
      profileHighlighted: true,
      childHandlesOwnScroll: true,
    );
  }
  if (state.matchedLocation == AppRoute.counselorPrivacyControls) {
    return const _CounselorRouteShellConfig(
      section: CounselorWorkspaceNavSection.dashboard,
      title: 'Privacy & Data Controls',
      subtitle:
          'Manage passkeys and export your counselor account data from the same workspace frame.',
      profileHighlighted: true,
      childHandlesOwnScroll: true,
    );
  }
  return _routeShellForLocation(state.matchedLocation);
}

String? _normalizedCounselorWorkspaceRoute(String? rawRoute) {
  final normalized = (rawRoute ?? '').trim();
  switch (normalized) {
    case AppRoute.counselorDashboard:
    case AppRoute.counselorAppointments:
    case AppRoute.counselorAvailability:
    case AppRoute.counselorLiveHub:
    case AppRoute.counselorDirectory:
    case AppRoute.counselorSettings:
      return normalized;
    default:
      return null;
  }
}

_CounselorRouteShellConfig _routeShellForLocation(String matchedLocation) {
  switch (matchedLocation) {
    case AppRoute.counselorAppointments:
      return const _CounselorRouteShellConfig(
        section: CounselorWorkspaceNavSection.sessions,
        title: 'Sessions',
        subtitle:
            'Keep booking requests, live appointments, and session outcomes in one stable counselor workflow.',
      );
    case AppRoute.counselorAvailability:
      return const _CounselorRouteShellConfig(
        section: CounselorWorkspaceNavSection.availability,
        title: 'Availability',
        subtitle:
            'Publish booking windows, manage the weekly grid, and keep your open inventory healthy.',
      );
    case AppRoute.counselorLiveHub:
      return const _CounselorRouteShellConfig(
        section: CounselorWorkspaceNavSection.live,
        title: 'Live',
        subtitle:
            'Join institution audio sessions and host live conversations without leaving the counselor workspace.',
      );
    case AppRoute.counselorDashboard:
    default:
      return const _CounselorRouteShellConfig(
        section: CounselorWorkspaceNavSection.dashboard,
        title: 'Dashboard',
        subtitle:
            'A fixed workspace frame with your live activity, quick actions, and daily priorities in one place.',
      );
  }
}

class CounselorWorkspaceScaffold extends StatelessWidget {
  const CounselorWorkspaceScaffold({
    super.key,
    required this.profile,
    required this.activeSection,
    required this.unreadNotifications,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onSelectSection,
    required this.onNotifications,
    required this.onProfile,
    required this.onLogout,
    this.childHandlesOwnScroll = false,
    this.notificationsHighlighted = false,
    this.profileHighlighted = false,
    this.showCounselorDirectory = false,
  });

  final UserProfile profile;
  final CounselorWorkspaceNavSection activeSection;
  final int unreadNotifications;
  final String title;
  final String subtitle;
  final Widget child;
  final ValueChanged<CounselorWorkspaceNavSection> onSelectSection;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final bool childHandlesOwnScroll;
  final bool notificationsHighlighted;
  final bool profileHighlighted;
  final bool showCounselorDirectory;

  @override
  Widget build(BuildContext context) {
    final overlayMode = notificationsHighlighted || profileHighlighted;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isMobileOverlay = overlayMode && viewportWidth < 760;
    final shellScaffold = Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _WorkspaceBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1120;
              final isTablet = constraints.maxWidth >= 760;
              final showLive =
                  !(!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);
              final navItems = _navItems(
                showCounselorDirectory,
                showLive: showLive,
              );
              if (isDesktop) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 284,
                        child: _DesktopSidebar(
                          profile: profile,
                          activeSection: activeSection,
                          navItems: navItems,
                          onSelectSection: onSelectSection,
                          onLogout: onLogout,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF8F8F3,
                            ).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x120F172A),
                                blurRadius: 30,
                                offset: Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _WorkspaceHeader(
                                title: title,
                                subtitle: subtitle,
                                profile: profile,
                                unreadNotifications: unreadNotifications,
                                desktop: true,
                                onNotifications: onNotifications,
                                onProfile: onProfile,
                                onLogout: onLogout,
                                notificationsHighlighted:
                                    notificationsHighlighted,
                                profileHighlighted: profileHighlighted,
                              ),
                              Expanded(
                                child: overlayMode
                                    ? const SizedBox.shrink()
                                    : childHandlesOwnScroll
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          28,
                                          8,
                                          28,
                                          28,
                                        ),
                                        child: child,
                                      )
                                    : SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                          28,
                                          8,
                                          28,
                                          28,
                                        ),
                                        child: child,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 20 : 14,
                  14,
                  isTablet ? 20 : 14,
                  20,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        _WorkspaceHeader(
                          title: title,
                          subtitle: subtitle,
                          profile: profile,
                          unreadNotifications: unreadNotifications,
                          desktop: false,
                          onNotifications: onNotifications,
                          onProfile: onProfile,
                          onLogout: onLogout,
                          notificationsHighlighted: notificationsHighlighted,
                          profileHighlighted: profileHighlighted,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: overlayMode
                              ? const SizedBox.shrink()
                              : childHandlesOwnScroll
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 116),
                                  child: child,
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 116),
                                  child: child,
                                ),
                        ),
                      ],
                    ),
                    if (!overlayMode)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                            child: _FloatingBottomNav(
                              items: navItems,
                              activeSection: activeSection,
                              onSelectSection: onSelectSection,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    if (isMobileOverlay) {
      return child;
    }

    if (overlayMode) {
      return Stack(
        fit: StackFit.expand,
        children: [
          shellScaffold,
          Positioned.fill(child: child),
        ],
      );
    }

    return shellScaffold;
  }
}

class _WorkspaceBackdrop extends StatelessWidget {
  const _WorkspaceBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEAF6FF), Color(0xFFF7FBF9), Color(0xFFEFF7F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          const _BlurOrb(
            size: 300,
            color: Color(0x5538BDF8),
            offset: Offset(-90, 140),
          ),
          const _BlurOrb(
            size: 260,
            color: Color(0x5514B8A6),
            offset: Offset(1180, 210),
          ),
          const _BlurOrb(
            size: 220,
            color: Color(0x55A7F3D0),
            offset: Offset(120, 760),
          ),
          child,
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.size,
    required this.color,
    required this.offset,
  });

  final double size;
  final Color color;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.profile,
    required this.activeSection,
    required this.navItems,
    required this.onSelectSection,
    required this.onLogout,
  });

  final UserProfile profile;
  final CounselorWorkspaceNavSection activeSection;
  final List<_ShellSidebarItem> navItems;
  final ValueChanged<CounselorWorkspaceNavSection> onSelectSection;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C2233),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.psychology_alt_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MindNest',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        profile.institutionName ?? 'Counselor workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7FA0B5),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            ...navItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SidebarNavItem(
                  item: item,
                  active: item.section == activeSection,
                  onTap: () => onSelectSection(item.section),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF132D41),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1F415A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WORKSPACE STATUS',
                    style: TextStyle(
                      color: Color(0xFF7FA0B5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Counselor sync active',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    profile.name.trim().isNotEmpty
                        ? profile.name.trim()
                        : profile.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBBD0DC),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF325068)),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.unreadNotifications,
    required this.desktop,
    required this.onNotifications,
    required this.onProfile,
    required this.onLogout,
    required this.notificationsHighlighted,
    required this.profileHighlighted,
  });

  final String title;
  final String subtitle;
  final UserProfile profile;
  final int unreadNotifications;
  final bool desktop;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final bool notificationsHighlighted;
  final bool profileHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        desktop ? 28 : 18,
        desktop ? 24 : 18,
        desktop ? 28 : 18,
        desktop ? 18 : 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: desktop ? 0 : 0.9),
        borderRadius: desktop ? null : BorderRadius.circular(28),
        border: Border.all(
          color: desktop ? Colors.transparent : const Color(0xFFDDE6EE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF081A30),
                        fontSize: desktop ? 31 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: desktop ? -1.2 : -0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: desktop ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6A7C93),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _HeaderIconButton(
                icon: Icons.notifications_none_rounded,
                badgeCount: unreadNotifications,
                onTap: onNotifications,
                active: notificationsHighlighted,
              ),
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: Icons.manage_accounts_rounded,
                onTap: onProfile,
                active: profileHighlighted,
              ),
              if (desktop) ...[
                const SizedBox(width: 10),
                const WindowsDesktopWindowControls(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: desktop ? 20 : 18,
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _initials(
                    profile.name.isNotEmpty ? profile.name : profile.email,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.trim().isNotEmpty
                          ? profile.name.trim()
                          : 'Counselor',
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      profile.institutionName ?? 'Institution workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7B8CA4),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _ShellSidebarItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF203A50) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active ? const Color(0xFF325068) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: active
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF89A3B6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFFD3DEE7),
                    fontWeight: FontWeight.w700,
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

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.items,
    required this.activeSection,
    required this.onSelectSection,
  });

  final List<_ShellSidebarItem> items;
  final CounselorWorkspaceNavSection activeSection;
  final ValueChanged<CounselorWorkspaceNavSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where(
          (item) => item.section != CounselorWorkspaceNavSection.counselors,
        )
        .toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = visibleItems.length;
            final activeIndex = visibleItems.indexWhere(
              (item) => item.section == activeSection,
            );
            final selectedIndex = activeIndex < 0 ? 0 : activeIndex;
            const outerInset = 6.0;
            const innerPadding = 6.0;
            const indicatorGap = 4.0;
            final innerWidth =
                constraints.maxWidth - (outerInset * 2) - (innerPadding * 2);
            final slotWidth = innerWidth / count;
            final indicatorWidth = slotWidth - indicatorGap;

            return SizedBox(
              height: 82,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 74,
                      margin: const EdgeInsets.symmetric(
                        horizontal: outerInset,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xF8FFFFFF), Color(0xEDF8FBFF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border.all(color: const Color(0xFFDCE6EF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A0F172A),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                          BoxShadow(
                            color: Color(0x160E9B90),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(innerPadding),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: LayoutBuilder(
                            builder: (context, innerConstraints) {
                              final usableWidth = innerConstraints.maxWidth;
                              final localSlotWidth = usableWidth / count;
                              return Stack(
                                children: [
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    left:
                                        localSlotWidth * selectedIndex +
                                        indicatorGap / 2,
                                    top: 4,
                                    width: indicatorWidth,
                                    height: 58,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF129D93),
                                            Color(0xFF0E879E),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x3314B8A6),
                                            blurRadius: 18,
                                            offset: Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: visibleItems
                                        .map(
                                          (item) => SizedBox(
                                            width: localSlotWidth,
                                            child: _FloatingNavItem(
                                              item: item,
                                              active:
                                                  item.section == activeSection,
                                              badgeCount: 0,
                                              onTap: () =>
                                                  onSelectSection(item.section),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.item,
    required this.active,
    required this.badgeCount,
    required this.onTap,
  });

  final _ShellSidebarItem item;
  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : const Color(0xFF5D7287);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox.expand(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(top: active ? 1 : 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: active ? 30 : 28,
                  height: active ? 30 : 28,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.18)
                        : const Color(0xFFF0F5FA),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active
                          ? Colors.white.withValues(alpha: 0.26)
                          : const Color(0xFFD9E3EC),
                    ),
                  ),
                  child: Icon(
                    item.icon,
                    size: active ? 16.5 : 16,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: active ? 10.0 : 9.6,
                    height: 1.0,
                    letterSpacing: active ? 0.0 : 0.1,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int? badgeCount;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF0C2233) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? const Color(0xFF0C2233)
                      : const Color(0xFFE1E7EF),
                ),
              ),
              child: Icon(
                icon,
                color: active ? Colors.white : const Color(0xFF0C2233),
              ),
            ),
          ),
        ),
        if ((badgeCount ?? 0) > 0)
          Positioned(
            right: -4,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${badgeCount!}',
                style: const TextStyle(
                  color: Color(0xFF0C2233),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShellSidebarItem {
  const _ShellSidebarItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final CounselorWorkspaceNavSection section;
  final String label;
  final IconData icon;
}

List<_ShellSidebarItem> _navItems(
  bool showCounselorDirectory, {
  required bool showLive,
}) {
  return [
    const _ShellSidebarItem(
      section: CounselorWorkspaceNavSection.dashboard,
      label: 'Dashboard',
      icon: Icons.home_outlined,
    ),
    const _ShellSidebarItem(
      section: CounselorWorkspaceNavSection.sessions,
      label: 'Sessions',
      icon: Icons.event_note_rounded,
    ),
    if (showLive)
      const _ShellSidebarItem(
        section: CounselorWorkspaceNavSection.live,
        label: 'Live',
        icon: Icons.podcasts_rounded,
      ),
    const _ShellSidebarItem(
      section: CounselorWorkspaceNavSection.availability,
      label: 'Availability',
      icon: Icons.calendar_month_rounded,
    ),
    if (showCounselorDirectory)
      const _ShellSidebarItem(
        section: CounselorWorkspaceNavSection.counselors,
        label: 'Counselors',
        icon: Icons.groups_rounded,
      ),
  ];
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'MN';
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
