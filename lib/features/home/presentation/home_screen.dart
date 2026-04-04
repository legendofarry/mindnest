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
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_profile_open_signal.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/features/ai/models/assistant_models.dart';
import 'package:mindnest/features/ai/presentation/assistant_fab.dart';
import 'package:mindnest/features/ai/presentation/home_ai_assistant_section.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_session.dart';
import 'package:mindnest/features/home/presentation/widgets/recent_activity_card.dart';
import 'package:mindnest/features/home/presentation/widgets/wellness_check_in_card.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

// ---------------------------------------------------------------------------
// Constants & theme helpers
// ---------------------------------------------------------------------------
const _teal = Color(0xFF0D9488);
const _slate = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
bool get _isWindowsApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

final _homeProfileAutoOpenTokenProvider = StateProvider<String?>((_) => null);
final _joinCodeInlineExpandedProvider = StateProvider.autoDispose<bool>(
  (_) => false,
);
final _joinCodeSubmittingProvider = StateProvider.autoDispose<bool>(
  (_) => false,
);
final _joinCodeTextControllerProvider =
    Provider.autoDispose<TextEditingController>((ref) {
      final controller = TextEditingController();
      ref.onDispose(controller.dispose);
      return controller;
    });

final _dashboardMoodStreakProvider = StreamProvider.autoDispose
    .family<int, String>((ref, userId) {
      final normalized = userId.trim();
      if (normalized.isEmpty || kUseWindowsRestAuth) {
        return Stream.value(0);
      }
      return ref
          .watch(firestoreProvider)
          .collection('mood_entries')
          .where('userId', isEqualTo: normalized)
          .snapshots()
          .map((snapshot) {
            final dateKeys = snapshot.docs
                .map((doc) => (doc.data()['dateKey'] as String?)?.trim() ?? '')
                .where((key) => key.isNotEmpty)
                .toSet();
            if (dateKeys.isEmpty) {
              return 0;
            }
            final now = DateTime.now().toLocal();
            var streak = 0;
            for (var day = 0; day < 365; day++) {
              final candidate = now.subtract(Duration(days: day));
              if (!dateKeys.contains(_dashboardDateKey(candidate))) {
                break;
              }
              streak += 1;
            }
            return streak;
          });
    });

final _dashboardAppointmentsProvider = StreamProvider.autoDispose
    .family<List<AppointmentRecord>, _DashboardScope>((ref, scope) {
      if (scope.institutionId.isEmpty || scope.userId.isEmpty) {
        return Stream.value(const <AppointmentRecord>[]);
      }
      return ref
          .watch(careRepositoryProvider)
          .watchStudentAppointments(
            institutionId: scope.institutionId,
            studentId: scope.userId,
          );
    });

