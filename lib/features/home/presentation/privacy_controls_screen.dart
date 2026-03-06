import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

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

    return MindNestShell(
      maxWidth: 880,
      appBar: AppBar(
        title: const Text('Privacy & Data Controls'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackToHomeButton(),
      ),
      child: userId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Sign in to manage privacy settings.'),
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('user_privacy_settings')
                  .doc(userId)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() ?? const <String, dynamic>{};
                final shareMood =
                    (data['shareMoodWithInstitution'] as bool?) ?? true;
                final shareAssessments =
                    (data['shareAssessmentsWithInstitution'] as bool?) ?? true;
                final shareCarePlan =
                    (data['shareCarePlanWithCounselors'] as bool?) ?? true;
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
                    const GlassCard(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Control what your institution can view and manage your personal data export/deletion.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
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
                              title: const Text('Share assessment outcomes'),
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
                              onChanged: (value) =>
                                  updateSetting('anonymousForumMode', value),
                              title: const Text('Anonymous forum mode'),
                              subtitle: const Text(
                                'Hide identifiable profile details in community forum.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Data Self-service',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
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
                                          setState(() => _isExporting = false);
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
                    ),
                  ],
                );
              },
            ),
    );
  }
}
