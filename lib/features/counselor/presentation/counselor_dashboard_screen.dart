import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/session_reassignment_request.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';

class CounselorDashboardScreen extends ConsumerStatefulWidget {
  const CounselorDashboardScreen({
    super.key,
    this.embeddedInCounselorShell = false,
  });

  final bool embeddedInCounselorShell;

  @override
  ConsumerState<CounselorDashboardScreen> createState() =>
      _CounselorDashboardScreenState();
}

enum _CounselorWorkspaceSection {
  overview,
  sessions,
  live,
  availability,
  counselors,
  notifications,
  profile,
}

class _CounselorDashboardScreenState
    extends ConsumerState<CounselorDashboardScreen>
    with SingleTickerProviderStateMixin {
  _CounselorWorkspaceSection _activeSection =
      _CounselorWorkspaceSection.overview;
  late final AnimationController _reassignmentPulseController;
  final Set<String> _homePendingRequestIds = <String>{};
  String? _homeReassignmentFeedbackMessage;
  bool _homeReassignmentFeedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _reassignmentPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _reassignmentPulseController.dispose();
    super.dispose();
  }

  void _setHomeReassignmentFeedback(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _homeReassignmentFeedbackMessage = message;
      _homeReassignmentFeedbackIsError = isError;
    });
  }

  String _formatActionError(Object error, String fallback) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return fallback;
    }
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .trim();
  }

  Future<void> _handleHomeReassignmentInterest(
    SessionReassignmentRequest request,
  ) async {
    if (_homePendingRequestIds.contains(request.id)) {
      return;
    }
    setState(() {
      _homePendingRequestIds.add(request.id);
      _homeReassignmentFeedbackMessage = null;
    });
    try {
      await ref
          .read(careRepositoryProvider)
          .expressInterestInReassignment(request.id);
      _setHomeReassignmentFeedback(
        'You were added to the interested counselors list.',
        isError: false,
      );
    } catch (error) {
      _setHomeReassignmentFeedback(
        _formatActionError(
          error,
          'Unable to respond to this coverage request right now.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _homePendingRequestIds.remove(request.id);
        });
      }
    }
  }

  void _syncReassignmentLifecycle(
    List<SessionReassignmentRequest> requests,
    String institutionId,
  ) {
    if (institutionId.trim().isEmpty) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    for (final request in requests) {
      final responseExpired =
          request.status == SessionReassignmentStatus.openForResponses &&
          nowUtc.isAfter(request.responseDeadlineAt);
      final choiceExpired =
          request.status == SessionReassignmentStatus.awaitingPatientChoice &&
          request.choiceDeadlineAt != null &&
          nowUtc.isAfter(request.choiceDeadlineAt!);
      if (responseExpired || choiceExpired) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(careRepositoryProvider)
              .syncReassignmentLifecycle(request.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final showLive =
        !(!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

    final dashboardContent = profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return const Center(child: _StateCard(message: 'Profile not found.'));
        }
        if (profile.role != UserRole.counselor) {
          return const Center(
            child: _StateCard(
              message: 'This workspace is available only for counselors.',
            ),
          );
        }

        final institutionId = (profile.institutionId ?? '').trim();
        if (institutionId.isEmpty) {
          return const Center(
            child: _StateCard(
              message: 'Your counselor profile is missing an institution link.',
            ),
          );
        }

        final unreadCount =
            ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
        final workflowSettings =
            ref
                .watch(counselorWorkflowSettingsProvider(institutionId))
                .valueOrNull ??
            const CounselorWorkflowSettings.disabled();
        final showCounselorDirectory = workflowSettings.directoryEnabled;
        final reassignmentRequests =
            ref
                .watch(institutionReassignmentBoardProvider(institutionId))
                .valueOrNull ??
            const <SessionReassignmentRequest>[];
        _syncReassignmentLifecycle(reassignmentRequests, institutionId);
        final sidebarItems = _sidebarItems(
          showCounselorDirectory,
          showLive: showLive,
        );

        return StreamBuilder<List<AppointmentRecord>>(
          stream: ref
              .read(careRepositoryProvider)
              .watchCounselorAppointments(
                institutionId: institutionId,
                counselorId: profile.id,
              ),
          builder: (context, appointmentsSnapshot) {
            final appointments = appointmentsSnapshot.data ?? const [];

            return StreamBuilder<List<AvailabilitySlot>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorSlots(
                    institutionId: institutionId,
                    counselorId: profile.id,
                  ),
              builder: (context, slotsSnapshot) {
                final slots = slotsSnapshot.data ?? const [];
                final summary = _WorkspaceSummary.build(
                  profile: profile,
                  appointments: appointments,
                  slots: slots,
                  unreadNotifications: unreadCount,
                );

                if (widget.embeddedInCounselorShell) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth >= 1120;
                      final overviewContent = _buildOverviewSection(
                        profile: profile,
                        summary: summary,
                        workflowSettings: workflowSettings,
                        reassignmentRequests: reassignmentRequests,
                        isDesktop: isDesktop,
                        onOpenAppointments: () =>
                            context.go(AppRoute.counselorAppointments),
                        onOpenAvailability: () =>
                            context.go(AppRoute.counselorAvailability),
                      );
                      if (!constraints.hasBoundedHeight) {
                        return overviewContent;
                      }
                      return SingleChildScrollView(
                        primary: false,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: overviewContent,
                        ),
                      );
                    },
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 1120;
                    final isTablet = constraints.maxWidth >= 760;
                    return isDesktop
                        ? _buildDesktopWorkspace(
                            context: context,
                            profile: profile,
                            summary: summary,
                            workflowSettings: workflowSettings,
                            reassignmentRequests: reassignmentRequests,
                            sidebarItems: sidebarItems,
                          )
                        : _buildMobileWorkspace(
                            context: context,
                            profile: profile,
                            summary: summary,
                            workflowSettings: workflowSettings,
                            reassignmentRequests: reassignmentRequests,
                            isTablet: isTablet,
                            sidebarItems: sidebarItems,
                          );
                  },
                );
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: _StateCard(
          message: error.toString().replaceFirst('Exception: ', ''),
        ),
      ),
    );

    if (widget.embeddedInCounselorShell) {
      return dashboardContent;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _DashboardBackdrop(child: SafeArea(child: dashboardContent)),
    );
  }

  Widget _buildDesktopWorkspace({
    required BuildContext context,
    required UserProfile profile,
    required _WorkspaceSummary summary,
    required CounselorWorkflowSettings workflowSettings,
    required List<SessionReassignmentRequest> reassignmentRequests,
    required List<_SidebarItem> sidebarItems,
  }) {
    final shell = _sectionShell(_activeSection);

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 284,
            child: _DesktopSidebar(
              profile: profile,
              activeSection: _activeSection,
              sidebarItems: sidebarItems,
              unreadNotifications: summary.unreadNotifications,
              onSelect: (section) {
                if (section == _CounselorWorkspaceSection.counselors) {
                  context.go(AppRoute.counselorDirectory);
                  return;
                }
                if (section == _CounselorWorkspaceSection.live) {
                  context.go(AppRoute.counselorLiveHub);
                  return;
                }
                setState(() => _activeSection = section);
              },
              onLogout: () => confirmAndLogout(context: context, ref: ref),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F3).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 30,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _WorkspaceHeader(
                    title: shell.title,
                    subtitle: shell.subtitle,
                    profile: profile,
                    unreadNotifications: summary.unreadNotifications,
                    desktop: true,
                    onNotifications: () => setState(() {
                      _activeSection = _CounselorWorkspaceSection.notifications;
                    }),
                    onProfile: () => setState(() {
                      _activeSection = _CounselorWorkspaceSection.profile;
                    }),
                    onLogout: () =>
                        confirmAndLogout(context: context, ref: ref),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: SingleChildScrollView(
                        key: ValueKey(_activeSection),
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                        child: _buildSectionContent(
                          context: context,
                          profile: profile,
                          summary: summary,
                          workflowSettings: workflowSettings,
                          reassignmentRequests: reassignmentRequests,
                          isDesktop: true,
                        ),
                      ),
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

  Widget _buildMobileWorkspace({
    required BuildContext context,
    required UserProfile profile,
    required _WorkspaceSummary summary,
    required CounselorWorkflowSettings workflowSettings,
    required List<SessionReassignmentRequest> reassignmentRequests,
    required bool isTablet,
    required List<_SidebarItem> sidebarItems,
  }) {
    final shell = _sectionShell(_activeSection);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 20 : 14,
        14,
        isTablet ? 20 : 14,
        20,
      ),
      child: Column(
        children: [
          _WorkspaceHeader(
            title: shell.title,
            subtitle: shell.subtitle,
            profile: profile,
            unreadNotifications: summary.unreadNotifications,
            desktop: false,
            onNotifications: () => setState(() {
              _activeSection = _CounselorWorkspaceSection.notifications;
            }),
            onProfile: () => setState(() {
              _activeSection = _CounselorWorkspaceSection.profile;
            }),
            onLogout: () => confirmAndLogout(context: context, ref: ref),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sidebarItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = sidebarItems[index];
                return _MobileSectionChip(
                  item: item,
                  active: item.section == _activeSection,
                  unreadNotifications: summary.unreadNotifications,
                  onTap: () {
                    if (item.section == _CounselorWorkspaceSection.counselors) {
                      context.go(AppRoute.counselorDirectory);
                      return;
                    }
                    if (item.section == _CounselorWorkspaceSection.live) {
                      context.go(AppRoute.counselorLiveHub);
                      return;
                    }
                    setState(() => _activeSection = item.section);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SingleChildScrollView(
                key: ValueKey(_activeSection),
                child: _buildSectionContent(
                  context: context,
                  profile: profile,
                  summary: summary,
                  workflowSettings: workflowSettings,
                  reassignmentRequests: reassignmentRequests,
                  isDesktop: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent({
    required BuildContext context,
    required UserProfile profile,
    required _WorkspaceSummary summary,
    required CounselorWorkflowSettings workflowSettings,
    required List<SessionReassignmentRequest> reassignmentRequests,
    required bool isDesktop,
  }) {
    switch (_activeSection) {
      case _CounselorWorkspaceSection.overview:
        return _buildOverviewSection(
          profile: profile,
          summary: summary,
          workflowSettings: workflowSettings,
          reassignmentRequests: reassignmentRequests,
          isDesktop: isDesktop,
          onOpenAppointments: () => context.go(AppRoute.counselorAppointments),
          onOpenAvailability: () => context.go(AppRoute.counselorAvailability),
        );
      case _CounselorWorkspaceSection.sessions:
        return _buildSessionsSection(
          summary: summary,
          isDesktop: isDesktop,
          onOpenAppointments: () => context.go(AppRoute.counselorAppointments),
          onOpenNotifications: () => context.go(AppRoute.notifications),
        );
      case _CounselorWorkspaceSection.availability:
        return _buildAvailabilitySection(
          summary: summary,
          isDesktop: isDesktop,
          onManageAvailability: () =>
              context.go(AppRoute.counselorAvailability),
        );
      case _CounselorWorkspaceSection.live:
        return const _LiveRedirectPanel();
      case _CounselorWorkspaceSection.counselors:
        return _buildCounselorsSection(
          onOpenDirectory: () => context.go(AppRoute.counselorDirectory),
        );
      case _CounselorWorkspaceSection.notifications:
        return _buildNotificationsSection(
          summary: summary,
          isDesktop: isDesktop,
          onOpenNotifications: () => context.go(AppRoute.notifications),
        );
      case _CounselorWorkspaceSection.profile:
        return _buildProfileSection(
          profile: profile,
          summary: summary,
          onEditProfile: () => context.go(AppRoute.counselorSettings),
        );
    }
  }

  Widget _buildOverviewSection({
    required UserProfile profile,
    required _WorkspaceSummary summary,
    required CounselorWorkflowSettings workflowSettings,
    required List<SessionReassignmentRequest> reassignmentRequests,
    required bool isDesktop,
    required VoidCallback onOpenAppointments,
    required VoidCallback onOpenAvailability,
  }) {
    final activeRequests = reassignmentRequests
        .where(
          (entry) =>
              entry.status == SessionReassignmentStatus.openForResponses ||
              entry.status == SessionReassignmentStatus.awaitingPatientChoice ||
              entry.status == SessionReassignmentStatus.patientSelected,
        )
        .toList(growable: false);
    final actionableRequests = activeRequests
        .where(
          (entry) =>
              entry.originalCounselorId != profile.id &&
              entry.status == SessionReassignmentStatus.openForResponses &&
              !entry.interestedCounselors.any(
                (item) => item.counselorId == profile.id,
              ),
        )
        .toList(growable: false);
    final myActiveRequests = activeRequests
        .where((entry) => entry.originalCounselorId == profile.id)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workflowSettings.reassignmentEnabled &&
            activeRequests.isNotEmpty) ...[
          _HomeReassignmentAlertCard(
            pulse: _reassignmentPulseController,
            actionableRequests: actionableRequests,
            myActiveRequests: myActiveRequests,
            pendingRequestIds: _homePendingRequestIds,
            feedbackMessage: _homeReassignmentFeedbackMessage,
            feedbackIsError: _homeReassignmentFeedbackIsError,
            onOpenBoard: onOpenAppointments,
            onTakeRequest: _handleHomeReassignmentInterest,
          ),
          const SizedBox(height: 20),
        ],
        if (isDesktop) ...[
          _HeroPanel(
            summary: summary,
            onPrimaryTap: onOpenAppointments,
            onSecondaryTap: onOpenAvailability,
            primaryLabel: 'Open Sessions',
            secondaryLabel: 'Manage Availability',
          ),
          const SizedBox(height: 20),
        ],
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _TodayQueueCard(
                  todayQueue: summary.todayQueue,
                  nextSession: summary.nextSession,
                  onOpenAppointments: onOpenAppointments,
                  title: 'Today\'s queue',
                  description:
                      'This fixed frame stays stable while the center content changes. Keep today\'s counseling queue moving here.',
                  isDesktop: true,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 5,
                child: _QuickActionsCard(
                  onOpenAppointments: onOpenAppointments,
                  onOpenAvailability: onOpenAvailability,
                ),
              ),
            ],
          )
        else ...[
          _TodayQueueCard(
            todayQueue: summary.todayQueue,
            nextSession: summary.nextSession,
            onOpenAppointments: onOpenAppointments,
            title: 'Today\'s queue',
            description:
                'This fixed frame stays stable while the center content changes. Keep today\'s counseling queue moving here.',
            isDesktop: false,
          ),
          const SizedBox(height: 16),
          _QuickActionsCard(
            onOpenAppointments: onOpenAppointments,
            onOpenAvailability: onOpenAvailability,
          ),
        ],
      ],
    );
  }

  Widget _buildSessionsSection({
    required _WorkspaceSummary summary,
    required bool isDesktop,
    required VoidCallback onOpenAppointments,
    required VoidCallback onOpenNotifications,
  }) {
    final stats = [
      _StatCardData(
        'Pending',
        '${summary.pendingRequests}',
        'need a response',
        const Color(0xFFF59E0B),
      ),
      _StatCardData(
        'Upcoming',
        '${summary.upcomingSessions}',
        'future sessions',
        const Color(0xFF2563EB),
      ),
      _StatCardData(
        'Completed',
        '${summary.completedThisWeek}',
        'this week',
        const Color(0xFF0E9B90),
      ),
      _StatCardData(
        'No-show',
        '${summary.noShows}',
        'recorded so far',
        const Color(0xFFEF4444),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop) ...[
          _ResponsiveStatRow(stats: stats, minCardWidth: 170),
          const SizedBox(height: 20),
        ],
        _SpotlightPanel(
          eyebrow: 'SESSION CONTROL',
          title: summary.nextSession == null
              ? 'No upcoming session is queued right now.'
              : 'Next live session is ${_formatAppointmentHeadline(summary.nextSession!)}.',
          body:
              'Use the appointments workspace for confirmations, completions, cancellations, and detailed session notes. This dashboard keeps the signal visible while the deeper workflow stays in the appointments screen.',
          primaryLabel: 'Open Appointments',
          onPrimaryTap: onOpenAppointments,
          accent: const [Color(0xFFF97316), Color(0xFFFB923C)],
        ),
        const SizedBox(height: 20),
        _TodayQueueCard(
          todayQueue: summary.todayQueue,
          nextSession: summary.nextSession,
          onOpenAppointments: onOpenAppointments,
          title: 'Today\'s counselor queue',
          description:
              'Today is where pending and confirmed counseling work becomes real. Keep this list moving and use the full session screen for detailed handling.',
          isDesktop: isDesktop,
        ),
      ],
    );
  }

  Widget _buildAvailabilitySection({
    required _WorkspaceSummary summary,
    required bool isDesktop,
    required VoidCallback onManageAvailability,
  }) {
    final guidance = summary.openSlots == 0
        ? 'No future open slot is live. Publish at least a small forward window so booking demand does not dead-end.'
        : summary.openSlots < 3
        ? 'Your open inventory is thin. Consider publishing a wider forward window to reduce booking bottlenecks.'
        : 'Your forward availability looks healthy. Keep reviewing gaps between today and the next open window.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpotlightPanel(
          eyebrow: 'AVAILABILITY PULSE',
          title: summary.nextOpenSlot == null
              ? 'You do not have a future open slot published.'
              : 'Next open slot starts ${_formatSlotHeadline(summary.nextOpenSlot!)}.',
          body:
              'Availability is where counselor demand is shaped. Keep enough future openings visible so students can book without friction, then move into the slot manager for actual edits.',
          primaryLabel: 'Open Availability Manager',
          onPrimaryTap: onManageAvailability,
          accent: const [Color(0xFF0E9B90), Color(0xFF2563EB)],
        ),
        const SizedBox(height: 20),
        _InsightCard(
          title: 'Coverage guidance',
          description: guidance,
          icon: Icons.schedule_rounded,
          accent: const Color(0xFF0E9B90),
        ),
      ],
    );
  }

  Widget _buildCounselorsSection({required VoidCallback onOpenDirectory}) {
    return _SpotlightPanel(
      eyebrow: 'COUNSELOR DIRECTORY',
      title: 'Open the internal counselor directory.',
      body:
          'Browse limited counselor identity details inside your institution when the admin enables directory visibility.',
      primaryLabel: 'Open Counselor Directory',
      onPrimaryTap: onOpenDirectory,
      accent: const [Color(0xFF0E9B90), Color(0xFF2563EB)],
    );
  }

  Widget _buildNotificationsSection({
    required _WorkspaceSummary summary,
    required bool isDesktop,
    required VoidCallback onOpenNotifications,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpotlightPanel(
          eyebrow: 'NOTIFICATION CENTER',
          title: summary.unreadNotifications == 0
              ? 'No unread notifications are waiting right now.'
              : '${summary.unreadNotifications} unread notifications still need attention.',
          body:
              'This summary is intentionally lightweight. Use the dedicated notifications screen for detailed booking changes, cancellations, reminders, and invite-related events.',
          primaryLabel: 'Open Notifications',
          onPrimaryTap: onOpenNotifications,
          accent: const [Color(0xFF7C3AED), Color(0xFF2563EB)],
        ),
        if (isDesktop) ...[
          const SizedBox(height: 20),
          _ResponsiveStatRow(
            stats: [
              _StatCardData(
                'Unread',
                '${summary.unreadNotifications}',
                'still active',
                const Color(0xFF7C3AED),
              ),
              _StatCardData(
                'Pending',
                '${summary.pendingRequests}',
                'likely to notify',
                const Color(0xFFF59E0B),
              ),
              _StatCardData(
                'Today',
                '${summary.todaySessions}',
                'session-linked',
                const Color(0xFF0E9B90),
              ),
            ],
            minCardWidth: 200,
          ),
        ],
      ],
    );
  }

  Widget _buildProfileSection({
    required UserProfile profile,
    required _WorkspaceSummary summary,
    required VoidCallback onEditProfile,
  }) {
    return _ProfileHero(summary: summary, onEditProfile: onEditProfile);
  }

  _SectionShell _sectionShell(_CounselorWorkspaceSection section) {
    switch (section) {
      case _CounselorWorkspaceSection.overview:
        return const _SectionShell(
          title: 'Dashboard',
          subtitle:
              'A fixed workspace frame with your live activity, quick actions, and daily priorities in one place.',
        );
      case _CounselorWorkspaceSection.sessions:
        return const _SectionShell(
          title: 'Sessions',
          subtitle:
              'Review pending demand, watch today\'s queue, and jump into the full appointments workflow when needed.',
        );
      case _CounselorWorkspaceSection.live:
        return const _SectionShell(
          title: 'Live',
          subtitle:
              'Join or host institution live sessions directly from your counselor workspace.',
        );
      case _CounselorWorkspaceSection.availability:
        return const _SectionShell(
          title: 'Availability',
          subtitle:
              'Keep your open slots healthy, spot gaps early, and move directly into slot management when you need to publish changes.',
        );
      case _CounselorWorkspaceSection.counselors:
        return const _SectionShell(
          title: 'Counselors',
          subtitle:
              'Browse the internal counselor directory when institution policy allows peer visibility.',
        );
      case _CounselorWorkspaceSection.notifications:
        return const _SectionShell(
          title: 'Notifications',
          subtitle:
              'Track unread activity, booking changes, and the actions that still need your attention.',
        );
      case _CounselorWorkspaceSection.profile:
        return const _SectionShell(
          title: 'Profile',
          subtitle:
              'See the professional identity students view and move into settings only when you need to edit the source data.',
        );
    }
  }
}

