import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';

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
  final _langs = TextEditingController();
  final _bio = TextEditingController();

  bool _seeded = false;
  bool _seededNotif = false;

  String _specialization = 'General Counseling';
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
  bool _exporting = false;

  static const _specs = <String>[
    'General Counseling',
    'Academic Counseling',
    'Workplace Wellbeing',
    'Anxiety & Stress Support',
    'Burnout Recovery',
    'Relationship Counseling',
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

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _years.dispose();
    _langs.dispose();
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
      _langs.text =
          (cp?.languages ??
                  ((setup['languages'] as List?) ?? const <dynamic>[])
                      .map((e) => e.toString())
                      .toList(growable: false))
              .join(', ');
      _bio.text = cp?.bio ?? (setup['bio'] as String? ?? '');

      _specialization =
          cp?.specialization ??
          (setup['specialization'] as String? ?? _specialization);
      if (!_specs.contains(_specialization)) _specialization = _specs.first;

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
    setState(() => _savingProfile = true);
    try {
      final years = int.tryParse(_years.text.trim()) ?? 0;
      final languages = _langs.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      await ref
          .read(counselorRepositoryProvider)
          .updateProfileAndSettings(
            displayName: _name.text,
            title: _title.text,
            specialization: _specialization,
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

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final data = await ref
          .read(authRepositoryProvider)
          .exportCurrentUserData();
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data copied to clipboard.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Counselor Profile & Settings'),
        leading: const BackToHomeButton(),
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null || profile.role != UserRole.counselor) {
            return const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Only counselors can access this page.'),
              ),
            );
          }
          return StreamBuilder<CounselorProfile?>(
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
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(
                          title: 'Public Profile',
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _active
                                  ? 'Visible to students'
                                  : 'Hidden from students',
                            ),
                            subtitle: Text(
                              profile.institutionName ?? 'Institution not set',
                            ),
                            value: _active,
                            onChanged: (value) =>
                                setState(() => _active = value),
                          ),
                        ),
                        _Section(
                          title: 'Professional Details',
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
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _title,
                                  decoration: const InputDecoration(
                                    labelText: 'Professional Title',
                                    prefixIcon: Icon(Icons.badge),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: _specialization,
                                  decoration: const InputDecoration(
                                    labelText: 'Specialization',
                                    prefixIcon: Icon(Icons.psychology_alt),
                                  ),
                                  items: _specs
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) => setState(
                                    () => _specialization =
                                        value ?? _specialization,
                                  ),
                                ),
                                const SizedBox(height: 10),
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
                                    const SizedBox(width: 10),
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
                                const SizedBox(height: 10),
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
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _langs,
                                  decoration: const InputDecoration(
                                    labelText: 'Languages',
                                    hintText: 'English, Swahili',
                                    prefixIcon: Icon(Icons.language),
                                  ),
                                ),
                                const SizedBox(height: 10),
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
                        _Section(
                          title: 'Practice Settings',
                          child: Column(
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
                              const SizedBox(height: 10),
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
                                onChanged: (value) =>
                                    setState(() => _breakMins = value.round()),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Allow Direct Booking'),
                                value: _direct,
                                onChanged: (value) =>
                                    setState(() => _direct = value),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Auto-approve Follow-ups'),
                                value: _followUps,
                                onChanged: (value) =>
                                    setState(() => _followUps = value),
                              ),
                            ],
                          ),
                        ),
                        _Section(
                          title: 'Notifications',
                          child: Column(
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Booking Updates'),
                                value: _bookingUpdates,
                                onChanged: (value) =>
                                    setState(() => _bookingUpdates = value),
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
                                onChanged: (value) =>
                                    setState(() => _cancellations = value),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: _savingNotif
                                      ? null
                                      : () => _saveNotif(profile),
                                  icon: const Icon(Icons.notifications_active),
                                  label: Text(
                                    _savingNotif
                                        ? 'Saving...'
                                        : 'Save Notifications',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Section(
                          title: 'Account',
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.lock_reset),
                                title: const Text('Send Password Reset Link'),
                                subtitle: Text(profile.email),
                                onTap: _sendingReset
                                    ? null
                                    : () => _sendReset(profile),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.privacy_tip),
                                title: const Text('Privacy & Data Controls'),
                                onTap: () =>
                                    context.go(AppRoute.privacyControls),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.download),
                                title: const Text('Export My Data'),
                                onTap: _exporting ? null : _exportData,
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _savingProfile
                                ? null
                                : () => _save(profile),
                            icon: const Icon(Icons.save),
                            label: Text(
                              _savingProfile ? 'Saving...' : 'Save All Changes',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error.toString()),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
