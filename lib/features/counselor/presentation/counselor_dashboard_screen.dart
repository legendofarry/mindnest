import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

class CounselorDashboardScreen extends ConsumerWidget {
  const CounselorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Counselor Workspace'),
        actions: [
          TextButton.icon(
            onPressed: () => confirmAndLogout(context: context, ref: ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ],
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const _InfoCard(message: 'Profile not found.');
          }
          if (profile.role != UserRole.counselor) {
            return const _InfoCard(
              message: 'This workspace is available only for counselors.',
            );
          }

          final setupData = profile.counselorSetupData;
          final specialization =
              (setupData['specialization'] as String?) ?? 'Not set';
          final title = (setupData['title'] as String?) ?? 'Counselor';
          final timezone = (setupData['timezone'] as String?) ?? '--';
          final sessionMode = (setupData['sessionMode'] as String?) ?? '--';
          final institutionId = profile.institutionId ?? '';

          return StreamBuilder<List<AppointmentRecord>>(
            stream: ref
                .read(careRepositoryProvider)
                .watchCounselorAppointments(
                  institutionId: institutionId,
                  counselorId: profile.id,
                ),
            builder: (context, snapshot) {
              final appointments = snapshot.data ?? const [];
              final pending = appointments
                  .where((entry) => entry.status == AppointmentStatus.pending)
                  .length;
              final today = appointments.where((entry) {
                final now = DateTime.now();
                final local = entry.startAt.toLocal();
                return local.year == now.year &&
                    local.month == now.month &&
                    local.day == now.day &&
                    (entry.status == AppointmentStatus.pending ||
                        entry.status == AppointmentStatus.confirmed);
              }).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${profile.name.isNotEmpty ? profile.name : profile.email}',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text('Title: $title'),
                          const SizedBox(height: 4),
                          Text('Specialization: $specialization'),
                          const SizedBox(height: 4),
                          Text('Session mode: $sessionMode'),
                          const SizedBox(height: 4),
                          Text('Timezone: $timezone'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 820;
                      final cards = [
                        _ActionCardData(
                          icon: Icons.event_available_rounded,
                          title: 'Today\'s Sessions',
                          subtitle:
                              '$today active sessions scheduled for today.',
                          onTap: () =>
                              context.go(AppRoute.counselorAppointments),
                        ),
                        _ActionCardData(
                          icon: Icons.calendar_month_rounded,
                          title: 'Availability',
                          subtitle:
                              'Publish and maintain public available slots.',
                          onTap: () =>
                              context.go(AppRoute.counselorAvailability),
                        ),
                        _ActionCardData(
                          icon: Icons.notifications_active_outlined,
                          title: 'Pending Requests',
                          subtitle:
                              '$pending appointment requests need your action.',
                          onTap: () =>
                              context.go(AppRoute.counselorAppointments),
                        ),
                        _ActionCardData(
                          icon: Icons.notifications_none_rounded,
                          title: 'Notifications',
                          subtitle: 'Open booking and cancellation updates.',
                          onTap: () => context.go(AppRoute.notifications),
                        ),
                        _ActionCardData(
                          icon: Icons.manage_accounts_rounded,
                          title: 'Profile & Settings',
                          subtitle:
                              'Edit profile, app preferences, and account controls.',
                          onTap: () => context.go(AppRoute.counselorSettings),
                        ),
                      ];

                      if (!isWide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: cards
                              .map(
                                (card) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _ActionCard(data: card),
                                ),
                              )
                              .toList(growable: false),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List<Widget>.generate(cards.length, (index) {
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == cards.length - 1 ? 0 : 10,
                              ),
                              child: _ActionCard(data: cards[index]),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Counselor Notes',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Use this workspace to manage schedules, approve requests, complete sessions, and track follow-ups.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _InfoCard(message: error.toString()),
      ),
    );
  }
}

class _ActionCardData {
  const _ActionCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data});

  final _ActionCardData data;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: data.onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: const Color(0xFF0284C7)),
                ),
                const SizedBox(height: 10),
                Text(
                  data.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  data.subtitle,
                  style: const TextStyle(color: Color(0xFF5E728D)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
    );
  }
}
