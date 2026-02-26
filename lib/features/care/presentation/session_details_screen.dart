import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final firestore = ref.watch(firestoreProvider);
    final source = GoRouterState.of(context).uri.queryParameters['from'] ?? '';
    final fromNotifications = source.trim().toLowerCase() == 'notifications';

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