String _dashboardDateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class _DashboardScope {
  const _DashboardScope({required this.institutionId, required this.userId});

  final String institutionId;
  final String userId;

  @override
  bool operator ==(Object other) {
    return other is _DashboardScope &&
        other.institutionId == institutionId &&
        other.userId == userId;
  }

  @override
  int get hashCode => Object.hash(institutionId, userId);
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.embeddedInDesktopShell = false});

  final bool embeddedInDesktopShell;

  static const String _sourceQueryKey = 'from';
  static const String _profileSourceValue = 'profile';
  static const String _openProfileQueryKey = 'openProfile';
  static const String _profileOpenTokenQueryKey = 'profileOpenTs';
  static const String _openJoinCodeQueryKey = AppRoute.openJoinCodeQuery;

  void _showTopErrorBanner(BuildContext context, String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (context) {
        final topPadding = MediaQuery.of(context).viewPadding.top;
        return Positioned(
          top: topPadding + 12,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
    });
  }

  String _formatInstitutionBadge(String? rawName) {
    const maxVisibleChars = 12;
    const stopWords = <String>{
      'of',
      'the',
      'and',
      'for',
      'at',
      'in',
      'on',
      'to',
      'a',
      'an',
      '&',
    };

    final normalized = (rawName ?? '').trim();
    if (normalized.isEmpty) {
      return 'INSTITUTION';
    }

    final compact = normalized.replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxVisibleChars) {
      return compact.toUpperCase();
    }

    final tokens = compact
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (tokens.length >= 2) {
      final filtered = tokens
          .where((part) => !stopWords.contains(part.toLowerCase()))
          .toList(growable: false);
      final source = filtered.length >= 2 ? filtered : tokens;
      final acronym = source
          .map((part) => part.substring(0, 1).toUpperCase())
          .join();
      if (acronym.length >= 2 && acronym.length <= maxVisibleChars) {
        return acronym;
      }
    }

    return compact.substring(0, maxVisibleChars).toUpperCase();
  }

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
      showModernBannerFromSnackBar(context, SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _openCrisisSupport(BuildContext context) {
    final homeContext = context;
    final isDesktopPanel = MediaQuery.sizeOf(context).width >= 900;

    void showComingSoonDialog() {
      showDialog<void>(
        context: homeContext,
        barrierDismissible: true,
        builder: (dialogContext) {
          Future.delayed(const Duration(seconds: 2), () {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          });
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Coming soon'),
            content: const Text('Stay tuned!'),
          );
        },
      );
    }

    Widget panelFor(BuildContext panelContext, {required bool desktopPanel}) {
      final radius = desktopPanel
          ? const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            )
          : const BorderRadius.vertical(top: Radius.circular(36));

      final panelContent = ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            border: desktopPanel
                ? const Border(
                    left: BorderSide(color: Color(0xFFDDE6F1), width: 1),
                  )
                : null,
            boxShadow: desktopPanel
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                      blurRadius: 30,
                      offset: const Offset(-8, 0),
                    ),
                  ]
                : null,
          ),
          child: SafeArea(
            top: desktopPanel,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, desktopPanel ? 20 : 14, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!desktopPanel) ...[
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
                  ],
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
                    'Kenya',
                    '999 / 0800 723 253',
                    'Emergency Services',
                    onTap: () => _openDialerForNumber(
                      context: homeContext,
                      number: '0800723253',
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: showComingSoonDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E9B90),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0E9B90,
                            ).withValues(alpha: 0.30),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.support_agent_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Talk to a counselor',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.of(panelContext).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF0EA5E9)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0D9488,
                            ).withValues(alpha: 0.35),
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
            ),
          ),
        ),
      );

      if (!desktopPanel) {
        return panelContent;
      }
      final viewportWidth = MediaQuery.sizeOf(panelContext).width;
      final panelWidth = viewportWidth >= 1400
          ? 430.0
          : viewportWidth >= 1100
          ? 400.0
          : 360.0;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: Material(color: Colors.transparent, child: panelContent),
        ),
      );
    }

    if (isDesktopPanel) {
      showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Crisis Support',
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (dialogContext, animation, secondaryAnimation) =>
            panelFor(dialogContext, desktopPanel: true),
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.10, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => panelFor(sheetContext, desktopPanel: false),
    );
  }

  Future<void> _openDialerForNumber({
    required BuildContext context,
    required String number,
  }) async {
    final telUri = Uri(scheme: 'tel', path: number);
    final didLaunch = await launchUrl(telUri);
    if (!didLaunch && context.mounted) {
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Could not open the phone dialer.')),
      );
    }
  }

  Future<void> _showInstitutionJoinGuide(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF0E9B90)),
              SizedBox(width: 8),
              Text('Institution Access'),
            ],
          ),
          content: const Text(
            'If your school/organization uses MindNest, ask your institution admin or counselor for the join code.\n\n'
            'If you already have the join code, tap "Enter Join Code" on this screen to connect your account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
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
    final isDesktopModal = MediaQuery.sizeOf(context).width >= 900;

    Widget panelFor(BuildContext sheetContext, {required bool desktopModal}) {
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

          final radius = desktopModal
              ? const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                )
              : const BorderRadius.vertical(top: Radius.circular(36));

          final panelContent = ClipRRect(
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: radius,
                border: desktopModal
                    ? Border(
                        left: BorderSide(
                          color: isDark
                              ? const Color(0xFF2A3A52)
                              : const Color(0xFFDDE6F1),
                          width: 1,
                        ),
                      )
                    : null,
                boxShadow: desktopModal
                    ? [
                        BoxShadow(
                          color:
                              (isDark ? Colors.black : const Color(0xFF0F172A))
                                  .withValues(alpha: isDark ? 0.34 : 0.12),
                          blurRadius: 30,
                          offset: const Offset(-8, 0),
                        ),
                      ]
                    : null,
              ),
              child: SafeArea(
                top: desktopModal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!desktopModal) ...[
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
                    ] else
                      const SizedBox(height: 20),
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
                                          themeModeControllerProvider.notifier,
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
                                      _withProfileSource(
                                        AppRoute.privacyControls,
                                      ),
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
                                      parentContext.go(
                                        _withProfileSource(AppRoute.carePlan),
                                      );
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
                                        _withProfileSource(
                                          AppRoute.homeWithJoinCodeIntent(),
                                        ),
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
                                        _withProfileSource(
                                          AppRoute.institutionAdmin,
                                        ),
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

          if (!desktopModal) {
            return FractionallySizedBox(
              heightFactor: 0.95,
              child: panelContent,
            );
          }

          final viewportWidth = MediaQuery.sizeOf(sheetContext).width;
          final panelWidth = viewportWidth >= 1400
              ? 430.0
              : viewportWidth >= 1100
              ? 400.0
              : 360.0;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: Material(color: Colors.transparent, child: panelContent),
            ),
          );
        },
      );
    }

    if (isDesktopModal) {
      showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Profile',
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (dialogContext, primaryAnimation, secondaryAnimation) =>
            panelFor(dialogContext, desktopModal: true),
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.10, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => panelFor(sheetContext, desktopModal: false),
    );
  }

  String _withProfileSource(String route) {
    final uri = Uri.parse(route);
    final updatedQuery = <String, String>{...uri.queryParameters};
    updatedQuery[_sourceQueryKey] = _profileSourceValue;
    return uri.replace(queryParameters: updatedQuery).toString();
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

  Widget _crisisContactTile(
    String region,
    String number,
    String label, {
    VoidCallback? onTap,
  }) {
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
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_forwarded_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Call',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
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
    required WidgetRef ref,
    required UserProfile profile,
    required AssistantAction action,
  }) async {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    final canUseLive = _canAccessLive(profile);

    void showMessage(String text) {
      showModernBannerFromSnackBar(context, SnackBar(content: Text(text)));
    }

    String withQuery(String path, Map<String, String> params) {
      if (params.isEmpty) {
        return path;
      }
      return Uri(path: path, queryParameters: params).toString();
    }

    switch (action.type) {
      case AssistantActionType.openLiveHub:
        if (_isWindowsApp) {
          showMessage('Live is on the web for now.');
          return;
        }
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
        if (_isWindowsApp) {
          showMessage('Live is on the web for now.');
          return;
        }
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
        context.go(withQuery(AppRoute.counselorDirectory, action.params));
        return;
      case AssistantActionType.openCounselorProfile:
        final counselorId = action.params['counselorId']?.trim() ?? '';
        if (counselorId.isEmpty) {
          context.go(AppRoute.counselorDirectory);
          return;
        }
        context.go(
          Uri(
            path: AppRoute.counselorProfile,
            queryParameters: <String, String>{'counselorId': counselorId},
          ).toString(),
        );
        return;
      case AssistantActionType.openSessions:
        if (!hasInstitution) {
          showMessage('Join an organization to manage sessions.');
          return;
        }
        context.go(withQuery(AppRoute.studentAppointments, action.params));
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
        context.go(AppRoute.homeWithJoinCodeIntent());
        return;
      case AssistantActionType.openPrivacy:
        context.go(AppRoute.privacyControls);
        return;
      case AssistantActionType.setThemeLight:
        await ref
            .read(themeModeControllerProvider.notifier)
            .setMode(ThemeMode.light);
        showMessage('Switched to light mode.');
        return;
      case AssistantActionType.setThemeDark:
        await ref
            .read(themeModeControllerProvider.notifier)
            .setMode(ThemeMode.dark);
        showMessage('Switched to dark mode.');
        return;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = viewportWidth >= 900;
    final useDesktopShell = embeddedInDesktopShell && isDesktop;
    final uri = GoRouterState.of(context).uri;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final loadedProfile = profileAsync.valueOrNull;
    final canOpenNotifications =
        loadedProfile != null && (loadedProfile.institutionId ?? '').isNotEmpty;
    final notificationUserId = loadedProfile?.id ?? '';
    final unreadCount = canOpenNotifications
        ? (ref
                  .watch(unreadNotificationCountProvider(notificationUserId))
                  .valueOrNull ??
              0)
        : 0;
    final hasInstitution = (loadedProfile?.institutionId ?? '').isNotEmpty;
    final canAccessLive =
        loadedProfile != null &&
        _canAccessLive(loadedProfile) &&
        !_isWindowsApp;

    final shouldAutoOpenProfile =
        uri.queryParameters[_openProfileQueryKey] == '1';
    final directProfileOpenRequest = useDesktopShell
        ? ref.watch(desktopProfileOpenRequestProvider)
        : null;
    final tokenFromQuery = uri.queryParameters[_profileOpenTokenQueryKey];
    final resolvedProfileOpenToken = directProfileOpenRequest != null
        ? 'desktop:$directProfileOpenRequest'
        : shouldAutoOpenProfile
        ? ((tokenFromQuery == null || tokenFromQuery.isEmpty)
              ? uri.toString()
              : tokenFromQuery)
        : null;
    if (resolvedProfileOpenToken != null && loadedProfile != null) {
      final lastToken = ref.read(_homeProfileAutoOpenTokenProvider);
      if (lastToken != resolvedProfileOpenToken) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) {
            return;
          }
          final currentToken = ref.read(_homeProfileAutoOpenTokenProvider);
          if (currentToken == resolvedProfileOpenToken) {
            return;
          }
          ref.read(_homeProfileAutoOpenTokenProvider.notifier).state =
              resolvedProfileOpenToken;
          _openProfilePanel(context, ref, loadedProfile);
        });
      }
    }

    final joinCodeFromQuery = uri.queryParameters['joinCode']
        ?.trim()
        .toUpperCase();
    final shouldAutoOpenJoin =
        uri.queryParameters[_openJoinCodeQueryKey] == '1';
    if (kDebugMode && shouldAutoOpenJoin) {
      debugPrint(
        '[JoinCodeIntent] openJoinCode=1 uri=$uri joinCodeParam='
        '${joinCodeFromQuery ?? '<none>'}',
      );
    }
    if (shouldAutoOpenJoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final notifier = ref.read(_joinCodeInlineExpandedProvider.notifier);
        if (!ref.read(_joinCodeInlineExpandedProvider)) {
          notifier.state = true;
        }
      });
    }

    if (useDesktopShell) {
      return profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text(
                'Profile not found.',
                style: TextStyle(color: Color(0xFF4A607C)),
              ),
            );
          }

          final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
          final canAccessLive = _canAccessLive(profile) && !_isWindowsApp;

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
          final showJoinInstitutionNudge =
              profile.role == UserRole.individual && !hasInstitution;

          return LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth.clamp(0.0, 1280.0);
              final showDesktopRightRailCards = contentWidth >= 1040;
              return Stack(
                children: [
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 86),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DesktopWorkspaceTopStrip(
                              firstName: firstName,
                              unreadCount: unreadCount,
                              canOpenNotifications: canOpenNotifications,
                              onNotifications: canOpenNotifications
                                  ? () => context.go(
                                      AppRoute.notificationsRoute(
                                        returnTo: AppRoute.home,
                                      ),
                                    )
                                  : null,
                              onProfile: () =>
                                  _openProfilePanel(context, ref, profile),
                            ),
                            const SizedBox(height: 18),
                            _DesktopOverviewMetricsRow(
                              profile: profile,
                              hasInstitution: hasInstitution,
                              unreadCount: unreadCount,
                            ),
                            if (showJoinInstitutionNudge) ...[
                              const SizedBox(height: 18),
                              _InstitutionJoinNudgeCard(
                                onHowItWorks: () =>
                                    _showInstitutionJoinGuide(context),
                                prefilledCode: joinCodeFromQuery,
                              ),
                            ],
                            if (unreadCount > 0) ...[
                              const SizedBox(height: 14),
                              _NotificationsSummaryBar(
                                unreadCount: unreadCount,
                                onTap: () => context.go(
                                  AppRoute.notificationsRoute(
                                    returnTo: AppRoute.home,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (showDesktopRightRailCards)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _HeroCardFrame(
                                      isDark: isDark,
                                      title: 'Open Slots',
                                      subtitle: 'Next counselor availability',
                                      icon: Icons.event_available_rounded,
                                      child: _OpenSlotsPreviewCard(
                                        profile: profile,
                                        onTapCounselor: (counselorId) {
                                          context.go(
                                            '${AppRoute.counselorProfile}?counselorId=$counselorId',
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 340,
                                    child: _DesktopNextSessionCard(
                                      profile: profile,
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              _HeroCardFrame(
                                isDark: isDark,
                                title: 'Open Slots',
                                subtitle: 'Next counselor availability',
                                icon: Icons.event_available_rounded,
                                child: _OpenSlotsPreviewCard(
                                  profile: profile,
                                  onTapCounselor: (counselorId) {
                                    context.go(
                                      '${AppRoute.counselorProfile}?counselorId=$counselorId',
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              _DesktopNextSessionCard(
                                profile: profile,
                                isDark: isDark,
                              ),
                            ],
                            const SizedBox(height: 14),
                            if (showDesktopRightRailCards)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        WellnessCheckInCard(profile: profile),
                                        const SizedBox(height: 14),
                                        _DesktopCrisisSupportCard(
                                          isDark: isDark,
                                          onTap: () =>
                                              _openCrisisSupport(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 3,
                                    child: RecentActivityCard(
                                      profile: profile,
                                      sideBySide: true,
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              WellnessCheckInCard(profile: profile),
                              const SizedBox(height: 14),
                              RecentActivityCard(
                                profile: profile,
                                sideBySide: true,
                              ),
                              const SizedBox(height: 14),
                              _DesktopCrisisSupportCard(
                                isDark: isDark,
                                onTap: () => _openCrisisSupport(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: AssistantFab(
                      heroTag: 'assistant-fab-home-desktop',
                      onPressed: () => showMindNestAssistantSheet(
                        context: context,
                        profile: profile,
                        onActionRequested: (action) => _runAssistantAction(
                          context: context,
                          ref: ref,
                          profile: profile,
                          action: action,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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
      );
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 68,
        titleSpacing: 16,
        title: isDesktop
            ? const SizedBox.shrink()
            : Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 99,
                    height: 99,
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                  ),
                ],
              ),
        centerTitle: false,
        actions: [
          _AppBarIconBtn(
            icon: Icons.notifications_none_rounded,
            enabled: canOpenNotifications,
            badgeCount: unreadCount,
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
                  final canAccessLive =
                      _canAccessLive(profile) && !_isWindowsApp;

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
                      ? _formatInstitutionBadge(profile.institutionName)
                      : 'INDIVIDUAL';
                  final showJoinInstitutionNudge =
                      profile.role == UserRole.individual && !hasInstitution;
                  void goAppointments() {
                    if (!hasInstitution) {
                      _showTopErrorBanner(
                        context,
                        'Join an institution to book sessions.',
                      );
                      return;
                    }
                    context.go(AppRoute.studentAppointments);
                  }

                  void goCounselors() {
                    if (!hasInstitution) {
                      _showTopErrorBanner(
                        context,
                        'Join an institution to view counselors.',
                      );
                      return;
                    }
                    context.go(AppRoute.counselorDirectory);
                  }

                  void goLive() {
                    if (_isWindowsApp) {
                      _showTopErrorBanner(
                        context,
                        'Live is on the web for now.',
                      );
                      return;
                    }
                    if (!canAccessLive) {
                      _showTopErrorBanner(
                        context,
                        'Live is available after joining an institution.',
                      );
                      return;
                    }
                    context.go(AppRoute.liveHub);
                  }

                  final mainContent = isDesktop
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 260,
                                    child: _HeroCarousel(
                                      profile: profile,
                                      firstName: firstName,
                                      roleLabel: profile.role.label,
                                      institutionName: institutionLabel,
                                      hasInstitution: hasInstitution,
                                      canAccessLive: canAccessLive,
                                      showLive: !_isWindowsApp,
                                      isDark: isDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 300,
                                  child: _DesktopNextSessionCard(
                                    profile: profile,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            if (showJoinInstitutionNudge) ...[
                              const SizedBox(height: 14),
                              _InstitutionJoinNudgeCard(
                                onHowItWorks: () =>
                                    _showInstitutionJoinGuide(context),
                                prefilledCode: joinCodeFromQuery,
                              ),
                            ],
                            if (unreadCount > 0) ...[
                              const SizedBox(height: 14),
                              _NotificationsSummaryBar(
                                unreadCount: unreadCount,
                                onTap: () => context.go(AppRoute.notifications),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _QuickActionsCard(
                                    isDark: isDark,
                                    showLive: !_isWindowsApp,
                                    onBookSession: goAppointments,
                                    onOpenCounselors: goCounselors,
                                    onOpenLive: goLive,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 1,
                                  child: _ProgressMiniCard(
                                    isDark: isDark,
                                    firstName: firstName,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _ResourceSpotlightCard(
                              isDark: isDark,
                              onOpen: () => context.go(AppRoute.notifications),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      WellnessCheckInCard(profile: profile),
                                      const SizedBox(height: 14),
                                      _DesktopCrisisSupportCard(
                                        isDark: isDark,
                                        onTap: () =>
                                            _openCrisisSupport(context),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 4,
                                  child: RecentActivityCard(
                                    profile: profile,
                                    sideBySide: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _SosButton(
                              onTap: () => _openCrisisSupport(context),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HeroCarousel(
                              profile: profile,
                              firstName: firstName,
                              roleLabel: profile.role.label,
                              institutionName: institutionLabel,
                              hasInstitution: hasInstitution,
                              canAccessLive: canAccessLive,
                              showLive: !_isWindowsApp,
                              isDark: isDark,
                            ),
                            if (showJoinInstitutionNudge) ...[
                              const SizedBox(height: 14),
                              _InstitutionJoinNudgeCard(
                                onHowItWorks: () =>
                                    _showInstitutionJoinGuide(context),
                                prefilledCode: joinCodeFromQuery,
                              ),
                            ],
                            if (unreadCount > 0) ...[
                              const SizedBox(height: 14),
                              _NotificationsSummaryBar(
                                unreadCount: unreadCount,
                                onTap: () => context.go(AppRoute.notifications),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _QuickActionsCard(
                              isDark: isDark,
                              showLive: !_isWindowsApp,
                              onBookSession: goAppointments,
                              onOpenCounselors: goCounselors,
                              onOpenLive: goLive,
                            ),
                            const SizedBox(height: 12),
                            _ProgressMiniCard(
                              isDark: isDark,
                              firstName: firstName,
                            ),
                            const SizedBox(height: 14),
                            _ResourceSpotlightCard(
                              isDark: isDark,
                              onOpen: () => context.go(AppRoute.notifications),
                            ),
                            const SizedBox(height: 18),
                            WellnessCheckInCard(profile: profile),
                            const SizedBox(height: 14),
                            RecentActivityCard(profile: profile),
                            const SizedBox(height: 14),
                            _DesktopCrisisSupportCard(
                              isDark: isDark,
                              onTap: () => _openCrisisSupport(context),
                            ),
                            const SizedBox(height: 8),
                          ],
                        );

                  if (isDesktop) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1260),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 296,
                                child: DesktopSectionNav(
                                  hasInstitution: hasInstitution,
                                  canAccessLive: canAccessLive,
                                ),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 860,
                                    ),
                                    child: mainContent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                        child: mainContent,
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
      bottomNavigationBar: isDesktop
          ? null
          : PrimaryMobileBottomNav(
              hasInstitution: hasInstitution,
              canAccessLive: canAccessLive,
            ),
      floatingActionButton: loadedProfile == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: isDesktop ? 0 : 0),
              child: AssistantFab(
                heroTag: 'assistant-fab-home',
                onPressed: () => showMindNestAssistantSheet(
                  context: context,
                  profile: loadedProfile,
                  onActionRequested: (action) => _runAssistantAction(
                    context: context,
                    ref: ref,
                    profile: loadedProfile,
                    action: action,
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
    required this.showLive,
    required this.isDark,
  });

  final UserProfile profile;
  final String firstName;
  final String roleLabel;
  final String institutionName;
  final bool hasInstitution;
  final bool canAccessLive;
  final bool showLive;
  final bool isDark;

  @override
  ConsumerState<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<_HeroCarousel> {
  static const Duration _autoSlideDelay = Duration(seconds: 4);
  late final PageController _pageController = PageController(
    initialPage: 1000 * (widget.showLive ? 4 : 3),
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
    final cardCount = widget.showLive ? 4 : 3;
    return SizedBox(
      height: 230,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _pauseTemporarily(),
        onHorizontalDragCancel: _resumeLater,
        onHorizontalDragEnd: (_) => _resumeLater(),
        child: PageView.builder(
          controller: _pageController,
          itemBuilder: (context, index) {
            final cardIndex = index % cardCount;
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

class _DesktopWorkspaceTopStrip extends StatelessWidget {
  const _DesktopWorkspaceTopStrip({
    required this.firstName,
    required this.unreadCount,
    required this.canOpenNotifications,
    required this.onNotifications,
    required this.onProfile,
  });

  final String firstName;
  final int unreadCount;
  final bool canOpenNotifications;
  final VoidCallback? onNotifications;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Good morning, $firstName',
                    style: const TextStyle(
                      color: Color(0xFF1E2432),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Here's your wellness overview for today.",
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppBarIconBtn(
              icon: Icons.notifications_none_rounded,
              enabled: canOpenNotifications,
              badgeCount: unreadCount,
              onTap: onNotifications,
            ),
            const SizedBox(width: 10),
            _AppBarIconBtn(
              icon: Icons.person_outline_rounded,
              enabled: true,
              onTap: onProfile,
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopOverviewMetricsRow extends ConsumerWidget {
  const _DesktopOverviewMetricsRow({
    required this.profile,
    required this.hasInstitution,
    required this.unreadCount,
  });

  final UserProfile profile;
  final bool hasInstitution;
  final int unreadCount;

  String _formatHours(double totalHours) {
    if (totalHours <= 0) {
      return '0h';
    }
    if (totalHours >= 10 || totalHours == totalHours.roundToDouble()) {
      return '${totalHours.toStringAsFixed(totalHours == totalHours.roundToDouble() ? 0 : 1)}h';
    }
    return '${totalHours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutionId = (profile.institutionId ?? '').trim();
    final scope = _DashboardScope(
      institutionId: institutionId,
      userId: profile.id.trim(),
    );
    final streakDays =
        ref.watch(_dashboardMoodStreakProvider(profile.id)).valueOrNull ?? 0;
    final appointments = hasInstitution
        ? (ref.watch(_dashboardAppointmentsProvider(scope)).valueOrNull ??
              const <AppointmentRecord>[])
        : const <AppointmentRecord>[];

    final completedAppointments = appointments
        .where((entry) => entry.status == AppointmentStatus.completed)
        .toList(growable: false);
    final upcomingAppointments = appointments
        .where(
          (entry) =>
              (entry.status == AppointmentStatus.pending ||
                  entry.status == AppointmentStatus.confirmed) &&
              entry.startAt.isAfter(DateTime.now().toUtc()),
        )
        .length;
    final totalHours = completedAppointments.fold<double>(
      0,
      (runningTotal, entry) =>
          runningTotal + entry.endAt.difference(entry.startAt).inMinutes / 60,
    );

    final cards = <_DesktopMetricData>[
      _DesktopMetricData(
        icon: Icons.local_fire_department_outlined,
        iconColor: const Color(0xFFF97316),
        value: '$streakDays',
        label: 'STREAK',
        sublabel: streakDays == 1 ? 'day' : 'days',
      ),
      _DesktopMetricData(
        icon: Icons.event_available_rounded,
        iconColor: const Color(0xFF10B981),
        value: '$upcomingAppointments',
        label: 'UPCOMING',
        sublabel: 'booked',
      ),
      _DesktopMetricData(
        icon: Icons.schedule_rounded,
        iconColor: const Color(0xFF0D9488),
        value: _formatHours(totalHours),
        label: 'HOURS',
        sublabel: 'completed',
      ),
      _DesktopMetricData(
        icon: Icons.notifications_active_outlined,
        iconColor: const Color(0xFFF97316),
        value: '$unreadCount',
        label: 'UNREAD',
        sublabel: 'updates',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth < 980;
        if (twoColumn) {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards
                .map(
                  (entry) => SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: _DesktopMetricCard(data: entry),
                  ),
                )
                .toList(growable: false),
          );
        }
        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: _DesktopMetricCard(data: cards[index])),
              if (index != cards.length - 1) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _DesktopMetricData {
  const _DesktopMetricData({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.sublabel,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String sublabel;
}

class _DesktopMetricCard extends StatelessWidget {
  const _DesktopMetricCard({required this.data});

  final _DesktopMetricData data;

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFF232733);
    final startColor = Color.alphaBlend(
      data.iconColor.withValues(alpha: 0.10),
      const Color(0xFF2A2F3D),
    );
    final endColor = Color.alphaBlend(
      data.iconColor.withValues(alpha: 0.05),
      const Color(0xFF1D212C),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [startColor, baseColor, endColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -32,
              right: -18,
              child: _AmbientOrb(
                size: 114,
                color: data.iconColor.withValues(alpha: 0.14),
              ),
            ),
            Positioned(
              bottom: -42,
              left: -22,
              child: _AmbientOrb(
                size: 96,
                color: data.iconColor.withValues(alpha: 0.09),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      data.iconColor.withValues(alpha: 0.18),
                      const Color(0xFF2C3140),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: data.iconColor.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(data.icon, color: data.iconColor, size: 22),
                ),
                const SizedBox(height: 14),
                Text(
                  data.value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.sublabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

class _DesktopNextSessionCard extends ConsumerWidget {
  const _DesktopNextSessionCard({required this.profile, required this.isDark});

  final UserProfile profile;
  final bool isDark;

  String _formatStart(DateTime value) {
    const months = <int, String>{
      1: 'Jan',
      2: 'Feb',
      3: 'Mar',
      4: 'Apr',
      5: 'May',
      6: 'Jun',
      7: 'Jul',
      8: 'Aug',
      9: 'Sep',
      10: 'Oct',
      11: 'Nov',
      12: 'Dec',
    };
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month]} ${local.day}, $hour:$minute $period';
  }

  String _daysLabel(DateTime value) {
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day).toLocal();
    final days = target.difference(today).inDays;
    if (days <= 0) {
      return 'TODAY';
    }
    if (days == 1) {
      return 'IN 1 DAY';
    }
    return 'IN $days DAYS';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutionId = (profile.institutionId ?? '').trim();
    final role = profile.role;

    const brandTeal = Color(0xFF0E9B90);
    const brandIndigo = Color(0xFF5146FF);
    final borderColor = isDark
        ? const Color(0xFF2A3A52)
        : const Color(0xFFDDE6F1);
    final titleColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0F172A);
    final mutedColor = isDark
        ? const Color(0xFF9FB2CC)
        : const Color(0xFF64748B);

    if (institutionId.isEmpty) {
      return _DesktopSideCardShell(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next Session',
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w800,
                fontSize: 28 / 2,
              ),
            ),
            const Spacer(),
            Text(
              'Join an institution to see upcoming sessions.',
              style: TextStyle(
                color: mutedColor,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final careRepo = ref.read(careRepositoryProvider);
    final stream = role == UserRole.counselor
        ? careRepo.watchCounselorAppointments(
            institutionId: institutionId,
            counselorId: profile.id,
          )
        : careRepo.watchStudentAppointments(
            institutionId: institutionId,
            studentId: profile.id,
          );

    return _DesktopSideCardShell(
      isDark: isDark,
      child: StreamBuilder<List<AppointmentRecord>>(
        stream: stream,
        builder: (context, snapshot) {
          final allSessions = snapshot.data ?? const <AppointmentRecord>[];
          final now = DateTime.now().toUtc();
          final upcoming =
              allSessions
                  .where(
                    (entry) =>
                        (entry.status == AppointmentStatus.pending ||
                            entry.status == AppointmentStatus.confirmed) &&
                        entry.startAt.isAfter(now),
                  )
                  .toList(growable: false)
                ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final nextSession = upcoming.isEmpty ? null : upcoming.first;
          final otherPartyName = nextSession == null
              ? '--'
              : role == UserRole.counselor
              ? ((nextSession.studentName ?? '').trim().isEmpty
                    ? 'Student'
                    : nextSession.studentName!.trim())
              : ((nextSession.counselorName ?? '').trim().isEmpty
                    ? 'Counselor'
                    : nextSession.counselorName!.trim());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Next Session',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 28 / 2,
                    ),
                  ),
                  const Spacer(),
                  if (nextSession != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: brandIndigo.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _daysLabel(nextSession.startAt.toLocal()),
                        style: TextStyle(
                          color: brandIndigo,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 0.45,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1B2A42)
                        : const Color(0xFFF6FAFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: nextSession == null
                      ? Center(
                          child: Text(
                            snapshot.connectionState == ConnectionState.waiting
                                ? 'Checking your sessions...'
                                : 'No upcoming sessions.',
                            style: TextStyle(
                              color: mutedColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF253754)
                                    : brandTeal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.person_outline_rounded,
                                color: isDark ? brandIndigo : brandTeal,
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    otherPartyName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: titleColor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatStart(nextSession.startAt),
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: nextSession == null
                      ? null
                      : () => context.go(
                          '${AppRoute.sessionDetails}?appointmentId=${nextSession.id}',
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandIndigo,
                    disabledBackgroundColor: const Color(0xFFD5DEEA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    nextSession == null ? 'No Session' : 'View Session',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
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

class _DesktopSideCardShell extends StatelessWidget {
  const _DesktopSideCardShell({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF2A3A52)
        : const Color(0xFFDDE6F1);
    const primaryAccent = Color(0xFFF97316);
    const secondaryAccent = Color(0xFF5146FF);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 230,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F31) : Colors.white,
          gradient: isDark
              ? null
              : LinearGradient(
                  colors: [
                    Color.alphaBlend(
                      primaryAccent.withValues(alpha: 0.08),
                      Colors.white,
                    ),
                    Colors.white,
                    Color.alphaBlend(
                      secondaryAccent.withValues(alpha: 0.06),
                      Colors.white,
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0x120F172A))
                  .withValues(alpha: isDark ? 0.22 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (!isDark)
              Positioned(
                top: -30,
                right: -18,
                child: _AmbientOrb(
                  size: 118,
                  color: primaryAccent.withValues(alpha: 0.13),
                ),
              ),
            if (!isDark)
              Positioned(
                bottom: -36,
                left: -24,
                child: _AmbientOrb(
                  size: 96,
                  color: secondaryAccent.withValues(alpha: 0.09),
                ),
              ),
            child,
          ],
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
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
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
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(height: 150, width: double.infinity, child: child),
          ),
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
    WidgetRef ref,
    List<String> counselorIds,
  ) async {
    if (counselorIds.isEmpty) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    for (var i = 0; i < counselorIds.length; i += 10) {
      final end = (i + 10 < counselorIds.length) ? i + 10 : counselorIds.length;
      final chunk = counselorIds.sublist(i, end);
      if (kUseWindowsRestAuth) {
        final profiles = await ref
            .read(windowsFirestoreRestClientProvider)
            .queryCollection(
              collectionId: 'counselor_profiles',
              filters: <WindowsFirestoreFieldFilter>[
                WindowsFirestoreFieldFilter.inList('__name__', chunk),
              ],
            );
        for (final doc in profiles) {
          final displayName = (doc.data['displayName'] as String?)?.trim();
          if (displayName != null && displayName.isNotEmpty) {
            result[doc.id] = displayName;
          }
        }
      } else {
        final profiles = await ref
            .read(firestoreProvider)
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
          future: _fetchCounselorNames(ref, counselorIds),
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
    this.onTapHowTo,
    this.onTapLocked,
  });

  final UserProfile profile;
  final bool canAccessLive;
  final ValueChanged<String> onTapLive;
  final VoidCallback? onTapHowTo;
  final VoidCallback? onTapLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutionId = (profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return _LiveEmptyState(
        message: 'Join an institution to see live sessions.',
        onTap: onTapHowTo,
      );
    }
    if (!canAccessLive) {
      return _LiveEmptyState(
        message: 'Live is available to student, staff, and counselor roles.',
        onTap: onTapLocked,
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
          return _LiveEmptyState(
            message: 'No live sessions right now.',
            onTap: onTapHowTo,
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
  const _AppBarIconBtn({
    required this.icon,
    required this.enabled,
    this.onTap,
    this.badgeCount = 0,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final int badgeCount;

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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  icon,
                  color: isDark
                      ? const Color(0xFFB7C6DA)
                      : const Color(0xFF4A607C),
                  size: 22,
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 6,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isDark ? const Color(0xFF131F32) : Colors.white,
                        width: 1.1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstitutionJoinNudgeCard extends ConsumerStatefulWidget {
  const _InstitutionJoinNudgeCard({
    required this.onHowItWorks,
    this.prefilledCode,
  });

  final VoidCallback onHowItWorks;
  final String? prefilledCode;

  @override
  ConsumerState<_InstitutionJoinNudgeCard> createState() =>
      _InstitutionJoinNudgeCardState();
}

class _InstitutionJoinNudgeCardState
    extends ConsumerState<_InstitutionJoinNudgeCard> {
  String? _inlineError;
  bool _maskJoinCode = true;
  String? _appliedPrefillCode;
  String? _selectedInviteId;

  Future<void> _submitJoinCode(
    BuildContext context, {
    required String? expectedJoinCode,
    required UserInvite? selectedInvite,
    required bool hasMultipleInvites,
  }) async {
    final code = ref.read(_joinCodeTextControllerProvider).text.trim();
    if (code.isEmpty) {
      setState(() => _inlineError = 'Join code is required.');
      return;
    }

    final normalizedInput = code.toUpperCase();

    if (hasMultipleInvites && selectedInvite == null) {
      setState(
        () => _inlineError = 'Choose which institution invite to accept.',
      );
      return;
    }

    if ((selectedInvite != null) &&
        (expectedJoinCode != null && expectedJoinCode.isNotEmpty) &&
        normalizedInput != expectedJoinCode.toUpperCase()) {
      setState(
        () => _inlineError =
            'This code belongs to another institution. Pick the matching invite or enter the correct code.',
      );
      return;
    }

    setState(() => _inlineError = null);
    ref.read(_joinCodeSubmittingProvider.notifier).state = true;
    try {
      await ref
          .read(institutionRepositoryProvider)
          .joinInstitutionByCode(code: code);
      if (!mounted) return;
      ref.read(_joinCodeInlineExpandedProvider.notifier).state = false;
      ref.read(_joinCodeTextControllerProvider).clear();
      final isVerified =
          ref.read(authRepositoryProvider).currentAuthUser?.emailVerified ??
          false;
      if (!mounted) return;
      context.go(isVerified ? AppRoute.home : AppRoute.verifyEmail);
    } catch (error) {
      if (!mounted) return;
      final homeWidget = context.findAncestorWidgetOfExactType<HomeScreen>();
      homeWidget?._showTopErrorBanner(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      ref.read(_joinCodeSubmittingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expanded = ref.watch(_joinCodeInlineExpandedProvider);
    final isSubmitting = ref.watch(_joinCodeSubmittingProvider);
    final controller = ref.watch(_joinCodeTextControllerProvider);
    final pendingInvitesAsync = ref.watch(pendingUserInvitesProvider);
    final pendingInvites = pendingInvitesAsync.value ?? const <UserInvite>[];
    final hasMultipleInvites = pendingInvites.length > 1;
    final effectiveInviteId =
        _selectedInviteId ??
        (pendingInvites.isNotEmpty ? pendingInvites.first.id : null);
    UserInvite? selectedInvite;
    if (pendingInvites.isNotEmpty) {
      selectedInvite = pendingInvites.firstWhere(
        (invite) => invite.id == effectiveInviteId,
        orElse: () => pendingInvites.first,
      );
    }
    final selectedInstitutionId = selectedInvite?.institutionId.trim() ?? '';
    final selectedInstitutionAsync = selectedInstitutionId.isNotEmpty
        ? ref.watch(institutionDocumentProvider(selectedInstitutionId))
        : const AsyncValue<Map<String, dynamic>?>.data(null);
    final joinCodeFromInstitution =
        (selectedInstitutionAsync.valueOrNull?['joinCode'] as String? ?? '')
            .trim()
            .toUpperCase();
    if (kDebugMode &&
        selectedInvite != null &&
        selectedInstitutionId.isNotEmpty &&
        joinCodeFromInstitution.isEmpty) {
      debugPrint(
        '[JoinCodeIntent] pending invite found for institution '
        '$selectedInstitutionId but joinCode is empty on document.',
      );
    }

    final normalizedPrefilled =
        (widget.prefilledCode ?? joinCodeFromInstitution).trim().toUpperCase();

    if (normalizedPrefilled.isNotEmpty &&
        _appliedPrefillCode != normalizedPrefilled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _appliedPrefillCode = normalizedPrefilled;
        controller.text = normalizedPrefilled;
        ref.read(_joinCodeInlineExpandedProvider.notifier).state = true;
        if (kDebugMode) {
          debugPrint(
            '[JoinCodeIntent] applied join code from '
            '${widget.prefilledCode?.isNotEmpty == true
                ? 'queryParam'
                : hasMultipleInvites
                ? 'selectedInvite'
                : 'pendingInvite'} '
            '(length ${normalizedPrefilled.length}).',
          );
        }
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1A2D45), Color(0xFF16354D)]
              : const [Color(0xFFEAF5FF), Color(0xFFEFFFFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD7E5F3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.apartment_rounded,
                color: Color(0xFF0E9B90),
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                'Belong to an Institution?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Once you receive an invite, this part will automatically open up. All you need to do is just connect!.',
            style: TextStyle(
              color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF516784),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (pendingInvites.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF102538)
                    : const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF204262)
                      : const Color(0xFFC7D8EE),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 18,
                    color: Color(0xFF0E7490),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Joining: ${selectedInvite?.institutionName ?? 'Institution'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (hasMultipleInvites)
                    TextButton(
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                          ),
                          builder: (sheetContext) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Choose invitation',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final invite in pendingInvites)
                                    ListTile(
                                      leading: const Icon(
                                        Icons.apartment_outlined,
                                        color: Color(0xFF0E7490),
                                      ),
                                      title: Text(invite.institutionName),
                                      subtitle: Text(
                                        'Role: ${invite.intendedRole.label}',
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedInviteId = invite.id;
                                          _inlineError = null;
                                        });
                                        Navigator.of(sheetContext).pop();
                                      },
                                    ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      child: const Text('Switch'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_inlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inlineError ?? '',
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  final notifier = ref.read(
                    _joinCodeInlineExpandedProvider.notifier,
                  );
                  notifier.state = !expanded;
                },
                icon: const Icon(Icons.key_rounded, size: 16),
                label: Text(expanded ? 'Hide Join Code' : 'Enter Join Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E9B90),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onHowItWorks,
                icon: const Icon(Icons.help_outline_rounded, size: 16),
                label: const Text('How it works'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0E7490),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F1C2C)
                            : const Color(0xFFF7FBFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF223449)
                              : const Color(0xFFC8D9EB),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: controller,
                            enabled: !isSubmitting,
                            textCapitalization: TextCapitalization.characters,
                            obscureText: _maskJoinCode,
                            obscuringCharacter: '•',
                            decoration: const InputDecoration(
                              labelText: 'Join code',
                              hintText: 'e.g. ABCD1234',
                            ),
                            onSubmitted: (_) {
                              if (!isSubmitting) {
                                _submitJoinCode(
                                  context,
                                  expectedJoinCode: joinCodeFromInstitution,
                                  selectedInvite: selectedInvite,
                                  hasMultipleInvites: hasMultipleInvites,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => _submitJoinCode(
                                        context,
                                        expectedJoinCode:
                                            joinCodeFromInstitution,
                                        selectedInvite: selectedInvite,
                                        hasMultipleInvites: hasMultipleInvites,
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E7490),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                child: Text(
                                  isSubmitting ? 'Joining...' : 'Connect',
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () {
                                        controller.clear();
                                        ref
                                                .read(
                                                  _joinCodeInlineExpandedProvider
                                                      .notifier,
                                                )
                                                .state =
                                            false;
                                      },
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
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

class _WellnessCheckInCard extends ConsumerStatefulWidget {
  const _WellnessCheckInCard({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_WellnessCheckInCard> createState() =>
      _WellnessCheckInCardState();
}

class _WellnessCheckInCardState extends ConsumerState<_WellnessCheckInCard> {
  bool _saving = false;
  static const Duration _windowsPollInterval = Duration(seconds: 15);

  static const List<_MoodChoice> _moods = <_MoodChoice>[
    _MoodChoice(
      key: 'great',
      emoji: 'ðŸ˜€',
      label: 'Great',
      color: Color(0xFF10B981),
    ),
    _MoodChoice(
      key: 'good',
      emoji: 'ðŸ™‚',
      label: 'Good',
      color: Color(0xFF22C55E),
    ),
    _MoodChoice(
      key: 'okay',
      emoji: 'ðŸ˜',
      label: 'Okay',
      color: Color(0xFFF59E0B),
    ),
    _MoodChoice(
      key: 'low',
      emoji: 'ðŸ˜”',
      label: 'Low',
      color: Color(0xFFF97316),
    ),
    _MoodChoice(
      key: 'stressed',
      emoji: 'ðŸ˜£',
      label: 'Stressed',
      color: Color(0xFFEF4444),
    ),
  ];

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  IconData _energyIcon(int level) {
    switch (level) {
      case 1:
        return Icons.battery_1_bar_rounded;
      case 2:
        return Icons.battery_2_bar_rounded;
      case 3:
        return Icons.battery_3_bar_rounded;
      case 4:
        return Icons.battery_4_bar_rounded;
      default:
        return Icons.battery_full_rounded;
    }
  }

  _MoodChoice _resolveMood(String? key) {
    return _moods.firstWhere(
      (entry) => entry.key == key,
      orElse: () => _moods[2],
    );
  }

  bool get _useWindowsPollingWorkaround =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  List<_WellnessEntry> _parseEntries(Iterable<Map<String, dynamic>> docs) {
    final entries = <_WellnessEntry>[];
    for (final data in docs) {
      final key = (data['dateKey'] as String?) ?? '';
      if (key.isEmpty) {
        continue;
      }
      final moodKey = (data['mood'] as String?) ?? 'okay';
      final energyRaw = data['energy'];
      final energy = energyRaw is int ? energyRaw.clamp(1, 5) : 3;
      entries.add(_WellnessEntry(dateKey: key, mood: moodKey, energy: energy));
    }
    return entries;
  }

  String _entriesSignature(List<_WellnessEntry> entries) => entries
      .map((entry) => '${entry.dateKey}|${entry.mood}|${entry.energy}')
      .join(';');

  Stream<List<_WellnessEntry>> _watchMoodEntries(String userId) {
    if (!_useWindowsPollingWorkaround) {
      final query = ref
          .read(firestoreProvider)
          .collection('mood_entries')
          .where('userId', isEqualTo: userId);
      return query.snapshots().map(
        (snapshot) => _parseEntries(snapshot.docs.map((doc) => doc.data())),
      );
    }
    return _buildWindowsPollingStream<List<_WellnessEntry>>(
      load: () async {
        final documents = await ref
            .read(windowsFirestoreRestClientProvider)
            .queryCollection(
              collectionId: 'mood_entries',
              filters: <WindowsFirestoreFieldFilter>[
                WindowsFirestoreFieldFilter.equal('userId', userId),
              ],
            );
        return _parseEntries(documents.map((doc) => doc.data));
      },
      signature: _entriesSignature,
    );
  }

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

    controller = StreamController<T>(
      onListen: () {
        unawaited(emitIfChanged());
        timer = Timer.periodic(_windowsPollInterval, (_) {
          unawaited(emitIfChanged());
        });
      },
      onCancel: () async {
        timer?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<void> _save({required String mood, required int energy}) async {
    final userId = widget.profile.id.trim();
    if (userId.isEmpty || _saving) {
      return;
    }

    final windowsRest = ref.read(windowsFirestoreRestClientProvider);
    final todayKey = _dateKey(DateTime.now());
    final docId = '${userId}_$todayKey';
    final now = DateTime.now().toUtc();

    setState(() => _saving = true);
    try {
      if (_useWindowsPollingWorkaround) {
        final existing =
            (await windowsRest.getDocument('mood_entries/$docId'))?.data ??
            const <String, dynamic>{};
        await windowsRest.setDocument('mood_entries/$docId', {
          ...existing,
          'userId': userId,
          'dateKey': todayKey,
          'mood': mood,
          'energy': energy.clamp(1, 5),
          'updatedAt': now,
          'createdAt': existing['createdAt'] ?? now,
        });
      } else {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('mood_entries').doc(docId).set({
          'userId': userId,
          'dateKey': todayKey,
          'mood': mood,
          'energy': energy.clamp(1, 5),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userId = widget.profile.id.trim();

    final cardColor = isDark ? const Color(0xFF151F31) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2A3A52)
        : const Color(0xFFDDE6F1);
    final headingColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0F172A);
    final mutedColor = isDark
        ? const Color(0xFF9FB2CC)
        : const Color(0xFF64748B);
    final selectedBg = isDark
        ? const Color(0xFF1F2D44)
        : const Color(0xFFEAF2FB);

    if (userId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<_WellnessEntry>>(
      stream: _watchMoodEntries(userId),
      builder: (context, snapshot) {
        final byDate = <String, _WellnessEntry>{};
        for (final entry in snapshot.data ?? const <_WellnessEntry>[]) {
          byDate[entry.dateKey] = entry;
        }

        final todayKey = _dateKey(DateTime.now());
        final today = byDate[todayKey];
        final selectedMood = _resolveMood(today?.mood);
        final selectedEnergy = today?.energy ?? 3;

        final now = DateTime.now();
        final last7 = List<DateTime>.generate(
          7,
          (index) => DateTime(now.year, now.month, now.day - (6 - index)),
          growable: false,
        );
        final dayLetters = const <int, String>{
          DateTime.monday: 'M',
          DateTime.tuesday: 'T',
          DateTime.wednesday: 'W',
          DateTime.thursday: 'T',
          DateTime.friday: 'F',
          DateTime.saturday: 'S',
          DateTime.sunday: 'S',
        };

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0x120F172A))
                    .withValues(alpha: isDark ? 0.22 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E9B90).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.self_improvement_rounded,
                      size: 18,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Wellness Check-in',
                    style: TextStyle(
                      color: headingColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (_saving)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0E9B90),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Daily check-in. Update anytime today.',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Mood',
                style: TextStyle(
                  color: headingColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _moods
                    .map((entry) {
                      final selected = selectedMood.key == entry.key;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () =>
                              _save(mood: entry.key, energy: selectedEnergy),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? selectedBg : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected
                                    ? entry.color
                                    : borderColor.withValues(alpha: 0.85),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.emoji,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  entry.label,
                                  style: TextStyle(
                                    color: selected ? entry.color : mutedColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              Text(
                'Energy',
                style: TextStyle(
                  color: headingColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List<Widget>.generate(5, (index) {
                  final level = index + 1;
                  final selected = level <= selectedEnergy;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () =>
                            _save(mood: selectedMood.key, energy: level),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: selected ? selectedBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF0E9B90)
                                  : borderColor.withValues(alpha: 0.85),
                            ),
                          ),
                          child: Icon(
                            _energyIcon(level),
                            size: 18,
                            color: selected
                                ? const Color(0xFF0E9B90)
                                : mutedColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Text(
                'Last 7 days',
                style: TextStyle(
                  color: headingColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: last7
                    .map((day) {
                      final key = _dateKey(day);
                      final point = byDate[key];
                      final mood = _resolveMood(point?.mood);
                      return Expanded(
                        child: Column(
                          children: [
                            Text(
                              dayLetters[day.weekday] ?? '-',
                              style: TextStyle(
                                color: mutedColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              point == null ? 'â€¢' : mood.emoji,
                              style: TextStyle(
                                fontSize: point == null ? 15 : 16,
                                color: point == null ? mutedColor : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List<Widget>.generate(5, (index) {
                                final filled =
                                    point != null && index < point.energy;
                                return Container(
                                  width: 3.5,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: filled
                                        ? const Color(0xFF0E9B90)
                                        : borderColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveEmptyState extends StatelessWidget {
  const _LiveEmptyState({required this.message, this.onTap});

  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          message,
          style: TextStyle(
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.help_outline_rounded, size: 16),
            label: const Text('How to join'),
          ),
        ],
      ],
    );
  }
}

class _NotificationsSummaryBar extends StatelessWidget {
  const _NotificationsSummaryBar({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE7F4FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7E4FF)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFF0EA5E9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You have $unreadCount unread update${unreadCount == 1 ? '' : 's'}.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1A2F),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF0B1A2F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.isDark,
    required this.showLive,
    required this.onBookSession,
    required this.onOpenCounselors,
    required this.onOpenLive,
  });

  final bool isDark;
  final bool showLive;
  final VoidCallback onBookSession;
  final VoidCallback onOpenCounselors;
  final VoidCallback onOpenLive;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF111B2B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1F2D44)
        : const Color(0xFFD9E3EE);
    final actions = <_ActionItem>[
      _ActionItem(
        label: 'Book session',
        icon: Icons.calendar_month_rounded,
        onTap: onBookSession,
      ),
      _ActionItem(
        label: 'Counselors',
        icon: Icons.groups_rounded,
        onTap: onOpenCounselors,
      ),
      if (showLive)
        _ActionItem(
          label: 'Join live',
          icon: Icons.podcasts_rounded,
          onTap: onOpenLive,
        ),
      _ActionItem(
        label: 'Messages',
        icon: Icons.chat_bubble_outline_rounded,
        onTap: () => showModernBannerFromSnackBar(
          context,
          const SnackBar(content: Text('Messages coming soon.')),
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.22 : 0.07,
            ),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick actions',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0B1A2F),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions
                .map((action) => _ActionPill(action: action, isDark: isDark))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action, required this.isDark});

  final _ActionItem action;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF15233A) : const Color(0xFFF2F7FB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: 18,
                color: isDark
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFF0E9B90),
              ),
              const SizedBox(width: 8),
              Text(
                action.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressMiniCard extends StatelessWidget {
  const _ProgressMiniCard({required this.isDark, required this.firstName});

  final bool isDark;
  final String firstName;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF111B2B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1F2D44)
        : const Color(0xFFD9E3EE);

    final stats = [
      _StatRow(
        label: 'Today\'s check-in',
        value: 'Try a 30s update',
        icon: Icons.bolt_rounded,
        color: const Color(0xFF0E9B90),
      ),
      _StatRow(
        label: 'This week',
        value: 'Build a 3-day streak',
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF0EA5E9),
      ),
      _StatRow(
        label: 'Energy balance',
        value: 'Aim for 3+ today',
        icon: Icons.battery_charging_full_rounded,
        color: const Color(0xFFF59E0B),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.22 : 0.07,
            ),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$firstName, keep momentum',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0B1A2F),
            ),
          ),
          const SizedBox(height: 10),
          ...stats.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StatTile(stat: s, isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.isDark});

  final _StatRow stat;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: stat.color.withOpacity(isDark ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(stat.icon, color: stat.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stat.value,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF9FB2CC)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResourceSpotlightCard extends StatelessWidget {
  const _ResourceSpotlightCard({required this.isDark, required this.onOpen});

  final bool isDark;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0E1A2C), Color(0xFF0C3B5E)]
              : const [Color(0xFFEFF7FF), Color(0xFFE8FBF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2D44) : const Color(0xFFCFE5F3),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0x120F172A)).withValues(
              alpha: isDark ? 0.22 : 0.07,
            ),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0E9B90).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.self_improvement_rounded,
              color: Color(0xFF0E9B90),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Take a 2‑minute reset',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1A2F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Short guided breathing to steady your mood before the next task.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFB7C6DA)
                        : const Color(0xFF516784),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: onOpen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E7490),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                  label: const Text('Start quick reset'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodChoice {
  const _MoodChoice({
    required this.key,
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String key;
  final String emoji;
  final String label;
  final Color color;
}

class _WellnessEntry {
  const _WellnessEntry({
    required this.dateKey,
    required this.mood,
    required this.energy,
  });

  final String dateKey;
  final String mood;
  final int energy;
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

class _DesktopCrisisSupportCard extends StatelessWidget {
  const _DesktopCrisisSupportCard({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF463144)
        : const Color(0xFFFECACA);
    final titleColor = isDark
        ? const Color(0xFFFCE7F3)
        : const Color(0xFF111827);
    final bodyColor = isDark
        ? const Color(0xFFF9A8D4)
        : const Color(0xFF6B7280);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 196),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF2B1F2B), Color(0xFF1E1925)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [
                  Color(0xFFFFFBFB),
                  Color(0xFFFFF1F2),
                  Color(0xFFFFF7ED),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFFFDA4AF)).withValues(
              alpha: isDark ? 0.24 : 0.16,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -34,
            right: -26,
            child: _AmbientOrb(
              size: 124,
              color: const Color(0xFFFB7185).withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            bottom: -42,
            left: -28,
            child: _AmbientOrb(
              size: 108,
              color: const Color(0xFFF97316).withValues(alpha: 0.11),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2636)
                          : const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFFFB7185).withValues(alpha: 0.24),
                      ),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded,
                      color: Color(0xFFE11D48),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Need immediate support?',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'If things feel overwhelming, pause, breathe once, and open support for emergency contacts and next steps.',
                          style: TextStyle(
                            color: bodyColor,
                            fontSize: 13.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFFBCFE8),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: Color(0xFFF97316),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You do not have to figure this out alone. Reaching out early is a strength, not a failure.',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFE5E7EB)
                              : const Color(0xFF4B5563),
                          fontSize: 12.7,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: const Text('Open Crisis Support'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
