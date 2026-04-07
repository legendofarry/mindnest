import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_primary_shell.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';

class PrivacyControlsScreen extends ConsumerStatefulWidget {
  const PrivacyControlsScreen({
    super.key,
    this.embeddedInDesktopShell = false,
    this.embeddedInAdminShell = false,
  });

  final bool embeddedInDesktopShell;
  final bool embeddedInAdminShell;

  @override
  ConsumerState<PrivacyControlsScreen> createState() =>
      _PrivacyControlsScreenState();
}

class _PrivacyControlsScreenState extends ConsumerState<PrivacyControlsScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isPrimaryUser =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.individual);
    final role = profile?.role ?? UserRole.other;
    final usesFloatingDesktopHeader =
        isDesktop &&
        !isPrimaryUser &&
        !widget.embeddedInDesktopShell &&
        !widget.embeddedInAdminShell;
    final adminEmbedded =
        widget.embeddedInAdminShell && role == UserRole.institutionAdmin;
    final maxContentWidth = adminEmbedded
        ? double.infinity
        : role == UserRole.counselor
        ? 1220.0
        : 900.0;
    final contentAlignment = adminEmbedded || role == UserRole.counselor
        ? Alignment.topLeft
        : Alignment.topCenter;
    final onExport = () => showAccountExportSheet(
      context: context,
      ref: ref,
      title: 'Download your account data',
      subtitle:
          'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON for your account export.',
    );
    final onOpenAdminProfile =
        widget.embeddedInAdminShell && role == UserRole.institutionAdmin
        ? () => context.go(
            Uri(
              path: AppRoute.institutionAdmin,
              queryParameters: const <String, String>{
                AppRoute.adminPanelQuery: 'profile',
              },
            ).toString(),
          )
        : null;

    final content = SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          adminEmbedded ? 0 : 16,
          usesFloatingDesktopHeader
              ? 92
              : adminEmbedded
              ? 0
              : 10,
          adminEmbedded ? 0 : 16,
          adminEmbedded ? 0 : 18,
        ),
        child: Align(
          alignment: contentAlignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: userId.isEmpty
                ? const _PrivacyStateCard(
                    message: 'Sign in to manage privacy settings.',
                  )
                : role == UserRole.counselor
                ? _CounselorPrivacyContent(
                    onOpenProfile: () => context.go(AppRoute.counselorSettings),
                    onExport: onExport,
                  )
                : _RoleScopedPrivacyContent(
                    role: role,
                    onOpenProfile: onOpenAdminProfile,
                    onExport: onExport,
                    compactEmbedded: adminEmbedded,
                  ),
          ),
        ),
      ),
    );

    if (widget.embeddedInDesktopShell || widget.embeddedInAdminShell) {
      return content;
    }

    if (isDesktop && isPrimaryUser) {
      return DesktopPrimaryShell(
        matchedLocation: AppRoute.privacyControls,
        child: content,
      );
    }

    if (usesFloatingDesktopHeader) {
      return _PrivacyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              content,
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _PrivacyFloatingHeader(
                    title: 'Privacy & Data Controls',
                    leadingIcon: role == UserRole.counselor
                        ? Icons.arrow_back_rounded
                        : Icons.home_rounded,
                    onLeadingPressed: () {
                      if (role == UserRole.counselor) {
                        context.go(AppRoute.counselorSettings);
                        return;
                      }
                      if (role == UserRole.institutionAdmin) {
                        context.go(AppRoute.institutionAdmin);
                        return;
                      }
                      context.go(AppRoute.home);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: content,
      bottomNavigationBar: null,
    );
  }
}

