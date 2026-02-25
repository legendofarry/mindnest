import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/care_goal.dart';

class StudentCarePlanScreen extends ConsumerWidget {
  const StudentCarePlanScreen({super.key});

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final studentId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: null,
      child: institutionId.isEmpty || studentId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution to access your care plan.'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Track counselor-recommended goals and review post-session action items.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Goals',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<CareGoal>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchStudentGoals(
                        institutionId: institutionId,
                        studentId: studentId,
                      ),
                  builder: (context, goalSnapshot) {
                    final goals = goalSnapshot.data ?? const [];
                    if (goalSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        goals.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (goals.isEmpty) {
                      return const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No active goals yet. Goals will appear after counselor follow-ups.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: goals
                          .map(
                            (goal) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(
                                child: CheckboxListTile(
                                  value: goal.isCompleted,
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    ref
                                        .read(careRepositoryProvider)
                                        .updateGoalCompletion(
                                          goalId: goal.id,
                                          completed: value,
                                        );
                                  },
                                  title: Text(goal.title),
                                  subtitle: Text(
                                    goal.isCompleted
                                        ? 'Completed'
                                        : 'Active goal',
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  'Session Notes Timeline',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<AppointmentRecord>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchStudentAppointments(
                        institutionId: institutionId,
                        studentId: studentId,
                      ),
                  builder: (context, appointmentSnapshot) {
                    final items = (appointmentSnapshot.data ?? const [])
                        .where(
                          (appointment) =>
                              appointment.status ==
                                  AppointmentStatus.completed &&
                              ((appointment.counselorSessionNote ?? '')
                                      .trim()
                                      .isNotEmpty ||
                                  appointment.counselorActionItems.isNotEmpty),
                        )
                        .toList(growable: false);
                    if (appointmentSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        items.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (items.isEmpty) {
                      return const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No follow-up notes yet. Completed sessions with counselor notes will appear here.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: items
                          .map(
                            (appointment) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appointment.counselorName ??
                                            appointment.counselorId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(_formatDate(appointment.startAt)),
                                      if ((appointment.counselorSessionNote ??
                                              '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          appointment.counselorSessionNote!
                                              .trim(),
                                        ),
                                      ],
                                      if (appointment
                                          .counselorActionItems
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Action items: ${appointment.counselorActionItems.join(', ')}',
                                          style: const TextStyle(
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
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
              ],
            ),
    );
  }
}
