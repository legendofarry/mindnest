// features/home/presentation/home_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/app/theme_mode_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/ai/models/assistant_models.dart';
import 'package:mindnest/features/ai/presentation/home_ai_assistant_section.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_session.dart';

// ---------------------------------------------------------------------------
// Constants & theme helpers
// ---------------------------------------------------------------------------
const _teal = Color(0xFF0D9488);
const _tealLight = Color(0xFF14B8A6);
const _navy = Color(0xFF0F172A);
const _slate = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _surface = Color(0xFFF8FAFC);
const _cardBg = Colors.white;

// Action card data
const _cardGradients = [
  [Color(0xFF0D9488), Color(0xFF0EA5E9)], // Counselors – teal → sky
  [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Sessions   – indigo → violet
  [Color(0xFF8B5CF6), Color(0xFFEC4899)], // Care Plan  – violet → pink
  [Color(0xFF0EA5E9), Color(0xFF06B6D4)], // Live Hub   – sky → cyan
];

// ---------------------------------------------------------------------------
// Animated fade+slide wrapper used on page load
// ---------------------------------------------------------------------------
class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated action card with press scale
// ---------------------------------------------------------------------------
class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
    this.isDisabled = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback? onTap;
  final bool isDisabled;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.93,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.reverse();
  void _onTapUp(_) => _ctrl.forward();
  void _onTapCancel() => _ctrl.forward();

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isDisabled;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: disabled ? null : _onTapDown,
        onTapUp: disabled ? null : _onTapUp,
        onTapCancel: disabled ? null : _onTapCancel,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: disabled ? 0.42 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                        color: widget.gradientColors.first.withValues(
                          alpha: 0.38,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // ---- kept logic methods (unchanged) ----

  Future<void> _confirmLeaveInstitution(
    BuildContext context,
    WidgetRef ref,
  ) async {
    bool acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFDC2626),
                size: 34,
              ),
              title: const Text('Leave Institution?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If you continue:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text('- You will be removed from this institution.'),
                  const Text('- Your role will switch to Individual.'),
                  const Text(
                    '- Your future pending/confirmed appointments will be cancelled.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: acknowledged,
                    onChanged: (value) {
                      setState(() => acknowledged = value ?? false);
                    },
                    title: const Text(
                      'I understand and want to continue',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep Institution'),
                ),
                ElevatedButton(
                  onPressed: acknowledged
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Yes, Leave'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      final cancelledCount = await ref
          .read(institutionRepositoryProvider)
          .leaveInstitution();
      if (!context.mounted) return;
      final message = cancelledCount > 0
          ? 'Left institution. Cancelled $cancelledCount future appointment(s).'
          : 'Left institution.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

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
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF1F2), Color(0xFFFFE4E6)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Immediate Support',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'You are not alone. Reach out now.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _crisisContactTile(
                'US & Canada',
                '988',
                'Suicide & Crisis Lifeline',
              ),
              _crisisContactTile('UK & ROI', '116 123', 'Samaritans'),
              _crisisContactTile('Kenya', '999 / 112', 'Emergency Services'),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D9488), Color(0xFF0EA5E9)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'I understand, close',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openProfilePanel(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
    final parentContext = context;
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, modalRef, _) {
            final mode = modalRef.watch(themeModeControllerProvider);
            final isDark = mode == ThemeMode.dark;
            final textPrimary = isDark
                ? const Color(0xFFE2E8F0)
                : const Color(0xFF0F172A);
            final textSecondary = isDark
                ? const Color(0xFF94A3B8)
                : const Color(0xFF64748B);
            final sheetBg = isDark ? const Color(0xFF101A2A) : Colors.white;
            final sectionBg = isDark
                ? const Color(0xFF131F32)
                : const Color(0xFFF8FBFF);
            final sectionBorder = isDark
                ? const Color(0xFF2A3A52)
                : const Color(0xFFDDE6F1);
            final canOpenNotifications =
                (profile.institutionId ?? '').isNotEmpty;

            return FractionallySizedBox(
              heightFactor: 0.95,
              child: Container(
                decoration: BoxDecoration(
                  color: sheetBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(36),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF153043),
                                      Color(0xFF1A3951),
                                    ],
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFFE6FFFA),
                                      Color(0xFFEFF6FF),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_teal, Color(0xFF0EA5E9)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                        color: textPrimary,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      profile.email,
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          children: [
                            Text(
                              'App Settings',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: sectionBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: sectionBorder),
                              ),
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    value: isDark,
                                    onChanged: (value) {
                                      modalRef
                                          .read(
                                            themeModeControllerProvider
                                                .notifier,
                                          )
                                          .setMode(
                                            value
                                                ? ThemeMode.dark
                                                : ThemeMode.light,
                                          );
                                    },
                                    title: Text(
                                      'Dark Theme',
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      isDark
                                          ? 'Dark mode enabled'
                                          : 'Light mode enabled',
                                      style: TextStyle(color: textSecondary),
                                    ),
                                    secondary: Icon(
                                      isDark
                                          ? Icons.dark_mode_rounded
                                          : Icons.light_mode_rounded,
                                      color: const Color(0xFF0E9B90),
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: sectionBorder.withValues(alpha: 0.9),
                                  ),
                                  _sheetTile(
                                    context: context,
                                    icon: Icons.notifications_active_outlined,
                                    label: 'Notifications',
                                    subtitle: canOpenNotifications
                                        ? 'Manage your notification center'
                                        : 'Join an institution to manage notifications',
                                    onTap: () {
                                      if (!canOpenNotifications) {
                                        ScaffoldMessenger.of(
                                          parentContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Join an organization to manage notifications.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.of(sheetContext).pop();
                                      parentContext.go(AppRoute.notifications);
                                    },
                                  ),
                                  _sheetTile(
                                    context: context,
                                    icon: Icons.language_rounded,
                                    label: 'Language',
                                    subtitle: 'Coming soon',
                                    onTap: () {
                                      ScaffoldMessenger.of(
                                        parentContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Language settings are coming soon.',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Account Settings',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: sectionBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: sectionBorder),
                              ),
                              child: Column(
                                children: [
                                  _sheetTile(
                                    context: context,
                                    icon: Icons.shield_moon_rounded,
                                    label: 'Privacy & Data',
                                    subtitle: 'Security and privacy controls',
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      parentContext.go(
                                        AppRoute.privacyControls,
                                      );
                                    },
                                  ),
                                  if (hasInstitution)
                                    _sheetTile(
                                      context: context,
                                      icon: Icons.favorite_border_rounded,
                                      label: 'Care Plan',
                                      subtitle: 'Your care goals and progress',
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        parentContext.go(AppRoute.carePlan);
                                      },
                                    ),
                                  if (!hasInstitution)
                                    _sheetTile(
                                      context: context,
                                      icon: Icons.add_business_rounded,
                                      label: 'Join Institution',
                                      subtitle:
                                          'Connect to your school/organization',
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        parentContext.go(
                                          AppRoute.joinInstitution,
                                        );
                                      },
                                    ),
                                  if (profile.role == UserRole.institutionAdmin)
                                    _sheetTile(
                                      context: context,
                                      icon: Icons.admin_panel_settings_rounded,
                                      label: 'Admin Dashboard',
                                      subtitle: 'Manage your institution',
                                      iconColor: _teal,
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        parentContext.go(
                                          AppRoute.institutionAdmin,
                                        );
                                      },
                                    ),
                                  if (hasInstitution)
                                    _sheetTile(
                                      context: context,
                                      icon: Icons.exit_to_app_rounded,
                                      label: 'Leave Institution',
                                      subtitle:
                                          'Switch your account role back to Individual',
                                      iconColor: const Color(0xFFE11D48),
                                      labelColor: const Color(0xFFE11D48),
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        _confirmLeaveInstitution(
                                          parentContext,
                                          ref,
                                        );
                                      },
                                    ),
                                  _sheetTile(
                                    context: context,
                                    icon: Icons.logout_rounded,
                                    label: 'Logout',
                                    subtitle: 'Sign out on this device',
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      Future<void>.delayed(Duration.zero, () {
                                        if (!parentContext.mounted) {
                                          return;
                                        }
                                        confirmAndLogout(
                                          context: parentContext,
                                          ref: ref,
                                        );
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
    Color iconColor = _muted,
    Color labelColor = _slate,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedLabelColor = isDark && labelColor == _slate
        ? const Color(0xFFE2E8F0)
        : labelColor;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: resolvedLabelColor,
              fontSize: 15,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: (isDark ? const Color(0xFF94A3B8) : _muted).withValues(
          alpha: 0.7,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _crisisContactTile(String region, String number, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.phone_in_talk_rounded,
              color: Color(0xFFE11D48),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
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
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '$region - $label',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- build ----

  bool _canAccessLive(UserProfile profile) {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    return hasInstitution &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.counselor);
  }

  Future<void> _runAssistantAction({
    required BuildContext context,
    required UserProfile profile,
    required AssistantAction action,
  }) async {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    final canUseLive = _canAccessLive(profile);

    void showMessage(String text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    switch (action.type) {
      case AssistantActionType.openLiveHub:
        if (!hasInstitution) {
          showMessage('Join an organization to access Live Hub.');
          return;
        }
        if (!canUseLive) {
          showMessage('Your role cannot access Live Hub.');
          return;
        }
        context.go(AppRoute.liveHub);
        return;
      case AssistantActionType.goLiveCreate:
        if (!hasInstitution) {
          showMessage('Join an organization before creating a live session.');
          return;
        }
        if (!canUseLive) {
          showMessage('Your role cannot create live sessions.');
          return;
        }
        context.go('${AppRoute.liveHub}?openCreate=1&source=ai');
        return;
      case AssistantActionType.openCounselors:
        if (!hasInstitution) {
          showMessage('Join an organization to view counselors.');
          return;
        }
        context.go(AppRoute.counselorDirectory);
        return;
      case AssistantActionType.openSessions:
        if (!hasInstitution) {
          showMessage('Join an organization to manage sessions.');
          return;
        }
        context.go(AppRoute.studentAppointments);
        return;
      case AssistantActionType.openNotifications:
        context.go(AppRoute.notifications);
        return;
      case AssistantActionType.openCarePlan:
        if (!hasInstitution) {
          showMessage('Join an organization to access Care Plan.');
          return;
        }
        context.go(AppRoute.carePlan);
        return;
      case AssistantActionType.openJoinInstitution:
        context.go(AppRoute.joinInstitution);
        return;
      case AssistantActionType.openPrivacy:
        context.go(AppRoute.privacyControls);
        return;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final loadedProfile = profileAsync.valueOrNull;
    final canOpenNotifications =
        loadedProfile != null && (loadedProfile.institutionId ?? '').isNotEmpty;
    final hasInstitution = (loadedProfile?.institutionId ?? '').isNotEmpty;
    final canAccessLive =
        loadedProfile != null && _canAccessLive(loadedProfile);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF15A39A), Color(0xFF0E9B90)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.psychology_alt_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'MindNest',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF071937),
                fontSize: 20,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          _AppBarIconBtn(
            icon: Icons.notifications_none_rounded,
            enabled: canOpenNotifications,
            onTap: canOpenNotifications
                ? () => context.go(AppRoute.notifications)
                : null,
          ),
          const SizedBox(width: 8),
          _AppBarIconBtn(
            icon: Icons.person_outline_rounded,
            enabled: loadedProfile != null,
            onTap: loadedProfile == null
                ? null
                : () => _openProfilePanel(context, ref, loadedProfile),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B1220), Color(0xFF0E1A2E)]
                : const [Color(0xFFF4F7FB), Color(0xFFF1F5F9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _AnimatedHomeBlobs(isDark: isDark)),
            SafeArea(
              child: profileAsync.when(
                data: (profile) {
                  if (profile == null) {
                    return const Center(
                      child: Text(
                        'Profile not found.',
                        style: TextStyle(color: Color(0xFF4A607C)),
                      ),
                    );
                  }

                  final hasInstitution =
                      (profile.institutionId ?? '').isNotEmpty;
                  final canAccessLive = _canAccessLive(profile);

                  if (kDebugMode) {
                    final blockers = <String>[
                      if (!hasInstitution) 'institutionId is empty',
                      if (!(profile.role == UserRole.student ||
                          profile.role == UserRole.staff ||
                          profile.role == UserRole.counselor))
                        'role is ${profile.role.name} (not student/staff/counselor)',
                    ];
                    debugPrint(
                      '[LiveHub][Home] uid=${profile.id} role=${profile.role.name} '
                      'institutionId=${profile.institutionId ?? 'null'} '
                      'institutionName=${profile.institutionName ?? 'null'} '
                      'hasInstitution=$hasInstitution canAccessLive=$canAccessLive '
                      'blockers=${blockers.isEmpty ? 'none' : blockers.join(' | ')}',
                    );
                  }

                  final firstName = profile.name.split(' ')[0];
                  final institutionLabel = hasInstitution
                      ? (profile.institutionName ?? 'Institution').toUpperCase()
                      : 'INDIVIDUAL';

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          kToolbarHeight + 16,
                          20,
                          118,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HeroCarousel(
                              profile: profile,
                              firstName: firstName,
                              roleLabel: profile.role.label,
                              institutionName: institutionLabel,
                              hasInstitution: hasInstitution,
                              canAccessLive: canAccessLive,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 24),
                            HomeAiAssistantSection(
                              profile: profile,
                              onActionRequested: (action) =>
                                  _runAssistantAction(
                                    context: context,
                                    profile: profile,
                                    action: action,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            _SosButton(
                              onTap: () => _openCrisisSupport(context),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0E9B90),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (error, _) => Center(
                  child: Text(
                    'Error: $error',
                    style: const TextStyle(color: Color(0xFFBE123C)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _HomeBottomNav(
        hasInstitution: hasInstitution,
        canAccessLive: canAccessLive,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted sub-widgets (UI only)
// ---------------------------------------------------------------------------

class _AnimatedHomeBlobs extends StatefulWidget {
  const _AnimatedHomeBlobs({required this.isDark});

  final bool isDark;

  @override
  State<_AnimatedHomeBlobs> createState() => _AnimatedHomeBlobsState();
}

class _AnimatedHomeBlobsState extends State<_AnimatedHomeBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob(double size, List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.45),
            blurRadius: 64,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blobA = widget.isDark
        ? const [Color(0x2E38BDF8), Color(0x0038BDF8)]
        : const [Color(0x300BA4FF), Color(0x000BA4FF)];
    final blobB = widget.isDark
        ? const [Color(0x2E14B8A6), Color(0x0014B8A6)]
        : const [Color(0x2A15A39A), Color(0x0015A39A)];
    final blobC = widget.isDark
        ? const [Color(0x2E22D3EE), Color(0x0022D3EE)]
        : const [Color(0x2418A89D), Color(0x0018A89D)];

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          return Stack(
            children: [
              Positioned(
                left: -70 + math.sin(t) * 28,
                top: -10 + math.cos(t * 1.2) * 20,
                child: _blob(320, blobA),
              ),
              Positioned(
                right: -70 + math.cos(t * 0.9) * 24,
                top: 150 + math.sin(t * 1.3) * 18,
                child: _blob(340, blobB),
              ),
              Positioned(
                left: 70 + math.cos(t * 1.1) * 18,
                bottom: -90 + math.sin(t * 0.75) * 22,
                child: _blob(280, blobC),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCarousel extends ConsumerStatefulWidget {
  const _HeroCarousel({
    required this.profile,
    required this.firstName,
    required this.roleLabel,
    required this.institutionName,
    required this.hasInstitution,
    required this.canAccessLive,
    required this.isDark,
  });

  final UserProfile profile;
  final String firstName;
  final String roleLabel;
  final String institutionName;
  final bool hasInstitution;
  final bool canAccessLive;
  final bool isDark;

  @override
  ConsumerState<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<_HeroCarousel> {
  static const int _cardCount = 4;
  static const Duration _autoSlideDelay = Duration(seconds: 4);
  late final PageController _pageController = PageController(
    initialPage: 1000 * _cardCount,
  );
  Timer? _autoSlideTimer;
  Timer? _resumeTimer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(_autoSlideDelay, (_) {
      if (_paused || !_pageController.hasClients) {
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pauseTemporarily() {
    _resumeTimer?.cancel();
    setState(() => _paused = true);
  }

  void _resumeLater() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _paused = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _pauseTemporarily(),
        onHorizontalDragCancel: _resumeLater,
        onHorizontalDragEnd: (_) => _resumeLater(),
        child: PageView.builder(
          controller: _pageController,
          itemBuilder: (context, index) {
            final cardIndex = index % _cardCount;
            switch (cardIndex) {
              case 0:
                return _WelcomeHero(
                  firstName: widget.firstName,
                  roleLabel: widget.roleLabel,
                  institutionName: widget.institutionName,
                  hasInstitution: widget.hasInstitution,
                  isDark: widget.isDark,
                );
              case 1:
                return _HeroCardFrame(
                  isDark: widget.isDark,
                  title: 'Sessions',
                  subtitle: 'Tap any session to open details',
                  icon: Icons.calendar_month_rounded,
                  child: _SessionsPreviewCard(
                    profile: widget.profile,
                    onUserInteractionStart: _pauseTemporarily,
                    onUserInteractionEnd: _resumeLater,
                  ),
                );
              case 2:
                return _HeroCardFrame(
                  isDark: widget.isDark,
                  title: 'Open Slots',
                  subtitle: 'Next counselor availability',
                  icon: Icons.event_available_rounded,
                  child: _OpenSlotsPreviewCard(
                    profile: widget.profile,
                    onTapCounselor: (counselorId) {
                      _pauseTemporarily();
                      context.go(
                        '${AppRoute.counselorProfile}?counselorId=$counselorId',
                      );
                    },
                  ),
                );
              default:
                return _HeroCardFrame(
                  isDark: widget.isDark,
                  title: 'Live Now',
                  subtitle: 'Tap a live room to join directly',
                  icon: Icons.podcasts_rounded,
                  child: _LiveNowPreviewCard(
                    profile: widget.profile,
                    canAccessLive: widget.canAccessLive,
                    onTapLive: (sessionId) {
                      _pauseTemporarily();
                      context.go('${AppRoute.liveRoom}?sessionId=$sessionId');
                    },
                  ),
                );
            }
          },
        ),
      ),
    );
  }
}

class _HeroCardFrame extends StatelessWidget {
  const _HeroCardFrame({
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final bool isDark;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF2A3A52)
        : const Color(0xFFDDE6F1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF11263A), Color(0xFF132C43)]
              : const [Color(0xFFE6FFFA), Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.28 : 0.07,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0E9B90), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF516784),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SessionsPreviewCard extends ConsumerStatefulWidget {
  const _SessionsPreviewCard({
    required this.profile,
    required this.onUserInteractionStart,
    required this.onUserInteractionEnd,
  });

  final UserProfile profile;
  final VoidCallback onUserInteractionStart;
  final VoidCallback onUserInteractionEnd;

  @override
  ConsumerState<_SessionsPreviewCard> createState() =>
      _SessionsPreviewCardState();
}

class _SessionsPreviewCardState extends ConsumerState<_SessionsPreviewCard> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  Timer? _resumeTimer;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (_isInteracting || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent <= 0) {
        return;
      }
      var nextOffset = position.pixels + 0.45;
      if (nextOffset >= position.maxScrollExtent) {
        nextOffset = 0;
      }
      _scrollController.jumpTo(nextOffset);
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _pauseInteraction() {
    _resumeTimer?.cancel();
    if (!_isInteracting) {
      setState(() => _isInteracting = true);
      widget.onUserInteractionStart();
    }
  }

  void _resumeInteractionLater() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      if (_isInteracting) {
        setState(() => _isInteracting = false);
        widget.onUserInteractionEnd();
      }
    });
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.profile.role;
    final institutionId = (widget.profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return const Center(
        child: Text(
          'Join an institution to view sessions.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (role == UserRole.institutionAdmin) {
      return const Center(
        child: Text(
          'Session preview is not available for institution admins.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final careRepo = ref.read(careRepositoryProvider);
    final stream = role == UserRole.counselor
        ? careRepo.watchCounselorAppointments(
            institutionId: institutionId,
            counselorId: widget.profile.id,
          )
        : careRepo.watchStudentAppointments(
            institutionId: institutionId,
            studentId: widget.profile.id,
          );

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle) {
          _pauseInteraction();
        } else {
          _resumeInteractionLater();
        }
        return false;
      },
      child: Listener(
        onPointerDown: (_) => _pauseInteraction(),
        onPointerUp: (_) => _resumeInteractionLater(),
        onPointerCancel: (_) => _resumeInteractionLater(),
        child: StreamBuilder<List<AppointmentRecord>>(
          stream: stream,
          builder: (context, snapshot) {
            final allSessions = snapshot.data ?? const <AppointmentRecord>[];
            final sessions =
                allSessions
                    .where((entry) => entry.endAt.isAfter(DateTime.now()))
                    .toList(growable: false)
                  ..sort((a, b) => a.startAt.compareTo(b.startAt));
            final display = sessions.take(12).toList(growable: false);

            if (display.isEmpty) {
              return const Center(
                child: Text(
                  'No upcoming sessions.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            return ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: display.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final session = display[index];
                final name = (session.counselorName ?? '').trim().isNotEmpty
                    ? session.counselorName!.trim()
                    : session.counselorId;
                return GestureDetector(
                  onTap: () => context.go(
                    '${AppRoute.sessionDetails}?appointmentId=${session.id}',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_note_rounded,
                          size: 16,
                          color: Color(0xFF0E9B90),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$name - ${_formatDate(session.startAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _OpenSlotsPreviewCard extends ConsumerWidget {
  const _OpenSlotsPreviewCard({
    required this.profile,
    required this.onTapCounselor,
  });

  final UserProfile profile;
  final ValueChanged<String> onTapCounselor;

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<Map<String, String>> _fetchCounselorNames(
    FirebaseFirestore firestore,
    List<String> counselorIds,
  ) async {
    if (counselorIds.isEmpty) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    for (var i = 0; i < counselorIds.length; i += 10) {
      final end = (i + 10 < counselorIds.length) ? i + 10 : counselorIds.length;
      final chunk = counselorIds.sublist(i, end);
      final profiles = await firestore
          .collection('counselor_profiles')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in profiles.docs) {
        final displayName = (doc.data()['displayName'] as String?)?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          result[doc.id] = displayName;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutionId = (profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return const Center(
        child: Text(
          'Join an institution to view counselor slots.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final stream = ref
        .read(careRepositoryProvider)
        .watchInstitutionPublicAvailability(institutionId: institutionId);
    final firestore = ref.read(firestoreProvider);

    return StreamBuilder<List<AvailabilitySlot>>(
      stream: stream,
      builder: (context, snapshot) {
        final slots = snapshot.data ?? const <AvailabilitySlot>[];
        final topSlots = slots.take(8).toList(growable: false);
        if (topSlots.isEmpty) {
          return const Center(
            child: Text(
              'No open counselor slots right now.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final counselorIds = topSlots
            .map((entry) => entry.counselorId)
            .where((entry) => entry.isNotEmpty)
            .toSet()
            .toList(growable: false);

        return FutureBuilder<Map<String, String>>(
          future: _fetchCounselorNames(firestore, counselorIds),
          builder: (context, namesSnapshot) {
            final names = namesSnapshot.data ?? const <String, String>{};
            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: topSlots.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final slot = topSlots[index];
                final counselorName =
                    names[slot.counselorId] ?? 'Counselor ${slot.counselorId}';
                return GestureDetector(
                  onTap: () => onTapCounselor(slot.counselorId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: Color(0xFF0E9B90),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$counselorName - ${_formatDate(slot.startAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LiveNowPreviewCard extends ConsumerWidget {
  const _LiveNowPreviewCard({
    required this.profile,
    required this.canAccessLive,
    required this.onTapLive,
  });

  final UserProfile profile;
  final bool canAccessLive;
  final ValueChanged<String> onTapLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutionId = (profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return const Center(
        child: Text(
          'Join an institution to see live sessions.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (!canAccessLive) {
      return const Center(
        child: Text(
          'Live is available to student, staff, and counselor roles.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return StreamBuilder<List<LiveSession>>(
      stream: ref
          .read(liveRepositoryProvider)
          .watchInstitutionLives(institutionId: institutionId),
      builder: (context, snapshot) {
        final liveSessions = snapshot.data ?? const <LiveSession>[];
        final topSessions = liveSessions.take(8).toList(growable: false);
        if (topSessions.isEmpty) {
          return const Center(
            child: Text(
              'No live sessions right now.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: topSessions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final live = topSessions[index];
            return GestureDetector(
              onTap: () => onTapLive(live.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.podcasts_rounded,
                      size: 16,
                      color: Color(0xFF0E9B90),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${live.title} - ${live.hostName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AppBarIconBtn extends StatelessWidget {
  const _AppBarIconBtn({required this.icon, required this.enabled, this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131F32) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD2DCE9),
            ),
          ),
          child: Icon(
            icon,
            color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF4A607C),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({
    required this.firstName,
    required this.roleLabel,
    required this.institutionName,
    required this.hasInstitution,
    required this.isDark,
  });
  final String firstName;
  final String roleLabel;
  final String institutionName;
  final bool hasInstitution;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF11263A), Color(0xFF132C43)]
              : const [Color(0xFFE6FFFA), Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.30 : 0.07,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How are you,',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF516784),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            firstName,
            style: const TextStyle(
              fontSize: 50,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0E9B90),
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _Pill(
                label: roleLabel,
                bg: isDark ? const Color(0xFF183744) : const Color(0xFFE7F3F1),
                textColor: isDark
                    ? const Color(0xFF6EE7D8)
                    : const Color(0xFF0E9B90),
                icon: Icons.school_outlined,
              ),
              const SizedBox(width: 8),
              _Pill(
                label: institutionName,
                bg: isDark ? const Color(0xFF1C2F4A) : const Color(0xFFEFF6FF),
                textColor: isDark
                    ? const Color(0xFFB9CCEA)
                    : const Color(0xFF516784),
                icon: hasInstitution
                    ? Icons.business_center_outlined
                    : Icons.person_outline_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.bg,
    required this.textColor,
    required this.icon,
  });
  final String label;
  final Color bg;
  final Color textColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({
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
    final items = <_BottomNavItem>[
      const _BottomNavItem(
        label: 'Home',
        icon: Icons.home_outlined,
        route: AppRoute.home,
      ),
      _BottomNavItem(
        label: 'Counselors',
        icon: Icons.groups_outlined,
        route: AppRoute.counselorDirectory,
      ),
      _BottomNavItem(
        label: 'Sessions',
        icon: Icons.calendar_month_outlined,
        route: AppRoute.studentAppointments,
      ),
      _BottomNavItem(
        label: 'Live',
        icon: Icons.podcasts_outlined,
        route: AppRoute.liveHub,
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF101A2A) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD2DCE9),
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0x120F172A))
                  .withValues(alpha: isDark ? 0.22 : 0.07),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: items.map((item) {
            final active =
                location == item.route ||
                (item.route == AppRoute.liveHub &&
                    location == AppRoute.liveRoom);
            return Expanded(
              child: GestureDetector(
                onTap: () => _handleTap(context, item.route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? (isDark
                              ? const Color(0xFF143440)
                              : const Color(0xFFE7F3F1))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: active
                            ? const Color(0xFF0E9B90)
                            : (isDark
                                  ? const Color(0xFF8FA4C2)
                                  : const Color(0xFF6A7D96)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
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
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BottomNavItem {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

class _RiskAlert extends StatelessWidget {
  const _RiskAlert({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE68A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFB45309),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Checking in on you',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB45309),
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "We've noticed some heavy moods lately. Remember that professional support is just a click away.",
              style: TextStyle(
                color: Color(0xFF92400E),
                height: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFB45309),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB45309).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.headset_mic_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Talk to someone now',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFECDD3), width: 1.2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFBE123C),
              size: 20,
            ),
            SizedBox(width: 10),
            Text(
              'Immediate Crisis Support',
              style: TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
