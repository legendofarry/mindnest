import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';

class StudentAppointmentsScreen extends ConsumerStatefulWidget {
  const StudentAppointmentsScreen({super.key});

  @override
  ConsumerState<StudentAppointmentsScreen> createState() =>
      _StudentAppointmentsScreenState();
}

class _StudentAppointmentsScreenState
    extends ConsumerState<StudentAppointmentsScreen> {
  bool _timelineView = false;
  int _refreshTick = 0;

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

  Future<void> _rescheduleAppointment(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppointmentRecord appointment,
  ) async {
    final institutionId = profile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join an institution first.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: StreamBuilder<List<AvailabilitySlot>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorPublicAvailability(
                    institutionId: institutionId,
                    counselorId: appointment.counselorId,
                  ),
              builder: (context, snapshot) {
                final slots = (snapshot.data ?? const [])
                    .where((slot) => slot.id != appointment.slotId)
                    .toList(growable: false);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    slots.isEmpty) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Reschedule Session',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pick a new available slot from this counselor.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    if (slots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No alternate slots available right now.'),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: slots.length.clamp(0, 18),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final slot = slots[index];
                            return ListTile(
                              tileColor: const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: Text(_formatDate(slot.startAt)),
                              subtitle: Text(
                                'Ends: ${_formatDate(slot.endAt)}',
                              ),
                              trailing: ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(careRepositoryProvider)
                                        .rescheduleAppointmentAsStudent(
                                          appointment: appointment,
                                          newSlot: slot,
                                          currentProfile: profile,
                                        );
                                    if (!mounted) {
                                      return;
                                    }
                                    Navigator.of(this.context).pop();
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Appointment rescheduled.',
                                        ),
                                      ),
                                    );
                                  } catch (error) {
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
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
                                },
                                child: const Text('Choose'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
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

  Widget _buildTimeline(List<AppointmentRecord> appointments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: appointments
          .map((appointment) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _openSessionDetails(context, appointment),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor(appointment.status),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 70,
                          color: const Color(0xFFD1D5DB),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.counselorName ??
                                    appointment.counselorId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Start: ${_formatDate(appointment.startAt)}',
                              ),
                              Text('Status: ${appointment.status.name}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  void _openSessionDetails(
    BuildContext context,
    AppointmentRecord appointment,
  ) {
    context.go('${AppRoute.sessionDetails}?appointmentId=${appointment.id}');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final userId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('My Counseling Sessions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackToHomeButton(),
        actions: [
          IconButton(
            tooltip: 'Retry',
            onPressed: () => setState(() => _refreshTick++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: institutionId.isEmpty || userId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution to manage appointments.'),
              ),
            )
          : StreamBuilder<List<AppointmentRecord>>(
              key: ValueKey(_refreshTick),
              stream: ref
                  .read(careRepositoryProvider)
                  .watchStudentAppointments(
                    institutionId: institutionId,
                    studentId: userId,
                  ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            snapshot.error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => setState(() => _refreshTick++),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final appointments = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    appointments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (appointments.isEmpty) {
                  return const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No appointments yet. Open Find Counselors and book your first session.',
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GlassCard(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Cancellation policy: cancel early when possible so the counselor can reopen the slot for other students.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'View',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Cards'),
                          selected: !_timelineView,
                          onSelected: (_) =>
                              setState(() => _timelineView = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Timeline'),
                          selected: _timelineView,
                          onSelected: (_) =>
                              setState(() => _timelineView = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_timelineView)
                      _buildTimeline(appointments)
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: appointments
                            .map(
                              (appointment) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () =>
                                      _openSessionDetails(context, appointment),
                                  child: GlassCard(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(
                                                    appointment.status,
                                                  ).withValues(alpha: 0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(
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
                                              (appointment.counselorCancelMessage ??
                                                      '')
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF7ED),
                                                borderRadius:
                                                    BorderRadius.circular(10),
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
                                          if (appointment.status ==
                                                  AppointmentStatus.completed &&
                                              (appointment.counselorSessionNote ??
                                                      '')
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Session note: ${appointment.counselorSessionNote!.trim()}',
                                                style: const TextStyle(
                                                  color: Color(0xFF0C4A6E),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (appointment.status ==
                                                  AppointmentStatus.completed &&
                                              appointment
                                                  .counselorActionItems
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Action items: ${appointment.counselorActionItems.join(', ')}',
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              if (appointment.status ==
                                                      AppointmentStatus
                                                          .pending ||
                                                  appointment.status ==
                                                      AppointmentStatus
                                                          .confirmed)
                                                OutlinedButton(
                                                  onPressed: profile == null
                                                      ? null
                                                      : () =>
                                                            _rescheduleAppointment(
                                                              context,
                                                              ref,
                                                              profile,
                                                              appointment,
                                                            ),
                                                  child: const Text(
                                                    'Reschedule',
                                                  ),
                                                ),
                                              if (appointment.status ==
                                                      AppointmentStatus
                                                          .pending ||
                                                  appointment.status ==
                                                      AppointmentStatus
                                                          .confirmed)
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      _cancelAppointment(
                                                        context,
                                                        ref,
                                                        appointment,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                              if (appointment.status ==
                                                      AppointmentStatus
                                                          .completed &&
                                                  !appointment.rated)
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      _rateAppointment(
                                                        context,
                                                        ref,
                                                        appointment,
                                                      ),
                                                  child: const Text(
                                                    'Rate Session',
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