class _SectionShell {
  const _SectionShell({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class _WorkspaceSummary {
  const _WorkspaceSummary({
    required this.displayName,
    required this.institutionName,
    required this.title,
    required this.specializations,
    required this.sessionMode,
    required this.timezone,
    required this.languages,
    required this.gender,
    required this.unreadNotifications,
    required this.pendingRequests,
    required this.todaySessions,
    required this.upcomingSessions,
    required this.completedThisWeek,
    required this.noShows,
    required this.openSlots,
    required this.bookedSlots,
    required this.blockedSlots,
    required this.nextSession,
    required this.nextOpenSlot,
    required this.todayQueue,
  });

  factory _WorkspaceSummary.build({
    required UserProfile profile,
    required List<AppointmentRecord> appointments,
    required List<AvailabilitySlot> slots,
    required int unreadNotifications,
  }) {
    final setupData = profile.counselorSetupData;
    final now = DateTime.now();
    final todayAppointments =
        appointments
            .where((entry) {
              final local = entry.startAt.toLocal();
              return local.year == now.year &&
                  local.month == now.month &&
                  local.day == now.day &&
                  (entry.status == AppointmentStatus.pending ||
                      entry.status == AppointmentStatus.confirmed);
            })
            .toList(growable: false)
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final upcoming =
        appointments
            .where((entry) {
              return entry.startAt.isAfter(now) &&
                  (entry.status == AppointmentStatus.pending ||
                      entry.status == AppointmentStatus.confirmed);
            })
            .toList(growable: false)
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final availableSlots =
        slots
            .where((slot) {
              return slot.endAt.isAfter(now) &&
                  slot.status == AvailabilitySlotStatus.available;
            })
            .toList(growable: false)
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final languagesRaw = setupData['languages'];
    final languages = <String>[];
    if (languagesRaw is List) {
      for (final item in languagesRaw) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          languages.add(text);
        }
      }
    } else if (languagesRaw is String && languagesRaw.trim().isNotEmpty) {
      languages.addAll(
        languagesRaw
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
    }

    final specializationRaw = (setupData['specialization'] as String? ?? '')
        .trim();

    return _WorkspaceSummary(
      displayName: profile.name.trim().isNotEmpty
          ? profile.name.trim()
          : 'Counselor',
      institutionName: (profile.institutionName ?? '').trim().isNotEmpty
          ? profile.institutionName!.trim()
          : 'Institution workspace',
      title: (setupData['title'] as String? ?? 'Counselor').trim(),
      specializations: specializationRaw.isEmpty
          ? const <String>[]
          : specializationRaw
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false),
      sessionMode: (setupData['sessionMode'] as String? ?? '--').trim(),
      timezone: (setupData['timezone'] as String? ?? 'UTC').trim(),
      languages: languages,
      gender: (setupData['gender'] as String?)?.trim(),
      unreadNotifications: unreadNotifications,
      pendingRequests: appointments
          .where((entry) => entry.status == AppointmentStatus.pending)
          .length,
      todaySessions: todayAppointments.length,
      upcomingSessions: upcoming.length,
      completedThisWeek: appointments
          .where(
            (entry) =>
                entry.startAt.isAfter(startOfWeek) &&
                entry.status == AppointmentStatus.completed,
          )
          .length,
      noShows: appointments
          .where((entry) => entry.status == AppointmentStatus.noShow)
          .length,
      openSlots: availableSlots.length,
      bookedSlots: slots
          .where(
            (slot) =>
                slot.endAt.isAfter(now) &&
                slot.status == AvailabilitySlotStatus.booked,
          )
          .length,
      blockedSlots: slots
          .where(
            (slot) =>
                slot.endAt.isAfter(now) &&
                slot.status == AvailabilitySlotStatus.blocked,
          )
          .length,
      nextSession: upcoming.isEmpty ? null : upcoming.first,
      nextOpenSlot: availableSlots.isEmpty ? null : availableSlots.first,
      todayQueue: todayAppointments.take(4).toList(growable: false),
    );
  }

  final String displayName;
  final String institutionName;
  final String title;
  final List<String> specializations;
  final String sessionMode;
  final String timezone;
  final List<String> languages;
  final String? gender;
  final int unreadNotifications;
  final int pendingRequests;
  final int todaySessions;
  final int upcomingSessions;
  final int completedThisWeek;
  final int noShows;
  final int openSlots;
  final int bookedSlots;
  final int blockedSlots;
  final AppointmentRecord? nextSession;
  final AvailabilitySlot? nextOpenSlot;
  final List<AppointmentRecord> todayQueue;
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop({required this.child});

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
          const _BlurOrb(
            size: 300,
            color: Color(0x5538BDF8),
            offset: Offset(-90, 40),
          ),
          const _BlurOrb(
            size: 260,
            color: Color(0x5514B8A6),
            offset: Offset(1180, 210),
          ),
          const _BlurOrb(
            size: 220,
            color: Color(0x55A7F3D0),
            offset: Offset(120, 760),
          ),
          child,
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.size,
    required this.color,
    required this.offset,
  });

  final double size;
  final Color color;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.profile,
    required this.activeSection,
    required this.sidebarItems,
    required this.unreadNotifications,
    required this.onSelect,
    required this.onLogout,
  });

  final UserProfile profile;
  final _CounselorWorkspaceSection activeSection;
  final List<_SidebarItem> sidebarItems;
  final int unreadNotifications;
  final ValueChanged<_CounselorWorkspaceSection> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C2233),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.psychology_alt_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MindNest',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        profile.institutionName ?? 'Counselor workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7FA0B5),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            ...sidebarItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SidebarNavItem(
                  item: item,
                  active: item.section == activeSection,
                  badgeCount:
                      item.section == _CounselorWorkspaceSection.notifications
                      ? unreadNotifications
                      : null,
                  onTap: () => onSelect(item.section),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF132D41),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1F415A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WORKSPACE STATUS',
                    style: TextStyle(
                      color: Color(0xFF7FA0B5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Counselor sync active',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    profile.name.trim().isNotEmpty
                        ? profile.name.trim()
                        : profile.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBBD0DC),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF325068)),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.unreadNotifications,
    required this.desktop,
    required this.onNotifications,
    required this.onProfile,
    required this.onLogout,
  });

  final String title;
  final String subtitle;
  final UserProfile profile;
  final int unreadNotifications;
  final bool desktop;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  void _openMobileAccountSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDDE6EE)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6E4F2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_rounded),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.of(context).pop();
                    onProfile();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFB91C1C),
                  ),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Color(0xFFB91C1C)),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    onLogout();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        desktop ? 28 : 18,
        desktop ? 24 : 18,
        desktop ? 28 : 18,
        desktop ? 18 : 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: desktop ? 0 : 0.9),
        borderRadius: desktop ? null : BorderRadius.circular(28),
        border: Border.all(
          color: desktop ? Colors.transparent : const Color(0xFFDDE6EE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF081A30),
                        fontSize: desktop ? 31 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: desktop ? -1.2 : -0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: desktop ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6A7C93),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _HeaderIconButton(
                icon: Icons.notifications_none_rounded,
                badgeCount: unreadNotifications,
                onTap: onNotifications,
              ),
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: Icons.manage_accounts_rounded,
                onTap: () {
                  if (desktop) {
                    onProfile();
                    return;
                  }
                  _openMobileAccountSheet(context);
                },
              ),
              if (desktop) ...[
                const SizedBox(width: 10),
                const WindowsDesktopWindowControls(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: desktop ? 20 : 18,
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _initials(
                    profile.name.isNotEmpty ? profile.name : profile.email,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.trim().isNotEmpty
                          ? profile.name.trim()
                          : 'Counselor',
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      profile.institutionName ?? 'Institution workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7B8CA4),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.summary,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final _WorkspaceSummary summary;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;
  final String primaryLabel;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF173D63), Color(0xFF1AA9A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackVertical = constraints.maxWidth < 780;
          final leading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow(
                text: 'COUNSELOR WORKSPACE',
                color: Color(0xFFFDE68A),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome back, ${summary.displayName}.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1.02,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.0,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${summary.institutionName} is active. Your dashboard keeps sessions, slots, notifications, and profile state visible without leaving the workspace frame.',
                style: const TextStyle(
                  color: Color(0xFFD7E5F0),
                  fontSize: 15.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onPrimaryTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0C2233),
                    ),
                    icon: const Icon(Icons.arrow_outward_rounded),
                    label: Text(primaryLabel),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSecondaryTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x66FFFFFF)),
                    ),
                    icon: const Icon(Icons.grid_view_rounded),
                    label: Text(secondaryLabel),
                  ),
                ],
              ),
            ],
          );

          final sideCard = Container(
            width: stackVertical ? double.infinity : 260,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x55FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Right now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _MiniSignal(
                  label: 'Pending requests',
                  value: '${summary.pendingRequests}',
                  tone: const Color(0xFFFDE68A),
                ),
                const SizedBox(height: 12),
                _MiniSignal(
                  label: 'Open slots',
                  value: '${summary.openSlots}',
                  tone: const Color(0xFFA7F3D0),
                ),
                const SizedBox(height: 12),
                _MiniSignal(
                  label: 'Unread alerts',
                  value: '${summary.unreadNotifications}',
                  tone: const Color(0xFFBFDBFE),
                ),
              ],
            ),
          );

          return stackVertical
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [leading, const SizedBox(height: 18), sideCard],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leading),
                    const SizedBox(width: 20),
                    sideCard,
                  ],
                );
        },
      ),
    );
  }
}

