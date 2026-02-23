// features/home/presentation/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

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
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SafeArea(
            top: false,
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
                const SizedBox(height: 20),
                // Avatar + name row
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE6FFFA), Color(0xFFEFF6FF)],
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: _navy,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              profile.email,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sheetTile(
                  icon: Icons.shield_moon_rounded,
                  label: 'Privacy & Data',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(AppRoute.privacyControls);
                  },
                ),
                if (!hasInstitution)
                  _sheetTile(
                    icon: Icons.add_business_rounded,
                    label: 'Join Institution',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.go(AppRoute.joinInstitution);
                    },
                  ),
                if (profile.role == UserRole.institutionAdmin)
                  _sheetTile(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Admin Dashboard',
                    iconColor: _teal,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.go(AppRoute.institutionAdmin);
                    },
                  ),
                if (hasInstitution)
                  _sheetTile(
                    icon: Icons.exit_to_app_rounded,
                    label: 'Leave Institution',
                    iconColor: const Color(0xFFE11D48),
                    labelColor: const Color(0xFFE11D48),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmLeaveInstitution(context, ref);
                    },
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),
                _sheetTile(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    confirmAndLogout(context: context, ref: ref);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = _muted,
    Color labelColor = _slate,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: labelColor,
          fontSize: 15,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: _muted.withValues(alpha: 0.5),
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
                  '$region · $label',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final loadedProfile = profileAsync.valueOrNull;
    final canOpenNotifications =
        loadedProfile != null && (loadedProfile.institutionId ?? '').isNotEmpty;

    return MindNestShell(
      maxWidth: 760,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_teal, Color(0xFF0EA5E9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.spa_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'MindNest',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _navy,
                fontSize: 22,
                letterSpacing: -0.5,
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
          const SizedBox(width: 4),
          _AppBarIconBtn(
            icon: Icons.account_circle_rounded,
            enabled: loadedProfile != null,
            onTap: loadedProfile == null
                ? null
                : () => _openProfilePanel(context, ref, loadedProfile),
          ),
          const SizedBox(width: 10),
        ],
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found.'));
          }

          final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
          final canAccessLive =
              hasInstitution &&
              (profile.role == UserRole.student ||
                  profile.role == UserRole.staff ||
                  profile.role == UserRole.counselor);

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

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- WELCOME HERO ----
                _Reveal(
                  delay: const Duration(milliseconds: 0),
                  child: _WelcomeHero(
                    firstName: firstName,
                    roleLabel: profile.role.label,
                    institutionName: hasInstitution
                        ? (profile.institutionName ?? 'Active Member')
                        : 'Independent',
                    hasInstitution: hasInstitution,
                  ),
                ),

                const SizedBox(height: 28),

                // ---- RISK ALERT ----
                if (profile.role != UserRole.institutionAdmin)
                  FutureBuilder<bool>(
                    future: _hasElevatedRisk(
                      firestore: ref.read(firestoreProvider),
                      userId: profile.id,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return _Reveal(
                        delay: const Duration(milliseconds: 80),
                        child: _RiskAlert(
                          onTap: () => _openCrisisSupport(context),
                        ),
                      );
                    },
                  ),

                // ---- SECTION LABEL ----
                _Reveal(
                  delay: const Duration(milliseconds: 120),
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Text(
                          'Your Care Hub',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Divider(
                            color: Color(0xFFF1F5F9),
                            thickness: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- ACTION CARDS GRID ----
                _Reveal(
                  delay: const Duration(milliseconds: 180),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.92,
                    children: [
                      _ActionCard(
                        title: 'Counselors',
                        subtitle: 'Find your match',
                        icon: Icons.spa_rounded,
                        gradientColors: _cardGradients[0],
                        isDisabled: !hasInstitution,
                        onTap: hasInstitution
                            ? () => context.go(AppRoute.counselorDirectory)
                            : null,
                      ),
                      _ActionCard(
                        title: 'Sessions',
                        subtitle: 'Book & manage',
                        icon: Icons.calendar_today_rounded,
                        gradientColors: _cardGradients[1],
                        isDisabled: !hasInstitution,
                        onTap: hasInstitution
                            ? () => context.go(AppRoute.studentAppointments)
                            : null,
                      ),
                      _ActionCard(
                        title: 'Care Plan',
                        subtitle: 'Your journey',
                        icon: Icons.assignment_turned_in_rounded,
                        gradientColors: _cardGradients[2],
                        isDisabled: !hasInstitution,
                        onTap: hasInstitution
                            ? () => context.go(AppRoute.carePlan)
                            : null,
                      ),
                      _ActionCard(
                        title: 'Live Hub',
                        subtitle: 'Real-time support',
                        icon: Icons.podcasts_rounded,
                        gradientColors: _cardGradients[3],
                        isDisabled: !canAccessLive,
                        onTap: canAccessLive
                            ? () => context.go(AppRoute.liveHub)
                            : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ---- SOS BUTTON ----
                _Reveal(
                  delay: const Duration(milliseconds: 260),
                  child: _SosButton(onTap: () => _openCrisisSupport(context)),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_teal, Color(0xFF0EA5E9)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading your space…',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted sub-widgets (UI only)
// ---------------------------------------------------------------------------

class _AppBarIconBtn extends StatelessWidget {
  const _AppBarIconBtn({required this.icon, required this.enabled, this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _slate, size: 22),
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
  });
  final String firstName;
  final String roleLabel;
  final String institutionName;
  final bool hasInstitution;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Row(
            children: [
              const Text('🌿', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'How are you,',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            firstName,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          // Pills row
          Row(
            children: [
              _Pill(
                label: roleLabel,
                bg: Colors.white.withValues(alpha: 0.18),
                textColor: Colors.white,
                icon: Icons.badge_rounded,
              ),
              const SizedBox(width: 8),
              _Pill(
                label: institutionName,
                bg: Colors.white.withValues(alpha: 0.18),
                textColor: Colors.white,
                icon: hasInstitution
                    ? Icons.account_balance_rounded
                    : Icons.person_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFE11D48),
              size: 20,
            ),
            SizedBox(width: 10),
            Text(
              'Immediate Crisis Support',
              style: TextStyle(
                color: Color(0xFFE11D48),
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
