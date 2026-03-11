import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/app/theme_mode_controller.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';

class InstitutionAdminProfileScreen extends ConsumerStatefulWidget {
  const InstitutionAdminProfileScreen({super.key});

  @override
  ConsumerState<InstitutionAdminProfileScreen> createState() =>
      _InstitutionAdminProfileScreenState();
}

class _InstitutionAdminProfileScreenState
    extends ConsumerState<InstitutionAdminProfileScreen> {
  final _name = TextEditingController();
  final _primaryPhone = TextEditingController(text: '+254');
  final _additionalPhone = TextEditingController();

  bool _seeded = false;
  bool _saving = false;
  bool _sendingReset = false;
  bool _exporting = false;

  @override
  void dispose() {
    _name.dispose();
    _primaryPhone.dispose();
    _additionalPhone.dispose();
    super.dispose();
  }

  void _seed(UserProfile profile) {
    if (_seeded) return;
    _name.text = profile.name;
    _primaryPhone.text = (profile.phoneNumber ?? '').isNotEmpty
        ? profile.phoneNumber!
        : '+254';
    _additionalPhone.text = profile.additionalPhoneNumber ?? '';
    _seeded = true;
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((element) => element.isNotEmpty);
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }

  Future<void> _save(UserProfile profile) async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateAccountProfile(
            name: _name.text.trim(),
            phoneNumber: _primaryPhone.text.trim(),
            additionalPhoneNumber: _additionalPhone.text.trim().isEmpty
                ? null
                : _additionalPhone.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendReset(UserProfile profile) async {
    setState(() => _sendingReset = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordReset(profile.email.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _export(UserProfile profile) async {
    setState(() => _exporting = true);
    try {
      final export =
          await ref.read(authRepositoryProvider).exportCurrentUserData();
      final pretty = const JsonEncoder.withIndent('  ').convert(export);
      await Clipboard.setData(ClipboardData(text: pretty));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data export copied to clipboard.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final themeMode = ref.watch(themeModeControllerProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text(error.toString())),
      ),
      data: (profile) {
        if (profile == null) {
          return const Scaffold(
            body: Center(
              child: Text('No profile found for this account.'),
            ),
          );
        }
        _seed(profile);
        return _ProfileBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go(AppRoute.institutionAdmin),
              ),
              titleSpacing: 0,
              elevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: const Text(
                'Admin Profile',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.push(AppRoute.notifications),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Privacy & data',
                  onPressed: () => context.push(AppRoute.privacyControls),
                  icon: const Icon(Icons.privacy_tip_outlined),
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileHero(
                          name: profile.name,
                          email: profile.email,
                          institution: profile.institutionName ?? '',
                          initials: _initials(profile.name.isNotEmpty
                              ? profile.name
                              : profile.email),
                        ),
                        const SizedBox(height: 16),
                        _SettingsCard(
                          title: 'Account',
                          subtitle:
                              'Update your display name and mobile contacts.',
                          child: Column(
                            children: [
                              TextField(
                                controller: _name,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.badge_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _primaryPhone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Primary mobile (+254...)',
                                  prefixIcon: Icon(Icons.phone_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _additionalPhone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Additional mobile (optional)',
                                  prefixIcon: Icon(Icons.smartphone_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Use Kenya mobile numbers in +254 format.',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _saving ? null : () => _save(profile),
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: Text(_saving ? 'Saving...' : 'Save'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SettingsCard(
                          title: 'App settings',
                          subtitle: 'Personalize how MindNest feels for you.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Theme',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Light'),
                                    selected: themeMode == ThemeMode.light,
                                    onSelected: (_) => ref
                                        .read(
                                          themeModeControllerProvider.notifier,
                                        )
                                        .setMode(ThemeMode.light),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Dark'),
                                    selected: themeMode == ThemeMode.dark,
                                    onSelected: (_) => ref
                                        .read(
                                          themeModeControllerProvider.notifier,
                                        )
                                        .setMode(ThemeMode.dark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push(AppRoute.privacyControls),
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text('Privacy controls'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _exporting
                                    ? null
                                    : () => _export(profile),
                                icon: _exporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded),
                                label: Text(
                                  _exporting
                                      ? 'Preparing export...'
                                      : 'Export my data (JSON)',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SettingsCard(
                          title: 'Security',
                          subtitle:
                              'Manage sign-in and account protections.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.mail_outline_rounded),
                                title: const Text('Email'),
                                subtitle: Text(profile.email),
                                trailing: IconButton(
                                  tooltip: 'Copy email',
                                  icon: const Icon(Icons.copy_rounded),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: profile.email),
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Email copied.'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _sendingReset
                                    ? null
                                    : () => _sendReset(profile),
                                icon: _sendingReset
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.lock_reset_rounded),
                                label: Text(
                                  _sendingReset
                                      ? 'Sending reset...'
                                      : 'Send password reset',
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: const Color(0xFF0E9B90),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () => confirmAndLogout(
                                  context: context,
                                  ref: ref,
                                ),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('Log out'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop({required this.child});

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
            child: _Orb(color: const Color(0x3314B8A6), size: 220),
          ),
          Positioned(
            right: -40,
            top: 260,
            child: _Orb(color: const Color(0x3338BDF8), size: 260),
          ),
          Positioned(
            left: 120,
            bottom: -60,
            child: _Orb(color: const Color(0x3358D8C5), size: 210),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

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
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 90,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.email,
    required this.institution,
    required this.initials,
  });

  final String name;
  final String email;
  final String institution;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E9B90), Color(0xFF0B7D73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0E9B90),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF0E9B90),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFFE0F2F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (institution.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B6B63),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          institution,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
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
              fontSize: 16,
              color: Color(0xFF081A30),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
