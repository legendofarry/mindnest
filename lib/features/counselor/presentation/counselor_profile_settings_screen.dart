// ignore_for_file: unnecessary_string_interpolations, deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/auth/presentation/passkey_management_dialog.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/presentation/notification_center_screen.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/models/counselor_language_catalog.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

enum CounselorProfileSettingsSection {
  identity,
  professionalDetails,
  specializations,
  languages,
  bio,
  sessionRhythm,
  passwordSignIn,
  privacyData,
}

class _ProfileSettingsNavItem {
  const _ProfileSettingsNavItem({
    required this.section,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final CounselorProfileSettingsSection section;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
}

class CounselorProfileSettingsScreen extends ConsumerStatefulWidget {
  const CounselorProfileSettingsScreen({
    super.key,
    this.returnToRoute,
    this.initialSection = CounselorProfileSettingsSection.identity,
    this.embeddedInCounselorShell = false,
  });

  final String? returnToRoute;
  final CounselorProfileSettingsSection initialSection;
  final bool embeddedInCounselorShell;

  @override
  ConsumerState<CounselorProfileSettingsScreen> createState() =>
      _CounselorProfileSettingsScreenState();
}

class _CounselorProfileSettingsScreenState
    extends ConsumerState<CounselorProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _years = TextEditingController();
  final _bio = TextEditingController();

  bool _seeded = false;

  String _specialization = _specs.first;
  Set<String> _specializations = {_specs.first};
  String _mode = 'Hybrid';
  String _timezone = 'Africa/Nairobi';
  bool _active = true;
  int _duration = 50;
  int _breakMins = 10;
  bool _direct = true;
  bool _followUps = false;

  bool _savingProfile = false;
  bool _sendingReset = false;
  String _settingsSearchQuery = '';
  CounselorProfileSettingsSection _selectedSection =
      CounselorProfileSettingsSection.identity;
  bool _settingsDetailOpen = false;

  static const _specs = <String>[
    'Academic Stress',
    'Career Guidance',
    'Anxiety',
    'Depression',
    'Relationship Issues',
    'Family Problems',
    'Self-Esteem',
    'Trauma',
    'Substance Abuse',
    'Bullying',
    'Grief & Loss',
  ];
  static const _modes = <String>['In-person', 'Online', 'Hybrid'];
  static const _zones = <String>[
    'UTC',
    'Africa/Nairobi',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Dubai',
  ];
  static const _durations = <int>[30, 45, 50, 60, 75, 90];

  Set<String>? _languages;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _years.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _settingsDetailOpen =
        widget.initialSection != CounselorProfileSettingsSection.identity;
  }

