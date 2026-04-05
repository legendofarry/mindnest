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
import 'package:mindnest/core/ui/modern_banner.dart';

typedef _AppointmentStatusUpdater =
    Future<void> Function(
      AppointmentRecord appointment,
      AppointmentStatus status,
    );
typedef _AppointmentRouteOpener = void Function(AppointmentRecord appointment);
typedef _AppointmentDateFormatter = String Function(DateTime value);
typedef _AppointmentStatusColorResolver =
    Color Function(AppointmentStatus status);

enum _CounselorSessionTab { needsAction, upcoming, history, all }

enum _CounselorSessionSort { smart, soonest, latest, studentAz, studentZa }

enum _CounselorSessionViewMode { compact, timeline, table }

enum _CompactAppointmentAction { confirm, cancel, markNoShow, markCompleted }

DateTime _localDayStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _localNextDayStart(DateTime value) =>
    _localDayStart(value).add(const Duration(days: 1));

String _studentDisplayName(AppointmentRecord appointment) =>
    (appointment.studentName ?? '').trim().isEmpty
    ? appointment.studentId
    : appointment.studentName!.trim();

String _appointmentStatusLabel(AppointmentStatus status) {
  switch (status) {
    case AppointmentStatus.pending:
      return 'Pending';
    case AppointmentStatus.confirmed:
      return 'Confirmed';
    case AppointmentStatus.completed:
      return 'Completed';
    case AppointmentStatus.cancelled:
      return 'Cancelled';
    case AppointmentStatus.noShow:
      return 'No-show';
  }
}

String _sessionTabLabel(_CounselorSessionTab tab) {
  switch (tab) {
    case _CounselorSessionTab.needsAction:
      return 'Needs action';
    case _CounselorSessionTab.upcoming:
      return 'Upcoming';
    case _CounselorSessionTab.history:
      return 'History';
    case _CounselorSessionTab.all:
      return 'All sessions';
  }
}

String _sessionSortLabel(_CounselorSessionSort sort) {
  switch (sort) {
    case _CounselorSessionSort.smart:
      return 'Smart queue';
    case _CounselorSessionSort.soonest:
      return 'Soonest first';
    case _CounselorSessionSort.latest:
      return 'Latest first';
    case _CounselorSessionSort.studentAz:
      return 'Student A-Z';
    case _CounselorSessionSort.studentZa:
      return 'Student Z-A';
  }
}

String _sessionViewModeLabel(_CounselorSessionViewMode mode) {
  switch (mode) {
    case _CounselorSessionViewMode.compact:
      return 'Compact';
    case _CounselorSessionViewMode.timeline:
      return 'Timeline';
    case _CounselorSessionViewMode.table:
      return 'Table';
  }
}

bool _isHistoryAppointment(AppointmentRecord appointment) {
  return appointment.status == AppointmentStatus.completed ||
      appointment.status == AppointmentStatus.cancelled ||
      appointment.status == AppointmentStatus.noShow;
}

bool _isTodayAppointment(AppointmentRecord appointment, DateTime nowLocal) {
  final localStart = appointment.startAt.toLocal();
  final todayStart = _localDayStart(nowLocal);
  final tomorrowStart = _localNextDayStart(nowLocal);
  return !localStart.isBefore(todayStart) && localStart.isBefore(tomorrowStart);
}

bool _needsCounselorAttention(
  AppointmentRecord appointment,
  DateTime nowLocal,
) {
  if (appointment.status == AppointmentStatus.pending) {
    return true;
  }
  if (appointment.status != AppointmentStatus.confirmed) {
    return false;
  }
  final localStart = appointment.startAt.toLocal();
  final localEnd = appointment.endAt.toLocal();
  final tomorrowStart = _localNextDayStart(nowLocal);
  return !localEnd.isAfter(nowLocal) || localStart.isBefore(tomorrowStart);
}

bool _isUpcomingAppointment(AppointmentRecord appointment, DateTime nowLocal) {
  if (appointment.status != AppointmentStatus.confirmed) {
    return false;
  }
  final localStart = appointment.startAt.toLocal();
  return !localStart.isBefore(_localNextDayStart(nowLocal));
}

bool _matchesSessionTab(
  AppointmentRecord appointment,
  _CounselorSessionTab tab,
  DateTime nowLocal,
) {
  switch (tab) {
    case _CounselorSessionTab.needsAction:
      return _needsCounselorAttention(appointment, nowLocal);
    case _CounselorSessionTab.upcoming:
      return _isUpcomingAppointment(appointment, nowLocal);
    case _CounselorSessionTab.history:
      return _isHistoryAppointment(appointment);
    case _CounselorSessionTab.all:
      return true;
  }
}

