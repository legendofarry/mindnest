// features/care/presentation/notification_center_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
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
      return Icons.cancel_outlined;
    }
    if (normalized.contains('reminder')) {
      return Icons.notifications_active_outlined;
    }
    if (normalized.contains('attendance') || normalized.contains('no_show')) {
      return Icons.access_time_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  Widget _segmentedControl({
    required List<AppNotification> notifications,
    required bool isDark,
  }) {
    final bg = isDark ? const Color(0xFF111C2E) : const Color(0xFFE9EEF4);
    final activeBg = isDark ? const Color(0xFF0F8D95) : const Color(0xFF0E9B90);
    final textMuted = isDark
        ? const Color(0xFF9FB2CC)
        : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _segmentChip(
            label: 'All',
            active: !_showUnreadOnly,
            activeBg: activeBg,
            inactiveText: textMuted,
            onTap: () => setState(() => _showUnreadOnly = false),
          ),
          const SizedBox(width: 8),
          _segmentChip(
            label: 'Unread',
            active: _showUnreadOnly,
            activeBg: activeBg,
            inactiveText: textMuted,
            onTap: () => setState(() => _showUnreadOnly = true),
          ),
          const Spacer(),
          TextButton(
            onPressed: notifications.any((entry) => !entry.isRead)
                ? () => ref
                      .read(careRepositoryProvider)
                      .markAllNotificationsRead(
                        ref.read(currentUserProfileProvider).valueOrNull?.id ??
                            '',
                      )
                : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E9B90),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            child: const Text('Mark all read'),
          ),
        ],
      ),
    );
  }

  Widget _segmentChip({
    required String label,
    required bool active,
    required Color activeBg,
    required Color inactiveText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x33119095),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : inactiveText,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _notificationCard({
    required AppNotification entry,
    required bool isDark,
  }) {
    final cardColor = isDark ? const Color(0xFF151F31) : Colors.white;
    final border = isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1);
    final iconBg = isDark ? const Color(0xFF1D2B41) : const Color(0xFFEFF3F8);
    final titleColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF334155);
    final bodyColor = isDark
        ? const Color(0xFF9FB2CC)
        : const Color(0xFF516784);
    final dateColor = isDark
        ? const Color(0xFF89A0BE)
        : const Color(0xFF8A9AB4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(34),
        onTap: entry.isRead
            ? null
            : () => ref
                  .read(careRepositoryProvider)
                  .markNotificationRead(entry.id),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0x120F172A))
                    .withValues(alpha: isDark ? 0.28 : 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _typeIcon(entry.type),
                  color: const Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: entry.isRead
                                  ? FontWeight.w700
                                  : FontWeight.w800,
                              fontSize: 34 / 2,
                            ),
                          ),
                        ),
                        if (!entry.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0E9B90),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.body,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 17,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_formatDate(entry.createdAt)}  -  ${_formatTime(entry.createdAt)}',
                      style: TextStyle(
                        color: dateColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
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

  Widget _emptyCard(bool isDark) {
    final cardColor = isDark ? const Color(0xFF151F31) : Colors.white;
    final border = isDark ? const Color(0xFF2A3A52) : const Color(0xFFDDE6F1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: border),
      ),
      child: Text(
        'No notifications yet. Booking, reminders, and cancellations will show here.',
        style: TextStyle(
          color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF64748B),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1E293B);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Notification Center'),
        titleTextStyle: TextStyle(
          color: titleColor,
          fontSize: 41 / 2,
          fontWeight: FontWeight.w800,
        ),
        centerTitle: false,
        elevation: 0,
        leading: const BackToHomeButton(),
        actions: [
          _CircleActionButton(
            onPressed: () => setState(() => _refreshTick++),
            icon: Icons.refresh_rounded,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B1220), Color(0xFF0E1A2E)]
                : const [Color(0xFFF4F7FB), Color(0xFFF1F5F9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _NotificationsHomeBlobs(isDark: isDark)),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            20,
                            kToolbarHeight - 30,
                            20,
                            24,
                          ),
                          child: userId.isEmpty
                              ? _emptyCard(isDark)
                              : StreamBuilder<List<AppNotification>>(
                                  key: ValueKey(_refreshTick),
                                  stream: ref
                                      .read(careRepositoryProvider)
                                      .watchUserNotifications(userId),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return _emptyCard(isDark);
                                    }

                                    final notifications =
                                        snapshot.data ?? const [];
                                    final filtered = notifications
                                        .where(
                                          (entry) =>
                                              !_showUnreadOnly || !entry.isRead,
                                        )
                                        .toList(growable: false);

                                    if (snapshot.connectionState ==
                                            ConnectionState.waiting &&
                                        notifications.isEmpty) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Color(0xFF0E9B90),
                                        ),
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _segmentedControl(
                                          notifications: notifications,
                                          isDark: isDark,
                                        ),
                                        const SizedBox(height: 16),
                                        Expanded(
                                          child: filtered.isEmpty
                                              ? Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: _emptyCard(isDark),
                                                )
                                              : ListView.separated(
                                                  physics:
                                                      const BouncingScrollPhysics(),
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 6,
                                                      ),
                                                  itemCount: filtered.length,
                                                  separatorBuilder:
                                                      (context, index) =>
                                                          const SizedBox(
                                                            height: 14,
                                                          ),
                                                  itemBuilder: (context, index) {
                                                    final entry =
                                                        filtered[index];
                                                    return _notificationCard(
                                                      entry: entry,
                                                      isDark: isDark,
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.onPressed, required this.icon});

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: isDark ? const Color(0xFF131F32) : Colors.white,
        shape: const CircleBorder(),
        side: BorderSide(
          color: isDark ? const Color(0xFF2A3A52) : const Color(0xFFD2DCE9),
        ),
      ),
      icon: Icon(
        icon,
        color: isDark ? const Color(0xFFB7C6DA) : const Color(0xFF4A607C),
      ),
    );
  }
}

class _NotificationsHomeBlobs extends StatefulWidget {
  const _NotificationsHomeBlobs({required this.isDark});

  final bool isDark;

  @override
  State<_NotificationsHomeBlobs> createState() =>
      _NotificationsHomeBlobsState();
}

class _NotificationsHomeBlobsState extends State<_NotificationsHomeBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob(double size, List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.45),
            blurRadius: 64,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blobA = widget.isDark
        ? const [Color(0x2E38BDF8), Color(0x0038BDF8)]
        : const [Color(0x300BA4FF), Color(0x000BA4FF)];
    final blobB = widget.isDark
        ? const [Color(0x2E14B8A6), Color(0x0014B8A6)]
        : const [Color(0x2A15A39A), Color(0x0015A39A)];
    final blobC = widget.isDark
        ? const [Color(0x2E22D3EE), Color(0x0022D3EE)]
        : const [Color(0x2418A89D), Color(0x0018A89D)];

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          return Stack(
            children: [
              Positioned(
                left: -70 + math.sin(t) * 28,
                top: -10 + math.cos(t * 1.2) * 20,
                child: _blob(320, blobA),
              ),
              Positioned(
                right: -70 + math.cos(t * 0.9) * 24,
                top: 150 + math.sin(t * 1.3) * 18,
                child: _blob(340, blobB),
              ),
              Positioned(
                left: 70 + math.cos(t * 1.1) * 18,
                bottom: -90 + math.sin(t * 0.75) * 22,
                child: _blob(280, blobC),
              ),
            ],
          );
        },
      ),
    );
  }
}