  void _seed(UserProfile profile, CounselorProfile? cp) {
    if (!_seeded) {
      final setup = profile.counselorSetupData;
      final prefs = profile.counselorPreferences;
      _name.text = cp?.displayName ?? profile.name;
      _title.text = cp?.title ?? (setup['title'] as String? ?? '');
      _years.text =
          ((cp?.yearsExperience ??
                  (setup['yearsExperience'] as num?)?.toInt() ??
                  0))
              .toString();
      final langs = cp?.languages.isNotEmpty == true
          ? normalizeCounselorLanguages(cp!.languages)
          : normalizeCounselorLanguages(switch (setup['languages']) {
              final List<dynamic> values => values,
              final String value => value.split(','),
              _ => const <dynamic>[],
            });
      _languages = langs.isNotEmpty
          ? langs.toSet()
          : {counselorLanguageOptions.first};
      _bio.text = cp?.bio ?? (setup['bio'] as String? ?? '');

      final specializationRaw =
          cp?.specialization ?? (setup['specialization'] as String? ?? '');
      final parsedSpecs = specializationRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && _specs.contains(e))
          .toSet();
      _specializations = parsedSpecs.isNotEmpty ? parsedSpecs : {_specs.first};
      _specialization = _specializations.isNotEmpty
          ? _specializations.first
          : _specs.first;

      _mode = cp?.sessionMode ?? (setup['sessionMode'] as String? ?? _mode);
      if (!_modes.contains(_mode)) _mode = _modes.first;

      _timezone = cp?.timezone ?? (setup['timezone'] as String? ?? _timezone);
      if (!_zones.contains(_timezone)) _timezone = _zones.first;

      _active = cp?.isActive ?? (setup['isActive'] as bool? ?? true);
      final d = (prefs['defaultSessionMinutes'] as num?)?.toInt();
      if (d != null && _durations.contains(d)) _duration = d;
      final b = (prefs['breakBetweenSessionsMins'] as num?)?.toInt();
      if (b != null && b >= 0 && b <= 60) _breakMins = b;
      _direct = (prefs['allowDirectBooking'] as bool?) ?? true;
      _followUps = (prefs['autoApproveFollowUps'] as bool?) ?? false;
      _seeded = true;
    }
  }

  Future<void> _save(UserProfile profile) async {
    if (!_formKey.currentState!.validate()) return;
    _languages ??= {counselorLanguageOptions.first};
    setState(() => _savingProfile = true);
    try {
      final years = int.tryParse(_years.text.trim()) ?? 0;
      final languages = normalizeCounselorLanguages(_languages!);
      await ref
          .read(counselorRepositoryProvider)
          .updateProfileAndSettings(
            displayName: _name.text,
            title: _title.text,
            specialization: _specializations.join(', '),
            yearsExperience: years,
            sessionMode: _mode,
            timezone: _timezone,
            bio: _bio.text,
            languages: languages,
            isActive: _active,
            defaultSessionMinutes: _duration,
            breakBetweenSessionsMins: _breakMins,
            allowDirectBooking: _direct,
            autoApproveFollowUps: _followUps,
          );
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Counselor profile updated.')),
      );
      _seeded = false;
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _sendReset(UserProfile profile) async {
    setState(() => _sendingReset = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(profile.email);
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text('Password reset sent to ${profile.email}.')),
      );
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  void _navigateSection(
    BuildContext context,
    CounselorWorkspaceNavSection section,
  ) {
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
  }

  @override
  void didUpdateWidget(covariant CounselorProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _selectedSection = widget.initialSection;
      _settingsDetailOpen =
          widget.initialSection != CounselorProfileSettingsSection.identity;
    }
  }

  void _selectSection(CounselorProfileSettingsSection section) {
    setState(() {
      _selectedSection = section;
      _settingsDetailOpen = true;
    });
  }

  void _collapseSectionDetails() {
    if (!_settingsDetailOpen) {
      return;
    }
    setState(() => _settingsDetailOpen = false);
  }

  String _defaultCloseRoute() {
    if (widget.returnToRoute != null &&
        widget.returnToRoute!.trim().isNotEmpty) {
      return widget.returnToRoute!.trim();
    }
    return AppRoute.counselorDashboard;
  }

  void _closeOverlay(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(_defaultCloseRoute());
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
          final slide =
              Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
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

  List<_ProfileSettingsNavItem> _navItems(UserProfile profile) {
    final institution = profile.institutionName?.trim().isNotEmpty == true
        ? profile.institutionName!.trim()
        : 'Counselor workspace';
    final displayName = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    final visibleSummary = _active ? 'Visible to students' : 'Hidden';
    final specialized = _specializations.isEmpty
        ? 'No specialties set'
        : _specializations.join(' · ');
    final languageSummary = (_languages ?? {counselorLanguageOptions.first})
        .join(' · ');
    return <_ProfileSettingsNavItem>[
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.identity,
        group: 'PROFILE',
        title: 'Identity',
        subtitle: '$displayName · $institution',
        icon: Icons.person_rounded,
        accent: const Color(0xFF14B8A6),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.professionalDetails,
        group: 'PROFILE',
        title: 'Professional details',
        subtitle:
            '${_title.text.trim().isEmpty ? 'Licensed Counselor' : _title.text.trim()} · ${_years.text.trim().isEmpty ? '${_years.text.trim()}' : '${_years.text.trim()} yrs'} · $_mode',
        icon: Icons.work_history_rounded,
        accent: const Color(0xFF10B981),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.specializations,
        group: 'PROFILE',
        title: 'Specializations',
        subtitle: specialized,
        icon: Icons.shield_rounded,
        accent: const Color(0xFF8B5CF6),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.languages,
        group: 'PROFILE',
        title: 'Languages',
        subtitle: languageSummary,
        icon: Icons.translate_rounded,
        accent: const Color(0xFFEC4899),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.bio,
        group: 'PROFILE',
        title: 'Bio',
        subtitle: _bio.text.trim().isEmpty ? 'Not set yet' : _bio.text.trim(),
        icon: Icons.description_rounded,
        accent: const Color(0xFFF59E0B),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.sessionRhythm,
        group: 'PRACTICE',
        title: 'Session rhythm',
        subtitle: '$_duration min · $_breakMins min break',
        icon: Icons.schedule_rounded,
        accent: const Color(0xFF06B6D4),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.passwordSignIn,
        group: 'ACCOUNT',
        title: 'Password & sign-in',
        subtitle: profile.email,
        icon: Icons.vpn_key_rounded,
        accent: const Color(0xFF0E9B90),
      ),
      _ProfileSettingsNavItem(
        section: CounselorProfileSettingsSection.privacyData,
        group: 'ACCOUNT',
        title: 'Privacy & data',
        subtitle: visibleSummary,
        icon: Icons.public_rounded,
        accent: const Color(0xFF7C3AED),
      ),
    ];
  }

  bool _matchesNavSearch(_ProfileSettingsNavItem item) {
    final query = _settingsSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return [
      item.group,
      item.title,
      item.subtitle,
      item.section.name,
    ].join(' ').toLowerCase().contains(query);
  }

  String _sectionTitle(CounselorProfileSettingsSection section) {
    return switch (section) {
      CounselorProfileSettingsSection.identity => 'Identity',
      CounselorProfileSettingsSection.professionalDetails =>
        'Professional details',
      CounselorProfileSettingsSection.specializations => 'Specializations',
      CounselorProfileSettingsSection.languages => 'Languages',
      CounselorProfileSettingsSection.bio => 'Bio',
      CounselorProfileSettingsSection.sessionRhythm => 'Session rhythm',
      CounselorProfileSettingsSection.passwordSignIn => 'Password & sign-in',
      CounselorProfileSettingsSection.privacyData => 'Privacy & data',
    };
  }

  String _sectionDescription(CounselorProfileSettingsSection section) {
    return switch (section) {
      CounselorProfileSettingsSection.identity =>
        'Display name, avatar, and how students see your counselor identity.',
      CounselorProfileSettingsSection.professionalDetails =>
        'Title, years of practice, mode, and timezone.',
      CounselorProfileSettingsSection.specializations =>
        'The areas students can book you for.',
      CounselorProfileSettingsSection.languages =>
        'Languages you provide sessions in.',
      CounselorProfileSettingsSection.bio =>
        'A calm, human summary that helps students know what to expect.',
      CounselorProfileSettingsSection.sessionRhythm =>
        'Set your default rhythm, breaks, and booking preferences.',
      CounselorProfileSettingsSection.passwordSignIn =>
        'Send yourself a password reset link.',
      CounselorProfileSettingsSection.privacyData =>
        'Visibility, exports, and account data controls.',
    };
  }

  IconData _sectionIcon(CounselorProfileSettingsSection section) {
    return switch (section) {
      CounselorProfileSettingsSection.identity => Icons.person_rounded,
      CounselorProfileSettingsSection.professionalDetails =>
        Icons.work_history_rounded,
      CounselorProfileSettingsSection.specializations => Icons.shield_rounded,
      CounselorProfileSettingsSection.languages => Icons.translate_rounded,
      CounselorProfileSettingsSection.bio => Icons.description_rounded,
      CounselorProfileSettingsSection.sessionRhythm => Icons.schedule_rounded,
      CounselorProfileSettingsSection.passwordSignIn => Icons.vpn_key_rounded,
      CounselorProfileSettingsSection.privacyData => Icons.public_rounded,
    };
  }

  Color _sectionAccent(CounselorProfileSettingsSection section) {
    return switch (section) {
      CounselorProfileSettingsSection.identity => const Color(0xFF14B8A6),
      CounselorProfileSettingsSection.professionalDetails => const Color(
        0xFF10B981,
      ),
      CounselorProfileSettingsSection.specializations => const Color(
        0xFF8B5CF6,
      ),
      CounselorProfileSettingsSection.languages => const Color(0xFFEC4899),
      CounselorProfileSettingsSection.bio => const Color(0xFFF59E0B),
      CounselorProfileSettingsSection.sessionRhythm => const Color(0xFF06B6D4),
      CounselorProfileSettingsSection.passwordSignIn => const Color(0xFF0E9B90),
      CounselorProfileSettingsSection.privacyData => const Color(0xFF7C3AED),
    };
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null || profile.role != UserRole.counselor) {
          return const Scaffold(
            body: Center(child: Text('Only counselors can access this page.')),
          );
        }
        final unreadCount =
            ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
        final showCounselorDirectory =
            ref
                .watch(
                  counselorWorkflowSettingsProvider(
                    profile.institutionId ?? '',
                  ),
                )
                .valueOrNull
                ?.directoryEnabled ??
            false;
        final settingsBody = StreamBuilder<CounselorProfile?>(
          stream: ref
              .read(careRepositoryProvider)
              .watchCounselorProfile(profile.id),
          builder: (context, cpSnap) {
            _seed(profile, cpSnap.data);
            return _buildOverlayWorkspace(
              context,
              profile,
              unreadCount,
              showCounselorDirectory,
            );
          },
        );
        if (widget.embeddedInCounselorShell) {
          return settingsBody;
        }
        return CounselorWorkspaceScaffold(
          profile: profile,
          activeSection: CounselorWorkspaceNavSection.dashboard,
          showCounselorDirectory: showCounselorDirectory,
          unreadNotifications: unreadCount,
          profileHighlighted: true,
          title: 'Profile Settings',
          subtitle:
              'Manage the professional profile students see, tune booking rules, and update counselor account controls from one workspace.',
          onSelectSection: (section) => _navigateSection(context, section),
          onNotifications: () => _openCounselorNotificationsOverlay(context),
          onProfile: () {},
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: settingsBody,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyBuild(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null || profile.role != UserRole.counselor) {
          return const Scaffold(
            body: Center(child: Text('Only counselors can access this page.')),
          );
        }
        final unreadCount =
            ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
        final showCounselorDirectory =
            ref
                .watch(
                  counselorWorkflowSettingsProvider(
                    profile.institutionId ?? '',
                  ),
                )
                .valueOrNull
                ?.directoryEnabled ??
            false;
        final settingsBody = StreamBuilder<CounselorProfile?>(
          stream: ref
              .read(careRepositoryProvider)
              .watchCounselorProfile(profile.id),
          builder: (context, cpSnap) {
            _seed(profile, cpSnap.data);
            final settingsContent = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsHero(
                  profile: profile,
                  specialization: _specialization,
                  isActive: _active,
                  duration: _duration,
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoColumns = constraints.maxWidth >= 980;
                    final halfWidth = useTwoColumns
                        ? (constraints.maxWidth - 18) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        SizedBox(
                          width: halfWidth,
                          child: _SettingsSectionCard(
                            title: 'Practice Settings',
                            description:
                                'Define the default session rhythm and spacing that shape your counselor workflow.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<int>(
                                  initialValue: _duration,
                                  decoration: const InputDecoration(
                                    labelText: 'Default Session Duration',
                                    prefixIcon: Icon(Icons.timer_outlined),
                                  ),
                                  items: _durations
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text('$e min'),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) => setState(
                                    () => _duration = value ?? _duration,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Break Between Sessions'),
                                    ),
                                    Text('$_breakMins min'),
                                  ],
                                ),
                                Slider(
                                  value: _breakMins.toDouble(),
                                  min: 0,
                                  max: 30,
                                  divisions: 6,
                                  onChanged: (value) => setState(
                                    () => _breakMins = value.round(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: halfWidth,
                          child: _SettingsSectionCard(
                            title: 'Account',
                            description:
                                'Security, privacy, and export actions for your counselor account.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ActionTile(
                                  icon: Icons.lock_reset,
                                  title: 'Send Password Reset Link',
                                  subtitle: profile.email,
                                  onTap: _sendingReset
                                      ? null
                                      : () => _sendReset(profile),
                                ),
                                const SizedBox(height: 10),
                                _ActionTile(
                                  icon: Icons.privacy_tip_outlined,
                                  title: 'Privacy & Data Controls',
                                  subtitle:
                                      'Open privacy controls and account data settings.',
                                  onTap: () => context.go(
                                    AppRoute.counselorPrivacyControlsRoute(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: useTwoColumns
                              ? constraints.maxWidth
                              : halfWidth,
                          child: _SettingsSectionCard(
                            title: 'Professional Details',
                            description:
                                'Edit the professional identity and public profile content students see in your counselor listing.',
                            trailing: Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _savingProfile
                                    ? null
                                    : () => _save(profile),
                                icon: const Icon(Icons.save_rounded),
                                label: Text(
                                  _savingProfile
                                      ? 'Saving...'
                                      : 'Save All Changes',
                                ),
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _name,
                                    decoration: const InputDecoration(
                                      labelText: 'Display Name',
                                      prefixIcon: Icon(Icons.person),
                                    ),
                                    validator: (value) =>
                                        (value ?? '').trim().length < 2
                                        ? 'Enter at least 2 characters.'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _title,
                                    decoration: const InputDecoration(
                                      labelText: 'Professional Title',
                                      prefixIcon: Icon(Icons.badge),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _SpecializationChips(
                                    options: _specs,
                                    selected: _specializations,
                                    onChanged: (set) => setState(() {
                                      _specializations = set.isNotEmpty
                                          ? set
                                          : {_specs.first};
                                      _specialization = _specializations.first;
                                    }),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _years,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'Years',
                                            prefixIcon: Icon(Icons.timeline),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _mode,
                                          decoration: const InputDecoration(
                                            labelText: 'Mode',
                                            prefixIcon: Icon(Icons.video_call),
                                          ),
                                          items: _modes
                                              .map(
                                                (e) => DropdownMenuItem(
                                                  value: e,
                                                  child: Text(e),
                                                ),
                                              )
                                              .toList(growable: false),
                                          onChanged: (value) => setState(
                                            () => _mode = value ?? _mode,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: _timezone,
                                    decoration: const InputDecoration(
                                      labelText: 'Timezone',
                                      prefixIcon: Icon(Icons.public),
                                    ),
                                    items: _zones
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) => setState(
                                      () => _timezone = value ?? _timezone,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _LanguageSelector(
                                    options: counselorLanguageOptions,
                                    selected:
                                        _languages ??
                                        {counselorLanguageOptions.first},
                                    onToggle: (lang) {
                                      setState(() {
                                        _languages ??= {
                                          counselorLanguageOptions.first,
                                        };
                                        if (_languages!.contains(lang)) {
                                          _languages!.remove(lang);
                                        } else {
                                          _languages!.add(lang);
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _bio,
                                    minLines: 3,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Bio',
                                      alignLabelWithHint: true,
                                      prefixIcon: Icon(Icons.notes),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.hasBoundedHeight) {
                  return settingsContent;
                }
                return SingleChildScrollView(
                  primary: false,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: settingsContent,
                  ),
                );
              },
            );
          },
        );
        if (widget.embeddedInCounselorShell) {
          return settingsBody;
        }
        return CounselorWorkspaceScaffold(
          profile: profile,
          activeSection: CounselorWorkspaceNavSection.dashboard,
          showCounselorDirectory: showCounselorDirectory,
          unreadNotifications: unreadCount,
          profileHighlighted: true,
          title: 'Profile Settings',
          subtitle:
              'Manage the professional profile students see, tune booking rules, and update counselor account controls from one workspace.',
          onSelectSection: (section) => _navigateSection(context, section),
          onNotifications: () => _openCounselorNotificationsOverlay(context),
          onProfile: () {},
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: settingsBody,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
    );
  }

  Widget _buildOverlayWorkspace(
    BuildContext context,
    UserProfile profile,
    int unreadCount,
    bool showCounselorDirectory,
  ) {
    final navItems = _navItems(profile);
    final visibleItems = navItems
        .where(_matchesNavSearch)
        .toList(growable: false);
    final selectedItem = navItems.firstWhere(
      (item) => item.section == _selectedSection,
      orElse: () => navItems.first,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return _buildMobileOverlayWorkspace(
            context,
            profile,
            unreadCount,
            showCounselorDirectory,
            navItems,
            visibleItems,
            selectedItem,
          );
        }
        final isWide = constraints.maxWidth >= 1080;
        final panelWidth = _settingsDetailOpen
            ? math.min(constraints.maxWidth, 1360.0)
            : math.min(constraints.maxWidth, 460.0);
        final railWidth = math.min(390.0, panelWidth);

        return Scaffold(
          backgroundColor: const Color(0xFF07111D),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isWide ? 18 : 12, 12, 12, 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      currentChild ?? const SizedBox.shrink(),
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: _settingsDetailOpen
                    ? Row(
                        key: const ValueKey('settings-split'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: railWidth,
                            child: _buildSettingsRail(
                              context,
                              profile,
                              navItems,
                              visibleItems,
                              unreadCount,
                              showCounselorDirectory,
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          Expanded(
                            child: _buildSettingsPane(
                              context,
                              profile,
                              showCounselorDirectory,
                              selectedItem,
                            ),
                          ),
                        ],
                      )
                    : SizedBox.expand(
                        key: const ValueKey('settings-rail'),
                        child: _buildSettingsRail(
                          context,
                          profile,
                          navItems,
                          visibleItems,
                          unreadCount,
                          showCounselorDirectory,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileOverlayWorkspace(
    BuildContext context,
    UserProfile profile,
    int unreadCount,
    bool showCounselorDirectory,
    List<_ProfileSettingsNavItem> allItems,
    List<_ProfileSettingsNavItem> visibleItems,
    _ProfileSettingsNavItem selectedItem,
  ) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111D),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _settingsDetailOpen,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  offset: _settingsDetailOpen
                      ? const Offset(-1, 0)
                      : Offset.zero,
                  child: _buildSettingsRail(
                    context,
                    profile,
                    allItems,
                    visibleItems,
                    unreadCount,
                    showCounselorDirectory,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_settingsDetailOpen,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  offset: _settingsDetailOpen
                      ? Offset.zero
                      : const Offset(1, 0),
                  child: _buildSettingsPane(
                    context,
                    profile,
                    showCounselorDirectory,
                    selectedItem,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsRail(
    BuildContext context,
    UserProfile profile,
    List<_ProfileSettingsNavItem> allItems,
    List<_ProfileSettingsNavItem> visibleItems,
    int unreadCount,
    bool showCounselorDirectory,
  ) {
    final visibleSet = visibleItems.toSet();
    final grouped = <String, List<_ProfileSettingsNavItem>>{};
    for (final item in allItems) {
      if (!visibleSet.contains(item)) {
        continue;
      }
      grouped
          .putIfAbsent(item.group, () => <_ProfileSettingsNavItem>[])
          .add(item);
    }

    final displayName = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    final institution = profile.institutionName?.trim().isNotEmpty == true
        ? profile.institutionName!.trim()
        : 'Institution workspace';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF13D0C7), Color(0xFF0E9B90)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  displayName.trim().isNotEmpty
                      ? displayName.trim()[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Tune what students see and how you work.',
                      style: TextStyle(
                        color: Color(0xFF8EA0B8),
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _closeOverlay(context),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111B2B),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E9B90).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x220E9B90)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName
                              .trim()
                              .split(RegExp(r'\s+'))
                              .take(2)
                              .map((part) => part.isNotEmpty ? part[0] : '')
                              .join()
                              .toUpperCase()
                        : 'LW',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _active
                                  ? const Color(0x1A10B981)
                                  : const Color(0x1AF97316),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _active
                                    ? const Color(0x3310B981)
                                    : const Color(0x33F97316),
                              ),
                            ),
                            child: Text(
                              _active ? 'Visible' : 'Hidden',
                              style: TextStyle(
                                color: _active
                                    ? const Color(0xFF10E3B0)
                                    : const Color(0xFFF59E0B),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        institution,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF93A5BC),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _settingsSearchQuery = value),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search settings',
              hintStyle: const TextStyle(color: Color(0xFF6D7F97)),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: const Color(0xFF121D2F),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF0E9B90)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...['PROFILE', 'PRACTICE', 'ACCOUNT'].expand((group) {
                  final groupItems = grouped[group];
                  if (groupItems == null || groupItems.isEmpty) {
                    return const <Widget>[];
                  }
                  return <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        group,
                        style: const TextStyle(
                          color: Color(0xFF6C7E95),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...groupItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildNavTile(
                          context,
                          item,
                          item.section == _selectedSection,
                        ),
                      ),
                    ),
                  ];
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111B2B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_outlined,
                      color: Color(0xFF57D6C8),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Workspace status',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      unreadCount > 0 ? '$unreadCount unread' : 'All read',
                      style: const TextStyle(
                        color: Color(0xFF8EA0B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  showCounselorDirectory
                      ? 'Counselor directory is live for this institution.'
                      : 'Counselor directory visibility is currently off.',
                  style: const TextStyle(
                    color: Color(0xFF8EA0B8),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context,
    _ProfileSettingsNavItem item,
    bool selected,
  ) {
    return InkWell(
      onTap: () => _selectSection(item.section),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A2434)
              : const Color(0xFF121D2F).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF24344B) : const Color(0x1FFFFFFF),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: item.accent.withValues(alpha: 0.26)),
              ),
              child: Icon(item.icon, color: item.accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8EA0B8),
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: selected
                  ? const Color(0xFFBBD0DC)
                  : const Color(0xFF586C82),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPane(
    BuildContext context,
    UserProfile profile,
    bool showCounselorDirectory,
    _ProfileSettingsNavItem selectedItem,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 18, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _collapseSectionDetails,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('All settings'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _closeOverlay(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SingleChildScrollView(
                key: ValueKey(selectedItem.section),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _sectionAccent(
                              selectedItem.section,
                            ).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _sectionAccent(
                                selectedItem.section,
                              ).withValues(alpha: 0.24),
                            ),
                          ),
                          child: Icon(
                            _sectionIcon(selectedItem.section),
                            color: _sectionAccent(selectedItem.section),
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _sectionTitle(selectedItem.section).toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF57D6C8),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _sectionTitle(selectedItem.section),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _sectionDescription(selectedItem.section),
                      style: const TextStyle(
                        color: Color(0xFF9FB0C5),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildSectionContent(
                      context,
                      profile,
                      showCounselorDirectory,
                      selectedItem.section,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    UserProfile profile,
    bool showCounselorDirectory,
    CounselorProfileSettingsSection section,
  ) {
    final darkFieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
    );
    final darkFieldDecoration = InputDecoration(
      filled: true,
      fillColor: const Color(0xFF111B2B),
      border: darkFieldBorder,
      enabledBorder: darkFieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF0E9B90), width: 1.4),
      ),
      labelStyle: const TextStyle(color: Color(0xFF8EA0B8)),
      floatingLabelStyle: const TextStyle(color: Color(0xFF57D6C8)),
      hintStyle: const TextStyle(color: Color(0xFF63748A)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );

    Widget sectionCard({
      required String title,
      required String description,
      required Widget child,
      Widget? trailing,
    }) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF101A2A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xFF8EA0B8),
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
    }

    Widget actionBar({
      required String label,
      required VoidCallback? onPressed,
      bool primary = true,
      IconData icon = Icons.save_rounded,
    }) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: primary
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111B2B),
                  foregroundColor: Colors.white,
                ),
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }

    switch (section) {
      case CounselorProfileSettingsSection.identity:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Profile snapshot',
              description:
                  'A calm identity card that mirrors the screenshot style and keeps your public presence easy to scan.',
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0E9B90), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: const Color(0x3310E3B0)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.name.trim().isNotEmpty
                          ? profile.name
                                .trim()
                                .split(RegExp(r'\s+'))
                                .take(2)
                                .map((part) => part.isNotEmpty ? part[0] : '')
                                .join()
                                .toUpperCase()
                          : 'LW',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.trim().isNotEmpty
                              ? profile.name.trim()
                              : 'Counselor',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          profile.institutionName ?? 'Institution workspace',
                          style: const TextStyle(
                            color: Color(0xFF9FB0C5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _active
                          ? const Color(0x1A10B981)
                          : const Color(0x1AF97316),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _active
                            ? const Color(0x3310B981)
                            : const Color(0x33F97316),
                      ),
                    ),
                    child: Text(
                      _active ? 'Visible' : 'Hidden',
                      style: TextStyle(
                        color: _active
                            ? const Color(0xFF10E3B0)
                            : const Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            sectionCard(
              title: 'Identity details',
              description: 'Display name and institution name.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    style: const TextStyle(color: Colors.white),
                    decoration: darkFieldDecoration.copyWith(
                      labelText: 'Display name',
                      prefixIcon: const Icon(Icons.person_rounded),
                    ),
                    validator: (value) => (value ?? '').trim().length < 2
                        ? 'Enter at least 2 characters.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: profile.institutionName ?? '',
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: darkFieldDecoration.copyWith(
                      labelText: 'Institution',
                      prefixIcon: const Icon(Icons.apartment_rounded),
                    ),
                  ),
                ],
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.professionalDetails:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Professional details',
              description: 'Title, years of practice, mode, and timezone.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _title,
                    style: const TextStyle(color: Colors.white),
                    decoration: darkFieldDecoration.copyWith(
                      labelText: 'Professional title',
                      prefixIcon: const Icon(Icons.badge_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _years,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: darkFieldDecoration.copyWith(
                            labelText: 'Years of practice',
                            prefixIcon: const Icon(Icons.timeline_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _mode,
                          dropdownColor: const Color(0xFF111B2B),
                          style: const TextStyle(color: Colors.white),
                          decoration: darkFieldDecoration.copyWith(
                            labelText: 'Mode',
                            prefixIcon: const Icon(Icons.video_call_rounded),
                          ),
                          items: _modes
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              setState(() => _mode = value ?? _mode),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _timezone,
                    dropdownColor: const Color(0xFF111B2B),
                    style: const TextStyle(color: Colors.white),
                    decoration: darkFieldDecoration.copyWith(
                      labelText: 'Timezone',
                      prefixIcon: const Icon(Icons.public_rounded),
                    ),
                    items: _zones
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _timezone = value ?? _timezone),
                  ),
                ],
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.specializations:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Specializations',
              description: 'The areas students can book you for.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _specs
                    .map((item) {
                      final selected = _specializations.contains(item);
                      return FilterChip(
                        label: Text(item),
                        selected: selected,
                        onSelected: (value) => setState(() {
                          final next = Set<String>.from(_specializations);
                          if (value) {
                            next.add(item);
                          } else {
                            next.remove(item);
                          }
                          _specializations = next.isEmpty
                              ? {_specs.first}
                              : next;
                          _specialization = _specializations.first;
                        }),
                        selectedColor: const Color(0xFF17385B),
                        backgroundColor: const Color(0xFF111B2B),
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF9FB0C5),
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF0E9B90)
                              : const Color(0x1FFFFFFF),
                        ),
                        checkmarkColor: Colors.white,
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.languages:
        final selectedLanguages =
            _languages ?? {counselorLanguageOptions.first};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Languages',
              description: 'Languages you provide sessions in.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: counselorLanguageOptions
                    .map((lang) {
                      final selected = selectedLanguages.contains(lang);
                      return FilterChip(
                        label: Text(lang),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            _languages ??= {counselorLanguageOptions.first};
                            if (value) {
                              _languages!.add(lang);
                            } else {
                              _languages!.remove(lang);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF17385B),
                        backgroundColor: const Color(0xFF111B2B),
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF9FB0C5),
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF0E9B90)
                              : const Color(0x1FFFFFFF),
                        ),
                        checkmarkColor: Colors.white,
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.bio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Bio',
              description:
                  'A calm, human summary that helps students know what to expect.',
              child: TextFormField(
                controller: _bio,
                minLines: 5,
                maxLines: 8,
                style: const TextStyle(color: Colors.white),
                decoration: darkFieldDecoration.copyWith(
                  labelText: 'Bio',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_rounded),
                ),
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.sessionRhythm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Session rhythm',
              description:
                  'Set your default rhythm, breaks, and booking preferences.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _duration,
                    dropdownColor: const Color(0xFF111B2B),
                    style: const TextStyle(color: Colors.white),
                    decoration: darkFieldDecoration.copyWith(
                      labelText: 'Default session duration',
                      prefixIcon: const Icon(Icons.timer_outlined),
                    ),
                    items: _durations
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e, child: Text('$e min')),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _duration = value ?? _duration),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Break between sessions',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$_breakMins min',
                        style: const TextStyle(color: Color(0xFF9FB0C5)),
                      ),
                    ],
                  ),
                  Slider(
                    value: _breakMins.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 6,
                    activeColor: const Color(0xFF0E9B90),
                    inactiveColor: const Color(0xFF24344B),
                    onChanged: (value) =>
                        setState(() => _breakMins = value.round()),
                  ),
                  SwitchListTile.adaptive(
                    value: _direct,
                    onChanged: (value) => setState(() => _direct = value),
                    title: const Text(
                      'Allow direct booking',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Let students book without a manual approval step.',
                      style: TextStyle(color: Color(0xFF9FB0C5)),
                    ),
                    activeColor: const Color(0xFF0E9B90),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _followUps,
                    onChanged: (value) => setState(() => _followUps = value),
                    title: const Text(
                      'Auto-approve follow ups',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Keep repeat sessions moving without extra admin.',
                      style: TextStyle(color: Color(0xFF9FB0C5)),
                    ),
                    activeColor: const Color(0xFF0E9B90),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save changes',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
      case CounselorProfileSettingsSection.passwordSignIn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Password & sign-in',
              description: 'Send yourself a password reset link.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'We will email a secure reset link to ${profile.email}.',
                    style: const TextStyle(
                      color: Color(0xFF9FB0C5),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _sendingReset ? null : () => _sendReset(profile),
                    icon: const Icon(Icons.lock_reset_rounded),
                    label: Text(
                      _sendingReset ? 'Sending...' : 'Send reset link',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        showPasskeyManagementDialog(context: context),
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Manage passkeys'),
                  ),
                ],
              ),
            ),
          ],
        );
      case CounselorProfileSettingsSection.privacyData:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionCard(
              title: 'Privacy & data',
              description: 'Visibility, exports, and account data controls.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111B2B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Visible to students',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                showCounselorDirectory
                                    ? 'Appear in the counselor directory.'
                                    : 'Keep your counselor listing hidden from students.',
                                style: const TextStyle(
                                  color: Color(0xFF9FB0C5),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Switch.adaptive(
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          activeColor: const Color(0xFF0E9B90),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => showAccountExportSheet(
                      context: context,
                      ref: ref,
                      title: 'Download your counselor data',
                      subtitle:
                          'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON.',
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export my data'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        showPasskeyManagementDialog(context: context),
                    icon: const Icon(Icons.security_rounded),
                    label: const Text('Manage passkeys'),
                  ),
                ],
              ),
            ),
            actionBar(
              label: _savingProfile ? 'Saving...' : 'Save visibility',
              onPressed: _savingProfile ? null : () => _save(profile),
            ),
          ],
        );
    }
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({
    required this.profile,
    required this.specialization,
    required this.isActive,
    required this.duration,
  });

  final UserProfile profile;
  final String specialization;
  final bool isActive;
  final int duration;

  @override
  Widget build(BuildContext context) {
    final displayName = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF0E9B90)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1D1D4ED8),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroPill(
                label: isActive
                    ? 'VISIBLE TO STUDENTS'
                    : 'HIDDEN FROM STUDENTS',
                background: isActive
                    ? const Color(0x3310B981)
                    : const Color(0x33F97316),
              ),
              _HeroPill(
                label: specialization.toUpperCase(),
                background: const Color(0x22FFFFFF),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.institutionName ?? 'Institution workspace',
            style: const TextStyle(
              color: Color(0xFFE3F2FF),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _HeroMetricCard(label: 'Session default', value: '$duration min'),
              _HeroMetricCard(
                label: 'Profile status',
                value: isActive ? 'Visible' : 'Hidden',
              ),
              _HeroMetricCard(label: 'Email', value: profile.email),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpecializationChips extends StatelessWidget {
  const _SpecializationChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Specializations',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.start,
            runAlignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: options
                .map(
                  (item) => FilterChip(
                    label: Text(item),
                    selected: selected.contains(item),
                    onSelected: (value) {
                      final next = Set<String>.from(selected);
                      if (value) {
                        next.add(item);
                      } else {
                        next.remove(item);
                      }
                      onChanged(next);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF081A30),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF6A7C93),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            child,
            if (trailing != null) ...[const SizedBox(height: 16), trailing!],
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Languages',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF0B2442),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.start,
            runAlignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: options
                .asMap()
                .entries
                .map(
                  (entry) => _OptionPillSmall(
                    label: entry.value,
                    index: entry.key,
                    selected: selected.contains(entry.value),
                    onTap: () => onToggle(entry.value),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _OptionPillSmall extends StatelessWidget {
  const _OptionPillSmall({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  static const _gradients = [
    [Color(0xFFE7F8F5), Color(0xFFD5F1EC)],
    [Color(0xFFEAF2FF), Color(0xFFDCE8FF)],
    [Color(0xFFFFF2DD), Color(0xFFFFE8B8)],
    [Color(0xFFF2EAFE), Color(0xFFE7D8FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF0E9B90), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E9B90)
                  : const Color(0xFFD6E2F1),
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x330E9B90),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_rounded
                    : Icons.add_circle_outline_rounded,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF58708C),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0B2442),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDDE6EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF0E9B90)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6A7C93),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF7B8CA4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.background});

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _HeroMetricCard extends StatelessWidget {
  const _HeroMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFDDEBFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