String _appointmentCompactSummary(
  AppointmentRecord appointment,
  DateTime nowLocal,
) {
  switch (appointment.status) {
    case AppointmentStatus.pending:
      return 'Waiting for your approval or cancellation.';
    case AppointmentStatus.confirmed:
      if (appointment.endAt.toLocal().isBefore(nowLocal)) {
        return 'Session window passed. Record the outcome.';
      }
      if (_isTodayAppointment(appointment, nowLocal)) {
        return 'Scheduled for today. Keep an eye on timing and outcome.';
      }
      return 'Upcoming confirmed session.';
    case AppointmentStatus.completed:
      return 'Outcome saved for this session.';
    case AppointmentStatus.cancelled:
      return 'This session has been cancelled.';
    case AppointmentStatus.noShow:
      return 'No-show recorded for this session.';
  }
}

String _sessionDateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _sessionDateHeader(DateTime value) {
  final local = value.toLocal();
  final today = _localDayStart(DateTime.now());
  final target = _localDayStart(local);
  if (target == today) {
    return 'Today';
  }
  if (target == today.add(const Duration(days: 1))) {
    return 'Tomorrow';
  }
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _monthShortLabel(int month) {
  const months = <String>[
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
  return months[(month.clamp(1, 12)) - 1];
}

String _sessionDateSubheader(DateTime value) {
  final local = value.toLocal();
  return '${_monthShortLabel(local.month)} ${local.day}, ${local.year}';
}

String _sessionTimeRangeLabel(DateTime startAt, DateTime endAt) {
  String format(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  return '${format(startAt)} - ${format(endAt)}';
}

String _sessionDurationLabel(DateTime startAt, DateTime endAt) {
  final duration = endAt.difference(startAt);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) {
    return '${duration.inMinutes} min block';
  }
  if (minutes == 0) {
    return '${hours}h block';
  }
  return '${hours}h ${minutes}m block';
}

class CounselorAppointmentsScreen extends ConsumerWidget {
  const CounselorAppointmentsScreen({
    super.key,
    this.embeddedInCounselorShell = false,
  });

  final bool embeddedInCounselorShell;

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
      showModernBannerFromSnackBar(
        context,
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
      showModernBannerFromSnackBar(
        context,
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
      case CounselorWorkspaceNavSection.live:
        context.go(AppRoute.counselorLiveHub);
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
      case CounselorWorkspaceNavSection.counselors:
        context.go(AppRoute.counselorDirectory);
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
    final nowLocal = DateTime.now();
    final needsAction = sorted
        .where(
          (entry) => _matchesSessionTab(
            entry,
            _CounselorSessionTab.needsAction,
            nowLocal,
          ),
        )
        .length;
    final todayCount = sorted
        .where((entry) => _isTodayAppointment(entry, nowLocal))
        .length;
    final upcoming = sorted
        .where(
          (entry) => _matchesSessionTab(
            entry,
            _CounselorSessionTab.upcoming,
            nowLocal,
          ),
        )
        .length;
    final history = sorted
        .where(
          (entry) =>
              _matchesSessionTab(entry, _CounselorSessionTab.history, nowLocal),
        )
        .length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SessionStatCard(
              label: 'Needs Action',
              value: '$needsAction',
              hint: 'urgent queue',
              accent: const Color(0xFFF59E0B),
            ),
            _SessionStatCard(
              label: 'Today',
              value: '$todayCount',
              hint: 'scheduled sessions',
              accent: const Color(0xFF0E9B90),
            ),
            _SessionStatCard(
              label: 'Upcoming',
              value: '$upcoming',
              hint: 'later sessions',
              accent: const Color(0xFF2563EB),
            ),
            _SessionStatCard(
              label: 'History',
              value: '$history',
              hint: 'closed sessions',
              accent: const Color(0xFF7C3AED),
            ),
          ].map((card) => SizedBox(width: 190, child: card)).toList(),
        ),
        const SizedBox(height: 20),
        _CounselorSessionsWorkbench(
          appointments: sorted,
          loading: loading,
          formatDate: _formatDate,
          statusColorFor: _statusColor,
          onUpdateStatus: (appointment, status) =>
              _updateStatus(context, ref, appointment, status),
          onOpenDetails: (appointment) => context.go(
            Uri(
              path: AppRoute.sessionDetails,
              queryParameters: <String, String>{
                'appointmentId': appointment.id,
              },
            ).toString(),
          ),
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
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return content;
        }
        return SingleChildScrollView(
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
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

    final workflowSettings =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile.institutionId ?? ''),
            )
            .valueOrNull ??
        const CounselorWorkflowSettings.disabled();

    final appointmentsBody = StreamBuilder<List<AppointmentRecord>>(
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
    );

    if (embeddedInCounselorShell) {
      return appointmentsBody;
    }

    final unreadCount =
        ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;

    return CounselorWorkspaceScaffold(
      profile: profile,
      activeSection: CounselorWorkspaceNavSection.sessions,
      showCounselorDirectory: workflowSettings.directoryEnabled,
      unreadNotifications: unreadCount,
      title: 'Sessions',
      subtitle:
          'Keep booking requests, live appointments, and session outcomes in one stable counselor workflow.',
      onSelectSection: (section) => _navigateSection(context, section),
      onNotifications: () => context.go(AppRoute.notifications),
      onProfile: () => context.go(AppRoute.counselorSettings),
      onLogout: () => confirmAndLogout(context: context, ref: ref),
      child: appointmentsBody,
    );
  }
}

