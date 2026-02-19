import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

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
    }
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
    if (status == AppointmentStatus.cancelled) {
      final decision = await _promptCancellationReason(context);
      if (!context.mounted || decision == null) {
        return;
      }
      cancellationMessage = decision;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .updateAppointmentByCounselor(
            appointment: appointment,
            newStatus: status,
            counselorCancelMessage: cancellationMessage,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AppointmentStatus.cancelled
                ? 'Appointment cancelled and student notified.'
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final counselorId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Counselor Appointments'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: profile == null || profile.role != UserRole.counselor
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('This page is available only for counselors.'),
              ),
            )
          : StreamBuilder<List<AppointmentRecord>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorAppointments(
                    institutionId: institutionId,
                    counselorId: counselorId,
                  ),
              builder: (context, snapshot) {
                final appointments = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    appointments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (appointments.isEmpty) {
                  return const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No appointments yet.'),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: appointments
                      .map(
                        (appointment) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          appointment.studentName ??
                                              appointment.studentId,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(
                                            appointment.status,
                                          ).withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          appointment.status.name,
                                          style: TextStyle(
                                            color: _statusColor(
                                              appointment.status,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Start: ${_formatDate(appointment.startAt)}',
                                  ),
                                  Text(
                                    'End: ${_formatDate(appointment.endAt)}',
                                  ),
                                  if (appointment.status ==
                                          AppointmentStatus.cancelled &&
                                      (appointment.counselorCancelMessage ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Message sent: ${appointment.counselorCancelMessage!.trim()}',
                                        style: const TextStyle(
                                          color: Color(0xFF9A3412),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (appointment.status ==
                                          AppointmentStatus.pending)
                                        OutlinedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.confirmed,
                                          ),
                                          child: const Text('Confirm'),
                                        ),
                                      if (appointment.status ==
                                              AppointmentStatus.pending ||
                                          appointment.status ==
                                              AppointmentStatus.confirmed)
                                        OutlinedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.cancelled,
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      if (appointment.status ==
                                          AppointmentStatus.confirmed)
                                        ElevatedButton(
                                          onPressed: () => _updateStatus(
                                            context,
                                            ref,
                                            appointment,
                                            AppointmentStatus.completed,
                                          ),
                                          child: const Text('Mark Completed'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
    );
  }
}
