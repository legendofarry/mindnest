import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/session_reassignment_request.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class CounselorAppointmentsScreen extends ConsumerWidget {
  const CounselorAppointmentsScreen({super.key});

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return const Color(0xFFD97706);
      case AppointmentStatus.confirmed:
        return const Color(0xFF0369A1);
      case AppointmentStatus.completed:
        return const Color(0xFF059669);
      case AppointmentStatus.cancelled:
        return const Color(0xFFDC2626);
      case AppointmentStatus.noShow:
        return const Color(0xFF7C3AED);
    }
  }

  Future<Map<String, dynamic>?> _promptCompletionDetails(
    BuildContext context,
  ) async {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const _CompletionDetailsDialog(),
    );
  }

  Future<Map<String, dynamic>?> _promptNoShowDetails(BuildContext context) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mark No-show'),
          content: const Text('Who missed this session?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Back'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop({'attendanceStatus': 'student_no_show'}),
              child: const Text('Student No-show'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop({'attendanceStatus': 'counselor_no_show'}),
              child: const Text('Counselor No-show'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptCancellationReason(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Appointment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Optionally share a short reason with the student.'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Example: I have an urgent conflict this morning.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Cancel Session'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
    AppointmentStatus status,
  ) async {
    String? cancellationMessage;
    String? attendanceStatus;
    String? sessionNote;
    List<String> actionItems = const <String>[];
    List<String> goals = const <String>[];
    if (status == AppointmentStatus.cancelled) {
      final decision = await _promptCancellationReason(context);
      if (!context.mounted || decision == null) {
        return;
      }
      cancellationMessage = decision;
    }
    if (status == AppointmentStatus.noShow) {
      final details = await _promptNoShowDetails(context);
      if (!context.mounted || details == null) {
        return;
      }
      attendanceStatus = details['attendanceStatus'] as String?;
    }
    if (status == AppointmentStatus.completed) {
      final details = await _promptCompletionDetails(context);
      if (!context.mounted || details == null) {
        return;
      }
      sessionNote = details['sessionNote'] as String?;
      actionItems = (details['actionItems'] as List<dynamic>)
          .map((entry) => entry.toString())
          .toList(growable: false);
      goals = (details['recommendedGoals'] as List<dynamic>)
          .map((entry) => entry.toString())
          .toList(growable: false);
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .updateAppointmentByCounselor(
            appointment: appointment,
            newStatus: status,
            counselorCancelMessage: cancellationMessage,
            attendanceStatus: attendanceStatus,
            counselorSessionNote: sessionNote,
            counselorActionItems: actionItems,
            recommendedGoals: goals,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AppointmentStatus.cancelled
                ? 'Appointment cancelled and student notified.'
                : status == AppointmentStatus.noShow
                ? 'No-show status saved.'
                : 'Appointment marked as ${status.name}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _navigateSection(
    BuildContext context,
    CounselorWorkspaceNavSection section,
  ) {
    switch (section) {
      case CounselorWorkspaceNavSection.dashboard:
        context.go(AppRoute.counselorDashboard);
      case CounselorWorkspaceNavSection.sessions:
        context.go(AppRoute.counselorAppointments);
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
    }
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required UserProfile profile,
    required CounselorWorkflowSettings workflowSettings,
    required List<AppointmentRecord> appointments,
    required bool loading,
  }) {
    final sorted = [...appointments]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final now = DateTime.now().toUtc();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final pending = sorted
        .where((entry) => entry.status == AppointmentStatus.pending)
        .length;
    final confirmed = sorted
        .where((entry) => entry.status == AppointmentStatus.confirmed)
        .length;
    final completed = sorted
        .where((entry) => entry.status == AppointmentStatus.completed)
        .length;
    final todayCount = sorted
        .where(
          (entry) =>
              !entry.startAt.isBefore(todayStart) &&
              entry.startAt.isBefore(todayEnd),
        )
        .length;
    final nextLive = sorted.cast<AppointmentRecord?>().firstWhere(
      (entry) => entry != null && entry.startAt.isAfter(now),
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppointmentsHero(
          nextLive: nextLive,
          total: sorted.length,
          onOpenNotifications: () => context.go(AppRoute.notifications),
          onOpenDirectory: workflowSettings.directoryEnabled
              ? () => context.go(AppRoute.counselorDirectory)
              : null,
        ),
        const SizedBox(height: 20),
        _ReassignmentBoardModule(
          profile: profile,
          workflowSettings: workflowSettings,
          onOpenSession: (appointmentId) {
            context.go(
              Uri(
                path: AppRoute.sessionDetails,
                queryParameters: <String, String>{
                  'appointmentId': appointmentId,
                },
              ).toString(),
            );
          },
          onOpenDirectory: () => context.go(AppRoute.counselorDirectory),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SessionStatCard(
              label: 'Today',
              value: '$todayCount',
              hint: 'scheduled sessions',
              accent: const Color(0xFF0E9B90),
            ),
            _SessionStatCard(
              label: 'Pending',
              value: '$pending',
              hint: 'waiting response',
              accent: const Color(0xFFF59E0B),
            ),
            _SessionStatCard(
              label: 'Confirmed',
              value: '$confirmed',
              hint: 'currently live',
              accent: const Color(0xFF2563EB),
            ),
            _SessionStatCard(
              label: 'Completed',
              value: '$completed',
              hint: 'recorded',
              accent: const Color(0xFF7C3AED),
            ),
          ].map((card) => SizedBox(width: 190, child: card)).toList(),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _ModuleEyebrow(
                            label: 'SESSION CONTROL',
                            color: Color(0xFF2563EB),
                            background: Color(0xFFEFF6FF),
                            border: Color(0xFFBFDBFE),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Counselor appointments',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF081A30),
                                ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Review pending requests, close completed sessions, and handle cancellations or no-shows from a stable workflow surface.',
                            style: TextStyle(
                              color: Color(0xFF6A7C93),
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 16),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                if (sorted.isEmpty)
                  const _EmptyModuleCard(
                    message:
                        'No appointments are visible yet. New booking requests will appear here as soon as students create them.',
                  )
                else
                  Column(
                    children: sorted
                        .map(
                          (appointment) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AppointmentPanelCard(
                              appointment: appointment,
                              statusColor: _statusColor(appointment.status),
                              formatDate: _formatDate,
                              onConfirm:
                                  appointment.status ==
                                      AppointmentStatus.pending
                                  ? () => _updateStatus(
                                      context,
                                      ref,
                                      appointment,
                                      AppointmentStatus.confirmed,
                                    )
                                  : null,
                              onCancel:
                                  appointment.status ==
                                          AppointmentStatus.pending ||
                                      appointment.status ==
                                          AppointmentStatus.confirmed
                                  ? () => _updateStatus(
                                      context,
                                      ref,
                                      appointment,
                                      AppointmentStatus.cancelled,
                                    )
                                  : null,
                              onNoShow:
                                  appointment.status ==
                                      AppointmentStatus.confirmed
                                  ? () => _updateStatus(
                                      context,
                                      ref,
                                      appointment,
                                      AppointmentStatus.noShow,
                                    )
                                  : null,
                              onComplete:
                                  appointment.status ==
                                      AppointmentStatus.confirmed
                                  ? () => _updateStatus(
                                      context,
                                      ref,
                                      appointment,
                                      AppointmentStatus.completed,
                                    )
                                  : null,
                              onOpenDetails: () => context.go(
                                Uri(
                                  path: AppRoute.sessionDetails,
                                  queryParameters: <String, String>{
                                    'appointmentId': appointment.id,
                                  },
                                ).toString(),
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.role != UserRole.counselor) {
      return const Scaffold(
        body: Center(
          child: _EmptyModuleCard(
            message: 'This page is available only for counselors.',
          ),
        ),
      );
    }

    final unreadCount =
        ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
    final workflowSettings =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile.institutionId ?? ''),
            )
            .valueOrNull ??
        const CounselorWorkflowSettings.disabled();

    return CounselorWorkspaceScaffold(
      profile: profile,
      activeSection: CounselorWorkspaceNavSection.sessions,
      unreadNotifications: unreadCount,
      title: 'Sessions',
      subtitle:
          'Keep booking requests, live appointments, and session outcomes in one stable counselor workflow.',
      onSelectSection: (section) => _navigateSection(context, section),
      onNotifications: () => context.go(AppRoute.notifications),
      onProfile: () => context.go(AppRoute.counselorSettings),
      onLogout: () => confirmAndLogout(context: context, ref: ref),
      child: StreamBuilder<List<AppointmentRecord>>(
        stream: ref
            .read(careRepositoryProvider)
            .watchCounselorAppointments(
              institutionId: profile.institutionId ?? '',
              counselorId: profile.id,
            ),
        builder: (context, snapshot) {
          final appointments = snapshot.data ?? const <AppointmentRecord>[];
          return _buildBody(
            context,
            ref,
            profile: profile,
            workflowSettings: workflowSettings,
            appointments: appointments,
            loading:
                snapshot.connectionState == ConnectionState.waiting &&
                appointments.isEmpty,
          );
        },
      ),
    );
  }
}

class _AppointmentsHero extends StatelessWidget {
  const _AppointmentsHero({
    required this.nextLive,
    required this.total,
    required this.onOpenNotifications,
    required this.onOpenDirectory,
  });

  final AppointmentRecord? nextLive;
  final int total;
  final VoidCallback onOpenNotifications;
  final VoidCallback? onOpenDirectory;

  String _formatHeadline(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[local.weekday - 1]} ${local.day} at $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

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
          final stacked = constraints.maxWidth < 820;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ModuleEyebrow(
                label: 'COUNSELOR APPOINTMENTS',
                color: Color(0xFFFDE68A),
                background: Color(0x24FFFFFF),
                border: Color(0x44FFFFFF),
              ),
              const SizedBox(height: 16),
              Text(
                nextLive == null
                    ? 'No live session is queued right now.'
                    : 'Next session is ${_formatHeadline(nextLive!.startAt)}.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.04,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This screen keeps the active counseling queue visible while preserving fast status actions for each session.',
                style: TextStyle(
                  color: Color(0xFFD7E5F0),
                  fontSize: 15.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenNotifications,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0C2233),
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Open Notifications'),
              ),
              if (onOpenDirectory != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onOpenDirectory,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x48FFFFFF)),
                  ),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: const Text('Counselor Directory'),
                ),
              ],
            ],
          );

          final sideCard = Container(
            width: stacked ? double.infinity : 270,
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
                  'Queue pulse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _MiniSignal(
                  label: 'Sessions visible',
                  value: '$total',
                  tone: const Color(0xFFFDE68A),
                ),
                const SizedBox(height: 10),
                _MiniSignal(
                  label: 'Next live status',
                  value: nextLive == null ? 'idle' : 'queued',
                  tone: nextLive == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF10B981),
                ),
              ],
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [intro, const SizedBox(height: 18), sideCard],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intro),
              const SizedBox(width: 18),
              sideCard,
            ],
          );
        },
      ),
    );
  }
}

