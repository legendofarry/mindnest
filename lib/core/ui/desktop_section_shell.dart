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

class DesktopSectionNav extends StatelessWidget {
  const DesktopSectionNav({
    super.key,
    required this.hasInstitution,
    required this.canAccessLive,
  });

  final bool hasInstitution;
  final bool canAccessLive;

  void _showOrganizationRequiredModal(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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

  void _handleTap(BuildContext context, String route) {
    final needsInstitution =
        route == AppRoute.counselorDirectory ||
        route == AppRoute.studentAppointments ||
        route == AppRoute.liveHub;

    if (needsInstitution && !hasInstitution) {
      _showOrganizationRequiredModal(context);
      return;
    }

    if (route == AppRoute.liveHub && !canAccessLive) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
      return;
    }

    context.go(route);
  }

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
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101A2A) : const Color(0xFFFFFFFF),
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD2DCE9),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Text(
              'Navigation',
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF9FB2CC)
                    : const Color(0xFF516784),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.2,
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
                onTap: () => _handleTap(context, item.route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? (isDark
                              ? const Color(0xFF143440)
                              : const Color(0xFFE7F3F1))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: active
                            ? const Color(0xFF0E9B90)
                            : (isDark
                                  ? const Color(0xFF8FA4C2)
                                  : const Color(0xFF6A7D96)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
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
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
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