class _HomeReassignmentAlertCard extends StatelessWidget {
  const _HomeReassignmentAlertCard({
    required this.pulse,
    required this.actionableRequests,
    required this.myActiveRequests,
    required this.pendingRequestIds,
    required this.feedbackMessage,
    required this.feedbackIsError,
    required this.onOpenBoard,
    required this.onTakeRequest,
  });

  final Animation<double> pulse;
  final List<SessionReassignmentRequest> actionableRequests;
  final List<SessionReassignmentRequest> myActiveRequests;
  final Set<String> pendingRequestIds;
  final String? feedbackMessage;
  final bool feedbackIsError;
  final VoidCallback onOpenBoard;
  final Future<void> Function(SessionReassignmentRequest request) onTakeRequest;

  String _formatWindow(DateTime startAt, DateTime endAt) {
    final start = startAt.toLocal();
    final end = endAt.toLocal();
    return '${start.month}/${start.day} '
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  }

  String _headline(SessionReassignmentRequest request) {
    final specialization = request.requiredSpecialization.trim();
    if (specialization.isNotEmpty) {
      return specialization;
    }
    return 'Coverage request needs attention';
  }

  @override
  Widget build(BuildContext context) {
    final previewRequest = actionableRequests.isNotEmpty
        ? actionableRequests.first
        : myActiveRequests.first;
    final actionableCount = actionableRequests.length;
    final myCount = myActiveRequests.length;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = 0.16 + (pulse.value * 0.22);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFF5B21B6), Color(0xFF0F766E), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: glow),
                blurRadius: 34 + (pulse.value * 18),
                spreadRadius: 1.5 + (pulse.value * 3),
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(1.2),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(29),
              color: const Color(0xCC081A30),
              border: Border.all(
                color: const Color(
                  0xFFDDD6FE,
                ).withValues(alpha: 0.62 + (pulse.value * 0.28)),
              ),
            ),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const _Eyebrow(text: 'ACTION NEEDED', color: Color(0xFFFDE68A)),
              _AlertPill(
                icon: Icons.campaign_rounded,
                label: actionableCount > 0
                    ? '$actionableCount open request${actionableCount == 1 ? '' : 's'}'
                    : '$myCount live coverage request${myCount == 1 ? '' : 's'}',
              ),
              if (myCount > 0)
                _AlertPill(
                  icon: Icons.flag_rounded,
                  label: '$myCount yours live',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            actionableCount > 0
                ? 'Coverage request now live on your home screen.'
                : 'Your reassignment request is still active.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            actionableCount > 0
                ? 'A counselor in your institution needs replacement coverage. Respond from here or open the full board for the full queue.'
                : 'Your coverage board is active. Keep it visible here while you wait for interested counselors or move into the full sessions board.',
            style: const TextStyle(
              color: Color(0xFFD7E5F0),
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x44FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headline(previewRequest),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AlertPill(
                      icon: Icons.schedule_rounded,
                      label: _formatWindow(
                        previewRequest.sessionStartAt,
                        previewRequest.sessionEndAt,
                      ),
                    ),
                    _AlertPill(
                      icon: Icons.sync_alt_rounded,
                      label: 'Mode: ${previewRequest.sessionMode}',
                    ),
                    _AlertPill(
                      icon: Icons.groups_rounded,
                      label:
                          '${previewRequest.interestedCounselors.length}/${previewRequest.maxInterestedCounselors} interested',
                    ),
                  ],
                ),
                if (actionableCount > 1 || myCount > 1) ...[
                  const SizedBox(height: 12),
                  Text(
                    actionableCount > 1
                        ? '+${actionableCount - 1} more open request${actionableCount - 1 == 1 ? '' : 's'} waiting in the board.'
                        : '+${myCount - 1} more live request${myCount - 1 == 1 ? '' : 's'} in your board.',
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (feedbackMessage != null) ...[
            const SizedBox(height: 14),
            _HomeReassignmentFeedbackBanner(
              message: feedbackMessage!,
              isError: feedbackIsError,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (actionableCount > 0)
                FilledButton.icon(
                  onPressed: pendingRequestIds.contains(previewRequest.id)
                      ? null
                      : () => onTakeRequest(previewRequest),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0C2233),
                  ),
                  icon: pendingRequestIds.contains(previewRequest.id)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.volunteer_activism_outlined),
                  label: Text(
                    pendingRequestIds.contains(previewRequest.id)
                        ? 'Adding You...'
                        : 'I Can Take It',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: onOpenBoard,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x88FFFFFF)),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  actionableCount > 0 ? 'Open Coverage Board' : 'Open Sessions',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertPill extends StatelessWidget {
  const _AlertPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF8FAFC)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeReassignmentFeedbackBanner extends StatelessWidget {
  const _HomeReassignmentFeedbackBanner({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final background = isError
        ? const Color(0xFF7F1D1D).withValues(alpha: 0.75)
        : const Color(0xFF0F766E).withValues(alpha: 0.78);
    final border = isError ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0);
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border.withValues(alpha: 0.78)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayQueueCard extends StatelessWidget {
  const _TodayQueueCard({
    required this.todayQueue,
    required this.nextSession,
    required this.onOpenAppointments,
    required this.title,
    required this.description,
    required this.isDesktop,
  });

  final List<AppointmentRecord> todayQueue;
  final AppointmentRecord? nextSession;
  final VoidCallback onOpenAppointments;
  final String title;
  final String description;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF081A30),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xFF6A7C93),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenAppointments,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Appointments'),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ] else ...[
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF081A30),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: Color(0xFF6A7C93), height: 1.45),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenAppointments,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Appointments'),
            ),
            const SizedBox(height: 14),
          ],
          if (todayQueue.isEmpty)
            _EmptyStateLine(
              message: nextSession == null
                  ? 'Nothing is scheduled for today yet.'
                  : 'No session is scheduled for today. Next session is ${_formatAppointmentHeadline(nextSession!)}.',
            )
          else
            ...todayQueue.map((entry) => _AppointmentLine(entry: entry)),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onOpenAppointments,
    required this.onOpenAvailability,
  });

  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenAvailability;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick routes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep the dashboard as command center, then jump into the deeper workflow only when needed.',
            style: TextStyle(color: Color(0xFFB7C7D4), height: 1.45),
          ),
          const SizedBox(height: 18),
          _ActionTile(
            icon: Icons.event_note_rounded,
            title: 'Open appointments',
            subtitle: 'Approve, complete, cancel, and review session records.',
            onTap: onOpenAppointments,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.calendar_month_rounded,
            title: 'Open availability',
            subtitle: 'Publish and maintain future booking windows.',
            onTap: onOpenAvailability,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPanel extends StatelessWidget {
  const _SpotlightPanel({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimaryTap,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final List<Color> accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: accent,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(text: eyebrow, color: const Color(0xFFFDF2F8)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onPrimaryTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0C2233),
                ),
                icon: const Icon(Icons.arrow_outward_rounded),
                label: Text(primaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF081A30),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF6A7C93),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.summary, required this.onEditProfile});

  final _WorkspaceSummary summary;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _initials(summary.displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.displayName,
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.institutionName,
                      style: const TextStyle(
                        color: Color(0xFF6A7C93),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onEditProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E9B90),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit profile'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: summary.specializations.isEmpty
                ? const [_SoftTag(label: 'No specializations saved')]
                : summary.specializations
                      .map((entry) => _SoftTag(label: entry))
                      .toList(growable: false),
          ),
          if (summary.languages.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Languages',
              style: TextStyle(
                color: Color(0xFF7A8CA4),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: summary.languages
                  .map((entry) => _SoftTag(label: entry, muted: true))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponsiveStatRow extends StatelessWidget {
  const _ResponsiveStatRow({required this.stats, required this.minCardWidth});

  final List<_StatCardData> stats;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: stats
          .map(
            (stat) => SizedBox(
              width: math.max(minCardWidth, 150),
              child: _StatCard(data: stat),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StatCardData {
  const _StatCardData(this.label, this.value, this.detail, this.accent);

  final String label;
  final String value;
  final String detail;
  final Color accent;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label.toUpperCase(),
            style: TextStyle(
              color: data.accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: const TextStyle(
              color: Color(0xFF081A30),
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.detail,
            style: const TextStyle(
              color: Color(0xFF6A7C93),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentLine extends StatelessWidget {
  const _AppointmentLine({required this.entry});

  final AppointmentRecord entry;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (entry.status) {
      AppointmentStatus.pending => const Color(0xFFF59E0B),
      AppointmentStatus.confirmed => const Color(0xFF0E9B90),
      AppointmentStatus.completed => const Color(0xFF2563EB),
      AppointmentStatus.cancelled => const Color(0xFFEF4444),
      AppointmentStatus.noShow => const Color(0xFF7C3AED),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE7F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.schedule_rounded, color: statusColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (entry.studentName ?? 'Student').trim().isEmpty
                      ? 'Student'
                      : entry.studentName!.trim(),
                  style: const TextStyle(
                    color: Color(0xFF081A30),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTimeRange(entry.startAt, entry.endAt),
                  style: const TextStyle(color: Color(0xFF6A7C93)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              entry.status.name,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF132D41),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF244559)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFB7C7D4),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.onTap,
    this.badgeCount,
  });

  final _SidebarItem item;
  final bool active;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF243746) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? const Color(0xFF314A5C) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: active
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF89A3B6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFFD3DEE7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if ((badgeCount ?? 0) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${badgeCount!}',
                    style: const TextStyle(
                      color: Color(0xFF0C2233),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
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

class _MobileSectionChip extends StatelessWidget {
  const _MobileSectionChip({
    required this.item,
    required this.active,
    required this.unreadNotifications,
    required this.onTap,
  });

  final _SidebarItem item;
  final bool active;
  final int unreadNotifications;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = item.section == _CounselorWorkspaceSection.notifications
        ? unreadNotifications
        : 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF0E9B90)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? const Color(0xFF0E9B90) : const Color(0xFFD8E3EC),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                color: active ? Colors.white : const Color(0xFF4D647B),
              ),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF0C2233),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: active
                          ? const Color(0xFF0E9B90)
                          : const Color(0xFF0C2233),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE1E7EF)),
              ),
              child: Icon(icon, color: const Color(0xFF0C2233)),
            ),
          ),
        ),
        if ((badgeCount ?? 0) > 0)
          Positioned(
            right: -4,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${badgeCount!}',
                style: const TextStyle(
                  color: Color(0xFF0C2233),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _MiniSignal extends StatelessWidget {
  const _MiniSignal({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD6E4EE),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateLine extends StatelessWidget {
  const _EmptyStateLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE7F0)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF5E728D),
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SoftTag extends StatelessWidget {
  const _SoftTag({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF8FBFF) : const Color(0xFFE9FBF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted ? const Color(0xFFD9E5F0) : const Color(0xFFBEE7E1),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? const Color(0xFF5E728D) : const Color(0xFF0E9B90),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF0C2233),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final _CounselorWorkspaceSection section;
  final String label;
  final IconData icon;
}

class _LiveRedirectPanel extends StatelessWidget {
  const _LiveRedirectPanel();

  @override
  Widget build(BuildContext context) {
    // Redirect to Live Hub once the panel becomes active.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        context.go(AppRoute.counselorLiveHub);
      }
    });

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: const Row(
        children: [
          Icon(Icons.podcasts_rounded, color: Color(0xFF0E9B90)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Opening Live Hub…',
              style: TextStyle(
                color: Color(0xFF0C2233),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 8),
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ],
      ),
    );
  }
}

List<_SidebarItem> _sidebarItems(
  bool showCounselorDirectory, {
  required bool showLive,
}) {
  return [
    const _SidebarItem(
      section: _CounselorWorkspaceSection.overview,
      label: 'Dashboard',
      icon: Icons.home_outlined,
    ),
    const _SidebarItem(
      section: _CounselorWorkspaceSection.sessions,
      label: 'Sessions',
      icon: Icons.event_note_rounded,
    ),
    if (showLive)
      const _SidebarItem(
        section: _CounselorWorkspaceSection.live,
        label: 'Live',
        icon: Icons.podcasts_rounded,
      ),
    const _SidebarItem(
      section: _CounselorWorkspaceSection.availability,
      label: 'Availability',
      icon: Icons.calendar_month_rounded,
    ),
    if (showCounselorDirectory)
      const _SidebarItem(
        section: _CounselorWorkspaceSection.counselors,
        label: 'Counselors',
        icon: Icons.groups_rounded,
      ),
  ];
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'MN';
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _formatAppointmentHeadline(AppointmentRecord entry) =>
    '${_weekdayLabel(entry.startAt)} at ${_timeLabel(entry.startAt)}';
String _formatSlotHeadline(AvailabilitySlot slot) =>
    '${_weekdayLabel(slot.startAt)} at ${_timeLabel(slot.startAt)}';
String _formatDateTimeRange(DateTime start, DateTime end) =>
    '${_weekdayLabel(start)}, ${_monthLabel(start)} ${start.day}  ${_timeLabel(start)} - ${_timeLabel(end)}';

String _weekdayLabel(DateTime value) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[value.toLocal().weekday - 1];
}

String _monthLabel(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[value.toLocal().month - 1];
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}
