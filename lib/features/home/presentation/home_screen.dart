// features/home/presentation/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
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

  bool _canAccessLive(UserProfile profile) {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    return hasInstitution &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.counselor);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final loadedProfile = profileAsync.valueOrNull;
    final canOpenNotifications =
        loadedProfile != null && (loadedProfile.institutionId ?? '').isNotEmpty;
    final hasInstitution = (loadedProfile?.institutionId ?? '').isNotEmpty;
    final canAccessLive =
        loadedProfile != null && _canAccessLive(loadedProfile);

    return Scaffold(
      backgroundColor: const Color(0xFF070E19),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF090F1B),
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Color(0x1A94A3B8), width: 1),
        ),
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF001018),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'MindNest',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFFF4F7FF),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050B16), Color(0xFF061121), Color(0xFF07152A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -120,
              top: -20,
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x440FD1C8), Color(0x000FD1C8)],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -120,
              top: 180,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x332F6BFF), Color(0x002F6BFF)],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: profileAsync.when(
                data: (profile) {
                  if (profile == null) {
                    return const Center(
                      child: Text(
                        'Profile not found.',
                        style: TextStyle(color: Color(0xFFC9D5EA)),
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
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _WelcomeHero(
                              firstName: firstName,
                              roleLabel: profile.role.label,
                              institutionName: institutionLabel,
                              hasInstitution: hasInstitution,
                            ),
                            const SizedBox(height: 24),
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
                    color: Color(0xFF2CD4C0),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (error, _) => Center(
                  child: Text(
                    'Error: $error',
                    style: const TextStyle(color: Color(0xFFF87171)),
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1626),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x2A8AA2C8)),
          ),
          child: Icon(icon, color: const Color(0xFF9FB0CD), size: 22),
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
          colors: [Color(0xFF0B2A2B), Color(0xFF12253C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x3324D5C8), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0FD1C8).withValues(alpha: 0.10),
            blurRadius: 32,
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
              color: Colors.white.withValues(alpha: 0.62),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            firstName,
            style: const TextStyle(
              fontSize: 50,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2CD4C0),
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _Pill(
                label: roleLabel,
                bg: const Color(0xFF11363A),
                textColor: const Color(0xFF39E7CB),
                icon: Icons.school_outlined,
              ),
              const SizedBox(width: 8),
              _Pill(
                label: institutionName,
                bg: const Color(0xFF2B2242),
                textColor: const Color(0xFFA775FF),
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

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final items = <_BottomNavItem>[
      const _BottomNavItem(
        label: 'Home',
        icon: Icons.home_outlined,
        route: AppRoute.home,
        enabled: true,
      ),
      _BottomNavItem(
        label: 'Counselors',
        icon: Icons.groups_outlined,
        route: AppRoute.counselorDirectory,
        enabled: hasInstitution,
      ),
      _BottomNavItem(
        label: 'Sessions',
        icon: Icons.calendar_month_outlined,
        route: AppRoute.studentAppointments,
        enabled: hasInstitution,
      ),
      _BottomNavItem(
        label: 'Care Plan',
        icon: Icons.favorite_border_rounded,
        route: AppRoute.carePlan,
        enabled: hasInstitution,
      ),
      _BottomNavItem(
        label: 'Live',
        icon: Icons.podcasts_outlined,
        route: AppRoute.liveHub,
        enabled: canAccessLive,
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1727),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x2D7A8CA6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66030A14),
              blurRadius: 24,
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
                onTap: item.enabled ? () => context.go(item.route) : null,
                child: AnimatedOpacity(
                  opacity: item.enabled ? 1 : 0.35,
                  duration: const Duration(milliseconds: 180),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF113A44)
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
                              ? const Color(0xFF2FE6D4)
                              : const Color(0xFF8EA1BE),
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
                                ? const Color(0xFF2FE6D4)
                                : const Color(0xFF8EA1BE),
                          ),
                        ),
                      ],
                    ),
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
    required this.enabled,
  });

  final String label;
  final IconData icon;
  final String route;
  final bool enabled;
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
          color: const Color(0xFF17131C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF6F2233), width: 1.2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF4D61),
              size: 20,
            ),
            SizedBox(width: 10),
            Text(
              'Immediate Crisis Support',
              style: TextStyle(
                color: Color(0xFFFF4D61),
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
