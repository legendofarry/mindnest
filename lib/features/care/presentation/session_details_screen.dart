import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';

class SessionDetailsScreen extends ConsumerStatefulWidget {
  const SessionDetailsScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<SessionDetailsScreen> createState() =>
      _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends ConsumerState<SessionDetailsScreen> {
  bool _notesExpanded = false;

  String _formatDateLabel(DateTime value) {
    const monthNames = <String>[
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
    final local = value.toLocal();
    return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
  }

  String _formatClock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(AppointmentStatus status) {
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
        return 'No Show';
    }
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
        return const Color(0xFFEF4444);
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

  Widget _buildCounselorSessionWorkspace({
    required BuildContext context,
    required AppointmentRecord appointment,
    required bool fromNotifications,
  }) {
    final statusColor = _statusColor(appointment.status);
    final counselorName = (appointment.counselorName ?? '').trim().isNotEmpty
        ? appointment.counselorName!.trim()
        : appointment.counselorId;
    final studentName = (appointment.studentName ?? '').trim().isNotEmpty
        ? appointment.studentName!.trim()
        : appointment.studentId;
    final notes = (appointment.counselorSessionNote ?? '').trim().isNotEmpty
        ? appointment.counselorSessionNote!.trim()
        : (appointment.counselorCancelMessage ?? '').trim().isNotEmpty
        ? appointment.counselorCancelMessage!.trim()
        : 'No counselor notes were added for this session.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.go(
              fromNotifications
                  ? AppRoute.notifications
                  : AppRoute.counselorAppointments,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(
              fromNotifications ? 'Back to notifications' : 'Back to sessions',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0C2233),
              side: const BorderSide(color: Color(0xFFD7E0EA)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF2563EB), Color(0xFF0EA5A4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(34),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F2563EB),
                blurRadius: 28,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  const _SessionHeroPill(
                    label: 'SESSION DETAIL',
                    background: Color(0x26FFFFFF),
                  ),
                  _SessionHeroPill(
                    label: _statusLabel(appointment.status).toUpperCase(),
                    background: statusColor.withValues(alpha: 0.22),
                  ),
                  _SessionHeroPill(
                    label: _formatDateLabel(appointment.startAt).toUpperCase(),
                    background: const Color(0x20FFFFFF),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Counseling session context',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review the session state, student context, and counselor notes without leaving the counselor workspace.',
                style: TextStyle(
                  color: Color(0xFFE3F2FF),
                  fontSize: 18,
                  height: 1.42,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _SessionHeroMetricCard(
                    label: 'Time',
                    value:
                        '${_formatClock(appointment.startAt)} - ${_formatClock(appointment.endAt)}',
                  ),
                  _SessionHeroMetricCard(
                    label: 'Counselor',
                    value: counselorName,
                  ),
                  _SessionHeroMetricCard(label: 'Student', value: studentName),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  SizedBox(
                    width: 320,
                    child: _detailBlock(
                      label: 'Counselor',
                      value: counselorName,
                      icon: Icons.person_outline_rounded,
                      accent: const Color(0xFF2563EB),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: _detailBlock(
                      label: 'Student',
                      value: studentName,
                      icon: Icons.person_rounded,
                      accent: const Color(0xFF0E9B90),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: _detailBlock(
                      label: 'Date',
                      value: _formatDateLabel(appointment.startAt),
                      icon: Icons.event_note_rounded,
                      accent: const Color(0xFF7C3AED),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: _detailBlock(
                      label: 'Time',
                      value:
                          '${_formatClock(appointment.startAt)} - ${_formatClock(appointment.endAt)}',
                      icon: Icons.schedule_rounded,
                      accent: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFE),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDDE6EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => _notesExpanded = !_notesExpanded);
                      },
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'COUNSELOR NOTES',
                              style: TextStyle(
                                color: Color(0xFF6E84A3),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Icon(
                            _notesExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: const Color(0xFF6E84A3),
                          ),
                        ],
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      crossFadeState: _notesExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          notes,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (appointment.status == AppointmentStatus.noShow) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This session was marked as a no-show. Review the record and contact the student if that attendance status is incorrect.',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => context.go(AppRoute.counselorAppointments),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('All Sessions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E9B90),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 56),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  if (fromNotifications)
                    OutlinedButton.icon(
                      onPressed: () => context.go(AppRoute.notifications),
                      icon: const Icon(Icons.notifications_none_rounded),
                      label: const Text('Open Notifications'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0C2233),
                        side: const BorderSide(color: Color(0xFFD4DCE8)),
                        minimumSize: const Size(220, 56),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailBlock({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE6EE)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF7B8CA4),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0C2233),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final firestore = ref.watch(firestoreProvider);
    final source = GoRouterState.of(context).uri.queryParameters['from'] ?? '';
    final fromNotifications = source.trim().toLowerCase() == 'notifications';
    final isCounselorWorkspace =
        profile != null && profile.role == UserRole.counselor;

    if (isCounselorWorkspace) {
      final unreadCount =
          ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
      if (widget.appointmentId.trim().isEmpty) {
        return CounselorWorkspaceScaffold(
          profile: profile,
          activeSection: CounselorWorkspaceNavSection.sessions,
          unreadNotifications: unreadCount,
          title: 'Session Detail',
          subtitle:
              'Review a single session record with the same counselor workspace structure used across the rest of the flow.',
          onSelectSection: (section) => _navigateSection(context, section),
          onNotifications: () => context.go(AppRoute.notifications),
          onProfile: () => context.go(AppRoute.counselorSettings),
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: const _SessionStateCard(message: 'Invalid session id.'),
        );
      }

      return CounselorWorkspaceScaffold(
        profile: profile,
        activeSection: CounselorWorkspaceNavSection.sessions,
        unreadNotifications: unreadCount,
        title: 'Session Detail',
        subtitle:
            'Review a single session record with the same counselor workspace structure used across the rest of the flow.',
        onSelectSection: (section) => _navigateSection(context, section),
        onNotifications: () => context.go(AppRoute.notifications),
        onProfile: () => context.go(AppRoute.counselorSettings),
        onLogout: () => confirmAndLogout(context: context, ref: ref),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('appointments')
              .doc(widget.appointmentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _SessionStateCard(
                message: snapshot.error.toString().replaceFirst(
                  'Exception: ',
                  '',
                ),
              );
            }

            if (!snapshot.hasData) {
              return const _SessionLoadingCard();
            }

            final doc = snapshot.data!;
            if (!doc.exists || doc.data() == null) {
              return const _SessionStateCard(message: 'Session not found.');
            }

            final appointment = AppointmentRecord.fromMap(doc.id, doc.data()!);
            final canView = _canView(
              profile: profile,
              appointment: appointment,
            );
            if (!canView) {
              return const _SessionStateCard(
                message: 'You do not have access to this session.',
              );
            }

            return _buildCounselorSessionWorkspace(
              context: context,
              appointment: appointment,
              fromNotifications: fromNotifications,
            );
          },
        ),
      );
    }

    if (widget.appointmentId.trim().isEmpty) {
      return _baseScaffold(
        child: const Center(
          child: Text(
            'Invalid session id.',
            style: TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return _baseScaffold(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('appointments')
            .doc(widget.appointmentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _centeredCard(
              child: Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data!;
          if (!doc.exists || doc.data() == null) {
            return _centeredCard(
              child: const Text(
                'Session not found.',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final appointment = AppointmentRecord.fromMap(doc.id, doc.data()!);
          final canView = _canView(profile: profile, appointment: appointment);
          if (!canView) {
            return _centeredCard(
              child: const Text(
                'You do not have access to this session.',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final statusColor = _statusColor(appointment.status);
          final counselorName =
              (appointment.counselorName ?? '').trim().isNotEmpty
              ? appointment.counselorName!.trim()
              : appointment.counselorId;
          final studentName = (appointment.studentName ?? '').trim().isNotEmpty
              ? appointment.studentName!.trim()
              : appointment.studentId;
          final notes =
              (appointment.counselorSessionNote ?? '').trim().isNotEmpty
              ? appointment.counselorSessionNote!.trim()
              : (appointment.counselorCancelMessage ?? '').trim().isNotEmpty
              ? appointment.counselorCancelMessage!.trim()
              : 'No counselor notes were added for this session.';

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBackRow(
                      context: context,
                      fromNotifications: fromNotifications,
                      profile: profile,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: const Color(0xFFE6EAF0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x140F172A),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                size: 16,
                                color: Color(0xFF4F46E5),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'SESSION DETAILS',
                                style: TextStyle(
                                  color: Color(0xFF4F46E5),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Text(
                                  _statusLabel(appointment.status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Counseling Session',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                              fontSize: 23,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: _partyCard(
                                  label: 'COUNSELOR',
                                  name: counselorName,
                                  icon: Icons.person_outline_rounded,
                                  iconTint: const Color(0xFF4F46E5),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _partyCard(
                                  label: 'STUDENT',
                                  name: studentName,
                                  icon: Icons.person_outline_rounded,
                                  iconTint: const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FB),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFE8ECF2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFDDE4ED),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x120F172A),
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.schedule_rounded,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'TIME & DURATION',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${_formatClock(appointment.startAt)}  ->  ${_formatClock(appointment.endAt)}',
                                            style: const TextStyle(
                                              color: Color(0xFF1E293B),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'DATE',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _formatDateLabel(appointment.startAt),
                                          style: const TextStyle(
                                            color: Color(0xFF1E293B),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(
                                  color: Color(0xFFDDE4ED),
                                  height: 1,
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setState(
                                      () => _notesExpanded = !_notesExpanded,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '... COUNSELOR NOTES',
                                            style: TextStyle(
                                              color: Color(0xFF8EA0BD),
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          _notesExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                    .keyboard_arrow_down_rounded,
                                          color: const Color(0xFF8EA0BD),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                AnimatedCrossFade(
                                  duration: const Duration(milliseconds: 180),
                                  crossFadeState: _notesExpanded
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                  firstChild: const SizedBox.shrink(),
                                  secondChild: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '"$notes"',
                                      style: const TextStyle(
                                        color: Color(0xFF334155),
                                        fontSize: 17,
                                        height: 1.45,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (appointment.status ==
                              AppointmentStatus.noShow) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F2),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFFECACA),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: 1),
                                    child: Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'This session was marked as a no-show. Please contact your counselor if you believe this is an error.',
                                      style: TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => context.go(
                                    '${AppRoute.counselorProfile}?counselorId=${appointment.counselorId}',
                                  ),
                                  icon: const Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                  label: const Text('View Counselor'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(58),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      context.go(AppRoute.studentAppointments),
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                  label: const Text('All Sessions'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF334155),
                                    minimumSize: const Size.fromHeight(58),
                                    side: const BorderSide(
                                      color: Color(0xFFD4DCE8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  bool _canView({
    required UserProfile? profile,
    required AppointmentRecord appointment,
  }) {
    if (profile == null) {
      return false;
    }
    if (profile.id == appointment.studentId ||
        profile.id == appointment.counselorId) {
      return true;
    }
    return profile.role == UserRole.institutionAdmin &&
        (profile.institutionId ?? '') == appointment.institutionId;
  }

  Widget _baseScaffold({required Widget child}) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[Color(0xFFF3F5FA), Color(0xFFEFF3F8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _centeredCard({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTopBackRow({
    required BuildContext context,
    required bool fromNotifications,
    required UserProfile? profile,
  }) {
    String destination;
    String label;
    if (fromNotifications) {
      destination = AppRoute.notifications;
      label = 'Back to notifications';
    } else if (profile?.role == UserRole.counselor) {
      destination = AppRoute.counselorAppointments;
      label = 'Back to sessions';
    } else {
      destination = AppRoute.studentAppointments;
      label = 'Back to sessions';
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.go(destination),
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: Color(0xFF64748B),
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
      ),
    );
  }

  Widget _partyCard({
    required String label,
    required String name,
    required IconData icon,
    required Color iconTint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8EA0BD),
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, color: iconTint, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SessionHeroPill extends StatelessWidget {
  const _SessionHeroPill({required this.label, required this.background});

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SessionHeroMetricCard extends StatelessWidget {
  const _SessionHeroMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFDDEBFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStateCard extends StatelessWidget {
  const _SessionStateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF506176),
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    );
  }
}

class _SessionLoadingCard extends StatelessWidget {
  const _SessionLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
