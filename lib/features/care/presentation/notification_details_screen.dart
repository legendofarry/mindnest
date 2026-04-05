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
import 'package:mindnest/features/care/models/session_reassignment_request.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

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
  const NotificationDetailsScreen({
    super.key,
    required this.notificationId,
    this.embedded = false,
  });

  final String notificationId;
  final bool embedded;

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
    if (normalized == 'institution_invite') {
      return Icons.mark_email_unread_rounded;
    }
    if (normalized == 'admin_message' || normalized == 'counselor_message') {
      return Icons.chat_bubble_outline_rounded;
    }
    if (normalized.contains('reassignment')) {
      return Icons.swap_horiz_rounded;
    }
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
    if (normalized == 'institution_invite') {
      return const Color(0xFF0E9B90);
    }
    if (normalized == 'admin_message' || normalized == 'counselor_message') {
      return const Color(0xFF2563EB);
    }
    if (normalized.contains('reassignment')) {
      return const Color(0xFF4F46E5);
    }
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
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final accent = _typeAccent(scheme, notification.type);
    final icon = _typeIcon(notification.type);

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

  Widget _buildCounselorNotificationView({
    required BuildContext context,
    required AppNotification notification,
    required AppointmentRecord? appointment,
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

    final actionPanel = _buildCounselorNotificationActionPanel(
      notification: notification,
      profile: profile,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetails(
          context: context,
          notification: notification,
          appointment: appointment,
        ),
        if (actionPanel != null) ...[const SizedBox(height: 16), actionPanel],
      ],
    );
  }

  Widget? _buildCounselorNotificationActionPanel({
    required AppNotification notification,
    required UserProfile profile,
  }) {
    final type = notification.type.toLowerCase().trim();
    if (type == 'institution_invite') {
      return _CounselorInviteNotificationActionCard(
        notification: notification,
        profile: profile,
      );
    }
    if (type == 'reassignment_request_available') {
      return _CounselorReassignmentInterestActionCard(
        notification: notification,
        profile: profile,
      );
    }
    if (type == 'reassignment_patient_selected') {
      return _CounselorReassignmentSelectionActionCard(
        notification: notification,
        profile: profile,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
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
      if (embedded) {
        return const _CounselorDetailStateCard(
          message: 'Invalid notification.',
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
              profile: profile,
            );
          }
          return _buildDetails(
            context: context,
            notification: notification,
            appointment: appointment,
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

    if (embedded) {
      return detailStream;
    }

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
    String twoDigits(int v) => v.toString().padLeft(2, '0');
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
                      WindowsFirestoreFieldFilter.equal('threadKey', threadKey),
                    ],
                  );
                  final items = documents
                      .map(
                        (doc) => <String, dynamic>{'id': doc.id, ...doc.data},
                      )
                      .toList(growable: false);
                  items.sort((left, right) {
                    DateTime parse(dynamic raw) {
                      if (raw is Timestamp) {
                        return raw.toDate();
                      }
                      if (raw is DateTime) {
                        return raw;
                      }
                      return DateTime.fromMillisecondsSinceEpoch(0);
                    }

                    return parse(
                      right['createdAt'],
                    ).compareTo(parse(left['createdAt']));
                  });
                  return items;
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
                  .where('threadKey', isEqualTo: threadKey)
                  .snapshots()
                  .map((snapshot) {
                    final items = snapshot.docs
                        .map(
                          (doc) => <String, dynamic>{
                            'id': doc.id,
                            ...doc.data(),
                          },
                        )
                        .toList(growable: false);
                    items.sort((left, right) {
                      DateTime parse(dynamic raw) {
                        if (raw is Timestamp) {
                          return raw.toDate();
                        }
                        if (raw is DateTime) {
                          return raw;
                        }
                        return DateTime.fromMillisecondsSinceEpoch(0);
                      }

                      return parse(
                        right['createdAt'],
                      ).compareTo(parse(left['createdAt']));
                    });
                    return items;
                  });

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
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
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

class _CounselorActionPanelCard extends StatelessWidget {
  const _CounselorActionPanelCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B1A33),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CounselorInlineFeedback extends StatelessWidget {
  const _CounselorInlineFeedback({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? const Color(0xFFDC2626) : const Color(0xFF0E9B90);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

class _CounselorInviteNotificationActionCard extends ConsumerStatefulWidget {
  const _CounselorInviteNotificationActionCard({
    required this.notification,
    required this.profile,
  });

  final AppNotification notification;
  final UserProfile profile;

  @override
  ConsumerState<_CounselorInviteNotificationActionCard> createState() =>
      _CounselorInviteNotificationActionCardState();
}

class _CounselorInviteNotificationActionCardState
    extends ConsumerState<_CounselorInviteNotificationActionCard> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _setFeedback(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  Future<void> _accept(UserInvite invite) async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _setFeedback(
        'Enter the institution code to accept this invite.',
        isError: true,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .acceptInvite(invite: invite, institutionCode: code);
      await syncAuthSessionState(ref);
      if (!mounted) {
        return;
      }
      final refreshedProfile = ref.read(currentUserProfileProvider).valueOrNull;
      if (refreshedProfile?.role == UserRole.counselor &&
          refreshedProfile?.counselorSetupCompleted == true) {
        context.go(AppRoute.counselorDashboard);
        return;
      }
      context.go(AppRoute.counselorSetup);
    } catch (error) {
      _setFeedback(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _decline(UserInvite invite) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(institutionRepositoryProvider).declineInvite(invite);
      _codeController.clear();
      _setFeedback(
        'Invite declined. The alert will remain here as history, but no further action is needed.',
        isError: false,
      );
    } catch (error) {
      _setFeedback(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteId = widget.notification.relatedId?.trim() ?? '';
    if (inviteId.isEmpty) {
      return const _CounselorDetailStateCard(
        message: 'This invite alert is missing its invite reference.',
      );
    }

    final inviteAsync = ref.watch(inviteByIdProvider(inviteId));

    return inviteAsync.when(
      loading: () => const _CounselorLoadingCard(),
      error: (error, _) => _CounselorDetailStateCard(
        message: error.toString().replaceFirst('Exception: ', ''),
      ),
      data: (invite) {
        if (invite == null) {
          return const _CounselorDetailStateCard(
            message: 'This invite is no longer available.',
          );
        }
        if (invite.inviteeUid.trim().isNotEmpty &&
            invite.inviteeUid != widget.profile.id) {
          return const _CounselorDetailStateCard(
            message: 'This invite belongs to another account.',
          );
        }

        final institutionDocAsync = ref.watch(
          institutionDocumentProvider(invite.institutionId),
        );
        final joinCode =
            (institutionDocAsync.valueOrNull?['joinCode'] as String? ?? '')
                .trim()
                .toUpperCase();
        if (joinCode.isNotEmpty &&
            widget.profile.role == UserRole.counselor &&
            _codeController.text.trim() != joinCode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _codeController.text.trim() != joinCode) {
              _codeController.text = joinCode;
            }
          });
        }

        if (!invite.isPending) {
          final statusLabel = switch (invite.status) {
            UserInviteStatus.accepted => 'accepted',
            UserInviteStatus.declined => 'declined',
            UserInviteStatus.revoked => 'revoked',
            UserInviteStatus.pending =>
              invite.isExpired ? 'expired' : 'pending',
            UserInviteStatus.unknown => 'closed',
          };
          final resolvedChild = _feedback != null
              ? _CounselorInlineFeedback(
                  message: _feedback!,
                  isError: _feedbackIsError,
                )
              : const Text(
                  'No further action is needed here.',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w700,
                  ),
                );
          return _CounselorActionPanelCard(
            title: 'Invite action already resolved',
            body:
                'This invite is now $statusLabel, so the notification stays informational only.',
            icon: Icons.mark_email_read_rounded,
            accent: const Color(0xFF0E9B90),
            child: resolvedChild,
          );
        }

        return _CounselorActionPanelCard(
          title: 'Invite decision needed',
          body:
              'This is a real pending institution invite, so this is one of the few counselor notifications that should keep actions.',
          icon: Icons.mark_email_unread_rounded,
          accent: const Color(0xFF0E9B90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Institution code',
                  hintText: 'Enter or confirm the institution code',
                  prefixIcon: const Icon(Icons.key_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                _CounselorInlineFeedback(
                  message: _feedback!,
                  isError: _feedbackIsError,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : () => _accept(invite),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _isSubmitting ? 'Accepting...' : 'Accept invite',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : () => _decline(invite),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Decline invite'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CounselorReassignmentInterestActionCard extends ConsumerStatefulWidget {
  const _CounselorReassignmentInterestActionCard({
    required this.notification,
    required this.profile,
  });

  final AppNotification notification;
  final UserProfile profile;

  @override
  ConsumerState<_CounselorReassignmentInterestActionCard> createState() =>
      _CounselorReassignmentInterestActionCardState();
}

class _CounselorReassignmentInterestActionCardState
    extends ConsumerState<_CounselorReassignmentInterestActionCard> {
  bool _submitting = false;
  String? _feedback;
  bool _feedbackIsError = false;

  void _setFeedback(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  Future<void> _expressInterest(SessionReassignmentRequest request) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .expressInterestInReassignment(request.id);
      _setFeedback(
        'Interest recorded. The original counselor and student were updated immediately.',
        isError: false,
      );
    } catch (error) {
      _setFeedback(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointmentId =
        widget.notification.relatedAppointmentId?.trim() ?? '';
    if (appointmentId.isEmpty) {
      return const _CounselorDetailStateCard(
        message: 'This transfer alert is missing its session reference.',
      );
    }

    final requestAsync = ref.watch(
      appointmentReassignmentRequestProvider(appointmentId),
    );

    return requestAsync.when(
      loading: () => const _CounselorLoadingCard(),
      error: (error, _) => _CounselorDetailStateCard(
        message: error.toString().replaceFirst('Exception: ', ''),
      ),
      data: (request) {
        if (request == null) {
          return const _CounselorDetailStateCard(
            message: 'This reassignment request is no longer active.',
          );
        }
        final alreadyInterested = request.interestedCounselors.any(
          (entry) => entry.counselorId == widget.profile.id,
        );
        final canRespond =
            request.originalCounselorId != widget.profile.id &&
            request.status == SessionReassignmentStatus.openForResponses &&
            DateTime.now().toUtc().isBefore(request.responseDeadlineAt) &&
            !alreadyInterested;

        return _CounselorActionPanelCard(
          title: 'Coverage decision available',
          body:
              'This alert is still actionable, so it keeps one inline decision instead of dumping you into a redirect.',
          icon: Icons.volunteer_activism_outlined,
          accent: const Color(0xFF4F46E5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (alreadyInterested)
                const _CounselorInlineFeedback(
                  message:
                      'You already raised your hand for this reassignment request.',
                  isError: false,
                )
              else if (!canRespond)
                const _CounselorInlineFeedback(
                  message:
                      'This request is no longer accepting counselor responses.',
                  isError: true,
                )
              else
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _expressInterest(request),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.volunteer_activism_outlined),
                  label: Text(
                    _submitting ? 'Submitting...' : 'I can take this session',
                  ),
                ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                _CounselorInlineFeedback(
                  message: _feedback!,
                  isError: _feedbackIsError,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CounselorReassignmentSelectionActionCard extends ConsumerStatefulWidget {
  const _CounselorReassignmentSelectionActionCard({
    required this.notification,
    required this.profile,
  });

  final AppNotification notification;
  final UserProfile profile;

  @override
  ConsumerState<_CounselorReassignmentSelectionActionCard> createState() =>
      _CounselorReassignmentSelectionActionCardState();
}

class _CounselorReassignmentSelectionActionCardState
    extends ConsumerState<_CounselorReassignmentSelectionActionCard> {
  bool _submitting = false;
  String? _feedback;
  bool _feedbackIsError = false;

  void _setFeedback(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  Future<void> _confirmTransfer(SessionReassignmentRequest request) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .confirmReassignmentTransfer(request.id);
      _setFeedback(
        'Transfer confirmed. The replacement counselor now owns the session.',
        isError: false,
      );
    } catch (error) {
      _setFeedback(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointmentId =
        widget.notification.relatedAppointmentId?.trim() ?? '';
    if (appointmentId.isEmpty) {
      return const _CounselorDetailStateCard(
        message:
            'This transfer-selection alert is missing its session reference.',
      );
    }

    final requestAsync = ref.watch(
      appointmentReassignmentRequestProvider(appointmentId),
    );

    return requestAsync.when(
      loading: () => const _CounselorLoadingCard(),
      error: (error, _) => _CounselorDetailStateCard(
        message: error.toString().replaceFirst('Exception: ', ''),
      ),
      data: (request) {
        if (request == null) {
          return const _CounselorDetailStateCard(
            message: 'This reassignment request is no longer active.',
          );
        }

        final isOriginalCounselor =
            request.originalCounselorId == widget.profile.id;
        final isSelectedCounselor =
            request.selectedCounselorId == widget.profile.id;
        final canConfirm =
            isOriginalCounselor &&
            request.status == SessionReassignmentStatus.patientSelected &&
            (request.selectedCounselorId ?? '').trim().isNotEmpty;

        final title = isOriginalCounselor
            ? 'Patient choice is ready'
            : 'Patient selected you';
        final body = isOriginalCounselor
            ? 'This is still a live decision for the original counselor, so confirming the transfer here makes sense.'
            : 'You were selected as the replacement counselor. This stays informational because the original counselor still has the final handoff step.';

        return _CounselorActionPanelCard(
          title: title,
          body: body,
          icon: Icons.swap_horiz_rounded,
          accent: const Color(0xFF4F46E5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canConfirm)
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _confirmTransfer(request),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _submitting ? 'Confirming...' : 'Confirm transfer',
                  ),
                )
              else if (isSelectedCounselor)
                const _CounselorInlineFeedback(
                  message:
                      'You have been selected as the replacement counselor. Wait for the original counselor to finalize the handoff.',
                  isError: false,
                )
              else
                const _CounselorInlineFeedback(
                  message:
                      'This transfer selection is already resolved or no longer actionable here.',
                  isError: true,
                ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                _CounselorInlineFeedback(
                  message: _feedback!,
                  isError: _feedbackIsError,
                ),
              ],
            ],
          ),
        );
      },
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
