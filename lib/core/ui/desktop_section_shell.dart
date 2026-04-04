import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';

bool get _isWindowsApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class DesktopSectionBody extends StatelessWidget {
  const DesktopSectionBody({
    super.key,
    required this.isDesktop,
    required this.hasInstitution,
    required this.canAccessLive,
    required this.child,
    this.sidebarWidth = 296,
    this.gap = 18,
  });

  final bool isDesktop;
  final bool hasInstitution;
  final bool canAccessLive;
  final Widget child;
  final double sidebarWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return child;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: DesktopSectionNav(
            hasInstitution: hasInstitution,
            canAccessLive: canAccessLive,
          ),
        ),
        SizedBox(width: gap),
        Expanded(child: child),
      ],
    );
  }
}

void _showOrganizationRequiredModal(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFBE123C),
          size: 32,
        ),
        title: const Text('Organization Required'),
        content: const Text(
          'You need to be in an organization to access this section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

void _showLiveAccessLimitedModal(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFF0E9B90),
          size: 30,
        ),
        title: const Text('Live Access Limited'),
        content: const Text(
          'Only student, staff, or counselor roles can access Live.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

void _handlePrimaryNavTap(
  BuildContext context, {
  required String route,
  required bool hasInstitution,
  required bool canAccessLive,
}) {
  final needsInstitution =
      route == AppRoute.counselorDirectory ||
      route == AppRoute.studentAppointments ||
      route == AppRoute.liveHub;

  if (needsInstitution && !hasInstitution) {
    _showOrganizationRequiredModal(context);
    return;
  }

  if (route == AppRoute.liveHub && !canAccessLive) {
    _showLiveAccessLimitedModal(context);
    return;
  }

  context.go(route);
}

class DesktopSectionNav extends ConsumerWidget {
  const DesktopSectionNav({
    super.key,
    required this.hasInstitution,
    required this.canAccessLive,
  });

  final bool hasInstitution;
  final bool canAccessLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = GoRouterState.of(context);
    final location = state.matchedLocation;
    final activeLocation = _resolvePrimaryNavLocation(
      matchedLocation: location,
      currentUri: state.uri,
    );
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final displayName = _displayName(profile);
    final roleLabel = _roleLabel(profile);
    final initials = _initialsForProfile(profile);
    final items = <_DesktopNavItem>[
      const _DesktopNavItem(
        label: 'Home',
        icon: Icons.home_outlined,
        route: AppRoute.home,
      ),
      const _DesktopNavItem(
        label: 'Counselors',
        icon: Icons.groups_outlined,
        route: AppRoute.counselorDirectory,
      ),
      const _DesktopNavItem(
        label: 'Sessions',
        icon: Icons.calendar_month_outlined,
        route: AppRoute.studentAppointments,
      ),
      if (!_isWindowsApp)
        const _DesktopNavItem(
          label: 'Live',
          icon: Icons.podcasts_outlined,
          route: AppRoute.liveHub,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2430),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.center,
            child: Image(
              image: AssetImage('assets/mindnest-logo.png'),
              height: 84,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
            child: Text(
              'NAVIGATION',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.76),
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.8,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...items.map((item) {
                    final active =
                        activeLocation == item.route ||
                        (item.route == AppRoute.liveHub &&
                            activeLocation == AppRoute.liveRoom);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _handlePrimaryNavTap(
                          context,
                          route: item.route,
                          hasInstitution: hasInstitution,
                          canAccessLive: canAccessLive,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFF2C3442)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(
                                          0xFF60E2CC,
                                        ).withValues(alpha: 0.14)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: 20,
                                  color: active
                                      ? const Color(0xFF60E2CC)
                                      : Colors.white.withValues(alpha: 0.84),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: active
                                        ? const Color(0xFF60E2CC)
                                        : Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF60E2CC)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A3140), Color(0xFF242B38)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRO TIP',
                          style: TextStyle(
                            color: Color(0xFF60E2CC),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Regular check-ins help counselors better understand your journey.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF60E2CC), Color(0xFF1F8EB6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _SidebarFooterIconButton(
                tooltip: 'Logout',
                icon: Icons.logout_rounded,
                onTap: () => confirmAndLogout(context: context, ref: ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _resolvePrimaryNavLocation({
  required String matchedLocation,
  required Uri currentUri,
}) {
  if (matchedLocation != AppRoute.notifications) {
    return matchedLocation;
  }

  final rawReturnTo = currentUri.queryParameters[AppRoute.returnToQuery];
  final returnToUri = Uri.tryParse((rawReturnTo ?? '').trim());
  switch (returnToUri?.path) {
    case AppRoute.home:
    case AppRoute.counselorDirectory:
    case AppRoute.studentAppointments:
    case AppRoute.liveHub:
      return returnToUri!.path;
    default:
      return AppRoute.home;
  }
}

class _SidebarFooterIconButton extends StatelessWidget {
  const _SidebarFooterIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.86),
            size: 20,
          ),
        ),
      ),
    );
  }
}

String _displayName(UserProfile? profile) {
  final rawName = profile?.name.trim() ?? '';
  if (rawName.isNotEmpty) {
    return rawName;
  }
  final email = profile?.email.trim() ?? '';
  if (email.contains('@')) {
    return email.split('@').first;
  }
  if (email.isNotEmpty) {
    return email;
  }
  return 'MindNest User';
}

String _roleLabel(UserProfile? profile) {
  return profile?.role.label ?? 'Member';
}

String _initialsForProfile(UserProfile? profile) {
  final parts = _displayName(profile)
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'MN';
  }
  final buffer = StringBuffer();
  buffer.write(parts.first.substring(0, 1).toUpperCase());
  if (parts.length > 1) {
    buffer.write(parts.last.substring(0, 1).toUpperCase());
  } else if (parts.first.length > 1) {
    buffer.write(parts.first[1].toUpperCase());
  }
  return buffer.toString();
}

