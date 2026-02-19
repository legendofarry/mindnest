import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

class StudentAppointmentsScreen extends ConsumerWidget {
  const StudentAppointmentsScreen({super.key});

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
    }
  }

  Future<void> _cancelAppointment(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
  ) async {
    try {
      await ref
          .read(careRepositoryProvider)
          .cancelAppointmentAsStudent(appointment);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
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

  Future<void> _rateAppointment(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
  ) async {
    int selectedRating = 5;
    final feedbackController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rate Session'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: List<Widget>.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        onPressed: () => setState(() => selectedRating = value),
                        icon: Icon(
                          value <= selectedRating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: feedbackController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Feedback (optional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .submitRating(
            appointment: appointment,
            rating: selectedRating,
            feedback: feedbackController.text,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rating submitted.')));
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
    final userId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('My Counseling Sessions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: institutionId.isEmpty || userId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution to manage appointments.'),
              ),
            )
          : StreamBuilder<List<AppointmentRecord>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchStudentAppointments(
                    institutionId: institutionId,
                    studentId: userId,
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
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          appointment.counselorName ??
                                              appointment.counselorId,
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
                                  const SizedBox(height: 3),
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
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Counselor message: ${appointment.counselorCancelMessage!.trim()}',
                                        style: const TextStyle(
                                          color: Color(0xFF9A3412),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (appointment.status ==
                                              AppointmentStatus.pending ||
                                          appointment.status ==
                                              AppointmentStatus.confirmed)
                                        OutlinedButton(
                                          onPressed: () => _cancelAppointment(
                                            context,
                                            ref,
                                            appointment,
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      if (appointment.status ==
                                              AppointmentStatus.completed &&
                                          !appointment.rated)
                                        ElevatedButton(
                                          onPressed: () => _rateAppointment(
                                            context,
                                            ref,
                                            appointment,
                                          ),
                                          child: const Text('Rate Session'),
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
