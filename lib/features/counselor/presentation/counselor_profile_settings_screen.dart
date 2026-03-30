import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class CounselorProfileSettingsScreen extends ConsumerStatefulWidget {
  const CounselorProfileSettingsScreen({super.key});

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
  bool _seededNotif = false;

  String _specialization = _specs.first;
  Set<String> _specializations = {_specs.first};
  String _mode = 'Hybrid';
  String _timezone = 'UTC';
  bool _active = true;
  int _duration = 50;
  int _breakMins = 10;
  bool _direct = true;
  bool _followUps = false;

  bool _bookingUpdates = true;
  bool _reminders = true;
  bool _cancellations = true;

  bool _savingProfile = false;
  bool _savingNotif = false;
  bool _sendingReset = false;

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
  static const _languageOptions = <String>[
    'English',
    'Kiswahili',
    'Kikuyu',
    'Luo',
    'Kalenjin',
    'Luhya',
    'Kamba',
    'Somali',
  ];

  Set<String>? _languages;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _years.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(
    UserProfile profile,
    CounselorProfile? cp,
    Map<String, dynamic> n,
  ) {
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
      final langs =
          cp?.languages ??
          ((setup['languages'] as List?) ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(growable: false);
      _languages = langs.isNotEmpty ? langs.toSet() : {_languageOptions.first};
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
    if (!_seededNotif) {
      _bookingUpdates = (n['bookingUpdates'] as bool?) ?? true;
      _reminders = (n['reminders'] as bool?) ?? true;
      _cancellations = (n['cancellations'] as bool?) ?? true;
      _seededNotif = true;
    }
  }

  Future<void> _save(UserProfile profile) async {
    if (!_formKey.currentState!.validate()) return;
    _languages ??= {_languageOptions.first};
    setState(() => _savingProfile = true);
    try {
      final years = int.tryParse(_years.text.trim()) ?? 0;
      final languages = _languages!.toList(growable: false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Counselor profile updated.')),
      );
      _seeded = false;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveNotif(UserProfile profile) async {
    setState(() => _savingNotif = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .saveNotificationSettings(
            userId: profile.id,
            bookingUpdates: _bookingUpdates,
            reminders: _reminders,
            cancellations: _cancellations,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingNotif = false);
    }
  }

  Future<void> _sendReset(UserProfile profile) async {
    setState(() => _sendingReset = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(profile.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset sent to ${profile.email}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
          onNotifications: () => context.go(AppRoute.notifications),
          onProfile: () {},
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: StreamBuilder<CounselorProfile?>(
            stream: ref
                .read(careRepositoryProvider)
                .watchCounselorProfile(profile.id),
            builder: (context, cpSnap) {
              return StreamBuilder<Map<String, dynamic>>(
                stream: ref
                    .read(careRepositoryProvider)
                    .watchNotificationSettings(profile.id),
                builder: (context, nSnap) {
                  _seed(profile, cpSnap.data, nSnap.data ?? const {});
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingsHero(
                        profile: profile,
                        specialization: _specialization,
                        isActive: _active,
                        duration: _duration,
                        directBooking: _direct,
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
                                  title: 'Public Profile',
                                  description:
                                      'Control whether students can discover and book you from the institution directory.',
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      _active
                                          ? 'Visible to students'
                                          : 'Hidden from students',
                                    ),
                                    subtitle: Text(
                                      profile.institutionName ??
                                          'Institution not set',
                                    ),
                                    value: _active,
                                    onChanged: (value) =>
                                        setState(() => _active = value),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: halfWidth,
                                child: _SettingsSectionCard(
                                  title: 'Practice Settings',
                                  description:
                                      'Define the default session rhythm and how booking requests should behave.',
                                  child: Column(
                                    children: [
                                      DropdownButtonFormField<int>(
                                        initialValue: _duration,
                                        decoration: const InputDecoration(
                                          labelText: 'Default Session Duration',
                                          prefixIcon: Icon(
                                            Icons.timer_outlined,
                                          ),
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
                                            child: Text(
                                              'Break Between Sessions',
                                            ),
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
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Allow Direct Booking',
                                        ),
                                        value: _direct,
                                        onChanged: (value) =>
                                            setState(() => _direct = value),
                                      ),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Auto-approve Follow-ups',
                                        ),
                                        value: _followUps,
                                        onChanged: (value) =>
                                            setState(() => _followUps = value),
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
                                            _specialization =
                                                _specializations.first;
                                          }),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _years,
                                                keyboardType:
                                                    TextInputType.number,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Years',
                                                      prefixIcon: Icon(
                                                        Icons.timeline,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    initialValue: _mode,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: 'Mode',
                                                          prefixIcon: Icon(
                                                            Icons.video_call,
                                                          ),
                                                        ),
                                                    items: _modes
                                                        .map(
                                                          (e) =>
                                                              DropdownMenuItem(
                                                                value: e,
                                                                child: Text(e),
                                                              ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                    onChanged: (value) =>
                                                        setState(
                                                          () => _mode =
                                                              value ?? _mode,
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
                                            () =>
                                                _timezone = value ?? _timezone,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _LanguageSelector(
                                          options: _languageOptions,
                                          selected:
                                              _languages ??
                                              {_languageOptions.first},
                                          onToggle: (lang) {
                                            setState(() {
                                              _languages ??= {
                                                _languageOptions.first,
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
                              SizedBox(
                                width: halfWidth,
                                child: _SettingsSectionCard(
                                  title: 'Notifications',
                                  description:
                                      'Choose which counselor workflow alerts should be pushed into your notification center.',
                                  trailing: Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: _savingNotif
                                          ? null
                                          : () => _saveNotif(profile),
                                      icon: const Icon(
                                        Icons.notifications_active,
                                      ),
                                      label: Text(
                                        _savingNotif
                                            ? 'Saving...'
                                            : 'Save Notifications',
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Booking Updates'),
                                        value: _bookingUpdates,
                                        onChanged: (value) => setState(
                                          () => _bookingUpdates = value,
                                        ),
                                      ),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Reminders'),
                                        value: _reminders,
                                        onChanged: (value) =>
                                            setState(() => _reminders = value),
                                      ),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Cancellations'),
                                        value: _cancellations,
                                        onChanged: (value) => setState(
                                          () => _cancellations = value,
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
                                          AppRoute.privacyControls,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _ActionTile(
                                        icon: Icons.download_rounded,
                                        title: 'Download My Data',
                                        subtitle:
                                            'Download a polished PDF summary, CSV tables, or advanced raw JSON for your counselor account.',
                                        onTap: () {
                                          showAccountExportSheet(
                                            context: context,
                                            ref: ref,
                                            title:
                                                'Download your counselor account data',
                                            subtitle:
                                                'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON for your counselor account export.',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({
    required this.profile,
    required this.specialization,
    required this.isActive,
    required this.duration,
    required this.directBooking,
  });

  final UserProfile profile;
  final String specialization;
  final bool isActive;
  final int duration;
  final bool directBooking;

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
                label: 'Direct booking',
                value: directBooking ? 'Enabled' : 'Manual review',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 6),
          child: Text(
            'Specializations',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        Wrap(
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
    return Column(
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
