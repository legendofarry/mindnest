import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/app_notification.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

const Duration _windowsPollInterval = Duration(seconds: 15);
bool get _useWindowsRestFirestore =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Stream<T> _buildWindowsPollingStream<T>({
  required Future<T> Function() load,
  required String Function(T value) signature,
}) {
  late final StreamController<T> controller;
  Timer? timer;
  String? lastEmissionSignature;

  Future<void> emitIfChanged() async {
    if (controller.isClosed) {
      return;
    }
    try {
      final value = await load();
      final nextSignature = 'value:${signature(value)}';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.add(value);
      }
    } catch (error, stackTrace) {
      final nextSignature = 'error:$error';
      if (nextSignature == lastEmissionSignature) {
        return;
      }
      lastEmissionSignature = nextSignature;
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  controller = StreamController<T>(
    onListen: () {
      unawaited(emitIfChanged());
      timer = Timer.periodic(_windowsPollInterval, (_) {
        unawaited(emitIfChanged());
      });
    },
    onCancel: () {
      timer?.cancel();
    },
  );

  return controller.stream;
}

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
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
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
      final encodedCounselorId = Uri.encodeQueryComponent(
        appointment.counselorId,
      );
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

  void _navigateSection(
    BuildContext context,
    CounselorWorkspaceNavSection section,
  ) {
    switch (section) {
      case CounselorWorkspaceNavSection.dashboard:
        context.go(AppRoute.counselorDashboard);
      case CounselorWorkspaceNavSection.sessions:
        context.go(AppRoute.counselorAppointments);
      case CounselorWorkspaceNavSection.live:
        context.go(AppRoute.counselorLiveHub);
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
      case CounselorWorkspaceNavSection.counselors:
        context.go(AppRoute.counselorDirectory);
    }
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
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
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
                      '${_formatClock(appointment.startAt)} - ${_formatClock(appointment.endAt)}',
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
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                    color: notification.isRead
                        ? scheme.onSurfaceVariant
                        : accent,
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
            '${_formatDate(notification.createdAt)} - ${_formatTime(notification.createdAt)}',
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
              children: actions
                  .map((action) {
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
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.75,
                              ),
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
                  })
                  .toList(growable: false),
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
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
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

  Widget _buildCounselorHero({
    required BuildContext context,
    required AppNotification notification,
    required AppointmentRecord? appointment,
  }) {
    final theme = Theme.of(context);
    final accent = _typeAccent(theme.colorScheme, notification.type);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF2563EB), Color(0xFF0EA5A4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1D4ED8),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroPill(
                label: _statusHeadline(notification).toUpperCase(),
                background: const Color(0x26FFFFFF),
              ),
              _HeroPill(
                label: notification.isRead ? 'READ' : 'UNREAD',
                background: notification.isRead
                    ? const Color(0x22FFFFFF)
                    : accent.withValues(alpha: 0.22),
              ),
              if (appointment != null)
                _HeroPill(
                  label: _statusLabel(appointment.status).toUpperCase(),
                  background: _statusColor(
                    theme.colorScheme,
                    appointment.status,
                  ).withValues(alpha: 0.22),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            notification.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review the alert, verify the latest session context, and take the next action without leaving the counselor workspace.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFE3F2FF),
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _HeroMetricCard(
                label: 'Received',
                value:
                    '${_formatDate(notification.createdAt)} ${_formatTime(notification.createdAt)}',
              ),
              _HeroMetricCard(
                label: 'Type',
                value: _formatDisplayType(notification.type),
              ),
              if (appointment != null)
                _HeroMetricCard(
                  label: 'Session date',
                  value: _formatDate(appointment.startAt),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounselorNotificationView({
    required BuildContext context,
    required AppNotification notification,
    required AppointmentRecord? appointment,
    required UserRole role,
    required UserProfile profile,
  }) {
    final isAdminMessage =
        notification.type.toLowerCase().trim() == 'admin_message';
    if (isAdminMessage) {
      return _AdminMessageReplyCard(
        notification: notification,
        profile: profile,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.go(AppRoute.notifications),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to notifications'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0C2233),
              side: const BorderSide(color: Color(0xFFD7E0EA)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildCounselorHero(
          context: context,
          notification: notification,
          appointment: appointment,
        ),
        const SizedBox(height: 18),
        _buildDetails(
          context: context,
          notification: notification,
          appointment: appointment,
          role: role,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.other;
    final firestore = _useWindowsRestFirestore
        ? null
        : ref.watch(firestoreProvider);
    final windowsRest = ref.watch(windowsFirestoreRestClientProvider);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isCounselorWorkspace =
        profile != null && profile.role == UserRole.counselor;
    final showCounselorDirectory =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile?.institutionId ?? ''),
            )
            .valueOrNull
            ?.directoryEnabled ??
        false;

    if (notificationId.trim().isEmpty) {
      if (isCounselorWorkspace) {
        final unreadCount =
            ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
        return CounselorWorkspaceScaffold(
          profile: profile,
          activeSection: CounselorWorkspaceNavSection.dashboard,
          showCounselorDirectory: showCounselorDirectory,
          unreadNotifications: unreadCount,
          notificationsHighlighted: true,
          title: 'Notification Detail',
          subtitle:
              'Review a single alert with the same counselor workspace structure used across sessions and availability.',
          onSelectSection: (section) => _navigateSection(context, section),
          onNotifications: () => context.go(AppRoute.notifications),
          onProfile: () => context.go(AppRoute.counselorSettings),
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: const _CounselorDetailStateCard(
            message: 'Invalid notification.',
          ),
        );
      }
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Text(
              'Invalid notification.',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    final notificationStream = _useWindowsRestFirestore
        ? _buildWindowsPollingStream<AppNotification?>(
            load: () async {
              final document = await windowsRest.getDocument(
                'notifications/$notificationId',
              );
              if (document == null) {
                return null;
              }
              return AppNotification.fromMap(document.id, document.data);
            },
            signature: (notification) => notification == null
                ? 'null'
                : '${notification.id}|${notification.type}|${notification.isRead}|${notification.isPinned}|${notification.isArchived}|${notification.createdAt.toIso8601String()}',
          )
        : firestore!
              .collection('notifications')
              .doc(notificationId)
              .snapshots()
              .map((doc) {
                if (!doc.exists || doc.data() == null) {
                  return null;
                }
                return AppNotification.fromMap(doc.id, doc.data()!);
              });

    final detailStream = StreamBuilder<AppNotification?>(
      stream: notificationStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final message = snapshot.error.toString().replaceFirst(
            'Exception: ',
            '',
          );
          return isCounselorWorkspace
              ? _CounselorDetailStateCard(message: message)
              : _buildErrorCard(context: context, message: message);
        }
        if (!snapshot.hasData) {
          return isCounselorWorkspace
              ? const _CounselorLoadingCard()
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                );
        }

        final notification = snapshot.data;
        if (notification == null) {
          return isCounselorWorkspace
              ? const _CounselorDetailStateCard(
                  message: 'This notification was not found.',
                )
              : _buildErrorCard(
                  context: context,
                  message: 'This notification was not found.',
                );
        }

        final relatedAppointmentId =
            notification.relatedAppointmentId?.trim() ?? '';

        Widget buildResolved(AppointmentRecord? appointment) {
          if (isCounselorWorkspace) {
            return _buildCounselorNotificationView(
              context: context,
              notification: notification,
              appointment: appointment,
              role: role,
              profile: profile,
            );
          }
          return _buildDetails(
            context: context,
            notification: notification,
            appointment: appointment,
            role: role,
          );
        }

        if (relatedAppointmentId.isEmpty) {
          return buildResolved(null);
        }

        final appointmentStream = _useWindowsRestFirestore
            ? _buildWindowsPollingStream<AppointmentRecord?>(
                load: () async {
                  final document = await windowsRest.getDocument(
                    'appointments/$relatedAppointmentId',
                  );
                  if (document == null) {
                    return null;
                  }
                  return AppointmentRecord.fromMap(document.id, document.data);
                },
                signature: (appointment) => appointment == null
                    ? 'null'
                    : '${appointment.id}|${appointment.status.name}|${appointment.startAt.toIso8601String()}|${appointment.endAt.toIso8601String()}|${appointment.counselorSessionNote ?? ''}|${appointment.counselorCancelMessage ?? ''}',
              )
            : firestore!
                  .collection('appointments')
                  .doc(relatedAppointmentId)
                  .snapshots()
                  .map((doc) {
                    if (!doc.exists || doc.data() == null) {
                      return null;
                    }
                    return AppointmentRecord.fromMap(doc.id, doc.data()!);
                  });

        return StreamBuilder<AppointmentRecord?>(
          stream: appointmentStream,
          builder: (context, appointmentSnapshot) {
            return buildResolved(appointmentSnapshot.data);
          },
        );
      },
    );

    if (isCounselorWorkspace) {
      final unreadCount =
          ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
      return CounselorWorkspaceScaffold(
        profile: profile,
        activeSection: CounselorWorkspaceNavSection.dashboard,
        showCounselorDirectory: showCounselorDirectory,
        unreadNotifications: unreadCount,
        notificationsHighlighted: true,
        title: 'Notification Detail',
        subtitle:
            'Review a single alert with the same counselor workspace structure used across sessions and availability.',
        onSelectSection: (section) => _navigateSection(context, section),
        onNotifications: () => context.go(AppRoute.notifications),
        onProfile: () => context.go(AppRoute.counselorSettings),
        onLogout: () => confirmAndLogout(context: context, ref: ref),
        child: detailStream,
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
                children: [detailStream],
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

class _AdminMessageReplyCard extends ConsumerStatefulWidget {
  const _AdminMessageReplyCard({
    required this.notification,
    required this.profile,
  });

  final AppNotification notification;
  final UserProfile profile;

  @override
  ConsumerState<_AdminMessageReplyCard> createState() =>
      _AdminMessageReplyCardState();
}

class _AdminMessageReplyCardState
    extends ConsumerState<_AdminMessageReplyCard> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _inlineError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return 'pending...';
    final local = value.toLocal();
    final twoDigits = (int v) => v.toString().padLeft(2, '0');
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} ${twoDigits(hour12)}:${twoDigits(local.minute)} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final relatedId = widget.notification.relatedId?.trim() ?? '';
    final firestore = _useWindowsRestFirestore
        ? null
        : ref.watch(firestoreProvider);
    final windowsRest = ref.watch(windowsFirestoreRestClientProvider);
    final scheme = Theme.of(context).colorScheme;

    if (relatedId.isEmpty) {
      return const _CounselorDetailStateCard(
        message: 'Message reference missing for this notification.',
      );
    }

    final rootStream = _useWindowsRestFirestore
        ? _buildWindowsPollingStream<Map<String, dynamic>?>(
            load: () async => (await windowsRest.getDocument(
              'admin_counselor_messages/$relatedId',
            ))?.data,
            signature: (data) => data == null ? 'null' : data.toString(),
          )
        : firestore!
              .collection('admin_counselor_messages')
              .doc(relatedId)
              .snapshots()
              .map((doc) => doc.data());

    return StreamBuilder<Map<String, dynamic>?>(
      stream: rootStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CounselorDetailStateCard(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return const _CounselorDetailStateCard(
            message: 'The admin message could not be loaded.',
          );
        }

        final root = snapshot.data!;

        final adminId = (root['adminId'] as String?) ?? '';
        final counselorId = (root['counselorId'] as String?) ?? '';
        final institutionId = (root['institutionId'] as String?) ?? '';
        final threadKey = '$adminId|$counselorId';

        if (counselorId != widget.profile.id) {
          return const _CounselorDetailStateCard(
            message: 'This message is not assigned to your account.',
          );
        }

        final messagesStream = _useWindowsRestFirestore
            ? _buildWindowsPollingStream<List<Map<String, dynamic>>>(
                load: () async {
                  final documents = await windowsRest.queryCollection(
                    collectionId: 'admin_counselor_messages',
                    filters: <WindowsFirestoreFieldFilter>[
                      WindowsFirestoreFieldFilter.equal('adminId', adminId),
                      WindowsFirestoreFieldFilter.equal(
                        'counselorId',
                        counselorId,
                      ),
                    ],
                    orderBy: const <WindowsFirestoreOrderBy>[
                      WindowsFirestoreOrderBy('createdAt', descending: true),
                    ],
                  );
                  return documents
                      .map(
                        (doc) => <String, dynamic>{'id': doc.id, ...doc.data},
                      )
                      .toList(growable: false);
                },
                signature: (items) => items
                    .map(
                      (item) =>
                          '${item['id'] ?? ''}|${item['senderRole'] ?? ''}|${item['body'] ?? ''}|${item['createdAt'] ?? ''}',
                    )
                    .join(';'),
              )
            : firestore!
                  .collection('admin_counselor_messages')
                  .where('adminId', isEqualTo: adminId)
                  .where('counselorId', isEqualTo: counselorId)
                  .orderBy('createdAt', descending: true)
                  .snapshots()
                  .map(
                    (snapshot) => snapshot.docs
                        .map(
                          (doc) => <String, dynamic>{
                            'id': doc.id,
                            ...doc.data(),
                          },
                        )
                        .toList(growable: false),
                  );

        Future<void> send() async {
          final text = _controller.text.trim();
          if (text.isEmpty) return;
          setState(() {
            _sending = true;
            _inlineError = null;
          });
          try {
            if (_useWindowsRestFirestore) {
              final now = DateTime.now().toUtc();
              final msgId =
                  'msg_${widget.profile.id}_${now.microsecondsSinceEpoch}';
              final notifId =
                  'notif_${widget.profile.id}_${now.microsecondsSinceEpoch}';
              await windowsRest.setDocument(
                'admin_counselor_messages/$msgId',
                <String, dynamic>{
                  'threadKey': threadKey,
                  'adminId': adminId,
                  'counselorId': counselorId,
                  'institutionId': institutionId,
                  'senderRole': 'counselor',
                  'senderId': widget.profile.id,
                  'body': text,
                  'isRead': false,
                  'createdAt': now,
                },
              );
              await windowsRest
                  .setDocument('notifications/$notifId', <String, dynamic>{
                    'userId': adminId,
                    'institutionId': institutionId,
                    'type': 'counselor_message',
                    'title': 'Reply from ${widget.profile.name}',
                    'body': text,
                    'priority': 'normal',
                    'actionRequired': false,
                    'relatedId': msgId,
                    'createdAt': now,
                    'updatedAt': now,
                    'isRead': false,
                    'isPinned': false,
                    'isArchived': false,
                  });
            } else {
              final msgRef = firestore!
                  .collection('admin_counselor_messages')
                  .doc();
              await firestore.runTransaction((txn) async {
                txn.set(msgRef, {
                  'threadKey': threadKey,
                  'adminId': adminId,
                  'counselorId': counselorId,
                  'institutionId': institutionId,
                  'senderRole': 'counselor',
                  'senderId': widget.profile.id,
                  'body': text,
                  'isRead': false,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                final notifRef = firestore.collection('notifications').doc();
                txn.set(notifRef, {
                  'userId': adminId,
                  'institutionId': institutionId,
                  'type': 'counselor_message',
                  'title': 'Reply from ${widget.profile.name}',
                  'body': text,
                  'priority': 'normal',
                  'actionRequired': false,
                  'relatedId': msgRef.id,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                  'isRead': false,
                  'isPinned': false,
                  'isArchived': false,
                });
              });
            }
            _controller.clear();
          } catch (error) {
            setState(() => _inlineError = error.toString());
          } finally {
            if (mounted) setState(() => _sending = false);
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(
              'Conversation with your institution admin',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              height: 360,
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: messagesStream,
                builder: (context, msgSnapshot) {
                  if (msgSnapshot.hasError) {
                    return Center(
                      child: Text(
                        msgSnapshot.error.toString(),
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    );
                  }
                  final docs =
                      msgSnapshot.data ?? const <Map<String, dynamic>>[];
                  if (msgSnapshot.connectionState == ConnectionState.waiting &&
                      docs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  }

                  return ListView.separated(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index];
                      final isCounselor =
                          (data['senderRole'] as String?) == 'counselor';
                      DateTime? created;
                      final raw = data['createdAt'];
                      if (raw is Timestamp) {
                        created = raw.toDate();
                      } else if (raw is DateTime) {
                        created = raw;
                      }
                      return Align(
                        alignment: isCounselor
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isCounselor
                                ? scheme.primary
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['body'] as String?) ?? '',
                                  style: TextStyle(
                                    color: isCounselor
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(created),
                                  style: TextStyle(
                                    color: isCounselor
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Reply to the admin...',
                      filled: true,
                      fillColor: Color(0xFFF8FAFC),
                      prefixIcon: Icon(Icons.chat_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _sending || _controller.text.trim().isEmpty
                      ? null
                      : send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_sending ? 'Sending...' : 'Send'),
                ),
              ],
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 8),
              Text(
                _inlineError!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.background});

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _HeroMetricCard extends StatelessWidget {
  const _HeroMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFDDEBFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CounselorDetailStateCard extends StatelessWidget {
  const _CounselorDetailStateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF506176),
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    );
  }
}

class _CounselorLoadingCard extends StatelessWidget {
  const _CounselorLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
