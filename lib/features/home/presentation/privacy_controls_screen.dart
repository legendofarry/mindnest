import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_primary_shell.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';

const Duration _windowsPollInterval = Duration(seconds: 15);
bool get _useWindowsRestFirestore =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Stream<T> _buildWindowsPollingStream<T>({
  required Future<T> Function() load,
  required String Function(T value) signature,
}) {
  late final StreamController<T> controller;
  Timer? timer;
  String? lastEmissionSignature;

  Future<void> emitIfChanged() async {
    if (controller.isClosed) {
      return;
    }
    try {
      final value = await load();
      final nextSignature = 'value:${signature(value)}';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.add(value);
      }
    } catch (error, stackTrace) {
      final nextSignature = 'error:$error';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      unawaited(emitIfChanged());
      timer = Timer.periodic(_windowsPollInterval, (_) {
        unawaited(emitIfChanged());
      });
    },
    onCancel: () {
      timer?.cancel();
    },
  );

  return controller.stream;
}

class PrivacyControlsScreen extends ConsumerStatefulWidget {
  const PrivacyControlsScreen({super.key});

  @override
  ConsumerState<PrivacyControlsScreen> createState() =>
      _PrivacyControlsScreenState();
}

class _PrivacyControlsScreenState extends ConsumerState<PrivacyControlsScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';
    final firestore = _useWindowsRestFirestore
        ? null
        : ref.watch(firestoreProvider);
    final windowsRest = ref.watch(windowsFirestoreRestClientProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isPrimaryUser =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.individual);
    final role = profile?.role ?? UserRole.other;
    final showsVisibilityControls =
        role == UserRole.student ||
        role == UserRole.staff ||
        role == UserRole.individual;
    final usesFloatingDesktopHeader = isDesktop && !isPrimaryUser;
    final privacySettingsStream = userId.isEmpty || !showsVisibilityControls
        ? null
        : _useWindowsRestFirestore
        ? _buildWindowsPollingStream<Map<String, dynamic>>(
            load: () async =>
                (await windowsRest.getDocument(
                  'user_privacy_settings/$userId',
                ))?.data ??
                const <String, dynamic>{},
            signature: (data) => data.toString(),
          )
        : firestore!
              .collection('user_privacy_settings')
              .doc(userId)
              .snapshots()
              .map((doc) => doc.data() ?? const <String, dynamic>{});

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              usesFloatingDesktopHeader ? 92 : 10,
              16,
              18,
            ),
            child: userId.isEmpty
                ? const _PrivacyStateCard(
                    message: 'Sign in to manage privacy settings.',
                  )
                : !showsVisibilityControls
                ? _RoleScopedPrivacyContent(
                    role: role,
                    onExport: () {
                      return showAccountExportSheet(
                        context: context,
                        ref: ref,
                        title: 'Download your account data',
                        subtitle:
                            'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON for your account export.',
                      );
                    },
                  )
                : StreamBuilder<Map<String, dynamic>>(
                    key: ValueKey<String>('privacy:$userId:${role.name}'),
                    stream: privacySettingsStream,
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? const <String, dynamic>{};
                      final shareMood =
                          (data['shareMoodWithInstitution'] as bool?) ?? true;
                      final shareAssessments =
                          (data['shareAssessmentsWithInstitution'] as bool?) ??
                          true;
                      final shareCarePlan =
                          (data['shareCarePlanWithCounselors'] as bool?) ??
                          true;
                      final anonymousForum =
                          (data['anonymousForumMode'] as bool?) ?? true;

                      Future<void> updateSetting(String key, bool value) async {
                        if (_useWindowsRestFirestore) {
                          final existing =
                              (await windowsRest.getDocument(
                                'user_privacy_settings/$userId',
                              ))?.data ??
                              const <String, dynamic>{};
                          await windowsRest.setDocument(
                            'user_privacy_settings/$userId',
                            <String, dynamic>{
                              ...existing,
                              'userId': userId,
                              key: value,
                              'updatedAt': DateTime.now().toUtc(),
                            },
                          );
                          return;
                        }
                        await firestore!
                            .collection('user_privacy_settings')
                            .doc(userId)
                            .set({
                              'userId': userId,
                              key: value,
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                      }

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _PrivacyHeroCard(),
                            const SizedBox(height: 16),
                            const _PrivacyStateCard(
                              message:
                                  'Control what your institution can view and manage your personal data export preferences from one place.',
                            ),
                            const SizedBox(height: 12),
                            _PrivacyModuleCard(
                              title: 'Visibility & sharing',
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    value: shareMood,
                                    onChanged: (value) => updateSetting(
                                      'shareMoodWithInstitution',
                                      value,
                                    ),
                                    title: const Text('Share mood insights'),
                                    subtitle: const Text(
                                      'Allow institution wellness team to view mood trends.',
                                    ),
                                  ),
                                  SwitchListTile(
                                    value: shareAssessments,
                                    onChanged: (value) => updateSetting(
                                      'shareAssessmentsWithInstitution',
                                      value,
                                    ),
                                    title: const Text(
                                      'Share assessment outcomes',
                                    ),
                                    subtitle: const Text(
                                      'Allow staff to view high-level assessment summaries.',
                                    ),
                                  ),
                                  SwitchListTile(
                                    value: shareCarePlan,
                                    onChanged: (value) => updateSetting(
                                      'shareCarePlanWithCounselors',
                                      value,
                                    ),
                                    title: const Text(
                                      'Share care plan progress',
                                    ),
                                    subtitle: const Text(
                                      'Allow counselors to monitor your goal completion.',
                                    ),
                                  ),
                                  SwitchListTile(
                                    value: anonymousForum,
                                    onChanged: (value) => updateSetting(
                                      'anonymousForumMode',
                                      value,
                                    ),
                                    title: const Text('Anonymous forum mode'),
                                    subtitle: const Text(
                                      'Hide identifiable profile details in community forum.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                      showAccountExportSheet(
                                        context: context,
                                        ref: ref,
                                        title: 'Download your account data',
                                        subtitle:
                                            'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON for your account export.',
                                      );
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
                    },
                  ),
          ),
        ),
      ),
    );

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
  const _RoleScopedPrivacyContent({required this.role, required this.onExport});

  final UserRole role;
  final Future<void> Function() onExport;

  String get _roleLabel {
    switch (role) {
      case UserRole.institutionAdmin:
        return 'Institution admin';
      case UserRole.counselor:
        return 'Counselor';
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
          _PrivacyHeroCard(
            title: 'Privacy & Data Controls',
            description: _heroDescription,
          ),
          const SizedBox(height: 16),
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
