import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/app_notification.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  bool _showUnreadOnly = false;
  final Set<String> _openingNotificationIds = <String>{};
  final Set<String> _actionNotificationIds = <String>{};

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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

  String _notificationDetailsRoute(String notificationId) {
    return Uri(
      path: AppRoute.notificationDetails,
      queryParameters: <String, String>{'notificationId': notificationId},
    ).toString();
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (_openingNotificationIds.contains(notification.id)) {
      return;
    }
    setState(() => _openingNotificationIds.add(notification.id));

    try {
      if (!notification.isRead) {
        await ref
            .read(careRepositoryProvider)
            .markNotificationRead(notification.id);
      }
      if (!mounted) {
        return;
      }
      context.go(_notificationDetailsRoute(notification.id));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingNotificationIds.remove(notification.id));
      }
    }
  }

  RelativeRect _menuPosition(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromCircle(center: globalPosition, radius: 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _showNotificationMenu({
    required AppNotification notification,
    required Offset globalPosition,
  }) async {
    final selected = await showMenu<_NotificationContextAction>(
      context: context,
      position: _menuPosition(globalPosition),
      items: <PopupMenuEntry<_NotificationContextAction>>[
        PopupMenuItem<_NotificationContextAction>(
          value: notification.isPinned
              ? _NotificationContextAction.unpin
              : _NotificationContextAction.pin,
          child: Row(
            children: [
              Icon(
                notification.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
              ),
              const SizedBox(width: 10),
              Text(
                notification.isPinned
                    ? 'Unpin notification'
                    : 'Pin notification',
              ),
            ],
          ),
        ),
        if (!notification.isRead)
          const PopupMenuItem<_NotificationContextAction>(
            value: _NotificationContextAction.markRead,
            child: Row(
              children: [
                Icon(Icons.mark_email_read_outlined),
                SizedBox(width: 10),
                Text('Mark as read'),
              ],
            ),
          ),
        const PopupMenuItem<_NotificationContextAction>(
          value: _NotificationContextAction.archive,
          child: Row(
            children: [
              Icon(Icons.archive_outlined),
              SizedBox(width: 10),
              Text('Archive'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_NotificationContextAction>(
          value: _NotificationContextAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Text('Delete notification'),
            ],
          ),
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    await _runNotificationAction(notification: notification, action: selected);
  }

  Future<void> _runNotificationAction({
    required AppNotification notification,
    required _NotificationContextAction action,
  }) async {
    if (_actionNotificationIds.contains(notification.id) ||
        _openingNotificationIds.contains(notification.id)) {
      return;
    }
    setState(() => _actionNotificationIds.add(notification.id));
    try {
      final repo = ref.read(careRepositoryProvider);
      switch (action) {
        case _NotificationContextAction.pin:
          await repo.setNotificationPinned(
            notificationId: notification.id,
            pinned: true,
          );
        case _NotificationContextAction.unpin:
          await repo.setNotificationPinned(
            notificationId: notification.id,
            pinned: false,
          );
        case _NotificationContextAction.markRead:
          await repo.markNotificationRead(notification.id);
        case _NotificationContextAction.archive:
          await repo.setNotificationArchived(
            notificationId: notification.id,
            archived: true,
          );
        case _NotificationContextAction.delete:
          await repo.deleteNotification(notification.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actionNotificationIds.remove(notification.id));
      }
    }
  }

  Widget _header({
    required BuildContext context,
    required List<AppNotification> notifications,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unreadCount = notifications
        .where((entry) => !entry.isRead && !entry.isArchived)
        .length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: textTheme.headlineMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unreadCount > 0
                    ? '$unreadCount unread updates'
                    : 'Stay updated with your sessions',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: null,
          icon: Icon(
            Icons.more_horiz_rounded,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          tooltip: 'More',
        ),
      ],
    );
  }

  Widget _segmentedControl({
    required BuildContext context,
    required List<AppNotification> notifications,
    required String userId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final containerColor = scheme.surfaceContainerHighest.withValues(
      alpha: 0.45,
    );
    final activeBg = scheme.surface;
    final activeText = scheme.onSurface;
    final inactiveText = scheme.onSurfaceVariant;
    final canMarkAllRead =
        userId.isNotEmpty &&
        notifications.any((entry) => !entry.isRead && !entry.isArchived);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _segmentChip(
            context: context,
            label: 'All',
            active: !_showUnreadOnly,
            activeBg: activeBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () => setState(() => _showUnreadOnly = false),
          ),
          const SizedBox(width: 8),
          _segmentChip(
            context: context,
            label: 'Unread',
            active: _showUnreadOnly,
            activeBg: activeBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () => setState(() => _showUnreadOnly = true),
          ),
          const Spacer(),
          TextButton(
            onPressed: canMarkAllRead
                ? () => ref
                      .read(careRepositoryProvider)
                      .markAllNotificationsRead(userId)
                : null,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              textStyle: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Mark all read'),
          ),
        ],
      ),
    );
  }

  Widget _segmentChip({
    required BuildContext context,
    required String label,
    required bool active,
    required Color activeBg,
    required Color activeText,
    required Color inactiveText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? activeText : inactiveText,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _notificationCard({
    required BuildContext context,
    required AppNotification entry,
    required bool isBusy,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _typeAccent(scheme, entry.type);
    final iconBg = accent.withValues(alpha: 0.12);
    final cardBg = scheme.surface;
    final borderColor = entry.isRead
        ? scheme.outlineVariant.withValues(alpha: 0.45)
        : scheme.primary.withValues(alpha: 0.26);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: isBusy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_typeIcon(entry.type), color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: textTheme.titleLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: entry.isRead
                                  ? FontWeight.w700
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (entry.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 8),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                        if (isBusy)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (!entry.isRead)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.body,
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_formatDate(entry.createdAt)}  •  ${_formatTime(entry.createdAt)}',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context, {required bool forUnread}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        forUnread
            ? 'No unread notifications right now.'
            : 'No notifications yet. Booking, reminders, and cancellations will show here.',
        style: textTheme.titleMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: userId.isEmpty
                  ? _emptyCard(context, forUnread: false)
                  : StreamBuilder<List<AppNotification>>(
                      stream: ref
                          .read(careRepositoryProvider)
                          .watchUserNotifications(userId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _emptyCard(context, forUnread: false);
                        }

                        final notifications = snapshot.data ?? const [];
                        final filtered = notifications
                            .where(
                              (entry) =>
                                  !entry.isArchived &&
                                  (!_showUnreadOnly || !entry.isRead),
                            )
                            .toList(growable: false);

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            notifications.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(
                              context: context,
                              notifications: notifications,
                            ),
                            const SizedBox(height: 16),
                            _segmentedControl(
                              context: context,
                              notifications: notifications,
                              userId: userId,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: filtered.isEmpty
                                  ? Align(
                                      alignment: Alignment.topCenter,
                                      child: _emptyCard(
                                        context,
                                        forUnread: _showUnreadOnly,
                                      ),
                                    )
                                  : ListView.separated(
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.only(bottom: 8),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, index) {
                                        final entry = filtered[index];
                                        final isBusy =
                                            _openingNotificationIds.contains(
                                              entry.id,
                                            ) ||
                                            _actionNotificationIds.contains(
                                              entry.id,
                                            );
                                        return GestureDetector(
                                          onSecondaryTapDown: isBusy
                                              ? null
                                              : (details) =>
                                                    _showNotificationMenu(
                                                      notification: entry,
                                                      globalPosition: details
                                                          .globalPosition,
                                                    ),
                                          onLongPressStart: isBusy
                                              ? null
                                              : (details) =>
                                                    _showNotificationMenu(
                                                      notification: entry,
                                                      globalPosition: details
                                                          .globalPosition,
                                                    ),
                                          child: _notificationCard(
                                            context: context,
                                            entry: entry,
                                            isBusy: isBusy,
                                            onTap: () =>
                                                _openNotification(entry),
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
          ),
        ),
      ),
    );
  }
}

enum _NotificationContextAction { pin, unpin, markRead, archive, delete }
