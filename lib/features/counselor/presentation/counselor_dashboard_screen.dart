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
import 'package:mindnest/features/institutions/data/institution_providers.dart';

enum _CounselorHeaderAction { profile, notifications, logout }

class CounselorDashboardScreen extends ConsumerStatefulWidget {
  const CounselorDashboardScreen({super.key});

  @override
  ConsumerState<CounselorDashboardScreen> createState() =>
      _CounselorDashboardScreenState();
}

class _CounselorDashboardScreenState
    extends ConsumerState<CounselorDashboardScreen> {
  static const String _devClearEmail = 'legendofarrie@gmail.com';
  bool _isClearingDev = false;

  Future<void> _clearDevelopmentData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all Firestore data?'),
        content: const Text(
          'Development action. This will delete all app data and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Clear DB'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _isClearingDev = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .clearAllDataForDevelopment();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Development data cleared.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst('Exception: ', '')
                .replaceFirst('[cloud_firestore/permission-denied] ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingDev = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final showDevClear =
        (authUser?.email ?? '').trim().toLowerCase() == _devClearEmail;

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Counselor Workspace'),
        actions: [
          PopupMenuButton<_CounselorHeaderAction>(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_rounded),
            onSelected: (value) {
              switch (value) {
                case _CounselorHeaderAction.profile:
                  context.go(AppRoute.counselorSettings);
                case _CounselorHeaderAction.notifications:
                  context.go(AppRoute.notifications);
                case _CounselorHeaderAction.logout:
                  confirmAndLogout(context: context, ref: ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _CounselorHeaderAction.profile,
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_rounded),
                  title: Text('Profile & Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _CounselorHeaderAction.notifications,
                child: ListTile(
                  leading: Icon(Icons.notifications_none_rounded),
                  title: Text('Notifications'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _CounselorHeaderAction.logout,
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Logout'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
                          icon: Icons.podcasts_rounded,
                          title: 'Live Hub',
                          subtitle:
                              'Create or join institution live audio sessions.',
                          onTap: () => context.go(AppRoute.liveHub),
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
                  if (showDevClear) ...[
                    const SizedBox(height: 14),
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _isClearingDev
                                ? null
                                : _clearDevelopmentData,
                            icon: Icon(
                              _isClearingDev
                                  ? Icons.hourglass_top_rounded
                                  : Icons.delete_forever_rounded,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade200),
                            ),
                            label: Text(
                              _isClearingDev
                                  ? 'Clearing...'
                                  : 'Dev only: Clear DB',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
