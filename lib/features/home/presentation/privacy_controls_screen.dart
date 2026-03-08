import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_primary_shell.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class PrivacyControlsScreen extends ConsumerStatefulWidget {
  const PrivacyControlsScreen({super.key});

  @override
  ConsumerState<PrivacyControlsScreen> createState() =>
      _PrivacyControlsScreenState();
}

class _PrivacyControlsScreenState extends ConsumerState<PrivacyControlsScreen> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';
    final firestore = ref.watch(firestoreProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isPrimaryUser =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.individual);
    final hasInstitution = (profile?.institutionId ?? '').isNotEmpty;
    final canAccessLive =
        profile != null &&
        (profile.role == UserRole.student || profile.role == UserRole.staff);

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: userId.isEmpty
                ? const _PrivacyStateCard(
                    message: 'Sign in to manage privacy settings.',
                  )
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: firestore
                        .collection('user_privacy_settings')
                        .doc(userId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final data =
                          snapshot.data?.data() ?? const <String, dynamic>{};
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

                      Future<void> updateSetting(String key, bool value) {
                        return firestore
                            .collection('user_privacy_settings')
                            .doc(userId)
                            .set({
                              'userId': userId,
                              key: value,
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                      }

                      return Column(
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
                                  title: const Text('Share care plan progress'),
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
                                  'Export a copy of your current data package in JSON format.',
                                  style: TextStyle(
                                    color: Color(0xFF5A6E87),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _isExporting
                                      ? null
                                      : () async {
                                          setState(() => _isExporting = true);
                                          try {
                                            final export = await ref
                                                .read(authRepositoryProvider)
                                                .exportCurrentUserData();
                                            final pretty =
                                                const JsonEncoder.withIndent(
                                                  '  ',
                                                ).convert(export);
                                            await Clipboard.setData(
                                              ClipboardData(text: pretty),
                                            );
                                            if (!context.mounted) {
                                              return;
                                            }
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Your export JSON was copied to clipboard.',
                                                ),
                                              ),
                                            );
                                          } catch (error) {
                                            if (!context.mounted) {
                                              return;
                                            }
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  error.toString().replaceFirst(
                                                    'Exception: ',
                                                    '',
                                                  ),
                                                ),
                                              ),
                                            );
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => _isExporting = false,
                                              );
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(
                                    _isExporting
                                        ? 'Preparing export...'
                                        : 'Export My Data (JSON)',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: content,
      bottomNavigationBar: !isDesktop && isPrimaryUser
          ? PrimaryMobileBottomNav(
              hasInstitution: hasInstitution,
              canAccessLive: canAccessLive,
            )
          : null,
    );
  }
}

class _PrivacyHeroCard extends StatelessWidget {
  const _PrivacyHeroCard();

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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy & Data Controls',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Choose what your institution can see and manage your personal data export settings without leaving the workspace.',
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
