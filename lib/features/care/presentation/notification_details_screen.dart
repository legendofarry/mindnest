import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/models/app_notification.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';

class NotificationDetailsScreen extends ConsumerWidget {
  const NotificationDetailsScreen({super.key, required this.notificationId});

  final String notificationId;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatClock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDisplayType(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Notification';
    }
    return normalized
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  IconData _typeIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('confirm')) {
      return Icons.check_circle_outline_rounded;
    }
    if (normalized.contains('cancel')) {
      return Icons.event_busy_outlined;
    }
    if (normalized.contains('reminder')) {
      return Icons.notifications_active_outlined;
    }
    if (normalized.contains('attendance') || normalized.contains('no_show')) {
      return Icons.access_time_rounded;
    }
    if (normalized.contains('approved')) {
      return Icons.verified_rounded;
    }
    if (normalized.contains('declined')) {
      return Icons.report_gmailerrorred_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  Color _typeAccent(ColorScheme scheme, String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('confirm') || normalized.contains('completed')) {
      return const Color(0xFF059669);
    }
    if (normalized.contains('cancel') || normalized.contains('declined')) {
      return scheme.error;
    }
    if (normalized.contains('attendance') || normalized.contains('no_show')) {
      return const Color(0xFFDC2626);
    }
    if (normalized.contains('reminder')) {
      return const Color(0xFFD97706);
    }
    return scheme.primary;
  }

  bool _canOpenCounselorProfile(UserRole role) {
    return role == UserRole.student ||
        role == UserRole.staff ||
        role == UserRole.individual;
  }

  String _statusHeadline(AppNotification notification) {
    final type = notification.type.toLowerCase();
    if (type == 'session_no_show') {
      return 'Attendance update';
    }
    if (type == 'appointment_cancelled') {
      return 'Session update';
    }
    if (type == 'booking_confirmed') {
      return 'Session confirmed';
    }
    if (type == 'booking_reminder') {
      return 'Reminder';
    }
    if (type == 'session_completed') {
      return 'Session completed';
    }
    return _formatDisplayType(notification.type);
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

  Color _statusColor(ColorScheme scheme, AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return const Color(0xFFD97706);
      case AppointmentStatus.confirmed:
        return const Color(0xFF0369A1);
      case AppointmentStatus.completed:
        return const Color(0xFF059669);
      case AppointmentStatus.cancelled:
        return scheme.error;
      case AppointmentStatus.noShow:
        return const Color(0xFFDC2626);
    }
  }

  String _appointmentsRouteForRole(UserRole role) {
    switch (role) {
      case UserRole.counselor:
        return AppRoute.counselorAppointments;
      case UserRole.institutionAdmin:
        return AppRoute.institutionAdmin;
      case UserRole.student:
      case UserRole.staff:
      case UserRole.individual:
      case UserRole.other:
        return AppRoute.studentAppointments;
    }
  }

  String _appointmentsLabelForRole(UserRole role) {
    if (role == UserRole.institutionAdmin) {
      return 'Dashboard';
    }
    return 'All Sessions';
  }

  List<_NotificationAction> _buildActions({
    required UserRole role,
    required AppointmentRecord? appointment,
  }) {
    final actions = <_NotificationAction>[];

    if (appointment != null &&
        appointment.counselorId.trim().isNotEmpty &&
        _canOpenCounselorProfile(role)) {
      final encodedCounselorId = Uri.encodeQueryComponent(appointment.counselorId);
      actions.add(
        _NotificationAction(
          label: 'View Counselor',
          route:
              '${AppRoute.counselorProfile}?counselorId=$encodedCounselorId&from=notifications',
          icon: Icons.person_outline_rounded,
          primary: true,
        ),
      );
    }

    actions.add(
      _NotificationAction(
        label: _appointmentsLabelForRole(role),
        route: _appointmentsRouteForRole(role),
        icon: Icons.calendar_month_rounded,
        primary: appointment == null,
      ),
    );
    return actions;
  }

  Widget _summaryField({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _appointmentSummary({
    required BuildContext context,
    required AppointmentRecord appointment,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final counselor = (appointment.counselorName ?? '').trim().isNotEmpty
        ? appointment.counselorName!.trim()
        : appointment.counselorId;
    final student = (appointment.studentName ?? '').trim().isNotEmpty
        ? appointment.studentName!.trim()
        : appointment.studentId;
    final notes = (appointment.counselorSessionNote ?? '').trim().isNotEmpty
        ? appointment.counselorSessionNote!.trim()
        : (appointment.counselorCancelMessage ?? '').trim();
    final hasNotes = notes.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session Context',
            style: textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryField(
                  context: context,
                  label: 'Counselor',
                  value: counselor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryField(
                  context: context,
                  label: 'Student',
                  value: student,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryField(
                  context: context,
                  label: 'Time',
                  value:
                      '${_formatClock(appointment.startAt)} -> ${_formatClock(appointment.endAt)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryField(
                  context: context,
                  label: 'Date',
                  value: _formatDate(appointment.startAt),
                ),
              ),
            ],
          ),
          if (hasNotes) ...[
            const SizedBox(height: 12),
            Text(
              'Counselor note',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notes,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetails({
    required BuildContext context,
    required AppNotification notification,
    required AppointmentRecord? appointment,
    required UserRole role,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final accent = _typeAccent(scheme, notification.type);
    final icon = _typeIcon(notification.type);
    final actions = _buildActions(role: role, appointment: appointment);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusHeadline(notification),
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: notification.isRead
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
                      : accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: notification.isRead
                        ? scheme.outlineVariant.withValues(alpha: 0.55)
                        : accent.withValues(alpha: 0.26),
                  ),
                ),
                child: Text(
                  notification.isRead ? 'Read' : 'Unread',
                  style: textTheme.labelMedium?.copyWith(
                    color: notification.isRead ? scheme.onSurfaceVariant : accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            notification.title,
            style: textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            notification.body,
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_formatDate(notification.createdAt)}  •  ${_formatTime(notification.createdAt)}',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (appointment != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Current session status:',
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(appointment.status),
                  style: textTheme.labelLarge?.copyWith(
                    color: _statusColor(scheme, appointment.status),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _appointmentSummary(context: context, appointment: appointment),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actions.map((action) {
                final style = action.primary
                    ? ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      )
                    : OutlinedButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.75),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      );
                final button = action.primary
                    ? ElevatedButton.icon(
                        onPressed: () => context.go(action.route),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.label),
                        style: style,
                      )
                    : OutlinedButton.icon(
                        onPressed: () => context.go(action.route),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.label),
                        style: style,
                      );
                return button;
              }).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard({
    required BuildContext context,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.other;
    final firestore = ref.watch(firestoreProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (notificationId.trim().isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Text(
              'Invalid notification.',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go(AppRoute.notifications),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        tooltip: 'Back to notifications',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Back to notifications',
                        style: textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: firestore
                        .collection('notifications')
                        .doc(notificationId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _buildErrorCard(
                          context: context,
                          message: snapshot.error.toString().replaceFirst(
                            'Exception: ',
                            '',
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        );
                      }

                      final doc = snapshot.data!;
                      if (!doc.exists || doc.data() == null) {
                        return _buildErrorCard(
                          context: context,
                          message: 'This notification was not found.',
                        );
                      }

                      final notification = AppNotification.fromMap(
                        doc.id,
                        doc.data()!,
                      );
                      final relatedAppointmentId =
                          notification.relatedAppointmentId?.trim() ?? '';

                      if (relatedAppointmentId.isEmpty) {
                        return _buildDetails(
                          context: context,
                          notification: notification,
                          appointment: null,
                          role: role,
                        );
                      }

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: firestore
                            .collection('appointments')
                            .doc(relatedAppointmentId)
                            .snapshots(),
                        builder: (context, appointmentSnapshot) {
                          AppointmentRecord? appointment;
                          if (appointmentSnapshot.hasData) {
                            final appointmentDoc = appointmentSnapshot.data!;
                            if (appointmentDoc.exists &&
                                appointmentDoc.data() != null) {
                              appointment = AppointmentRecord.fromMap(
                                appointmentDoc.id,
                                appointmentDoc.data()!,
                              );
                            }
                          }

                          return _buildDetails(
                            context: context,
                            notification: notification,
                            appointment: appointment,
                            role: role,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationAction {
  const _NotificationAction({
    required this.label,
    required this.route,
    required this.icon,
    this.primary = false,
  });

  final String label;
  final String route;
  final IconData icon;
  final bool primary;
}
