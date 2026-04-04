import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/app_notification.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/live/models/live_participant.dart';

final _recentNotificationsProvider = StreamProvider.autoDispose
    .family<List<AppNotification>, String>((ref, userId) {
      final normalized = userId.trim();
      if (normalized.isEmpty) {
        return Stream.value(const <AppNotification>[]);
      }
      return ref
          .watch(careRepositoryProvider)
          .watchUserNotifications(normalized);
    });

final _recentAppointmentsProvider = StreamProvider.autoDispose
    .family<List<AppointmentRecord>, _ActivityScope>((ref, scope) {
      if (scope.institutionId.isEmpty || scope.userId.isEmpty) {
        return Stream.value(const <AppointmentRecord>[]);
      }
      return ref
          .watch(careRepositoryProvider)
          .watchStudentAppointments(
            institutionId: scope.institutionId,
            studentId: scope.userId,
          );
    });

final _recentLiveJoinsProvider = StreamProvider.autoDispose
    .family<List<_LiveJoinActivity>, String>((ref, userId) {
      final normalized = userId.trim();
      if (normalized.isEmpty || kUseWindowsRestAuth) {
        return Stream.value(const <_LiveJoinActivity>[]);
      }
      final firestore = ref.watch(firestoreProvider);
      final sessionCache = <String, _LiveSessionSummary>{};

      return firestore
          .collectionGroup('participants')
          .where('userId', isEqualTo: normalized)
          .snapshots()
          .asyncMap((snapshot) async {
            final joins = snapshot.docs
                .map((doc) {
                  final sessionId = doc.reference.parent.parent?.id ?? '';
                  if (sessionId.isEmpty) {
                    return null;
                  }
                  final participant = LiveParticipant.fromMap(doc.data());
                  if (participant.joinedAt.millisecondsSinceEpoch <= 0) {
                    return null;
                  }
                  return _LiveJoinActivity(
                    sessionId: sessionId,
                    joinedAt: participant.joinedAt,
                    kind: participant.kind,
                  );
                })
                .whereType<_LiveJoinActivity>()
                .toList(growable: false);

            joins.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
            final limited = joins.take(6).toList(growable: false);
            final missingIds = limited
                .map((entry) => entry.sessionId)
                .where((id) => !sessionCache.containsKey(id))
                .toSet();

            if (missingIds.isNotEmpty) {
              await Future.wait(
                missingIds.map((sessionId) async {
                  final doc = await firestore
                      .collection('live_sessions')
                      .doc(sessionId)
                      .get();
                  final data = doc.data() ?? const <String, dynamic>{};
                  final rawTitle = (data['title'] as String?)?.trim() ?? '';
                  final rawHost = (data['hostName'] as String?)?.trim() ?? '';
                  sessionCache[sessionId] = _LiveSessionSummary(
                    title: rawTitle.isEmpty ? 'Live audio room' : rawTitle,
                    hostName: rawHost,
                  );
                }),
              );
            }

            return limited
                .map(
                  (entry) => entry.copyWith(
                    title:
                        sessionCache[entry.sessionId]?.title ??
                        'Live audio room',
                    hostName: sessionCache[entry.sessionId]?.hostName ?? '',
                  ),
                )
                .toList(growable: false);
          });
    });

class RecentActivityCard extends ConsumerWidget {
  const RecentActivityCard({
    super.key,
    required this.profile,
    this.sideBySide = false,
  });

  final UserProfile profile;
  final bool sideBySide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notificationsAsync = ref.watch(
      _recentNotificationsProvider(profile.id),
    );
    final appointmentsAsync = (profile.institutionId ?? '').trim().isEmpty
        ? const AsyncData<List<AppointmentRecord>>(<AppointmentRecord>[])
        : ref.watch(
            _recentAppointmentsProvider(
              _ActivityScope(
                institutionId: (profile.institutionId ?? '').trim(),
                userId: profile.id.trim(),
              ),
            ),
          );
    final liveJoinsAsync = ref.watch(_recentLiveJoinsProvider(profile.id));

    final notifications =
        notificationsAsync.valueOrNull ?? const <AppNotification>[];
    final appointments =
        appointmentsAsync.valueOrNull ?? const <AppointmentRecord>[];
    final liveJoins = liveJoinsAsync.valueOrNull ?? const <_LiveJoinActivity>[];