class _SessionStatCard extends StatelessWidget {
  const _SessionStatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
  });

  final String label;
  final String value;
  final String hint;
  final Color accent;

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
            label.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF081A30),
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              color: Color(0xFF7B8CA4),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReassignmentBoardModule extends ConsumerWidget {
  const _ReassignmentBoardModule({
    required this.profile,
    required this.workflowSettings,
    required this.onOpenSession,
    required this.onOpenDirectory,
  });

  final UserProfile profile;
  final CounselorWorkflowSettings workflowSettings;
  final ValueChanged<String> onOpenSession;
  final VoidCallback onOpenDirectory;

  String _formatSlot(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!workflowSettings.reassignmentEnabled) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFDDE6EE)),
        ),
        child: const Text(
          'Counselor-to-counselor reassignment requests are disabled for this institution.',
          style: TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      );
    }

    return StreamBuilder<List<SessionReassignmentRequest>>(
      stream: ref
          .read(careRepositoryProvider)
          .watchInstitutionReassignmentBoard(
            institutionId: profile.institutionId ?? '',
          ),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <SessionReassignmentRequest>[];
        for (final request in requests) {
          final nowUtc = DateTime.now().toUtc();
          final responseExpired =
              request.status == SessionReassignmentStatus.openForResponses &&
              nowUtc.isAfter(request.responseDeadlineAt);
          final choiceExpired =
              request.status ==
                  SessionReassignmentStatus.awaitingPatientChoice &&
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
        final mine = requests
            .where((entry) => entry.originalCounselorId == profile.id)
            .toList(growable: false);
        final others = requests
            .where((entry) => entry.originalCounselorId != profile.id)
            .toList(growable: false);

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDDE6EE)),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ModuleEyebrow(
                          label: 'REASSIGNMENT BOARD',
                          color: Color(0xFF7C3AED),
                          background: Color(0xFFF5F3FF),
                          border: Color(0xFFDDD6FE),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Counselor coverage requests',
                          style: TextStyle(
                            color: Color(0xFF081A30),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Respond to peer coverage requests here. Original counselors still control the patient conversation and final handoff.',
                          style: TextStyle(
                            color: Color(0xFF6A7C93),
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (workflowSettings.directoryEnabled)
                    OutlinedButton.icon(
                      onPressed: onOpenDirectory,
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('Directory'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (requests.isEmpty)
                const _EmptyModuleCard(
                  message:
                      'No reassignment requests are open right now. When a counselor needs replacement coverage, it will appear here.',
                )
              else ...[
                if (mine.isNotEmpty) ...[
                  const Text(
                    'Your requests',
                    style: TextStyle(
                      color: Color(0xFF081A30),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...mine.map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReassignmentRequestCard(
                        request: request,
                        currentCounselorId: profile.id,
                        formatSlot: _formatSlot,
                        onOpenSession: () =>
                            onOpenSession(request.appointmentId),
                        onExpressInterest: null,
                      ),
                    ),
                  ),
                ],
                if (others.isNotEmpty) ...[
                  if (mine.isNotEmpty) const SizedBox(height: 6),
                  const Text(
                    'Requests from other counselors',
                    style: TextStyle(
                      color: Color(0xFF081A30),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...others.map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReassignmentRequestCard(
                        request: request,
                        currentCounselorId: profile.id,
                        formatSlot: _formatSlot,
                        onOpenSession: () =>
                            onOpenSession(request.appointmentId),
                        onExpressInterest:
                            request.status ==
                                    SessionReassignmentStatus
                                        .openForResponses &&
                                !request.interestedCounselors.any(
                                  (entry) => entry.counselorId == profile.id,
                                )
                            ? () async {
                                try {
                                  await ref
                                      .read(careRepositoryProvider)
                                      .expressInterestInReassignment(
                                        request.id,
                                      );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'You were added to the interested counselors list.',
                                      ),
                                    ),
                                  );
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReassignmentRequestCard extends StatelessWidget {
  const _ReassignmentRequestCard({
    required this.request,
    required this.currentCounselorId,
    required this.formatSlot,
    required this.onOpenSession,
    required this.onExpressInterest,
  });

  final SessionReassignmentRequest request;
  final String currentCounselorId;
  final String Function(DateTime value) formatSlot;
  final VoidCallback onOpenSession;
  final VoidCallback? onExpressInterest;

  @override
  Widget build(BuildContext context) {
    final alreadyInterested = request.interestedCounselors.any(
      (entry) => entry.counselorId == currentCounselorId,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _RequestPill(label: request.status.wireName.replaceAll('_', ' ')),
              _RequestPill(
                label:
                    '${request.interestedCounselors.length}/${request.maxInterestedCounselors} interested',
              ),
              if (request.originalCounselorRecommendationId ==
                  currentCounselorId)
                const _RequestPill(label: 'recommended by counselor A'),
              if (request.selectedCounselorId == currentCounselorId)
                const _RequestPill(label: 'selected by patient'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.requiredSpecialization.trim().isEmpty
                ? 'Coverage needed'
                : request.requiredSpecialization,
            style: const TextStyle(
              color: Color(0xFF081A30),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatSlot(request.sessionStartAt)} - ${formatSlot(request.sessionEndAt)}',
            style: const TextStyle(
              color: Color(0xFF5E728D),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mode: ${request.sessionMode}',
            style: const TextStyle(
              color: Color(0xFF6A7C93),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (request.originalCounselorId == currentCounselorId)
                OutlinedButton.icon(
                  onPressed: onOpenSession,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open Session'),
                ),
              if (onExpressInterest != null)
                FilledButton.icon(
                  onPressed: onExpressInterest,
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('I Can Take It'),
                )
              else if (alreadyInterested)
                const _RequestPill(label: 'you already responded'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestPill extends StatelessWidget {
  const _RequestPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E1EA)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AppointmentPanelCard extends StatelessWidget {
  const _AppointmentPanelCard({
    required this.appointment,
    required this.statusColor,
    required this.formatDate,
    required this.onOpenDetails,
    required this.onConfirm,
    required this.onCancel,
    required this.onNoShow,
    required this.onComplete,
  });

  final AppointmentRecord appointment;
  final Color statusColor;
  final String Function(DateTime value) formatDate;
  final VoidCallback onOpenDetails;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onNoShow;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.studentName ?? appointment.studentId,
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatDate(appointment.startAt)} - ${formatDate(appointment.endAt)}',
                      style: const TextStyle(
                        color: Color(0xFF5E728D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  appointment.status.name,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (appointment.status == AppointmentStatus.noShow &&
                  (appointment.attendanceStatus ?? '').trim().isNotEmpty)
                _InlineNoteCard(
                  tone: const Color(0xFF7C3AED),
                  background: const Color(0xFFF5F3FF),
                  text: 'Attendance: ${appointment.attendanceStatus}',
                ),
              if (appointment.status == AppointmentStatus.cancelled &&
                  (appointment.counselorCancelMessage ?? '').trim().isNotEmpty)
                _InlineNoteCard(
                  tone: const Color(0xFF9A3412),
                  background: const Color(0xFFFFF7ED),
                  text:
                      'Message sent: ${appointment.counselorCancelMessage!.trim()}',
                ),
              if (appointment.status == AppointmentStatus.completed &&
                  (appointment.counselorSessionNote ?? '').trim().isNotEmpty)
                _InlineNoteCard(
                  tone: const Color(0xFF0C4A6E),
                  background: const Color(0xFFEFF6FF),
                  text:
                      'Session note: ${appointment.counselorSessionNote!.trim()}',
                ),
            ],
          ),
          if (appointment.status == AppointmentStatus.completed &&
              appointment.counselorActionItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Action items: ${appointment.counselorActionItems.join(', ')}',
              style: const TextStyle(
                color: Color(0xFF415A77),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Detail'),
              ),
              if (onConfirm != null)
                OutlinedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Confirm'),
                ),
              if (onCancel != null)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              if (onNoShow != null)
                OutlinedButton.icon(
                  onPressed: onNoShow,
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('Mark No-show'),
                ),
              if (onComplete != null)
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Mark Completed'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineNoteCard extends StatelessWidget {
  const _InlineNoteCard({
    required this.tone,
    required this.background,
    required this.text,
  });

  final Color tone;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: tone, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ModuleEyebrow extends StatelessWidget {
  const _ModuleEyebrow({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
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

class _EmptyModuleCard extends StatelessWidget {
  const _EmptyModuleCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 540),
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
          height: 1.45,
        ),
      ),
    );
  }
}

enum _VoiceInputField { sessionNote, actionItems, careGoals }

class _CompletionDetailsDialog extends StatefulWidget {
  const _CompletionDetailsDialog();

  @override
  State<_CompletionDetailsDialog> createState() =>
      _CompletionDetailsDialogState();
}

class _CompletionDetailsDialogState extends State<_CompletionDetailsDialog> {
  final _noteController = TextEditingController();
  final _actionItemsController = TextEditingController();
  final _goalsController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _isInitializingVoice = false;
  _VoiceInputField? _activeField;
  String _baselineText = '';
  String? _voiceError;
  bool _permissionPromptShown = false;

  @override
  void initState() {
    super.initState();
    _initializeVoice(promptIfUnavailable: true);
  }

  @override
  void dispose() {
    _speech.stop();
    _noteController.dispose();
    _actionItemsController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  Future<void> _initializeVoice({bool promptIfUnavailable = false}) async {
    if (mounted) {
      setState(() {
        _isInitializingVoice = true;
      });
    }
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          if (status == 'notListening' || status == 'done') {
            setState(() {
              _isListening = false;
              _activeField = null;
            });
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isListening = false;
            _activeField = null;
            _voiceError = _friendlyVoiceError(error.errorMsg);
          });
        },
      );
      if (!mounted) {
        return;
      }
      final rawError = _speech.lastError?.errorMsg;
      setState(() {
        _speechReady = ready;
        if (!ready) {
          _voiceError = _friendlyVoiceError(rawError);
        } else {
          _voiceError = null;
        }
        _isInitializingVoice = false;
      });
      if (!ready && promptIfUnavailable && _shouldPromptPermission(rawError)) {
        _showPermissionPromptOnce();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
        _voiceError = _friendlyVoiceError(null);
        _isInitializingVoice = false;
      });
      if (promptIfUnavailable && _shouldPromptPermission(null)) {
        _showPermissionPromptOnce();
      }
    }
  }

  bool _isUnsupportedError(String? rawError) {
    final normalized = (rawError ?? '').toLowerCase();
    return normalized.contains('not supported') ||
        normalized.contains('speech_not_supported') ||
        normalized.contains('unsupported');
  }

  bool _isPermissionError(String? rawError) {
    final normalized = (rawError ?? '').toLowerCase();
    return normalized.contains('not-allowed') ||
        normalized.contains('service-not-allowed') ||
        normalized.contains('permission');
  }

  bool _shouldPromptPermission(String? rawError) {
    if (_isUnsupportedError(rawError)) {
      return false;
    }
    return true;
  }

  String _friendlyVoiceError(String? rawError) {
    if (_isUnsupportedError(rawError)) {
      if (kIsWeb) {
        return 'Voice dictation is not supported in this browser. Use latest Chrome or Edge.';
      }
      return 'Voice dictation is not supported on this device.';
    }
    if (_isPermissionError(rawError)) {
      if (kIsWeb) {
        return 'Microphone is blocked for this site. Allow mic in browser settings and reload this tab.';
      }
      return 'Microphone permission is required for voice dictation.';
    }
    if (rawError != null && rawError.trim().isNotEmpty) {
      return 'Voice input error: $rawError';
    }
    if (kIsWeb) {
      return 'Voice input is unavailable on web right now. Check browser support and microphone access.';
    }
    return 'Voice input could not start on this device.';
  }

  void _showPermissionPromptOnce() {
    if (_permissionPromptShown || !mounted) {
      return;
    }
    _permissionPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final shouldRetry = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enable Microphone'),
            content: const Text(
              'To auto-fill text while you speak, allow microphone access for MindNest.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Enable Mic'),
              ),
            ],
          );
        },
      );
      if (!mounted || shouldRetry != true) {
        return;
      }
      await _initializeVoice();
      if (!mounted || _speechReady) {
        return;
      }
      setState(() {
        _voiceError =
            'Microphone still unavailable. Enable it in system app settings and try again.';
      });
    });
  }

  TextEditingController _controllerFor(_VoiceInputField field) {
    switch (field) {
      case _VoiceInputField.sessionNote:
        return _noteController;
      case _VoiceInputField.actionItems:
        return _actionItemsController;
      case _VoiceInputField.careGoals:
        return _goalsController;
    }
  }

  Future<void> _toggleListening(_VoiceInputField field) async {
    if (!_speechReady) {
      await _initializeVoice();
      if (!mounted || _speechReady) {
        return;
      }
      setState(() {
        _voiceError = _friendlyVoiceError(_speech.lastError?.errorMsg);
      });
      return;
    }
    if (_isListening && _activeField == field) {
      await _speech.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _activeField = null;
      });
      return;
    }

    if (_isListening) {
      await _speech.stop();
    }

    final controller = _controllerFor(field);
    _baselineText = controller.text.trim();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceError = null;
      _isListening = true;
      _activeField = field;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }
        final transcript = result.recognizedWords.trim();
        final combined = transcript.isEmpty
            ? _baselineText
            : _baselineText.isEmpty
            ? transcript
            : '$_baselineText $transcript';

        final activeField = _activeField;
        if (activeField == null) {
          return;
        }
        final activeController = _controllerFor(activeField);
        activeController.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );

        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _activeField = null;
          });
        }
      },
      listenFor: const Duration(minutes: 3),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  List<String> _splitListInput(String rawValue) {
    return rawValue
        .split(RegExp(r'[,\n;]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _voiceButtonLabel(_VoiceInputField field) {
    final isActive = _isListening && _activeField == field;
    return isActive ? 'Stop Recording' : 'Use Voice';
  }

  IconData _voiceButtonIcon(_VoiceInputField field) {
    final isActive = _isListening && _activeField == field;
    return isActive ? Icons.stop_circle_rounded : Icons.mic_rounded;
  }

  Widget _buildVoiceField({
    required _VoiceInputField field,
    required String label,
    required String hint,
    required TextEditingController controller,
    int minLines = 1,
    int maxLines = 2,
    int? maxLength,
  }) {
    final isActive = _isListening && _activeField == field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _toggleListening(field),
              icon: Icon(_voiceButtonIcon(field), size: 18),
              label: Text(_voiceButtonLabel(field)),
              style: TextButton.styleFrom(
                foregroundColor: isActive
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0D9488),
              ),
            ),
          ],
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete Session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add post-session notes and action items. Use the microphone to dictate live.',
            ),
            const SizedBox(height: 10),
            if (_voiceError != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _voiceError!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_isInitializingVoice) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
            ],
            _buildVoiceField(
              field: _VoiceInputField.sessionNote,
              label: 'Session note',
              hint: 'Summary and recommendations for the student.',
              controller: _noteController,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            _buildVoiceField(
              field: _VoiceInputField.actionItems,
              label: 'Action items',
              hint: 'Comma/newline separated. Example: Breathing exercise',
              controller: _actionItemsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
            ),
            const SizedBox(height: 8),
            _buildVoiceField(
              field: _VoiceInputField.careGoals,
              label: 'Care goals',
              hint: 'Comma/newline separated. Example: Improve sleep schedule',
              controller: _goalsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Back'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop({
            'sessionNote': _noteController.text.trim(),
            'actionItems': _splitListInput(_actionItemsController.text),
            'recommendedGoals': _splitListInput(_goalsController.text),
          }),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}
