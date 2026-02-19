// features/home/presentation/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<bool> _hasElevatedRisk({
    required FirebaseFirestore firestore,
    required String userId,
  }) async {
    final onboardingSnapshot = await firestore
        .collection('onboarding_responses')
        .where('userId', isEqualTo: userId)
        .get();

    bool severeOnboardingSignal = false;
    if (onboardingSnapshot.docs.isNotEmpty) {
      onboardingSnapshot.docs.sort((a, b) {
        final aTs =
            (a.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
            0;
        final bTs =
            (b.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
            0;
        return bTs.compareTo(aTs);
      });
      final answers = onboardingSnapshot.docs.first.data()['answers'];
      if (answers is Map<String, dynamic>) {
        final intensity = (answers['intensity_recent'] as String?) ?? '';
        final mood = (answers['today_mood'] as String?) ?? '';
        severeOnboardingSignal =
            intensity == 'severe' || mood == 'low' || mood == 'stressed';
      }
    }

    int negativeCount = 0;
    try {
      final moodSnapshot = await firestore
          .collection('mood_entries')
          .where('userId', isEqualTo: userId)
          .get();
      for (final doc in moodSnapshot.docs) {
        final mood = ((doc.data()['mood'] as String?) ?? '').toLowerCase();
        if (mood == 'stressed' || mood == 'low' || mood == 'sad') {
          negativeCount++;
        }
      }
    } catch (_) {
      negativeCount = 0;
    }

    return severeOnboardingSignal || negativeCount >= 3;
  }

  void _openCrisisSupport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Immediate Support',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'If you are in immediate danger, please reach out now. You are not alone.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _crisisContactTile(
                'US & Canada',
                '988',
                'Suicide & Crisis Lifeline',
              ),
              _crisisContactTile('UK & ROI', '116 123', 'Samaritans'),
              _crisisContactTile('Kenya', '999 / 112', 'Emergency Services'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'I understand, close',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _crisisContactTile(String region, String number, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk_rounded, color: Color(0xFFE11D48)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF9F1239),
                  ),
                ),
                Text(
                  '$region: $label',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE11D48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return MindNestShell(
      maxWidth: 760,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'MindNest',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0D9488),
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => confirmAndLogout(context: context, ref: ref),
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found.'));
          }

          final hasInstitution = (profile.institutionId ?? '').isNotEmpty;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- WELCOME HEADER ---
                Text(
                  'How are you, ${profile.name.split(' ')[0]}? 🌿',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statusPill(
                      profile.role.label,
                      const Color(0xFFF1F5F9),
                      const Color(0xFF475569),
                    ),
                    const SizedBox(width: 8),
                    _statusPill(
                      hasInstitution
                          ? (profile.institutionName ?? 'Active Member')
                          : 'Independent',
                      const Color(0xFFF0FDFA),
                      const Color(0xFF0D9488),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- RISK ALERT ---
                if (profile.role != UserRole.institutionAdmin)
                  FutureBuilder<bool>(
                    future: _hasElevatedRisk(
                      firestore: ref.read(firestoreProvider),
                      userId: profile.id,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFFB45309),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Checking in on you',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFB45309),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'We’ve noticed some heavy moods lately. Remember that professional support is just a click away.',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _openCrisisSupport(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB45309),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Talk to someone now'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                // --- PRIMARY ACTIONS GRID ---
                const Text(
                  'Your Care Hub',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    _buildActionCard(
                      context,
                      'Counselors',
                      Icons.spa_rounded,
                      const Color(0xFF0D9488),
                      hasInstitution
                          ? () => context.go(AppRoute.counselorDirectory)
                          : null,
                    ),
                    _buildActionCard(
                      context,
                      'Sessions',
                      Icons.calendar_today_rounded,
                      const Color(0xFF3B82F6),
                      hasInstitution
                          ? () => context.go(AppRoute.studentAppointments)
                          : null,
                    ),
                    _buildActionCard(
                      context,
                      'Care Plan',
                      Icons.assignment_turned_in_rounded,
                      const Color(0xFF8B5CF6),
                      hasInstitution
                          ? () => context.go(AppRoute.carePlan)
                          : null,
                    ),
                    _buildActionCard(
                      context,
                      'Alerts',
                      Icons.notifications_active_rounded,
                      const Color(0xFFF59E0B),
                      hasInstitution
                          ? () => context.go(AppRoute.notifications)
                          : null,
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- INSTITUTION & PRIVACY ---
                const Text(
                  'Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    children: [
                      if (!hasInstitution)
                        _buildListTile(
                          'Join Institution',
                          Icons.add_business_rounded,
                          () => context.go(AppRoute.joinInstitution),
                        ),
                      if (profile.role == UserRole.institutionAdmin)
                        _buildListTile(
                          'Admin Dashboard',
                          Icons.admin_panel_settings_rounded,
                          () => context.go(AppRoute.institutionAdmin),
                          color: const Color(0xFF0D9488),
                        ),
                      _buildListTile(
                        'Privacy & Data',
                        Icons.shield_moon_rounded,
                        () => context.go(AppRoute.privacyControls),
                      ),
                      if (hasInstitution)
                        _buildListTile(
                          'Leave Institution',
                          Icons.exit_to_app_rounded,
                          () async {
                            await ref
                                .read(institutionRepositoryProvider)
                                .leaveInstitution();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Left Institution'),
                                ),
                              );
                            }
                          },
                          isDestructive: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // --- SOS BUTTON ---
                Center(
                  child: TextButton.icon(
                    onPressed: () => _openCrisisSupport(context),
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFE11D48),
                    ),
                    label: const Text(
                      'Immediate Crisis Support',
                      style: TextStyle(
                        color: Color(0xFFE11D48),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)),
        ),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _statusPill(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textCol,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    final bool isDisabled = onTap == null;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile(
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive
            ? const Color(0xFFE11D48)
            : (color ?? const Color(0xFF64748B)),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDestructive
              ? const Color(0xFFE11D48)
              : const Color(0xFF1E293B),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFCBD5E1),
      ),
      onTap: onTap,
    );
  }
}