class _PrivacyHeroCard extends StatelessWidget {
  const _PrivacyHeroCard({
    this.title = 'Privacy & Data Controls',
    this.description =
        'Choose what your institution can see and manage your personal data export settings without leaving the workspace.',
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1C35), Color(0xFF173B69)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              color: Color(0xFFD6E3F5),
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleScopedPrivacyContent extends StatelessWidget {
  const _RoleScopedPrivacyContent({
    required this.role,
    required this.onExport,
    this.onOpenProfile,
    this.compactEmbedded = false,
  });

  final UserRole role;
  final Future<void> Function() onExport;
  final VoidCallback? onOpenProfile;
  final bool compactEmbedded;

  String get _roleLabel {
    switch (role) {
      case UserRole.institutionAdmin:
        return 'Institution admin';
      case UserRole.counselor:
        return 'Counselor';
      case UserRole.student:
        return 'Student';
      case UserRole.staff:
        return 'Staff';
      case UserRole.individual:
        return 'Individual';
      default:
        return role.label;
    }
  }

  String get _heroDescription {
    switch (role) {
      case UserRole.institutionAdmin:
        return 'Keep this page focused on your own admin account data. Student wellness-sharing controls live with each member profile, not here.';
      case UserRole.counselor:
        return 'Keep this page focused on your counselor account data. Student wellbeing-sharing controls are handled on the member side, not in counselor settings.';
      case UserRole.student:
      case UserRole.staff:
      case UserRole.individual:
        return 'Use this page for your own account privacy basics and polished data export without leaving the workspace.';
      default:
        return 'Manage the privacy actions relevant to your account from one place.';
    }
  }

  String get _scopeMessage {
    switch (role) {
      case UserRole.institutionAdmin:
        return 'Institution admins do not use student mood, assessment, or care-plan sharing toggles. Your useful action here is personal data export.';
      case UserRole.counselor:
        return 'Counselors do not use the student-facing wellness sharing toggles on this page. Your useful action here is personal data export.';
      case UserRole.student:
      case UserRole.staff:
      case UserRole.individual:
        return 'The visibility and sharing toggles were removed here so this screen stays focused on clean personal data control and export.';
      default:
        return 'This role only needs account-level privacy actions on this screen.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (role == UserRole.counselor || role == UserRole.institutionAdmin) ...[
            _PrivacyBreadcrumb(
              items: role == UserRole.institutionAdmin
                  ? const ['Admin Profile', 'Privacy & Data Controls']
                  : const ['Profile', 'Privacy & Data Controls'],
              onTapLeading: onOpenProfile,
            ),
            const SizedBox(height: 12),
          ],
          if (!compactEmbedded) ...[
            _PrivacyHeroCard(
              title: 'Privacy & Data Controls',
              description: _heroDescription,
            ),
            const SizedBox(height: 16),
          ],
          _PrivacyStateCard(message: '$_roleLabel scope. $_scopeMessage'),
          const SizedBox(height: 12),
          _PrivacyModuleCard(
            title: 'Data self-service',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Download your current data package as a polished PDF summary, CSV tables, or advanced raw JSON.',
                  style: TextStyle(
                    color: Color(0xFF5A6E87),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    unawaited(onExport());
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download My Data'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CounselorPrivacyContent extends StatelessWidget {
  const _CounselorPrivacyContent({
    required this.onExport,
    required this.onOpenProfile,
  });

  final Future<void> Function() onExport;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useTwoColumns = constraints.maxWidth >= 1000;

          final leadColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PrivacyHeroCard(
                title: 'Counselor Privacy & Data Controls',
                description:
                    'Keep this page focused on your counselor account data. Student wellbeing-sharing controls live on member accounts, not here.',
              ),
              const SizedBox(height: 16),
              const _PrivacyModuleCard(
                title: 'Counselor account scope',
                child: Text(
                  'This area is intentionally narrower in responsibility than the member privacy screen. Your useful actions here are account-level controls and clean personal data export, not student sharing toggles.',
                  style: TextStyle(
                    color: Color(0xFF5A6E87),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          );

          final sideColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PrivacyStateCard(
                message:
                    'Use this page for your own counselor account data only. It is not a recycled student privacy screen.',
              ),
              const SizedBox(height: 16),
              _PrivacyModuleCard(
                title: 'Data self-service',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Download your current account data package as a polished PDF summary, CSV tables, or advanced raw JSON whenever you need it.',
                      style: TextStyle(
                        color: Color(0xFF5A6E87),
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        unawaited(onExport());
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download My Data'),
                    ),
                  ],
                ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PrivacyBreadcrumb(
                items: const ['Profile', 'Privacy & Data Controls'],
                onTapLeading: onOpenProfile,
              ),
              const SizedBox(height: 14),
              if (useTwoColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: leadColumn),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: sideColumn),
                  ],
                )
              else ...[
                leadColumn,
                const SizedBox(height: 16),
                sideColumn,
              ],
              const SizedBox(height: 18),
            ],
          );
        },
      ),
    );
  }
}

class _PrivacyBreadcrumb extends StatelessWidget {
  const _PrivacyBreadcrumb({required this.items, this.onTapLeading});

  final List<String> items;
  final VoidCallback? onTapLeading;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          Container(
            decoration: BoxDecoration(
              color: index == items.length - 1
                  ? const Color(0xFFE0F2FE)
                  : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: index == items.length - 1
                    ? const Color(0xFFBAE6FD)
                    : const Color(0xFFD9E3EE),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: index == 0 ? onTapLeading : null,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    items[index],
                    style: TextStyle(
                      color: index == items.length - 1
                          ? const Color(0xFF0C4A6E)
                          : const Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (index != items.length - 1)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
        ],
      ],
    );
  }
}

class _PrivacyStateCard extends StatelessWidget {
  const _PrivacyStateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E3EE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF4A607C),
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}

class _PrivacyModuleCard extends StatelessWidget {
  const _PrivacyModuleCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E3EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Color(0xFF10243F),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PrivacyFloatingHeader extends StatelessWidget {
  const _PrivacyFloatingHeader({
    required this.title,
    required this.leadingIcon,
    required this.onLeadingPressed,
  });

  final String title;
  final IconData leadingIcon;
  final VoidCallback onLeadingPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _PrivacyHeaderActionButton(
              tooltip: 'Route action',
              icon: leadingIcon,
              onPressed: onLeadingPressed,
            ),
            _PrivacyHeaderTitleChip(title: title),
          ],
        ),
        const Spacer(),
        const WindowsDesktopWindowControls(),
      ],
    );
  }
}

class _PrivacyHeaderTitleChip extends StatelessWidget {
  const _PrivacyHeaderTitleChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.2,
          color: Color(0xFF081A30),
        ),
      ),
    );
  }
}

class _PrivacyHeaderActionButton extends StatelessWidget {
  const _PrivacyHeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD8E2EE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF16324F)),
          ),
        ),
      ),
    );
  }
}

class _PrivacyBackdrop extends StatelessWidget {
  const _PrivacyBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEDF6FB), Color(0xFFEAF4F2), Color(0xFFF7F8F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -60,
            child: _PrivacyOrb(color: const Color(0x3314B8A6), size: 220),
          ),
          Positioned(
            right: -40,
            top: 260,
            child: _PrivacyOrb(color: const Color(0x3338BDF8), size: 260),
          ),
          Positioned(
            left: 120,
            bottom: -60,
            child: _PrivacyOrb(color: const Color(0x3358D8C5), size: 210),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _PrivacyOrb extends StatelessWidget {
  const _PrivacyOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 90, spreadRadius: 10)],
      ),
    );
  }
}
