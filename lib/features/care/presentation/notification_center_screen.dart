import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';

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
import 'package:mindnest/core/ui/modern_banner.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({
    super.key,
    this.initialSelectedNotificationId,
    this.returnToRoute,
    this.embeddedInCounselorShell = false,
    this.embeddedInDesktopShell = false,
  });

  final String? initialSelectedNotificationId;
  final String? returnToRoute;
  final bool embeddedInCounselorShell;
  final bool embeddedInDesktopShell;

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  _NotificationFilter _activeFilter = _NotificationFilter.all;
  String _searchQuery = '';
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
  bool _notificationDetailOpen = false;
  List<AppNotification> _cachedNotifications = const <AppNotification>[];

  @override
  void initState() {
    super.initState();
    _selectedNotificationId = widget.initialSelectedNotificationId?.trim();
    _notificationDetailOpen = _selectedNotificationId?.isNotEmpty == true;
  }

  @override
  void didUpdateWidget(covariant NotificationCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSelected = widget.initialSelectedNotificationId?.trim();
    if (nextSelected != oldWidget.initialSelectedNotificationId?.trim() &&
        nextSelected != _selectedNotificationId) {
      _selectedNotificationId = nextSelected;
      if (nextSelected != null && nextSelected.isNotEmpty) {
        _notificationDetailOpen = true;
      }
    }
  }

  bool get _useManualRefreshMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _useCompactDrawerStyle =>
      widget.embeddedInCounselorShell || widget.embeddedInDesktopShell;

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

  bool _matchesSearch(AppNotification entry) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final haystack = [
      entry.title,
      entry.body,
      entry.type,
      entry.relatedId ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
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
        showModernBannerFromSnackBar(context, SnackBar(content: Text(message)));
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
        _notificationDetailOpen = false;
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
        .where(_matchesSearch)
        .toList(growable: false);
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime value) {
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

  String _defaultNotificationExitRoute(UserProfile? profile) {
    if (profile?.role == UserRole.institutionAdmin) {
      return AppRoute.institutionAdmin;
    }
    if (profile?.role == UserRole.counselor) {
      return AppRoute.counselorDashboard;
    }
    return AppRoute.home;
  }

  String _notificationExitRoute(UserProfile? profile) {
    final normalized = widget.returnToRoute?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    return _defaultNotificationExitRoute(profile);
  }

  AppNotification? _notificationById(
    Iterable<AppNotification> notifications,
    String? notificationId,
  ) {
    final normalized = notificationId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final notification in notifications) {
      if (notification.id == normalized) {
        return notification;
      }
    }
    return null;
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

  Future<void> _selectNotification(AppNotification notification) async {
    if (_openingNotificationIds.contains(notification.id)) {
      return;
    }

    setState(() {
      _selectedNotificationId = notification.id;
      _notificationDetailOpen = true;
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
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
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

    return filtered.isNotEmpty ? filtered.first.id : null;
  }

  List<PopupMenuEntry<_NotificationContextAction>> _notificationMenuEntries(
    AppNotification notification,
  ) {
    return <PopupMenuEntry<_NotificationContextAction>>[
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
              notification.isPinned ? 'Unpin notification' : 'Pin notification',
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
    ];
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
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _actionNotificationIds.remove(notification.id));
      }
    }
  }

  Future<void> _showNotificationQuickActions(
    AppNotification notification,
  ) async {
    if (_actionNotificationIds.contains(notification.id) ||
        _openingNotificationIds.contains(notification.id)) {
      return;
    }

    final action = await showModalBottomSheet<_NotificationQuickAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final textTheme = Theme.of(sheetContext).textTheme;
        final title = notification.title.trim().isEmpty
            ? 'Notification'
            : notification.title.trim();

        Widget buildActionTile({
          required IconData icon,
          required String label,
          required String subtitle,
          required _NotificationQuickAction action,
          Color? accent,
        }) {
          final tint = accent ?? scheme.primary;
          return ListTile(
            onTap: () => Navigator.of(sheetContext).pop(action),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tint, size: 20),
            ),
            title: Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    scheme.surface.withValues(alpha: 0.98),
                    scheme.surfaceContainerHighest.withValues(alpha: 0.96),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick actions',
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                        buildActionTile(
                          icon: Icons.open_in_new_rounded,
                          label: 'Open details',
                          subtitle:
                              'Jump into the notification detail view on this page.',
                          action: _NotificationQuickAction.openDetails,
                          accent: const Color(0xFF0E9B90),
                        ),
                        buildActionTile(
                          icon: Icons.copy_rounded,
                          label: 'Copy title',
                          subtitle: 'Copy just the notification title.',
                          action: _NotificationQuickAction.copyTitle,
                        ),
                        buildActionTile(
                          icon: Icons.notes_rounded,
                          label: 'Copy body',
                          subtitle: 'Copy the message text only.',
                          action: _NotificationQuickAction.copyBody,
                        ),
                        buildActionTile(
                          icon: Icons.copy_all_rounded,
                          label: 'Copy full text',
                          subtitle: 'Copy the title and body together.',
                          action: _NotificationQuickAction.copyAll,
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == _NotificationQuickAction.openDetails) {
      await _selectNotification(notification);
      return;
    }

    if (action == _NotificationQuickAction.copyTitle) {
      await Clipboard.setData(ClipboardData(text: notification.title));
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Notification title copied.')),
      );
      return;
    }

    if (action == _NotificationQuickAction.copyBody) {
      await Clipboard.setData(ClipboardData(text: notification.body));
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Notification body copied.')),
      );
      return;
    }

    final buffer = StringBuffer(notification.title.trim());
    if (notification.body.trim().isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer.write(notification.body.trim());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    showModernBannerFromSnackBar(
      context,
      const SnackBar(content: Text('Notification text copied.')),
    );
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
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('All notifications deleted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingAll = false);
      }
    }
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
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
    }
  }

  Future<void> _markNotificationUnread(
    AppNotification notification, {
    bool selectAfter = false,
  }) async {
    try {
      await ref
          .read(careRepositoryProvider)
          .markNotificationUnread(notification.id);
      _replaceCachedNotification(notification.copyWith(isRead: false));
      if (selectAfter && mounted) {
        setState(() => _selectedNotificationId = notification.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
    }
  }

  Future<void> _toggleSelectedNotificationRead(
    AppNotification notification,
  ) async {
    if (notification.isRead) {
      await _markNotificationUnread(notification, selectAfter: true);
      return;
    }
    await _markNotificationRead(notification);
  }

  Future<void> _markNotificationRead(AppNotification notification) async {
    try {
      await ref
          .read(careRepositoryProvider)
          .markNotificationRead(notification.id);
      _replaceCachedNotification(notification.copyWith(isRead: true));
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text(_messageFromError(error))),
      );
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
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
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
    final canClearAll =
        !_clearingAll && userId.isNotEmpty && notifications.isNotEmpty;

    final chips = Wrap(
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
          onTap: () => setState(() => _activeFilter = _NotificationFilter.all),
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
      ],
    );

    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed:
              (_activeFilter == _NotificationFilter.archived || !canMarkAllRead)
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
      ],
    );

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useSplitRow = constraints.maxWidth >= 760;
          if (!useSplitRow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [chips, const SizedBox(height: 8), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: chips),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
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
    required VoidCallback onLongPress,
    required ValueChanged<_NotificationContextAction> onMenuSelected,
    required List<PopupMenuEntry<_NotificationContextAction>> menuEntries,
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
        onLongPress: isBusy ? null : onLongPress,
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
                          )
                        else
                          const SizedBox(width: 9, height: 9),
                        const SizedBox(width: 8),
                        PopupMenuButton<_NotificationContextAction>(
                          enabled: !isBusy,
                          tooltip: 'Notification options',
                          offset: const Offset(0, 42),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: scheme.surface,
                          surfaceTintColor: scheme.surface,
                          onSelected: onMenuSelected,
                          itemBuilder: (_) => menuEntries,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.primary.withValues(alpha: 0.10)
                                  : scheme.surfaceContainerHighest.withValues(
                                      alpha: 0.45,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
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
    required List<AppNotification> notifications,
    required bool showInlineDetails,
    required bool useCompactDrawerStyle,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
    required VoidCallback? onClose,
  }) {
    if (useCompactDrawerStyle) {
      return _buildCompactNotificationResults(
        context: context,
        userId: userId,
        notifications: notifications,
        showRefresh: showRefresh,
        refreshing: refreshing,
        onRefresh: onRefresh,
        onClose: onClose,
      );
    }

    final filtered = _filteredNotifications(notifications);
    final selectedNotificationId = _effectiveSelectedNotificationId(
      notifications,
      filtered,
      showInlineDetails,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _segmentedControl(
          context: context,
          notifications: notifications,
          userId: userId,
          showRefresh: showRefresh,
          refreshing: refreshing,
          onRefresh: onRefresh,
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
                                return _notificationCard(
                                  context: context,
                                  entry: entry,
                                  isBusy: isBusy,
                                  selected: selectedNotificationId == entry.id,
                                  onTap: () => _selectNotification(entry),
                                  onLongPress: () =>
                                      _showNotificationQuickActions(entry),
                                  onMenuSelected: (action) {
                                    _runNotificationAction(
                                      notification: entry,
                                      action: action,
                                    );
                                  },
                                  menuEntries: _notificationMenuEntries(entry),
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
                    return _notificationCard(
                      context: context,
                      entry: entry,
                      isBusy: isBusy,
                      selected: false,
                      onTap: () => _selectNotification(entry),
                      onLongPress: () => _showNotificationQuickActions(entry),
                      onMenuSelected: (action) {
                        _runNotificationAction(
                          notification: entry,
                          action: action,
                        );
                      },
                      menuEntries: _notificationMenuEntries(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCompactNotificationResults({
    required BuildContext context,
    required String userId,
    required List<AppNotification> notifications,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
    required VoidCallback? onClose,
  }) {
    final filtered = _filteredNotifications(notifications);
    final selectedNotificationId = _effectiveSelectedNotificationId(
      notifications,
      filtered,
      _notificationDetailOpen,
    );
    final selectedNotification = _notificationById(
      filtered,
      selectedNotificationId,
    );
    final unreadCount = notifications
        .where((entry) => !entry.isRead && !entry.isArchived)
        .length;
    final canMarkAllRead =
        userId.isNotEmpty &&
        notifications.any((entry) => !entry.isRead && !entry.isArchived);
    final canClearAll =
        !_clearingAll && userId.isNotEmpty && notifications.isNotEmpty;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactDrawerHeader(
          context: context,
          userId: userId,
          unreadCount: unreadCount,
          notifications: notifications,
          canMarkAllRead: canMarkAllRead,
          canClearAll: canClearAll,
          showRefresh: showRefresh,
          refreshing: refreshing,
          onRefresh: onRefresh,
          onClose: onClose,
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => _searchQuery = value),
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: scheme.primary,
          decoration: InputDecoration(
            hintText: 'Search updates',
            hintStyle: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() => _searchQuery = ''),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
            filled: true,
            fillColor: scheme.surface.withValues(alpha: 0.35),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.38),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.34),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.primary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _compactFilterChip(
              context: context,
              label: 'All',
              active: _activeFilter == _NotificationFilter.all,
              onTap: () =>
                  setState(() => _activeFilter = _NotificationFilter.all),
            ),
            _compactFilterChip(
              context: context,
              label: 'Unread',
              active: _activeFilter == _NotificationFilter.unread,
              onTap: () =>
                  setState(() => _activeFilter = _NotificationFilter.unread),
            ),
            _compactFilterChip(
              context: context,
              label: 'Archived',
              active: _activeFilter == _NotificationFilter.archived,
              onTap: () =>
                  setState(() => _activeFilter = _NotificationFilter.archived),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useSplitPane =
                  _notificationDetailOpen && constraints.maxWidth >= 1040;
              final listPane = _compactNotificationListPane(
                context: context,
                notifications: filtered,
                selectedNotificationId: selectedNotificationId,
              );
              final detailsPane = _compactNotificationDetailsPane(
                context: context,
                notification: selectedNotification,
                onClose: onClose,
              );

              if (!_notificationDetailOpen) {
                return listPane;
              }

              if (!useSplitPane) {
                return Column(
                  children: [
                    Expanded(flex: 11, child: listPane),
                    const SizedBox(height: 14),
                    Expanded(flex: 12, child: detailsPane),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 10, child: listPane),
                  const SizedBox(width: 14),
                  Expanded(flex: 12, child: detailsPane),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _compactDrawerHeader({
    required BuildContext context,
    required String userId,
    required int unreadCount,
    required List<AppNotification> notifications,
    required bool canMarkAllRead,
    required bool canClearAll,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
    required VoidCallback? onClose,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final clearLabel = _clearingAll ? 'Clearing...' : 'Clear';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unreadCount == 1
                    ? '1 unread update'
                    : '$unreadCount unread updates',
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: canMarkAllRead
                  ? () => _markAllNotificationsRead(userId)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                textStyle: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Mark all'),
            ),
            TextButton.icon(
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
                foregroundColor: const Color(0xFFF87171),
                textStyle: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: _clearingAll
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.error,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(clearLabel),
            ),
            if (showRefresh)
              Tooltip(
                message: 'Refresh notifications',
                child: IconButton(
                  onPressed: refreshing ? null : onRefresh,
                  style: IconButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: scheme.surface.withValues(alpha: 0.52),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.40),
                    ),
                  ),
                  icon: refreshing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                ),
              ),
            IconButton(
              onPressed: onClose,
              tooltip: 'Close notifications',
              style: IconButton.styleFrom(
                foregroundColor: scheme.onSurface,
                backgroundColor: scheme.surface.withValues(alpha: 0.52),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactFilterChip({
    required BuildContext context,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.15)
                : scheme.surface.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            label,
            style: textTheme.titleSmall?.copyWith(
              color: active ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileNotificationWorkspace(
    BuildContext context, {
    required String userId,
    required ThemeData panelTheme,
    required List<AppNotification> notifications,
    required bool showRefresh,
    required bool refreshing,
    required VoidCallback? onRefresh,
    required VoidCallback? onClose,
  }) {
    final filtered = _filteredNotifications(notifications);
    final selectedNotificationId = _effectiveSelectedNotificationId(
      notifications,
      filtered,
      _notificationDetailOpen,
    );
    final selectedNotification = _notificationById(
      filtered,
      selectedNotificationId,
    );
    final unreadCount = notifications
        .where((entry) => !entry.isRead && !entry.isArchived)
        .length;
    final canMarkAllRead =
        userId.isNotEmpty &&
        notifications.any((entry) => !entry.isRead && !entry.isArchived);
    final canClearAll =
        !_clearingAll && userId.isNotEmpty && notifications.isNotEmpty;

    Widget buildListPage() {
      return Container(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _compactDrawerHeader(
                context: context,
                userId: userId,
                unreadCount: unreadCount,
                notifications: notifications,
                canMarkAllRead: canMarkAllRead,
                canClearAll: canClearAll,
                showRefresh: showRefresh,
                refreshing: refreshing,
                onRefresh: onRefresh,
                onClose: onClose,
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: panelTheme.textTheme.titleSmall?.copyWith(
                  color: panelTheme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: panelTheme.colorScheme.primary,
                decoration: InputDecoration(
                  hintText: 'Search updates',
                  hintStyle: panelTheme.textTheme.titleSmall?.copyWith(
                    color: panelTheme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: panelTheme.colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(() => _searchQuery = ''),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: panelTheme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  filled: true,
                  fillColor: panelTheme.colorScheme.surface.withValues(
                    alpha: 0.35,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: panelTheme.colorScheme.outlineVariant.withValues(
                        alpha: 0.38,
                      ),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: panelTheme.colorScheme.outlineVariant.withValues(
                        alpha: 0.34,
                      ),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: panelTheme.colorScheme.primary.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _compactFilterChip(
                    context: context,
                    label: 'All',
                    active: _activeFilter == _NotificationFilter.all,
                    onTap: () =>
                        setState(() => _activeFilter = _NotificationFilter.all),
                  ),
                  _compactFilterChip(
                    context: context,
                    label: 'Unread',
                    active: _activeFilter == _NotificationFilter.unread,
                    onTap: () => setState(
                      () => _activeFilter = _NotificationFilter.unread,
                    ),
                  ),
                  _compactFilterChip(
                    context: context,
                    label: 'Archived',
                    active: _activeFilter == _NotificationFilter.archived,
                    onTap: () => setState(
                      () => _activeFilter = _NotificationFilter.archived,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _compactNotificationListPane(
                  context: context,
                  notifications: filtered,
                  selectedNotificationId: selectedNotificationId,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildDetailPage() {
      final selected = selectedNotification;
      final selectedId = selected?.id ?? '';
      final showDetail = selectedId.isNotEmpty;
      final canToggleRead = selected != null;

      return Container(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _selectedNotificationId = null;
                      _notificationDetailOpen = false;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC2CAD4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  if (canToggleRead)
                    TextButton.icon(
                      onPressed: () =>
                          _toggleSelectedNotificationRead(selected),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF7FAFC),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      icon: Icon(
                        selected.isRead
                            ? Icons.mark_email_unread_outlined
                            : Icons.mark_email_read_outlined,
                        size: 18,
                      ),
                      label: Text(
                        selected.isRead ? 'Mark unread' : 'Mark read',
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'Close notifications',
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFFF7FAFC),
                      backgroundColor: const Color(0xFF111B2B),
                      side: const BorderSide(color: Color(0x22384E63)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: !showDetail
                      ? _emptyDetailsState(context)
                      : SingleChildScrollView(
                          key: ValueKey(selectedId),
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NotificationDetailsScreen(
                            notificationId: selectedId,
                            embedded: true,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Theme(
      data: panelTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF07111D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _notificationDetailOpen,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        offset: _notificationDetailOpen
                            ? const Offset(-1, 0)
                            : Offset.zero,
                        child: buildListPage(),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_notificationDetailOpen,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        offset: _notificationDetailOpen
                            ? Offset.zero
                            : const Offset(1, 0),
                        child: buildDetailPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactNotificationListPane({
    required BuildContext context,
    required List<AppNotification> notifications,
    required String? selectedNotificationId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
            child: Row(
              children: [
                Text(
                  notifications.isEmpty
                      ? 'Inbox'
                      : 'Inbox - ${notifications.length}',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  _activeFilter == _NotificationFilter.unread
                      ? 'Unread only'
                      : _activeFilter == _NotificationFilter.archived
                      ? 'Archived'
                      : 'All updates',
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.24),
          ),
          Expanded(
            child: notifications.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: _compactEmptyState(
                      context,
                      message: _searchQuery.trim().isNotEmpty
                          ? 'No notifications match your search.'
                          : _activeFilter == _NotificationFilter.unread
                          ? 'No unread notifications right now.'
                          : _activeFilter == _NotificationFilter.archived
                          ? 'No archived notifications yet.'
                          : 'No notifications yet. Booking updates and reminders will appear here.',
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                      itemCount: notifications.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        indent: 70,
                        color: scheme.outlineVariant.withValues(alpha: 0.18),
                      ),
                      itemBuilder: (context, index) {
                        final entry = notifications[index];
                        final isBusy =
                            _openingNotificationIds.contains(entry.id) ||
                            _actionNotificationIds.contains(entry.id);
                        return _compactNotificationCard(
                          context: context,
                          entry: entry,
                          isBusy: isBusy,
                          selected: selectedNotificationId == entry.id,
                          onTap: () => _selectNotification(entry),
                          onLongPress: () =>
                              _showNotificationQuickActions(entry),
                          onMenuSelected: (action) {
                            _runNotificationAction(
                              notification: entry,
                              action: action,
                            );
                          },
                          menuEntries: _notificationMenuEntries(entry),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _compactNotificationCard({
    required BuildContext context,
    required AppNotification entry,
    required bool isBusy,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required ValueChanged<_NotificationContextAction> onMenuSelected,
    required List<PopupMenuEntry<_NotificationContextAction>> menuEntries,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _typeAccent(scheme, entry.type);
    final isInviteAction =
        entry.type.toLowerCase() == 'institution_invite' ||
        entry.actionRequired;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isBusy ? null : onTap,
        onLongPress: isBusy ? null : onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_typeIcon(entry.type), color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDisplayType(entry.type).toUpperCase(),
                                style: textTheme.labelLarge?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.title,
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  height: 1.22,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTime(entry.createdAt),
                              style: textTheme.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (entry.isPinned)
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 15,
                                    color: scheme.primary,
                                  ),
                                if (!entry.isRead) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                PopupMenuButton<_NotificationContextAction>(
                                  enabled: !isBusy,
                                  tooltip: 'Notification options',
                                  offset: const Offset(0, 42),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  color: scheme.surfaceContainerHighest,
                                  surfaceTintColor: scheme.surface,
                                  onSelected: onMenuSelected,
                                  itemBuilder: (_) => menuEntries,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? scheme.primary.withValues(
                                              alpha: 0.10,
                                            )
                                          : scheme.surface.withValues(
                                              alpha: 0.38,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: scheme.outlineVariant.withValues(
                                          alpha: 0.30,
                                        ),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.more_horiz_rounded,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isInviteAction) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Action required',
                          style: textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      entry.body,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
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

  Widget _compactNotificationDetailsPane({
    required BuildContext context,
    required AppNotification? notification,
    required VoidCallback? onClose,
  }) {
    if (notification == null) {
      return _compactEmptyState(
        context,
        message:
            'Select a notification to review its details here without leaving the drawer.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _typeAccent(scheme, notification.type);
    final icon = _typeIcon(notification.type);
    final details = <Widget>[
      Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedNotificationId = null;
              _notificationDetailOpen = false;
            }),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _toggleSelectedNotificationRead(notification),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurface,
              textStyle: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: Icon(
              notification.isRead
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
              size: 18,
            ),
            label: Text(notification.isRead ? 'Mark unread' : 'Mark read'),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Close notifications',
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surface.withValues(alpha: 0.52),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _compactFilterChip(
                      context: context,
                      label: _formatDisplayType(notification.type),
                      active: true,
                      onTap: () {},
                    ),
                    if (notification.isPinned)
                      _compactFilterChip(
                        context: context,
                        label: 'Pinned',
                        active: true,
                        onTap: () {},
                      ),
                    if (notification.actionRequired)
                      _compactFilterChip(
                        context: context,
                        label: 'Action needed',
                        active: true,
                        onTap: () {},
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  notification.title,
                  style: textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatDate(notification.createdAt)} • ${_formatTime(notification.createdAt)}',
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
      const SizedBox(height: 18),
      Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.38),
              scheme.surfaceContainerHighest.withValues(alpha: 0.26),
              const Color(0xFF0E131A),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.18),
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 16,
              child: Text(
                'MindNest notification detail',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text(
        notification.body,
        style: textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.65,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: () => _runNotificationAction(
              notification: notification,
              action: notification.isArchived
                  ? _NotificationContextAction.unarchive
                  : _NotificationContextAction.archive,
            ),
            icon: Icon(
              notification.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              size: 18,
            ),
            label: Text(notification.isArchived ? 'Unarchive' : 'Archive'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.26),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Details',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            _compactDetailRow(
              context,
              label: 'Type',
              value: _formatDisplayType(notification.type),
            ),
            _compactDetailRow(
              context,
              label: 'Priority',
              value: notification.priority,
            ),
            _compactDetailRow(
              context,
              label: 'Read status',
              value: notification.isRead ? 'Read' : 'Unread',
            ),
            _compactDetailRow(
              context,
              label: 'Action required',
              value: notification.actionRequired ? 'Yes' : 'No',
            ),
          ],
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: details,
          ),
        ),
      ),
    );
  }

  Widget _compactDetailRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactEmptyState(BuildContext context, {required String message}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 28,
            color: scheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'No selection yet',
            style: textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
            'Open any notification on the left to review its details here without leaving the page.',
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
    final isMobileEmbedded =
        widget.embeddedInCounselorShell &&
        MediaQuery.sizeOf(context).width < 760;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isPrimaryUser =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.individual);
    final content = _buildNotificationWorkspace(
      context,
      userId: userId,
      profile: profile,
      embeddedInCounselorShell: widget.embeddedInCounselorShell,
      embeddedInDesktopShell: widget.embeddedInDesktopShell,
      mobileFullScreenMode: isMobileEmbedded,
    );

    if (widget.embeddedInCounselorShell || widget.embeddedInDesktopShell) {
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
    required bool embeddedInCounselorShell,
    required bool embeddedInDesktopShell,
    required bool mobileFullScreenMode,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final isDesktop = viewport.width >= 900;
    final isCompactPanelStyle = _useCompactDrawerStyle;
    final usesFloatingHeader =
        !isCompactPanelStyle &&
        isDesktop &&
        profile != null &&
        profile.role != UserRole.student &&
        profile.role != UserRole.staff &&
        profile.role != UserRole.individual;

    final showInlineDetails = _notificationDetailOpen;
    final maxContentWidth = isCompactPanelStyle
        ? (_notificationDetailOpen ? 1320.0 : 620.0)
        : showInlineDetails
        ? 1320.0
        : 860.0;
    final topPadding = isCompactPanelStyle
        ? 16.0
        : embeddedInCounselorShell
        ? 0.0
        : usesFloatingHeader
        ? 92.0
        : 10.0;

    final panelTheme = Theme.of(context).copyWith(
      colorScheme: const ColorScheme.dark().copyWith(
        primary: const Color(0xFF34D6D1),
        secondary: const Color(0xFF17B6A3),
        surface: const Color(0xFF1F252D),
        surfaceContainerHighest: const Color(0xFF2A313A),
        onSurface: const Color(0xFFF7FAFC),
        onSurfaceVariant: const Color(0xFFC2CAD4),
        outlineVariant: const Color(0xFF3B4652),
        shadow: Colors.black,
        error: const Color(0xFFF87171),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: const Color(0xFFF7FAFC),
        displayColor: const Color(0xFFF7FAFC),
      ),
      iconTheme: Theme.of(
        context,
      ).iconTheme.copyWith(color: const Color(0xFFF7FAFC)),
    );

    void closeNotifications() {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
      context.go(_notificationExitRoute(profile));
    }

    final panel = Theme(
      data: isCompactPanelStyle ? panelTheme : Theme.of(context),
      child: Align(
        alignment: isCompactPanelStyle
            ? Alignment.centerRight
            : Alignment.center,
        child: SizedBox(
          width: isCompactPanelStyle
              ? math.min(maxContentWidth, viewport.width)
              : null,
          height: isCompactPanelStyle ? viewport.height : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isCompactPanelStyle ? 0 : 16,
              topPadding,
              isCompactPanelStyle ? 0 : 16,
              18,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isCompactPanelStyle
                      ? const Color(0xFF1F252D).withValues(alpha: 0.98)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(
                    isCompactPanelStyle ? 28 : 24,
                  ),
                  border: Border.all(
                    color: isCompactPanelStyle
                        ? const Color(0xFF38424E)
                        : Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isCompactPanelStyle ? 0.34 : 0.08,
                      ),
                      blurRadius: isCompactPanelStyle ? 34 : 18,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompactPanelStyle ? 18 : 20,
                    isCompactPanelStyle ? 18 : 20,
                    isCompactPanelStyle ? 18 : 20,
                    isCompactPanelStyle ? 18 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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

                                  if (mobileFullScreenMode) {
                                    return _buildMobileNotificationWorkspace(
                                      context,
                                      userId: userId,
                                      panelTheme: panelTheme,
                                      notifications: _cachedNotifications,
                                      showRefresh: true,
                                      refreshing: _refreshingNotifications,
                                      onRefresh: _refreshingNotifications
                                          ? null
                                          : () => _refreshNotifications(
                                              userId: userId,
                                            ),
                                      onClose: closeNotifications,
                                    );
                                  }

                                  return _buildNotificationResults(
                                    context: context,
                                    userId: userId,
                                    notifications: _cachedNotifications,
                                    showInlineDetails: showInlineDetails,
                                    useCompactDrawerStyle: isCompactPanelStyle,
                                    showRefresh: true,
                                    refreshing: _refreshingNotifications,
                                    onClose: closeNotifications,
                                    onRefresh: _refreshingNotifications
                                        ? null
                                        : () => _refreshNotifications(
                                            userId: userId,
                                          ),
                                  );
                                },
                              )
                            : StreamBuilder<List<AppNotification>>(
                                stream: _notificationStreamFor(userId),
                                builder: (context, snapshot) {
                                  final notifications =
                                      snapshot.data ?? const [];
                                  if (snapshot.hasError &&
                                      notifications.isEmpty) {
                                    return _statusCard(
                                      context,
                                      message: _messageFromError(
                                        snapshot.error!,
                                      ),
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

                                  if (mobileFullScreenMode) {
                                    return _buildMobileNotificationWorkspace(
                                      context,
                                      userId: userId,
                                      panelTheme: panelTheme,
                                      notifications: notifications,
                                      showRefresh: false,
                                      refreshing: false,
                                      onRefresh: null,
                                      onClose: closeNotifications,
                                    );
                                  }

                                  return _buildNotificationResults(
                                    context: context,
                                    userId: userId,
                                    notifications: notifications,
                                    showInlineDetails: showInlineDetails,
                                    useCompactDrawerStyle: isCompactPanelStyle,
                                    showRefresh: false,
                                    refreshing: false,
                                    onClose: closeNotifications,
                                    onRefresh: null,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final body = isCompactPanelStyle
        ? Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.6, -0.55),
                        radius: 1.5,
                        colors: [
                          const Color(0xFF0F1720).withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: panel),
            ],
          )
        : SafeArea(child: panel);

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

enum _NotificationContextAction {
  pin,
  unpin,
  markRead,
  archive,
  unarchive,
  delete,
}

enum _NotificationQuickAction { openDetails, copyTitle, copyBody, copyAll }

enum _NotificationFilter { all, unread, archived }
