import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_primary_shell.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/app_notification.dart';
import 'package:mindnest/features/care/presentation/notification_details_screen.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({
    super.key,
    this.initialSelectedNotificationId,
    this.embeddedInCounselorShell = false,
  });

  final String? initialSelectedNotificationId;
  final bool embeddedInCounselorShell;

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  _NotificationFilter _activeFilter = _NotificationFilter.all;
  bool _clearingAll = false;
  bool _refreshingNotifications = false;
  bool _notificationsLoaded = false;
  final Set<String> _openingNotificationIds = <String>{};
  final Set<String> _actionNotificationIds = <String>{};
  Stream<List<AppNotification>>? _notificationsStream;
  String? _notificationsStreamUserId;
  String? _loadedNotificationsUserId;
  String? _notificationsErrorMessage;
  String? _selectedNotificationId;
  List<AppNotification> _cachedNotifications = const <AppNotification>[];

  @override
  void initState() {
    super.initState();
    _selectedNotificationId = widget.initialSelectedNotificationId?.trim();
  }

  @override
  void didUpdateWidget(covariant NotificationCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSelected = widget.initialSelectedNotificationId?.trim();
    if (nextSelected != oldWidget.initialSelectedNotificationId?.trim() &&
        nextSelected != _selectedNotificationId) {
      _selectedNotificationId = nextSelected;
    }
  }

  bool get _useManualRefreshMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Stream<List<AppNotification>> _notificationStreamFor(String userId) {
    if (_notificationsStream == null || _notificationsStreamUserId != userId) {
      _notificationsStreamUserId = userId;
      _notificationsStream = ref
          .read(careRepositoryProvider)
          .watchUserNotifications(userId);
    }
    return _notificationsStream!;
  }

  List<AppNotification> _sortNotifications(
    Iterable<AppNotification> notifications,
  ) {
    final items = notifications.toList(growable: false);
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (a.isPinned && b.isPinned) {
        final aPinned = a.pinnedAt ?? a.createdAt;
        final bPinned = b.pinnedAt ?? b.createdAt;
        final pinnedCompare = bPinned.compareTo(aPinned);
        if (pinnedCompare != 0) {
          return pinnedCompare;
        }
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  String _messageFromError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  void _ensureManualNotificationsLoaded(String userId) {
    if (!_useManualRefreshMode || userId.trim().isEmpty) {
      return;
    }
    if (_loadedNotificationsUserId == userId &&
        (_notificationsLoaded || _refreshingNotifications)) {
      return;
    }
    _loadedNotificationsUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshNotifications(userId: userId, silent: true);
    });
  }

  Future<void> _refreshNotifications({
    required String userId,
    bool silent = false,
  }) async {
    if (userId.trim().isEmpty || _refreshingNotifications) {
      return;
    }
    if (mounted) {
      setState(() {
        _refreshingNotifications = true;
        if (!silent) {
          _notificationsErrorMessage = null;
        }
      });
    }
    try {
      final items = await ref
          .read(careRepositoryProvider)
          .getUserNotifications(userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedNotificationsUserId = userId;
        _cachedNotifications = _sortNotifications(items);
        _notificationsLoaded = true;
        _notificationsErrorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _messageFromError(error);
      setState(() {
        _loadedNotificationsUserId = userId;
        _notificationsLoaded = true;
        _notificationsErrorMessage = message;
      });
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingNotifications = false);
      }
    }
  }

  void _replaceCachedNotification(AppNotification updated) {
    if (!_useManualRefreshMode || !mounted) {
      return;
    }
    setState(() {
      _cachedNotifications = _sortNotifications(
        _cachedNotifications.map(
          (entry) => entry.id == updated.id ? updated : entry,
        ),
      );
    });
  }

  void _removeCachedNotification(String notificationId) {
    if (!_useManualRefreshMode || !mounted) {
      return;
    }
    setState(() {
      _cachedNotifications = _cachedNotifications
          .where((entry) => entry.id != notificationId)
          .toList(growable: false);
      if (_selectedNotificationId == notificationId) {
        _selectedNotificationId = null;
      }
    });
  }

  void _markAllCachedNotificationsRead() {
    if (!_useManualRefreshMode || !mounted) {
      return;
    }
    setState(() {
      _cachedNotifications = _cachedNotifications
          .map(
            (entry) => entry.isArchived ? entry : entry.copyWith(isRead: true),
          )
          .toList(growable: false);
    });
  }

  List<AppNotification> _filteredNotifications(
    List<AppNotification> notifications,
  ) {
    return notifications
        .where(
          (entry) => switch (_activeFilter) {
            _NotificationFilter.all => !entry.isArchived,
            _NotificationFilter.unread => !entry.isArchived && !entry.isRead,
            _NotificationFilter.archived => entry.isArchived,
          },
        )
        .toList(growable: false);
  }

  _NotificationScreenCopy _screenCopy(UserProfile? profile) {
    switch (profile?.role) {
      case UserRole.institutionAdmin:
        return const _NotificationScreenCopy(
          headerTitle: 'Notifications',
          subtitle: 'Track institution updates and action-required alerts.',
          heroText:
              'Track institution invites, counselor updates, and action-required changes without losing context.',
        );
      case UserRole.counselor:
        return const _NotificationScreenCopy(
          headerTitle: 'Notifications',
          subtitle: 'Track booking updates, reminders, and access changes.',
          heroText:
              'Track session changes, reminders, and action-required alerts without losing context.',
        );
      default:
        return const _NotificationScreenCopy(
          headerTitle: 'Notifications',
          subtitle: 'Stay updated with your sessions',
          heroText:
              'Track session updates, invites, reminders, and action-required changes without losing context.',
        );
    }
  }

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
    if (normalized == 'institution_invite') {
      return Icons.mark_email_unread_rounded;
    }
    if (normalized.contains('accepted')) {
      return Icons.check_circle_outline_rounded;
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
    if (normalized.contains('accepted')) {
      return const Color(0xFF059669);
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

  String _notificationDetailsRoute(String notificationId) {
    return Uri(
      path: AppRoute.notificationDetails,
      queryParameters: <String, String>{'notificationId': notificationId},
    ).toString();
  }

  String _notificationTargetRoute(AppNotification notification) {
    final normalizedType = notification.type.toLowerCase();
    if (normalizedType == 'admin_message' ||
        normalizedType == 'counselor_message') {
      return _notificationDetailsRoute(notification.id);
    }

    final rawRoute = (notification.route ?? '').trim();
    if (rawRoute.isNotEmpty) {
      return rawRoute;
    }
    if (normalizedType == 'institution_invite' &&
        (notification.relatedId ?? '').trim().isNotEmpty) {
      return Uri(
        path: AppRoute.inviteAccept,
        queryParameters: <String, String>{
          'inviteId': (notification.relatedId ?? '').trim(),
        },
      ).toString();
    }
    return _notificationDetailsRoute(notification.id);
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
        _replaceCachedNotification(notification.copyWith(isRead: true));
      }
      if (!mounted) {
        return;
      }
      context.go(_notificationTargetRoute(notification));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(error))));
    } finally {
      if (mounted) {
        setState(() => _openingNotificationIds.remove(notification.id));
      }
    }
  }

  Future<void> _selectNotification(AppNotification notification) async {
    if (_openingNotificationIds.contains(notification.id)) {
      return;
    }

    setState(() {
      _selectedNotificationId = notification.id;
      _openingNotificationIds.add(notification.id);
    });

    try {
      if (!notification.isRead) {
        await ref
            .read(careRepositoryProvider)
            .markNotificationRead(notification.id);
        _replaceCachedNotification(notification.copyWith(isRead: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(error))));
    } finally {
      if (mounted) {
        setState(() => _openingNotificationIds.remove(notification.id));
      }
    }
  }

  String? _effectiveSelectedNotificationId(
    List<AppNotification> notifications,
    List<AppNotification> filtered,
    bool useInlineDetails,
  ) {
    if (!useInlineDetails || filtered.isEmpty) {
      return null;
    }

    final current = _selectedNotificationId?.trim();
    if (current != null &&
        current.isNotEmpty &&
        filtered.any((entry) => entry.id == current)) {
      return current;
    }

    if (widget.initialSelectedNotificationId?.trim().isNotEmpty == true) {
      final initial = widget.initialSelectedNotificationId!.trim();
      if (filtered.any((entry) => entry.id == initial)) {
        return initial;
      }
    }

    final fallback = filtered.isNotEmpty ? filtered.first.id : null;
    return fallback;
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
        if (notification.isArchived)
          const PopupMenuItem<_NotificationContextAction>(
            value: _NotificationContextAction.unarchive,
            child: Row(
              children: [
                Icon(Icons.unarchive_outlined),
                SizedBox(width: 10),
                Text('Unarchive'),
              ],
            ),
          )
        else
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
      final now = DateTime.now();
      switch (action) {
        case _NotificationContextAction.pin:
          await repo.setNotificationPinned(
            notificationId: notification.id,
            pinned: true,
          );
          _replaceCachedNotification(
            notification.copyWith(isPinned: true, pinnedAt: now),
          );
        case _NotificationContextAction.unpin:
          await repo.setNotificationPinned(
            notificationId: notification.id,
            pinned: false,
          );
          _replaceCachedNotification(
            notification.copyWith(isPinned: false, pinnedAt: null),
          );
        case _NotificationContextAction.markRead:
          await repo.markNotificationRead(notification.id);
          _replaceCachedNotification(notification.copyWith(isRead: true));
        case _NotificationContextAction.archive:
          await repo.setNotificationArchived(
            notificationId: notification.id,
            archived: true,
          );
          _replaceCachedNotification(
            notification.copyWith(isArchived: true, archivedAt: now),
          );
        case _NotificationContextAction.unarchive:
          await repo.setNotificationArchived(
            notificationId: notification.id,
            archived: false,
          );
          _replaceCachedNotification(
            notification.copyWith(isArchived: false, archivedAt: null),
          );
        case _NotificationContextAction.delete:
          await repo.deleteNotification(notification.id);
          _removeCachedNotification(notification.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(error))));
    } finally {
      if (mounted) {
        setState(() => _actionNotificationIds.remove(notification.id));
      }
    }
  }

  Future<void> _confirmAndClearAllNotifications({
    required String userId,
    required int totalCount,
    required int pinnedCount,
  }) async {
    if (_clearingAll || userId.trim().isEmpty || totalCount <= 0) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            pinnedCount > 0
                ? 'Pinned notifications found'
                : 'Clear all notifications?',
          ),
          content: Text(
            pinnedCount > 0
                ? 'You have $pinnedCount pinned notification${pinnedCount == 1 ? '' : 's'}. '
                      'Clearing will permanently delete all $totalCount notifications, including pinned ones.'
                : 'This will permanently delete $totalCount notification${totalCount == 1 ? '' : 's'}. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(pinnedCount > 0 ? 'Terminate' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: Text(pinnedCount > 0 ? 'Proceed' : 'Clear all'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _clearingAll = true);
    try {
      await ref.read(careRepositoryProvider).clearAllNotifications(userId);
      if (_useManualRefreshMode && mounted) {
        setState(() {
          _cachedNotifications = const <AppNotification>[];
          _selectedNotificationId = null;
          _notificationsLoaded = true;
          _notificationsErrorMessage = null;
        });
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications deleted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(error))));
    } finally {
      if (mounted) {
        setState(() => _clearingAll = false);
      }
    }
  }

  Widget _header({
    required BuildContext context,
    required String userId,
    required List<AppNotification> notifications,
    required _NotificationScreenCopy copy,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unreadCount = notifications
        .where((entry) => !entry.isRead && !entry.isArchived)
        .length;
    final canClearAll =
        !_clearingAll && userId.isNotEmpty && notifications.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.headerTitle,
                style: textTheme.headlineMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unreadCount > 0 ? '$unreadCount unread updates' : copy.subtitle,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showRefresh)
              Tooltip(
                message: 'Refresh notifications',
                child: IconButton(
                  onPressed: onRefresh,
                  style: IconButton.styleFrom(
                    foregroundColor: scheme.primary,
                    backgroundColor: scheme.surface,
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  icon: refreshing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
              ),
            Tooltip(
              message: 'Permanently delete all notifications',
              child: TextButton.icon(
                onPressed: canClearAll
                    ? () => _confirmAndClearAllNotifications(
                        userId: userId,
                        totalCount: notifications.length,
                        pinnedCount: notifications
                            .where((entry) => entry.isPinned)
                            .length,
                      )
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  textStyle: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: _clearingAll
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(_clearingAll ? 'Clearing...' : 'Clear'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _markAllNotificationsRead(String userId) async {
    if (userId.trim().isEmpty) {
      return;
    }
    try {
      await ref.read(careRepositoryProvider).markAllNotificationsRead(userId);
      _markAllCachedNotificationsRead();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(error))));
    }
  }

  Widget _statusCard(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
    bool retrying = false,
  }) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retrying ? 'Refreshing...' : 'Try again'),
            ),
          ],
        ],
      ),
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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _segmentChip(
            context: context,
            label: 'All',
            active: _activeFilter == _NotificationFilter.all,
            activeBg: activeBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () =>
                setState(() => _activeFilter = _NotificationFilter.all),
          ),
          _segmentChip(
            context: context,
            label: 'Unread',
            active: _activeFilter == _NotificationFilter.unread,
            activeBg: activeBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () =>
                setState(() => _activeFilter = _NotificationFilter.unread),
          ),
          _segmentChip(
            context: context,
            label: 'Archived',
            active: _activeFilter == _NotificationFilter.archived,
            activeBg: activeBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () =>
                setState(() => _activeFilter = _NotificationFilter.archived),
          ),
          TextButton(
            onPressed:
                (_activeFilter == _NotificationFilter.archived ||
                    !canMarkAllRead)
                ? null
                : () => _markAllNotificationsRead(userId),
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
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _typeAccent(scheme, entry.type);
    final isInviteAction =
        entry.type.toLowerCase() == 'institution_invite' ||
        entry.actionRequired;
    final iconBg = accent.withValues(alpha: 0.12);
    final cardBg = selected
        ? scheme.primary.withValues(alpha: 0.05)
        : scheme.surface;
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.52)
        : isInviteAction
        ? accent.withValues(alpha: 0.45)
        : entry.isRead
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
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.shadow.withValues(alpha: 0.06),
                blurRadius: selected ? 18 : 16,
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
                    if (isInviteAction) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Action required',
                          style: textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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
    return _statusCard(
      context,
      message: forUnread
          ? 'No unread notifications right now.'
          : _activeFilter == _NotificationFilter.archived
          ? 'No archived notifications yet.'
          : 'No notifications yet. Booking, reminders, and cancellations will show here.',
    );
  }

  Widget _buildNotificationResults({
    required BuildContext context,
    required String userId,
    required _NotificationScreenCopy copy,
    required List<AppNotification> notifications,
    required bool showInlineDetails,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
  }) {
    final filtered = _filteredNotifications(notifications);
    final selectedNotificationId = _effectiveSelectedNotificationId(
      notifications,
      filtered,
      showInlineDetails,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context: context,
          userId: userId,
          notifications: notifications,
          copy: copy,
          showRefresh: showRefresh,
          refreshing: refreshing,
          onRefresh: onRefresh,
        ),
        const SizedBox(height: 16),
        _segmentedControl(
          context: context,
          notifications: notifications,
          userId: userId,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: showInlineDetails
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 11,
                      child: filtered.isEmpty
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: _emptyCard(
                                context,
                                forUnread:
                                    _activeFilter == _NotificationFilter.unread,
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
                                    _actionNotificationIds.contains(entry.id);
                                return GestureDetector(
                                  onSecondaryTapDown: isBusy
                                      ? null
                                      : (details) => _showNotificationMenu(
                                          notification: entry,
                                          globalPosition:
                                              details.globalPosition,
                                        ),
                                  onLongPressStart: isBusy
                                      ? null
                                      : (details) => _showNotificationMenu(
                                          notification: entry,
                                          globalPosition:
                                              details.globalPosition,
                                        ),
                                  child: _notificationCard(
                                    context: context,
                                    entry: entry,
                                    isBusy: isBusy,
                                    selected:
                                        selectedNotificationId == entry.id,
                                    onTap: () => _selectNotification(entry),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 10,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: selectedNotificationId == null
                            ? _emptyDetailsState(context)
                            : SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: NotificationDetailsScreen(
                                  notificationId: selectedNotificationId,
                                  embedded: true,
                                  showBackToNotifications: false,
                                ),
                              ),
                      ),
                    ),
                  ],
                )
              : filtered.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: _emptyCard(
                    context,
                    forUnread: _activeFilter == _NotificationFilter.unread,
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    final isBusy =
                        _openingNotificationIds.contains(entry.id) ||
                        _actionNotificationIds.contains(entry.id);
                    return GestureDetector(
                      onSecondaryTapDown: isBusy
                          ? null
                          : (details) => _showNotificationMenu(
                              notification: entry,
                              globalPosition: details.globalPosition,
                            ),
                      onLongPressStart: isBusy
                          ? null
                          : (details) => _showNotificationMenu(
                              notification: entry,
                              globalPosition: details.globalPosition,
                            ),
                      child: _notificationCard(
                        context: context,
                        entry: entry,
                        isBusy: isBusy,
                        selected: false,
                        onTap: () => _openNotification(entry),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyDetailsState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 28,
            color: scheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'Select a notification',
            style: textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open any notification on the left to review its details and actions here without leaving the page.',
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isPrimaryUser =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.individual);
    final copy = _screenCopy(profile);
    final content = _buildNotificationWorkspace(
      context,
      userId: userId,
      profile: profile,
      copy: copy,
      embeddedInCounselorShell: widget.embeddedInCounselorShell,
    );

    if (widget.embeddedInCounselorShell) {
      return content;
    }

    if (isDesktop && isPrimaryUser) {
      return DesktopPrimaryShell(
        matchedLocation: AppRoute.notifications,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: content,
      bottomNavigationBar: null,
    );
  }

  Widget _buildNotificationWorkspace(
    BuildContext context, {
    required String userId,
    required UserProfile? profile,
    required _NotificationScreenCopy copy,
    required bool embeddedInCounselorShell,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final usesFloatingHeader =
        !embeddedInCounselorShell &&
        isDesktop &&
        profile != null &&
        profile.role != UserRole.student &&
        profile.role != UserRole.staff &&
        profile.role != UserRole.individual;

    final showInlineDetails = MediaQuery.sizeOf(context).width >= 1180;
    final workspace = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: showInlineDetails ? 1320 : 860),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            embeddedInCounselorShell ? 0 : (usesFloatingHeader ? 92 : 10),
            16,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotificationHeroCard(copy: copy),
              const SizedBox(height: 16),
              Expanded(
                child: userId.isEmpty
                    ? _emptyCard(context, forUnread: false)
                    : _useManualRefreshMode
                    ? Builder(
                        builder: (context) {
                          _ensureManualNotificationsLoaded(userId);
                          if (!_notificationsLoaded &&
                              _cachedNotifications.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                              ),
                            );
                          }

                          if (_notificationsErrorMessage != null &&
                              _cachedNotifications.isEmpty) {
                            return _statusCard(
                              context,
                              message: _notificationsErrorMessage!,
                              onRetry: () =>
                                  _refreshNotifications(userId: userId),
                              retrying: _refreshingNotifications,
                            );
                          }

                          return _buildNotificationResults(
                            context: context,
                            userId: userId,
                            copy: copy,
                            notifications: _cachedNotifications,
                            showInlineDetails: showInlineDetails,
                            showRefresh: true,
                            refreshing: _refreshingNotifications,
                            onRefresh: _refreshingNotifications
                                ? null
                                : () => _refreshNotifications(userId: userId),
                          );
                        },
                      )
                    : StreamBuilder<List<AppNotification>>(
                        stream: _notificationStreamFor(userId),
                        builder: (context, snapshot) {
                          final notifications = snapshot.data ?? const [];
                          if (snapshot.hasError && notifications.isEmpty) {
                            return _statusCard(
                              context,
                              message: _messageFromError(snapshot.error!),
                            );
                          }

                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              notifications.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                              ),
                            );
                          }

                          return _buildNotificationResults(
                            context: context,
                            userId: userId,
                            copy: copy,
                            notifications: notifications,
                            showInlineDetails: showInlineDetails,
                            showRefresh: false,
                            refreshing: false,
                            onRefresh: null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = embeddedInCounselorShell
        ? workspace
        : SafeArea(child: workspace);

    if (!usesFloatingHeader) {
      return body;
    }

    return Stack(
      children: [
        body,
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _NotificationsFloatingHeader(
              profile: profile,
              onLeadingAction: () {
                if (profile.role == UserRole.institutionAdmin) {
                  context.go(AppRoute.institutionAdmin);
                  return;
                }
                context.go(AppRoute.counselorDashboard);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationHeroCard extends StatelessWidget {
  const _NotificationHeroCard({required this.copy});

  final _NotificationScreenCopy copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1C35), Color(0xFF15486E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  size: 16,
                  color: Color(0xFFBEEBF2),
                ),
                SizedBox(width: 8),
                Text(
                  'Notification center',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.heroText,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.28,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsFloatingHeader extends StatelessWidget {
  const _NotificationsFloatingHeader({
    required this.profile,
    required this.onLeadingAction,
  });

  final UserProfile profile;
  final VoidCallback onLeadingAction;

  @override
  Widget build(BuildContext context) {
    final isAdmin = profile.role == UserRole.institutionAdmin;
    return Row(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _NotificationsHeaderActionButton(
              tooltip: isAdmin
                  ? 'Institution home'
                  : 'Back to counselor workspace',
              icon: isAdmin ? Icons.home_rounded : Icons.arrow_back_rounded,
              onPressed: onLeadingAction,
            ),
            const _NotificationsHeaderTitleChip(title: 'Notifications'),
          ],
        ),
        const Spacer(),
        const WindowsDesktopWindowControls(),
      ],
    );
  }
}

class _NotificationsHeaderTitleChip extends StatelessWidget {
  const _NotificationsHeaderTitleChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.2,
          color: Color(0xFF081A30),
        ),
      ),
    );
  }
}

class _NotificationsHeaderActionButton extends StatelessWidget {
  const _NotificationsHeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD8E2EE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1D3557), size: 28),
          ),
        ),
      ),
    );
  }
}

class _NotificationScreenCopy {
  const _NotificationScreenCopy({
    required this.headerTitle,
    required this.subtitle,
    required this.heroText,
  });

  final String headerTitle;
  final String subtitle;
  final String heroText;
}

enum _NotificationContextAction {
  pin,
  unpin,
  markRead,
  archive,
  unarchive,
  delete,
}

enum _NotificationFilter { all, unread, archived }
