import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/care_goal.dart';

class StudentCarePlanScreen extends ConsumerWidget {
  const StudentCarePlanScreen({super.key, this.embeddedInDesktopShell = false});

  final bool embeddedInDesktopShell;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final studentId = profile?.id ?? '';
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final pageBody = institutionId.isEmpty || studentId.isEmpty
        ? const _CarePlanStateCard(
            icon: Icons.favorite_border_rounded,
            title: 'Care goals unlock after you join an institution',
            message:
                'Once your account is linked to a school or organisation, counselor goals and follow-up notes will live here.',
          )
        : StreamBuilder<List<CareGoal>>(
            stream: ref
                .read(careRepositoryProvider)
                .watchStudentGoals(
                  institutionId: institutionId,
                  studentId: studentId,
                ),
            builder: (context, goalSnapshot) {
              return StreamBuilder<List<AppointmentRecord>>(
                stream: ref
                    .read(careRepositoryProvider)
                    .watchStudentAppointments(
                      institutionId: institutionId,
                      studentId: studentId,
                    ),
                builder: (context, appointmentSnapshot) {
                  final goals = goalSnapshot.data ?? const <CareGoal>[];
                  final followUps =
                      (appointmentSnapshot.data ?? const <AppointmentRecord>[])
                          .where(
                            (appointment) =>
                                appointment.status ==
                                    AppointmentStatus.completed &&
                                ((appointment.counselorSessionNote ?? '')
                                        .trim()
                                        .isNotEmpty ||
                                    appointment
                                        .counselorActionItems
                                        .isNotEmpty),
                          )
                          .toList(growable: false);

                  final completedGoals = goals.where((goal) {
                    return goal.isCompleted;
                  }).length;
                  final activeGoals = goals.length - completedGoals;

                  if ((goalSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          goals.isEmpty) ||
                      (appointmentSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          followUps.isEmpty)) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF0F2342),
                                Color(0xFF20466F),
                                Color(0xFF1AA39A),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x150F172A),
                                blurRadius: 30,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.favorite_rounded,
                                      size: 16,
                                      color: Color(0xFFCFFAFE),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Care goals',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Stay on top of the small things that actually move your care forward.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Counselor goals, follow-up actions, and session notes stay together here so the plan feels alive instead of forgotten.',
                                style: TextStyle(
                                  color: Color(0xFFD7E5F0),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _HeroStatChip(
                                    label: 'Active goals',
                                    value: '$activeGoals',
                                    tone: const Color(0xFF8B5CF6),
                                  ),
                                  _HeroStatChip(
                                    label: 'Completed',
                                    value: '$completedGoals',
                                    tone: const Color(0xFF10B981),
                                  ),
                                  _HeroStatChip(
                                    label: 'Follow-up notes',
                                    value: '${followUps.length}',
                                    tone: const Color(0xFF38BDF8),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 980;
                            final goalColumn = _GoalLane(
                              goals: goals,
                              onToggleGoal: (goal, completed) {
                                return ref
                                    .read(careRepositoryProvider)
                                    .updateGoalCompletion(
                                      goalId: goal.id,
                                      completed: completed,
                                    );
                              },
                            );
                            final followUpColumn = _FollowUpLane(
                              formatDate: _formatDate,
                              items: followUps,
                            );
                            if (!twoColumns) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  goalColumn,
                                  const SizedBox(height: 16),
                                  followUpColumn,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 5, child: goalColumn),
                                const SizedBox(width: 16),
                                Expanded(flex: 4, child: followUpColumn),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );

    if (embeddedInDesktopShell) {
      return pageBody;
    }

    return MindNestShell(
      maxWidth: isDesktop ? 1220 : 980,
      backgroundMode: MindNestBackgroundMode.defaultShell,
      animateContent: true,
      appBar: null,
      child: pageBody,
    );
  }
}

class _GoalLane extends StatelessWidget {
  const _GoalLane({required this.goals, required this.onToggleGoal});

  final List<CareGoal> goals;
  final Future<void> Function(CareGoal goal, bool completed) onToggleGoal;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      eyebrow: 'Goals tracker',
      title: 'Care plan goals',
      description:
          'Keep the active commitments visible, then tick them off as you actually make progress.',
      child: goals.isEmpty
          ? const _EmptySectionMessage(
              icon: Icons.flag_circle_outlined,
              title: 'No active goals yet',
              message:
                  'Your counselor goals will appear here after a session follow-up is saved.',
            )
          : Column(
              children: goals
                  .map((goal) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: goal.isCompleted
                              ? const Color(0xFFEFFCF6)
                              : const Color(0xFFF8FBFD),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: goal.isCompleted
                                ? const Color(0xFFB8E8D2)
                                : const Color(0xFFDCE7F1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Transform.scale(
                              scale: 1.08,
                              child: Checkbox(
                                value: goal.isCompleted,
                                activeColor: const Color(0xFF0E9B90),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  onToggleGoal(goal, value);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          goal.title,
                                          style: TextStyle(
                                            color: const Color(0xFF10233E),
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            decoration: goal.isCompleted
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _StatusPill(
                                        label: goal.isCompleted
                                            ? 'Completed'
                                            : 'Active',
                                        foreground: goal.isCompleted
                                            ? const Color(0xFF0E8F61)
                                            : const Color(0xFF2457A6),
                                        background: goal.isCompleted
                                            ? const Color(0xFFE7FAF1)
                                            : const Color(0xFFEAF2FF),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _FollowUpLane extends StatelessWidget {
  const _FollowUpLane({required this.formatDate, required this.items});

  final String Function(DateTime value) formatDate;
  final List<AppointmentRecord> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      eyebrow: 'Follow-up lane',
      title: 'Completed session notes',
      description:
          'The practical next steps from completed sessions live here so you do not have to hunt for them.',
      child: items.isEmpty
          ? const _EmptySectionMessage(
              icon: Icons.sticky_note_2_outlined,
              title: 'No follow-up notes yet',
              message:
                  'Completed sessions with notes or action items will start filling this lane automatically.',
            )
          : Column(
              children: items
                  .map((appointment) {
                    final counselorName =
                        (appointment.counselorName ?? '').trim().isEmpty
                        ? 'Counselor'
                        : appointment.counselorName!.trim();
                    final sessionNote = (appointment.counselorSessionNote ?? '')
                        .trim();
                    final hasNote = sessionNote.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFD),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFDCE7F1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    counselorName,
                                    style: const TextStyle(
                                      color: Color(0xFF10233E),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                _StatusPill(
                                  label: 'Completed',
                                  foreground: const Color(0xFF0E8F61),
                                  background: const Color(0xFFE7FAF1),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              formatDate(appointment.startAt),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasNote) ...[
                              const SizedBox(height: 12),
                              Text(
                                sessionNote,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (appointment
                                .counselorActionItems
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: appointment.counselorActionItems
                                    .map(
                                      (item) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEAF2FF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFD5E3F8),
                                          ),
                                        ),
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            color: Color(0xFF2457A6),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDCE7F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF7A8CA7),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF5E728D),
              fontSize: 14.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            '$label $value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptySectionMessage extends StatelessWidget {
  const _EmptySectionMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2457A6)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF5E728D),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarePlanStateCard extends StatelessWidget {
  const _CarePlanStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE7F1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, color: const Color(0xFF2457A6), size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF10233E),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF5E728D),
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