class _CounselorSessionsWorkbench extends StatefulWidget {
  const _CounselorSessionsWorkbench({
    required this.appointments,
    required this.loading,
    required this.formatDate,
    required this.statusColorFor,
    required this.onUpdateStatus,
    required this.onOpenDetails,
  });

  final List<AppointmentRecord> appointments;
  final bool loading;
  final _AppointmentDateFormatter formatDate;
  final _AppointmentStatusColorResolver statusColorFor;
  final _AppointmentStatusUpdater onUpdateStatus;
  final _AppointmentRouteOpener onOpenDetails;

  @override
  State<_CounselorSessionsWorkbench> createState() =>
      _CounselorSessionsWorkbenchState();
}

class _CounselorSessionsWorkbenchState
    extends State<_CounselorSessionsWorkbench> {
  final TextEditingController _searchController = TextEditingController();

  _CounselorSessionTab _activeTab = _CounselorSessionTab.needsAction;
  _CounselorSessionSort _sort = _CounselorSessionSort.smart;
  AppointmentStatus? _statusFilter;
  bool _showExtendedRows = false;
  int _page = 0;

  _CounselorSessionViewMode _viewMode = _CounselorSessionViewMode.compact;

  static const int _baseRowsPerPage = 3;
  static const int _expandedRowsPerPage = 10;

  int get _rowsPerPage =>
      _showExtendedRows ? _expandedRowsPerPage : _baseRowsPerPage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CounselorSessionsWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointments.length != widget.appointments.length) {
      final totalRows = _applyFilters().length;
      final totalPages = totalRows == 0
          ? 1
          : ((totalRows - 1) ~/ _rowsPerPage) + 1;
      if (_page >= totalPages) {
        setState(() => _page = totalPages - 1);
      }
    }
  }

  List<AppointmentRecord> _applyFilters() {
    final nowLocal = DateTime.now();
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.appointments
        .where((appointment) {
          if (!_matchesSessionTab(appointment, _activeTab, nowLocal)) {
            return false;
          }
          if (_statusFilter != null && appointment.status != _statusFilter) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = <String>[
            _studentDisplayName(appointment),
            _appointmentStatusLabel(appointment.status),
            widget.formatDate(appointment.startAt),
            widget.formatDate(appointment.endAt),
            appointment.attendanceStatus ?? '',
            appointment.counselorSessionNote ?? '',
            appointment.counselorCancelMessage ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);

    if (_viewMode == _CounselorSessionViewMode.timeline) {
      filtered.sort((left, right) => left.startAt.compareTo(right.startAt));
      return filtered;
    }

    filtered.sort((left, right) {
      switch (_sort) {
        case _CounselorSessionSort.smart:
          final leftPriority = _priorityFor(left, nowLocal);
          final rightPriority = _priorityFor(right, nowLocal);
          if (leftPriority != rightPriority) {
            return leftPriority.compareTo(rightPriority);
          }
          if (_isHistoryAppointment(left) && _isHistoryAppointment(right)) {
            return right.startAt.compareTo(left.startAt);
          }
          return left.startAt.compareTo(right.startAt);
        case _CounselorSessionSort.soonest:
          return left.startAt.compareTo(right.startAt);
        case _CounselorSessionSort.latest:
          return right.startAt.compareTo(left.startAt);
        case _CounselorSessionSort.studentAz:
          return _studentDisplayName(
            left,
          ).compareTo(_studentDisplayName(right));
        case _CounselorSessionSort.studentZa:
          return _studentDisplayName(
            right,
          ).compareTo(_studentDisplayName(left));
      }
    });

    return filtered;
  }

  int _priorityFor(AppointmentRecord appointment, DateTime nowLocal) {
    if (appointment.status == AppointmentStatus.pending) {
      return 0;
    }
    if (appointment.status == AppointmentStatus.confirmed &&
        appointment.endAt.toLocal().isBefore(nowLocal)) {
      return 1;
    }
    if (appointment.status == AppointmentStatus.confirmed &&
        _isTodayAppointment(appointment, nowLocal)) {
      return 2;
    }
    if (appointment.status == AppointmentStatus.confirmed) {
      return 3;
    }
    if (appointment.status == AppointmentStatus.completed) {
      return 4;
    }
    if (appointment.status == AppointmentStatus.noShow) {
      return 5;
    }
    return 6;
  }

  int _countForTab(_CounselorSessionTab tab) {
    final nowLocal = DateTime.now();
    return widget.appointments
        .where((appointment) => _matchesSessionTab(appointment, tab, nowLocal))
        .length;
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _statusFilter != null ||
        _sort != _CounselorSessionSort.smart ||
        _activeTab != _CounselorSessionTab.needsAction ||
        _viewMode != _CounselorSessionViewMode.compact ||
        _showExtendedRows;
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _activeTab = _CounselorSessionTab.needsAction;
      _sort = _CounselorSessionSort.smart;
      _statusFilter = null;
      _showExtendedRows = false;
      _page = 0;
      _viewMode = _CounselorSessionViewMode.compact;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filtered = _applyFilters();
        final totalRows = filtered.length;
        final totalPages = totalRows == 0
            ? 1
            : ((totalRows - 1) ~/ _rowsPerPage) + 1;
        final safePage = _page >= totalPages ? totalPages - 1 : _page;
        final pageRows = filtered
            .skip(safePage * _rowsPerPage)
            .take(_rowsPerPage)
            .toList(growable: false);

        return Container(
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
                          Text(
                            widget.appointments.isEmpty
                                ? 'New booking requests and active appointments will appear here as soon as students create them.'
                                : 'Start in compact mode for fast scanning, then flip to timeline or table when you need broader context.',
                            style: const TextStyle(
                              color: Color(0xFF6A7C93),
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.loading) ...[
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
                _SessionQueueBanner(
                  needsActionCount: _countForTab(
                    _CounselorSessionTab.needsAction,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _CounselorSessionTab.values
                      .map(
                        (tab) => _SessionTabChip(
                          label: _sessionTabLabel(tab),
                          count: _countForTab(tab),
                          selected: _activeTab == tab,
                          onTap: () => setState(() {
                            _activeTab = tab;
                            _page = 0;
                          }),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth > 1180 ? 290 : 250,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() => _page = 0),
                        decoration: InputDecoration(
                          hintText: 'Search sessions',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _page = 0);
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    _WorkbenchMenuButton<_CounselorSessionSort>(
                      icon: Icons.swap_vert_rounded,
                      label: 'Sort',
                      valueLabel: _sessionSortLabel(_sort),
                      active: _sort != _CounselorSessionSort.smart,
                      options: _CounselorSessionSort.values
                          .map(
                            (sort) => _WorkbenchMenuOption(
                              value: sort,
                              label: _sessionSortLabel(sort),
                            ),
                          )
                          .toList(growable: false),
                      currentValue: _sort,
                      onSelected: (value) => setState(() {
                        _sort = value;
                        _page = 0;
                      }),
                    ),
                    _WorkbenchMenuButton<AppointmentStatus?>(
                      icon: Icons.flag_rounded,
                      label: 'Status',
                      valueLabel: _statusFilter == null
                          ? 'All statuses'
                          : _appointmentStatusLabel(_statusFilter!),
                      active: _statusFilter != null,
                      options: <_WorkbenchMenuOption<AppointmentStatus?>>[
                        const _WorkbenchMenuOption<AppointmentStatus?>(
                          value: null,
                          label: 'All statuses',
                        ),
                        ...AppointmentStatus.values.map(
                          (status) => _WorkbenchMenuOption<AppointmentStatus?>(
                            value: status,
                            label: _appointmentStatusLabel(status),
                          ),
                        ),
                      ],
                      currentValue: _statusFilter,
                      onSelected: (value) => setState(() {
                        _statusFilter = value;
                        _page = 0;
                      }),
                    ),
                    _SessionViewToggle(
                      selected: _viewMode,
                      onChanged: (mode) => setState(() {
                        _viewMode = mode;
                        _page = 0;
                      }),
                    ),
                    _RowsVisibilityButton(
                      expanded: _showExtendedRows,
                      enabled:
                          totalRows > _baseRowsPerPage || _showExtendedRows,
                      onTap: () => setState(() {
                        _showExtendedRows = !_showExtendedRows;
                        _page = 0;
                      }),
                    ),
                    if (_hasActiveFilters)
                      OutlinedButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SessionResultsMeta(
                  resultsShown: pageRows.length,
                  totalResults: totalRows,
                  page: safePage,
                  totalPages: totalPages,
                  tabLabel: _sessionTabLabel(_activeTab),
                  viewMode: _viewMode,
                  rowsPerPage: _rowsPerPage,
                ),
                const SizedBox(height: 14),
                if (widget.appointments.isEmpty)
                  const _EmptyModuleCard(
                    message:
                        'No appointments are visible yet. New booking requests will appear here as soon as students create them.',
                  )
                else if (pageRows.isEmpty)
                  const _EmptyModuleCard(
                    message:
                        'No sessions match the current search, filter, or queue view.',
                  )
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: switch (_viewMode) {
                      _CounselorSessionViewMode.compact =>
                        _CompactAppointmentsViewport(
                          key: const ValueKey('compact'),
                          appointments: pageRows,
                          minVisibleRows: _baseRowsPerPage,
                          formatDate: widget.formatDate,
                          statusColorFor: widget.statusColorFor,
                          onOpenDetails: widget.onOpenDetails,
                          onUpdateStatus: widget.onUpdateStatus,
                        ),
                      _CounselorSessionViewMode.timeline =>
                        _TimelineAppointmentsViewport(
                          key: const ValueKey('timeline'),
                          appointments: pageRows,
                          formatDate: widget.formatDate,
                          statusColorFor: widget.statusColorFor,
                          onOpenDetails: widget.onOpenDetails,
                          onUpdateStatus: widget.onUpdateStatus,
                        ),
                      _CounselorSessionViewMode.table =>
                        _TableAppointmentsViewport(
                          key: const ValueKey('table'),
                          appointments: pageRows,
                          formatDate: widget.formatDate,
                          statusColorFor: widget.statusColorFor,
                          onOpenDetails: widget.onOpenDetails,
                          onUpdateStatus: widget.onUpdateStatus,
                        ),
                    },
                  ),
                if (totalRows > _rowsPerPage) ...[
                  const SizedBox(height: 14),
                  _SessionPager(
                    page: safePage,
                    totalPages: totalPages,
                    onPrevious: safePage == 0
                        ? null
                        : () => setState(() => _page = safePage - 1),
                    onNext: safePage >= totalPages - 1
                        ? null
                        : () => setState(() => _page = safePage + 1),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

class _SessionQueueBanner extends StatelessWidget {
  const _SessionQueueBanner({required this.needsActionCount});

  final int needsActionCount;

  @override
  Widget build(BuildContext context) {
    final hasUrgentWork = needsActionCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasUrgentWork
              ? const [Color(0xFFFFFBEB), Color(0xFFFFF7ED)]
              : const [Color(0xFFF0FDF9), Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasUrgentWork
              ? const Color(0xFFFED7AA)
              : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: hasUrgentWork
                  ? const Color(0xFFFFEDD5)
                  : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              hasUrgentWork
                  ? Icons.priority_high_rounded
                  : Icons.task_alt_rounded,
              color: hasUrgentWork
                  ? const Color(0xFFD97706)
                  : const Color(0xFF0369A1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUrgentWork
                      ? '$needsActionCount sessions need your attention.'
                      : 'Your queue is under control.',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasUrgentWork
                      ? 'Pending decisions and same-day follow-up stay grouped together so you do not miss the urgent bits.'
                      : 'Use timeline or table view when you want a broader scan of the queue.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.35,
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
}

class _SessionTabChip extends StatelessWidget {
  const _SessionTabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFE0F2FE),
      side: BorderSide(
        color: selected ? const Color(0xFF0EA5E9) : const Color(0xFFD3E0EE),
      ),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0C4A6E) : const Color(0xFF475569),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _WorkbenchMenuOption<T> {
  const _WorkbenchMenuOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class _WorkbenchMenuButton<T> extends StatelessWidget {
  const _WorkbenchMenuButton({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.options,
    required this.currentValue,
    required this.onSelected,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final List<_WorkbenchMenuOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onSelected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: currentValue,
      onSelected: onSelected,
      offset: const Offset(0, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      elevation: 10,
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<T>(
              value: option.value,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Icon(
                      option.value == currentValue
                          ? Icons.check_rounded
                          : (option.icon ?? Icons.circle_outlined),
                      size: option.value == currentValue ? 18 : 16,
                      color: option.value == currentValue
                          ? const Color(0xFF0EA5E9)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF0F172A),
                        fontWeight: option.value == currentValue
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF0F9FF) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? const Color(0xFF7DD3FC) : const Color(0xFFD7E5F1),
          ),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x120EA5E9),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFFDFF3FF)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: active
                    ? const Color(0xFF0369A1)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 168),
              child: Text(
                '$label: $valueLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowsVisibilityButton extends StatelessWidget {
  const _RowsVisibilityButton({
    required this.expanded,
    required this.enabled,
    required this.onTap,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: expanded ? const Color(0xFFEFF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: expanded
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFFD7E5F1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 18,
                color: const Color(0xFF475569),
              ),
              const SizedBox(width: 8),
              Text(
                expanded ? 'View less' : 'View more',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                expanded ? '10 rows' : '3 rows',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionViewToggle extends StatelessWidget {
  const _SessionViewToggle({required this.selected, required this.onChanged});

  final _CounselorSessionViewMode selected;
  final ValueChanged<_CounselorSessionViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildChip({
      required _CounselorSessionViewMode mode,
      required String label,
      required IconData icon,
    }) {
      final active = selected == mode;
      return ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? const Color(0xFF0C4A6E) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        selected: active,
        onSelected: (_) => onChanged(mode),
        selectedColor: const Color(0xFFE0F2FE),
        side: BorderSide(
          color: active ? const Color(0xFF0EA5E9) : const Color(0xFFD3E0EE),
        ),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xFF0C4A6E) : const Color(0xFF475569),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        buildChip(
          mode: _CounselorSessionViewMode.compact,
          label: 'Compact',
          icon: Icons.table_rows_rounded,
        ),
        buildChip(
          mode: _CounselorSessionViewMode.timeline,
          label: 'Timeline',
          icon: Icons.timeline_rounded,
        ),
        buildChip(
          mode: _CounselorSessionViewMode.table,
          label: 'Table',
          icon: Icons.grid_view_rounded,
        ),
      ],
    );
  }
}

class _SessionResultsMeta extends StatelessWidget {
  const _SessionResultsMeta({
    required this.resultsShown,
    required this.totalResults,
    required this.page,
    required this.totalPages,
    required this.tabLabel,
    required this.viewMode,
    required this.rowsPerPage,
  });

  final int resultsShown;
  final int totalResults;
  final int page;
  final int totalPages;
  final String tabLabel;
  final _CounselorSessionViewMode viewMode;
  final int rowsPerPage;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$resultsShown shown of $totalResults sessions in ${tabLabel.toLowerCase()}.',
          style: const TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w700,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD3E0EE)),
          ),
          child: Text(
            '${_sessionViewModeLabel(viewMode)} view · $rowsPerPage rows',
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (totalResults > 0)
          Text(
            'Page ${page + 1} of $totalPages',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _SessionPager extends StatelessWidget {
  const _SessionPager({
    required this.page,
    required this.totalPages,
    this.onPrevious,
    this.onNext,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Previous'),
        ),
        const SizedBox(width: 10),
        Text(
          'Page ${page + 1} of $totalPages',
          style: const TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Next'),
        ),
      ],
    );
  }
}

class _AppointmentOverflowMenu extends StatelessWidget {
  const _AppointmentOverflowMenu({
    this.onConfirm,
    this.onCancel,
    this.onNoShow,
    this.onComplete,
  });

  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onNoShow;
  final Future<void> Function()? onComplete;

  Future<void> _handleAction(_CompactAppointmentAction action) async {
    switch (action) {
      case _CompactAppointmentAction.confirm:
        if (onConfirm != null) {
          await onConfirm!();
        }
        return;
      case _CompactAppointmentAction.cancel:
        if (onCancel != null) {
          await onCancel!();
        }
        return;
      case _CompactAppointmentAction.markNoShow:
        if (onNoShow != null) {
          await onNoShow!();
        }
        return;
      case _CompactAppointmentAction.markCompleted:
        if (onComplete != null) {
          await onComplete!();
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CompactAppointmentAction>(
      tooltip: 'Session actions',
      onSelected: (value) {
        _handleAction(value);
      },
      itemBuilder: (context) => [
        if (onConfirm != null)
          const PopupMenuItem(
            value: _CompactAppointmentAction.confirm,
            child: Text('Confirm'),
          ),
        if (onCancel != null)
          const PopupMenuItem(
            value: _CompactAppointmentAction.cancel,
            child: Text('Cancel'),
          ),
        if (onNoShow != null)
          const PopupMenuItem(
            value: _CompactAppointmentAction.markNoShow,
            child: Text('Mark no-show'),
          ),
        if (onComplete != null)
          const PopupMenuItem(
            value: _CompactAppointmentAction.markCompleted,
            child: Text('Mark completed'),
          ),
      ],
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7E5F1)),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: Color(0xFF475569)),
      ),
    );
  }
}

class _CompactAppointmentsViewport extends StatelessWidget {
  const _CompactAppointmentsViewport({
    super.key,
    required this.appointments,
    required this.minVisibleRows,
    required this.formatDate,
    required this.statusColorFor,
    required this.onOpenDetails,
    required this.onUpdateStatus,
  });

  final List<AppointmentRecord> appointments;
  final int minVisibleRows;
  final _AppointmentDateFormatter formatDate;
  final _AppointmentStatusColorResolver statusColorFor;
  final _AppointmentRouteOpener onOpenDetails;
  final _AppointmentStatusUpdater onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minVisibleRows * 118),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E5F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < appointments.length; index++) ...[
            _CompactAppointmentRow(
              appointment: appointments[index],
              formatDate: formatDate,
              statusColor: statusColorFor(appointments[index].status),
              onOpenDetails: () => onOpenDetails(appointments[index]),
              onConfirm: appointments[index].status == AppointmentStatus.pending
                  ? () => onUpdateStatus(
                      appointments[index],
                      AppointmentStatus.confirmed,
                    )
                  : null,
              onCancel:
                  appointments[index].status == AppointmentStatus.pending ||
                      appointments[index].status == AppointmentStatus.confirmed
                  ? () => onUpdateStatus(
                      appointments[index],
                      AppointmentStatus.cancelled,
                    )
                  : null,
              onNoShow:
                  appointments[index].status == AppointmentStatus.confirmed
                  ? () => onUpdateStatus(
                      appointments[index],
                      AppointmentStatus.noShow,
                    )
                  : null,
              onComplete:
                  appointments[index].status == AppointmentStatus.confirmed
                  ? () => onUpdateStatus(
                      appointments[index],
                      AppointmentStatus.completed,
                    )
                  : null,
            ),
            if (index != appointments.length - 1)
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          ],
        ],
      ),
    );
  }
}

class _TimelineAppointmentsViewport extends StatelessWidget {
  const _TimelineAppointmentsViewport({
    super.key,
    required this.appointments,
    required this.formatDate,
    required this.statusColorFor,
    required this.onOpenDetails,
    required this.onUpdateStatus,
  });

  final List<AppointmentRecord> appointments;
  final _AppointmentDateFormatter formatDate;
  final _AppointmentStatusColorResolver statusColorFor;
  final _AppointmentRouteOpener onOpenDetails;
  final _AppointmentStatusUpdater onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final orderedAppointments = appointments.toList(growable: false)
      ..sort((left, right) => left.startAt.compareTo(right.startAt));
    final grouped = <String, List<AppointmentRecord>>{};
    final dates = <String, DateTime>{};
    for (final appointment in orderedAppointments) {
      final key = _sessionDateKey(appointment.startAt);
      grouped.putIfAbsent(key, () => <AppointmentRecord>[]).add(appointment);
      dates[key] = appointment.startAt.toLocal();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 1080;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: grouped.entries
              .map((entry) {
                final date = dates[entry.key]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFD),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFD7E5F1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.timeline_rounded,
                                  size: 20,
                                  color: Color(0xFF0369A1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _sessionDateHeader(date),
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _sessionDateSubheader(date),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _TimelineCountPill(count: entry.value.length),
                            ],
                          ),
                        ),
                        if (wideLayout) ...[
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFD7E5F1),
                          ),
                          const _TimelineAppointmentsHeaderRow(),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFD7E5F1),
                          ),
                        ],
                        ...entry.value.asMap().entries.map((timelineEntry) {
                          final appointment = timelineEntry.value;
                          return Column(
                            children: [
                              _TimelineAppointmentTile(
                                appointment: appointment,
                                formatDate: formatDate,
                                statusColor: statusColorFor(appointment.status),
                                onOpenDetails: () => onOpenDetails(appointment),
                                onConfirm:
                                    appointment.status ==
                                        AppointmentStatus.pending
                                    ? () => onUpdateStatus(
                                        appointment,
                                        AppointmentStatus.confirmed,
                                      )
                                    : null,
                                onCancel:
                                    appointment.status ==
                                            AppointmentStatus.pending ||
                                        appointment.status ==
                                            AppointmentStatus.confirmed
                                    ? () => onUpdateStatus(
                                        appointment,
                                        AppointmentStatus.cancelled,
                                      )
                                    : null,
                                onNoShow:
                                    appointment.status ==
                                        AppointmentStatus.confirmed
                                    ? () => onUpdateStatus(
                                        appointment,
                                        AppointmentStatus.noShow,
                                      )
                                    : null,
                                onComplete:
                                    appointment.status ==
                                        AppointmentStatus.confirmed
                                    ? () => onUpdateStatus(
                                        appointment,
                                        AppointmentStatus.completed,
                                      )
                                    : null,
                              ),
                              if (timelineEntry.key != entry.value.length - 1)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Color(0xFFE2E8F0),
                                ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _TableAppointmentsViewport extends StatelessWidget {
  const _TableAppointmentsViewport({
    super.key,
    required this.appointments,
    required this.formatDate,
    required this.statusColorFor,
    required this.onOpenDetails,
    required this.onUpdateStatus,
  });

  final List<AppointmentRecord> appointments;
  final _AppointmentDateFormatter formatDate;
  final _AppointmentStatusColorResolver statusColorFor;
  final _AppointmentRouteOpener onOpenDetails;
  final _AppointmentStatusUpdater onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth > 940
                  ? constraints.maxWidth
                  : 940.0
            : 940.0;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFD),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFD7E5F1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TableAppointmentsHeaderRow(),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFD7E5F1),
                  ),
                  ...appointments.asMap().entries.map((entry) {
                    final appointment = entry.value;
                    return Column(
                      children: [
                        _TableAppointmentRow(
                          appointment: appointment,
                          formatDate: formatDate,
                          statusColor: statusColorFor(appointment.status),
                          onOpenDetails: () => onOpenDetails(appointment),
                          onConfirm:
                              appointment.status == AppointmentStatus.pending
                              ? () => onUpdateStatus(
                                  appointment,
                                  AppointmentStatus.confirmed,
                                )
                              : null,
                          onCancel:
                              appointment.status == AppointmentStatus.pending ||
                                  appointment.status ==
                                      AppointmentStatus.confirmed
                              ? () => onUpdateStatus(
                                  appointment,
                                  AppointmentStatus.cancelled,
                                )
                              : null,
                          onNoShow:
                              appointment.status == AppointmentStatus.confirmed
                              ? () => onUpdateStatus(
                                  appointment,
                                  AppointmentStatus.noShow,
                                )
                              : null,
                          onComplete:
                              appointment.status == AppointmentStatus.confirmed
                              ? () => onUpdateStatus(
                                  appointment,
                                  AppointmentStatus.completed,
                                )
                              : null,
                        ),
                        if (entry.key != appointments.length - 1)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFE2E8F0),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
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
                                  showModernBannerFromSnackBar(
                                    context,
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
                                  showModernBannerFromSnackBar(
                                    context,
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

class _CompactAppointmentRow extends StatelessWidget {
  const _CompactAppointmentRow({
    required this.appointment,
    required this.statusColor,
    required this.formatDate,
    required this.onOpenDetails,
    this.onConfirm,
    this.onCancel,
    this.onNoShow,
    this.onComplete,
  });

  final AppointmentRecord appointment;
  final Color statusColor;
  final String Function(DateTime value) formatDate;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onNoShow;
  final Future<void> Function()? onComplete;

  @override
  Widget build(BuildContext context) {
    final nowLocal = DateTime.now();
    final summary = _appointmentCompactSummary(appointment, nowLocal);
    final hasOverflowActions =
        onConfirm != null ||
        onCancel != null ||
        onNoShow != null ||
        onComplete != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout = constraints.maxWidth < 920;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _studentDisplayName(appointment),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatDate(appointment.startAt)} - ${formatDate(appointment.endAt)}',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          final statusPill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.24)),
            ),
            child: Text(
              _appointmentStatusLabel(appointment.status),
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
            ),
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open'),
              ),
              if (hasOverflowActions) ...[
                const SizedBox(width: 8),
                _AppointmentOverflowMenu(
                  onConfirm: onConfirm,
                  onCancel: onCancel,
                  onNoShow: onNoShow,
                  onComplete: onComplete,
                ),
              ],
            ],
          );

          if (compactLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 12),
                    statusPill,
                  ],
                ),
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: details),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: statusPill,
                ),
              ),
              const SizedBox(width: 14),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _TimelineCountPill extends StatelessWidget {
  const _TimelineCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        '$count sessions',
        style: const TextStyle(
          color: Color(0xFF0C4A6E),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TimelineAppointmentTile extends StatelessWidget {
  const _TimelineAppointmentTile({
    required this.appointment,
    required this.formatDate,
    required this.statusColor,
    required this.onOpenDetails,
    this.onConfirm,
    this.onCancel,
    this.onNoShow,
    this.onComplete,
  });

  final AppointmentRecord appointment;
  final _AppointmentDateFormatter formatDate;
  final Color statusColor;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onNoShow;
  final Future<void> Function()? onComplete;

  @override
  Widget build(BuildContext context) {
    final summary = _appointmentCompactSummary(appointment, DateTime.now());
    final hasOverflowActions =
        onConfirm != null ||
        onCancel != null ||
        onNoShow != null ||
        onComplete != null;
    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Text(
        _appointmentStatusLabel(appointment.status),
        style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 930;
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open'),
              ),
              if (hasOverflowActions) ...[
                const SizedBox(width: 8),
                _AppointmentOverflowMenu(
                  onConfirm: onConfirm,
                  onCancel: onCancel,
                  onNoShow: onNoShow,
                  onComplete: onComplete,
                ),
              ],
            ],
          );

          final timelineMarker = Container(
            width: narrow ? double.infinity : 108,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE6F0)),
            ),
            child: Column(
              crossAxisAlignment: narrow
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  _sessionTimeRangeLabel(
                    appointment.startAt,
                    appointment.endAt,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDate(appointment.startAt).split(' ').first,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _studentDisplayName(appointment),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                timelineMarker,
                const SizedBox(height: 12),
                statusPill,
                const SizedBox(height: 12),
                details,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              timelineMarker,
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 14),
              statusPill,
              const SizedBox(width: 14),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _TableAppointmentsHeaderRow extends StatelessWidget {
  const _TableAppointmentsHeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget header(
      String label,
      int flex, {
      Alignment alignment = Alignment.centerLeft,
    }) {
      return Expanded(
        flex: flex,
        child: Align(
          alignment: alignment,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Row(
        children: [
          header('STUDENT', 24),
          header('SCHEDULE', 28),
          header('STATUS', 16),
          header('SUMMARY', 32),
          header('ACTIONS', 20, alignment: Alignment.centerRight),
        ],
      ),
    );
  }
}

class _TableAppointmentRow extends StatelessWidget {
  const _TableAppointmentRow({
    required this.appointment,
    required this.formatDate,
    required this.statusColor,
    required this.onOpenDetails,
    this.onConfirm,
    this.onCancel,
    this.onNoShow,
    this.onComplete,
  });

  final AppointmentRecord appointment;
  final _AppointmentDateFormatter formatDate;
  final Color statusColor;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onNoShow;
  final Future<void> Function()? onComplete;

  @override
  Widget build(BuildContext context) {
    final summary = _appointmentCompactSummary(appointment, DateTime.now());
    final hasOverflowActions =
        onConfirm != null ||
        onCancel != null ||
        onNoShow != null ||
        onComplete != null;

    Widget buildCell(
      int flex,
      Widget child, {
      Alignment alignment = Alignment.centerLeft,
    }) {
      return Expanded(
        flex: flex,
        child: Align(alignment: alignment, child: child),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildCell(
            24,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _studentDisplayName(appointment),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _sessionTimeRangeLabel(
                    appointment.startAt,
                    appointment.endAt,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          buildCell(
            28,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDate(appointment.startAt),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _sessionTimeRangeLabel(
                    appointment.startAt,
                    appointment.endAt,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          buildCell(
            16,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.24)),
              ),
              child: Text(
                _appointmentStatusLabel(appointment.status),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          buildCell(
            32,
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          buildCell(
            20,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: onOpenDetails,
                  child: const Text('Open'),
                ),
                if (hasOverflowActions) ...[
                  const SizedBox(width: 8),
                  _AppointmentOverflowMenu(
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                    onNoShow: onNoShow,
                    onComplete: onComplete,
                  ),
                ],
              ],
            ),
            alignment: Alignment.centerRight,
          ),
        ],
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
