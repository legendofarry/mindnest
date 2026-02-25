import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

class SessionDetailsScreen extends ConsumerWidget {
  const SessionDetailsScreen({super.key, required this.appointmentId});

  final String appointmentId;

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final firestore = ref.watch(firestoreProvider);

    if (appointmentId.trim().isEmpty) {
      return MindNestShell(
        appBar: null,
        child: const GlassCard(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('Invalid session id.'),
          ),
        ),
      );
    }

    return MindNestShell(
      maxWidth: 860,
      appBar: null,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('appointments')
            .doc(appointmentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error.toString().replaceFirst('Exception: ', ''),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data!;
          if (!doc.exists || doc.data() == null) {
            return const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Session not found.'),
              ),
            );
          }

          final appointment = AppointmentRecord.fromMap(doc.id, doc.data()!);
          final canView = _canView(profile: profile, appointment: appointment);
          if (!canView) {
            return const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('You do not have access to this session.'),
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Counseling Session',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              appointment.status.name,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _detailRow('Counselor', counselorName),
                      _detailRow('Student', studentName),
                      _detailRow('Start', _formatDate(appointment.startAt)),
                      _detailRow('End', _formatDate(appointment.endAt)),
                      if ((appointment.counselorCancelMessage ?? '')
                          .trim()
                          .isNotEmpty)
                        _detailRow(
                          'Counselor message',
                          appointment.counselorCancelMessage!.trim(),
                        ),
                      if ((appointment.counselorSessionNote ?? '')
                          .trim()
                          .isNotEmpty)
                        _detailRow(
                          'Session note',
                          appointment.counselorSessionNote!.trim(),
                        ),
                      if (appointment.counselorActionItems.isNotEmpty)
                        _detailRow(
                          'Action items',
                          appointment.counselorActionItems.join(', '),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => context.go(
                              '${AppRoute.counselorProfile}?counselorId=${appointment.counselorId}',
                            ),
                            icon: const Icon(Icons.person_search_rounded),
                            label: const Text('View Counselor'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.go(AppRoute.studentAppointments),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: const Text('Back to Sessions'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