class PrimaryMobileBottomNav extends StatelessWidget {
  const PrimaryMobileBottomNav({
    super.key,
    required this.hasInstitution,
    required this.canAccessLive,
  });

  final bool hasInstitution;
  final bool canAccessLive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final location = GoRouterState.of(context).matchedLocation;
    final items = <_DesktopNavItem>[
      const _DesktopNavItem(
        label: 'Home',
        icon: Icons.home_outlined,
        route: AppRoute.home,
      ),
      const _DesktopNavItem(
        label: 'Counselors',
        icon: Icons.groups_outlined,
        route: AppRoute.counselorDirectory,
      ),
      const _DesktopNavItem(
        label: 'Sessions',
        icon: Icons.calendar_month_outlined,
        route: AppRoute.studentAppointments,
      ),
      if (!_isWindowsApp)
        const _DesktopNavItem(
          label: 'Live',
          icon: Icons.podcasts_outlined,
          route: AppRoute.liveHub,
        ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF101A2A) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD2DCE9),
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0x120F172A))
                  .withValues(alpha: isDark ? 0.22 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // When space is tight, show labels only for the active tab.
            final hideInactiveLabels = constraints.maxWidth < 300;
            return Row(
              children: items.map((item) {
                final active =
                    location == item.route ||
                    (item.route == AppRoute.liveHub &&
                        location == AppRoute.liveRoom);
                final showLabel = !hideInactiveLabels || active;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _handlePrimaryNavTap(
                      context,
                      route: item.route,
                      hasInstitution: hasInstitution,
                      canAccessLive: canAccessLive,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? (isDark
                                  ? const Color(0xFF143440)
                                  : const Color(0xFFE7F3F1))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            size: 22,
                            color: active
                                ? const Color(0xFF0E9B90)
                                : (isDark
                                      ? const Color(0xFF8FA4C2)
                                      : const Color(0xFF6A7D96)),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 16,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: showLabel
                                  ? Text(
                                      item.label,
                                      key: ValueKey(item.label),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: active
                                            ? const Color(0xFF0E9B90)
                                            : (isDark
                                                  ? const Color(0xFF8FA4C2)
                                                  : const Color(0xFF6A7D96)),
                                      ),
                                    )
                                  : const SizedBox(key: ValueKey('spacer')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _DesktopNavItem {
  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}
