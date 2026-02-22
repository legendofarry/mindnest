import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
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
  int _refreshTick = 0;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final userId = profile?.id ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Notification Center'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackToHomeButton(),
        actions: [
          IconButton(
            onPressed: () => setState(() => _refreshTick++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: userId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Sign in to view notifications.'),
              ),
            )
          : StreamBuilder<List<AppNotification>>(
              key: ValueKey(_refreshTick),
              stream: ref
                  .read(careRepositoryProvider)
                  .watchUserNotifications(userId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            snapshot.error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => setState(() => _refreshTick++),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final notifications = snapshot.data ?? const [];
                final filtered = notifications
                    .where((entry) => !_showUnreadOnly || !entry.isRead)
                    .toList(growable: false);

                if (snapshot.connectionState == ConnectionState.waiting &&
                    notifications.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: !_showUnreadOnly,
                              onSelected: (_) =>
                                  setState(() => _showUnreadOnly = false),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Unread'),
                              selected: _showUnreadOnly,
                              onSelected: (_) =>
                                  setState(() => _showUnreadOnly = true),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: notifications.any((e) => !e.isRead)
                                  ? () => ref
                                        .read(careRepositoryProvider)
                                        .markAllNotificationsRead(userId)
                                  : null,
                              child: const Text('Mark all read'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (filtered.isEmpty)
                      const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'No notifications yet. Booking, reminders, and cancellations will show here.',
                          ),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: filtered
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: GlassCard(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(24),
                                      onTap: entry.isRead
                                          ? null
                                          : () => ref
                                                .read(careRepositoryProvider)
                                                .markNotificationRead(entry.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              margin: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: entry.isRead
                                                    ? const Color(0xFFCBD5E1)
                                                    : const Color(0xFF0E9B90),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    entry.title,
                                                    style: TextStyle(
                                                      fontWeight: entry.isRead
                                                          ? FontWeight.w600
                                                          : FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(entry.body),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    _formatDate(
                                                      entry.createdAt,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