    final activities = _buildActivityItems(
      context: context,
      notifications: notifications,
      appointments: appointments,
      liveJoins: liveJoins,
    );
    final recentCounselors = _recentCounselors(appointments);
    final hasError =
        notificationsAsync.hasError ||
        appointmentsAsync.hasError ||
        liveJoinsAsync.hasError;
    final isLoading =
        notificationsAsync.isLoading ||
        appointmentsAsync.isLoading ||
        liveJoinsAsync.isLoading;
    final visibleActivities = activities
        .take(sideBySide ? 5 : 6)
        .toList(growable: false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF9FCFF), Color(0xFFF2FBF8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD7E3F3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140B1A33),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -44,
              right: -36,
              child: _ActivityGlow(
                size: 142,
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -34,
              child: _ActivityGlow(
                size: 118,
                color: const Color(0xFF60A5FA).withValues(alpha: 0.10),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F7F7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(
                            0xFF0D9488,
                          ).withValues(alpha: 0.10),
                        ),
                      ),
                      child: const Icon(
                        Icons.timeline_rounded,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Notifications, bookings, live joins, and counselor touchpoints in one place.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActivityStatChip(
                      icon: Icons.notifications_active_outlined,
                      label: 'Alerts',
                      value: notifications
                          .where((entry) => !entry.isArchived)
                          .length
                          .toString(),
                    ),
                    _ActivityStatChip(
                      icon: Icons.event_note_rounded,
                      label: 'Sessions',
                      value: appointments.length.toString(),
                    ),
                    _ActivityStatChip(
                      icon: Icons.podcasts_rounded,
                      label: 'Lives',
                      value: liveJoins.length.toString(),
                    ),
                  ],
                ),
                if (recentCounselors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Counselors interacted with',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: recentCounselors
                        .map(
                          (entry) => _CounselorChip(
                            counselor: entry,
                            onTap: entry.counselorId.isEmpty
                                ? null
                                : () => context.push(
                                    Uri(
                                      path: AppRoute.counselorProfile,
                                      queryParameters: <String, String>{
                                        'counselorId': entry.counselorId,
                                        'from': 'home',
                                      },
                                    ).toString(),
                                  ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Timeline',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (visibleActivities.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFD).withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD7E3F3)),
                    ),
                    child: Text(
                      (profile.institutionId ?? '').trim().isEmpty
                          ? 'Activity will build here once you start receiving alerts or joining an institution workspace.'
                          : 'No recent activity yet. Your bookings, alerts, and live joins will start appearing here.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (
                        var index = 0;
                        index < visibleActivities.length;
                        index++
                      ) ...[
                        _RecentActivityTile(item: visibleActivities[index]),
                        if (index != visibleActivities.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                      ],
                    ],
                  ),
                if (hasError) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Text(
                      'Some activity details are still loading. The visible items are safe to use.',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_RecentCounselor> _recentCounselors(
    List<AppointmentRecord> appointments,
  ) {
    final byCounselor = <String, _RecentCounselor>{};
    for (final appointment in appointments) {
      final counselorId = appointment.counselorId.trim();
      final counselorName = (appointment.counselorName ?? '').trim().isEmpty
          ? 'Counselor'
          : appointment.counselorName!.trim();
      final key = counselorId.isEmpty ? counselorName : counselorId;
      final seenAt = appointment.endAt.isAfter(appointment.startAt)
          ? appointment.endAt
          : appointment.startAt;
      final current = byCounselor[key];
      if (current == null || seenAt.isAfter(current.lastInteractionAt)) {
        byCounselor[key] = _RecentCounselor(
          counselorId: counselorId,
          name: counselorName,
          lastInteractionAt: seenAt,
        );
      }
    }
    final counselors = byCounselor.values.toList(growable: false);
    counselors.sort(
      (a, b) => b.lastInteractionAt.compareTo(a.lastInteractionAt),
    );
    return counselors.take(4).toList(growable: false);
  }

  List<_RecentActivityItem> _buildActivityItems({
    required BuildContext context,
    required List<AppNotification> notifications,
    required List<AppointmentRecord> appointments,
    required List<_LiveJoinActivity> liveJoins,
  }) {
    final sortedNotifications =
        notifications
            .where((entry) => !entry.isArchived)
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final items = <_RecentActivityItem>[
      ...sortedNotifications
          .take(3)
          .map((entry) => _notificationItem(context, entry)),
      ...appointments.take(3).map((entry) => _appointmentItem(context, entry)),
      ...liveJoins.take(2).map((entry) => _liveJoinItem(context, entry)),
    ];

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  _RecentActivityItem _notificationItem(
    BuildContext context,
    AppNotification notification,
  ) {
    final route = (notification.route ?? '').trim();
    return _RecentActivityItem(
      icon: Icons.notifications_active_outlined,
      accent: notification.isRead
          ? const Color(0xFFCBD5E1)
          : const Color(0xFF0D9488),
      title: notification.title.trim().isEmpty
          ? 'Notification'
          : notification.title.trim(),
      subtitle: notification.body.trim().isEmpty
          ? 'Open notifications to view the full update.'
          : notification.body.trim(),
      timestamp: notification.createdAt,
      meta: _relativeTime(notification.createdAt),
      onTap: () => context.go(route.isEmpty ? AppRoute.notifications : route),
    );
  }

  _RecentActivityItem _appointmentItem(
    BuildContext context,
    AppointmentRecord appointment,
  ) {
    final counselorName = (appointment.counselorName ?? '').trim().isEmpty
        ? 'your counselor'
        : appointment.counselorName!.trim();
    final statusLabel = switch (appointment.status) {
      AppointmentStatus.pending => 'Pending booking',
      AppointmentStatus.confirmed => 'Upcoming booking',
      AppointmentStatus.completed => 'Completed session',
      AppointmentStatus.cancelled => 'Cancelled session',
      AppointmentStatus.noShow => 'Missed session',
    };
    return _RecentActivityItem(
      icon: Icons.event_note_rounded,
      accent: _appointmentAccent(appointment.status),
      title: '$statusLabel with $counselorName',
      subtitle: _absoluteTimeLabel(appointment.startAt),
      timestamp: appointment.startAt,
      meta: _relativeTime(appointment.startAt),
      onTap: () => context.go(AppRoute.studentAppointments),
    );
  }

  _RecentActivityItem _liveJoinItem(
    BuildContext context,
    _LiveJoinActivity liveJoin,
  ) {
    final joinedLabel = liveJoin.kind == LiveParticipantKind.host
        ? 'Hosted'
        : 'Joined';
    final hostLabel = liveJoin.hostName.trim().isEmpty
        ? ''
        : ' | Host: ${liveJoin.hostName.trim()}';
    return _RecentActivityItem(
      icon: Icons.podcasts_rounded,
      accent: const Color(0xFF0F766E),
      title: '$joinedLabel ${liveJoin.title}',
      subtitle: '${_absoluteTimeLabel(liveJoin.joinedAt)}$hostLabel'.trim(),
      timestamp: liveJoin.joinedAt,
      meta: _relativeTime(liveJoin.joinedAt),
      onTap: () => context.go(AppRoute.liveHub),
    );
  }

  static String _absoluteTimeLabel(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date | $clock';
  }

  static String _relativeTime(DateTime value) {
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inSeconds < 45) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  static Color _appointmentAccent(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return const Color(0xFFD97706);
      case AppointmentStatus.confirmed:
        return const Color(0xFF0284C7);
      case AppointmentStatus.completed:
        return const Color(0xFF059669);
      case AppointmentStatus.cancelled:
        return const Color(0xFFDC2626);
      case AppointmentStatus.noShow:
        return const Color(0xFF7C3AED);
    }
  }
}

class _ActivityScope {
  const _ActivityScope({required this.institutionId, required this.userId});

  final String institutionId;
  final String userId;

  @override
  bool operator ==(Object other) {
    return other is _ActivityScope &&
        other.institutionId == institutionId &&
        other.userId == userId;
  }

  @override
  int get hashCode => Object.hash(institutionId, userId);
}

class _LiveSessionSummary {
  const _LiveSessionSummary({required this.title, required this.hostName});

  final String title;
  final String hostName;
}

class _LiveJoinActivity {
  const _LiveJoinActivity({
    required this.sessionId,
    required this.joinedAt,
    required this.kind,
    this.title = 'Live audio room',
    this.hostName = '',
  });

  final String sessionId;
  final DateTime joinedAt;
  final LiveParticipantKind kind;
  final String title;
  final String hostName;

  _LiveJoinActivity copyWith({String? title, String? hostName}) {
    return _LiveJoinActivity(
      sessionId: sessionId,
      joinedAt: joinedAt,
      kind: kind,
      title: title ?? this.title,
      hostName: hostName ?? this.hostName,
    );
  }
}

class _RecentCounselor {
  const _RecentCounselor({
    required this.counselorId,
    required this.name,
    required this.lastInteractionAt,
  });

  final String counselorId;
  final String name;
  final DateTime lastInteractionAt;
}

class _RecentActivityItem {
  const _RecentActivityItem({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.meta,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String meta;
  final VoidCallback? onTap;
}

class _ActivityStatChip extends StatelessWidget {
  const _ActivityStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E3F3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF0D9488)),
          const SizedBox(width: 7),
          Text(
            '$label $value',
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CounselorChip extends StatelessWidget {
  const _CounselorChip({required this.counselor, this.onTap});

  final _RecentCounselor counselor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFD),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD7E3F3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_rounded,
              size: 15,
              color: Color(0xFF0D9488),
            ),
            const SizedBox(width: 7),
            Text(
              counselor.name,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile({required this.item});

  final _RecentActivityItem item;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.8,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  item.meta,
                  style: const TextStyle(
                    color: Color(0xFF0D9488),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: Color(0xFF94A3B8),
            ),
          ],
        ],
      ),
    );

    if (item.onTap == null) {
      return content;
    }

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );
  }
}

class _ActivityGlow extends StatelessWidget {
  const _ActivityGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}
