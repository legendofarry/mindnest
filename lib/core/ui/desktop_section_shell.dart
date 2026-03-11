import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';

class DesktopSectionBody extends StatelessWidget {
  const DesktopSectionBody({
    super.key,
    required this.isDesktop,
    required this.hasInstitution,
    required this.canAccessLive,
    required this.child,
    this.sidebarWidth = 240,
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

class DesktopSectionNav extends StatelessWidget {
  const DesktopSectionNav({
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
      const _DesktopNavItem(
        label: 'Live',
        icon: Icons.podcasts_outlined,
        route: AppRoute.liveHub,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1220) : const Color(0xFF0C1B33),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Image(
                        image: AssetImage('assets/logo.png'),
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'MindNest',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Text(
                  'Student Workspace',
                  style: TextStyle(
                    color: Color(0xFFD6E3F5),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Core navigation for care, live spaces, and counselor discovery.',
                  style: TextStyle(
                    color: Color(0xFF9FB2CC),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'Navigation',
              style: TextStyle(
                color: const Color(0xFF9FB2CC),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items.map((item) {
            final active =
                location == item.route ||
                (item.route == AppRoute.liveHub &&
                    location == AppRoute.liveRoom);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _handlePrimaryNavTap(
                  context,
                  route: item.route,
                  hasInstitution: hasInstitution,
                  canAccessLive: canAccessLive,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF12314B)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF1F6BFF).withValues(alpha: 0.34)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF15A39A).withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.icon,
                          size: 18,
                          color: active
                              ? const Color(0xFF6EE7D8)
                              : const Color(0xFF8FA4C2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active
                                ? Colors.white
                                : const Color(0xFFB7C6DA),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 16,
                        color: active
                            ? const Color(0xFFD6E3F5)
                            : const Color(0xFF67819E),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.shield_moon_outlined,
                  color: Color(0xFF8FA4C2),
                  size: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Student, staff, and individual screens keep the same mobile bottom navigation.',
                    style: TextStyle(
                      color: Color(0xFF9FB2CC),
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
        child: Row(
          children: items.map((item) {
            final active =
                location == item.route ||
                (item.route == AppRoute.liveHub &&
                    location == AppRoute.liveRoom);
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
                      const SizedBox(height: 4),
                      Text(
                        item.label,
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
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
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
