import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';

class CounselorAvailabilityScreen extends ConsumerStatefulWidget {
  const CounselorAvailabilityScreen({super.key});

  @override
  ConsumerState<CounselorAvailabilityScreen> createState() =>
      _CounselorAvailabilityScreenState();
}

class _CounselorAvailabilityScreenState
    extends ConsumerState<CounselorAvailabilityScreen> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;
  late DateTime _weekStart;

  static const List<int> _gridHours = <int>[
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
  ];

  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final offset = local.weekday - DateTime.monday;
    return local.subtract(Duration(days: offset));
  }

  List<DateTime> _currentWeekDays() {
    return List<DateTime>.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
      growable: false,
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _weekRangeLabel() {
    final end = _weekStart.add(const Duration(days: 6));
    final startMonth = _monthNames[_weekStart.month - 1];
    final endMonth = _monthNames[end.month - 1];
    return '$startMonth ${_weekStart.day} - $endMonth ${end.day}, ${end.year}';
  }

  String _weekdayLabel(DateTime day) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[day.weekday - 1];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  DateTime? _composeDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _saveSlot(UserProfile profile) async {
    final startLocal = _composeDateTime(_date, _startTime);
    final endLocal = _composeDateTime(_date, _endTime);
    if (startLocal == null || endLocal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose date, start, and end time.')),
      );
      return;
    }
    if (!endLocal.isAfter(startLocal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    await _createSlot(
      profile: profile,
      startLocal: startLocal,
      endLocal: endLocal,
      successText: 'Availability slot created.',
    );
  }

  Future<void> _createSlot({
    required UserProfile profile,
    required DateTime startLocal,
    required DateTime endLocal,
    required String successText,
  }) async {
    final institutionId = profile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Counselor must be linked to institution.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .createAvailabilitySlot(
            institutionId: institutionId,
            startAtUtc: startLocal.toUtc(),
            endAtUtc: endLocal.toUtc(),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successText)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final handled = await _handleFirestoreIndexError(error);
      if (handled) {
        return;
      }
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
        setState(() => _isSaving = false);
      }
    }
  }

  String? _extractFirebaseIndexUrl(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final match = RegExp(
      r'https://console\.firebase\.google\.com/[^\s]+',
    ).firstMatch(normalized);
    return match?.group(0);
  }

  Future<bool> _handleFirestoreIndexError(Object error) async {
    if (error is! FirebaseException || error.code != 'failed-precondition') {
      return false;
    }
    final errorText = error.message ?? error.toString();
    final indexUrl = _extractFirebaseIndexUrl(errorText);
    if (indexUrl == null || !mounted) {
      return false;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Missing Firestore Index'),
          content: const Text(
            'Your project needs a composite index for this query. Copy the link and open it in your browser to create the index, then retry.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: indexUrl));
                if (!mounted) {
                  return;
                }
                Navigator.of(this.context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Index link copied. Open it in your browser and create the index.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Link'),
            ),
          ],
        );
      },
    );
    return true;
  }

  List<AvailabilitySlot> _slotsForCell({
    required List<AvailabilitySlot> slots,
    required DateTime day,
    required int hour,
  }) {
    final cellStart = DateTime(day.year, day.month, day.day, hour);
    final cellEnd = cellStart.add(const Duration(hours: 1));
    return slots
        .where((slot) {
          final start = slot.startAt.toLocal();
          final end = slot.endAt.toLocal();
          return start.isBefore(cellEnd) && end.isAfter(cellStart);
        })
        .toList(growable: false);
  }

  Future<void> _onCellTap({
    required UserProfile profile,
    required DateTime day,
    required int hour,
    required List<AvailabilitySlot> cellSlots,
  }) async {
    if (cellSlots.isEmpty) {
      final start = DateTime(day.year, day.month, day.day, hour);
      final end = start.add(const Duration(hours: 1));
      await _createSlot(
        profile: profile,
        startLocal: start,
        endLocal: end,
        successText: 'Quick slot added to calendar.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Scheduled Slots',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                ...cellSlots.map((slot) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDateTime(slot.startAt)} - ${_formatDateTime(slot.endAt)} (${slot.status.name})',
                          ),
                        ),
                        if (slot.status == AvailabilitySlotStatus.available)
                          IconButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await ref
                                  .read(careRepositoryProvider)
                                  .deleteAvailabilitySlot(slot);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _cellColor(List<AvailabilitySlot> slots) {
    if (slots.isEmpty) {
      return Colors.white;
    }
    if (slots.any((slot) => slot.status == AvailabilitySlotStatus.booked)) {
      return const Color(0xFFFFF7ED);
    }
    if (slots.any((slot) => slot.status == AvailabilitySlotStatus.blocked)) {
      return const Color(0xFFFFF1F2);
    }
    return const Color(0xFFEFFFFC);
  }

  Widget _buildWeeklyGrid(UserProfile profile, List<AvailabilitySlot> slots) {
    final days = _currentWeekDays();
    final weekControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () {
            setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
            );
          },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Flexible(
          child: Text(
            _weekRangeLabel(),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        IconButton(
          onPressed: () {
            setState(
              () => _weekStart = _weekStart.add(const Duration(days: 7)),
            );
          },
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 520;
                if (!isMobile) {
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Calendar Grid',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap an empty cell to quick-add a 1-hour slot. Tap occupied cells to manage existing slots.',
                              style: TextStyle(
                                color: Color(0xFF6A7C93),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 248, child: weekControls),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Calendar Grid',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap an empty cell to quick-add a 1-hour slot. Tap occupied cells to manage existing slots.',
                      style: TextStyle(color: Color(0xFF6A7C93), height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: weekControls),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 100 + (days.length * 132),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _HeaderCell(label: 'Time', width: 100),
                        ...days.map(
                          (day) => _HeaderCell(
                            label: '${_weekdayLabel(day)} ${day.day}',
                            width: 132,
                          ),
                        ),
                      ],
                    ),
                    ..._gridHours.map((hour) {
                      return Row(
                        children: [
                          _TimeCell(hour: hour),
                          ...days.map((day) {
                            final cellSlots = _slotsForCell(
                              slots: slots,
                              day: day,
                              hour: hour,
                            );
                            return _CalendarCell(
                              width: 132,
                              color: _cellColor(cellSlots),
                              slotCount: cellSlots.length,
                              isBusy: cellSlots.isNotEmpty,
                              onTap: _isSaving
                                  ? null
                                  : () => _onCellTap(
                                      profile: profile,
                                      day: day,
                                      hour: hour,
                                      cellSlots: cellSlots,
                                    ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
    }
  }

  Widget _buildBody(
    BuildContext context, {
    required UserProfile profile,
    required List<AvailabilitySlot> slots,
    required bool loading,
  }) {
    final available = slots
        .where((slot) => slot.status == AvailabilitySlotStatus.available)
        .length;
    final booked = slots
        .where((slot) => slot.status == AvailabilitySlotStatus.booked)
        .length;
    final blocked = slots
        .where((slot) => slot.status == AvailabilitySlotStatus.blocked)
        .length;
    final nextOpen =
        slots
            .where(
              (slot) =>
                  slot.status == AvailabilitySlotStatus.available &&
                  slot.startAt.isAfter(DateTime.now().toUtc()),
            )
            .toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AvailabilityHero(
          nextOpen: nextOpen.isEmpty ? null : nextOpen.first,
          onOpenSessions: () => context.go(AppRoute.counselorAppointments),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _AvailabilityStatCard(
              label: 'Open',
              value: '$available',
              hint: 'future slots live',
              accent: const Color(0xFF0E9B90),
            ),
            _AvailabilityStatCard(
              label: 'Booked',
              value: '$booked',
              hint: 'already claimed',
              accent: const Color(0xFF2563EB),
            ),
            _AvailabilityStatCard(
              label: 'Blocked',
              value: '$blocked',
              hint: 'not bookable',
              accent: const Color(0xFFF97316),
            ),
          ].map((card) => SizedBox(width: 200, child: card)).toList(),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AvailabilityEyebrow(
                  label: 'PUBLISH AVAILABILITY',
                  color: Color(0xFF0E9B90),
                  background: Color(0xFFE9FBF8),
                  border: Color(0xFFBEE7E1),
                ),
                const SizedBox(height: 12),
                Text(
                  'Add public slot',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF081A30),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Publish a visible booking window for students. You can create slots from the picker below or directly from empty cells in the weekly calendar.',
                  style: TextStyle(
                    color: Color(0xFF6A7C93),
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(
                        _date == null
                            ? 'Pick date'
                            : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickStartTime,
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(
                        _startTime == null
                            ? 'Start time'
                            : _startTime!.format(context),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickEndTime,
                      icon: const Icon(Icons.schedule_send_rounded),
                      label: Text(
                        _endTime == null
                            ? 'End time'
                            : _endTime!.format(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : () => _saveSlot(profile),
                    icon: Icon(
                      _isSaving
                          ? Icons.hourglass_top_rounded
                          : Icons.add_circle_outline_rounded,
                    ),
                    label: Text(_isSaving ? 'Saving...' : 'Publish slot'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildWeeklyGrid(profile, slots),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _AvailabilityEyebrow(
                            label: 'SLOT FEED',
                            color: Color(0xFF2563EB),
                            background: Color(0xFFEFF6FF),
                            border: Color(0xFFBFDBFE),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Published slots',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF081A30),
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 16),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (slots.isEmpty)
                  const _AvailabilityEmptyCard(
                    message:
                        'No availability slots are visible yet. Publish your first slot to start taking bookings.',
                  )
                else
                  Column(
                    children: slots
                        .map(
                          (slot) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SlotFeedCard(
                              slot: slot,
                              formatDateTime: _formatDateTime,
                              onDelete:
                                  slot.status ==
                                      AvailabilitySlotStatus.available
                                  ? () async {
                                      try {
                                        await ref
                                            .read(careRepositoryProvider)
                                            .deleteAvailabilitySlot(slot);
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              error.toString().replaceFirst(
                                                'Exception: ',
                                                '',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.role != UserRole.counselor) {
      return const Scaffold(
        body: Center(
          child: _AvailabilityEmptyCard(
            message: 'This page is available only for counselors.',
          ),
        ),
      );
    }

    final unreadCount =
        ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;

    return CounselorWorkspaceScaffold(
      profile: profile,
      activeSection: CounselorWorkspaceNavSection.availability,
      unreadNotifications: unreadCount,
      title: 'Availability',
      subtitle:
          'Publish booking windows, manage the weekly grid, and keep your open inventory healthy.',
      onSelectSection: (section) => _navigateSection(context, section),
      onNotifications: () => context.go(AppRoute.notifications),
      onProfile: () => context.go(AppRoute.counselorSettings),
      onLogout: () => confirmAndLogout(context: context, ref: ref),
      child: StreamBuilder<List<AvailabilitySlot>>(
        stream: ref
            .read(careRepositoryProvider)
            .watchCounselorSlots(
              institutionId: profile.institutionId ?? '',
              counselorId: profile.id,
            ),
        builder: (context, snapshot) {
          final slots = snapshot.data ?? const <AvailabilitySlot>[];
          return _buildBody(
            context,
            profile: profile,
            slots: slots,
            loading:
                snapshot.connectionState == ConnectionState.waiting &&
                slots.isEmpty,
          );
        },
      ),
    );
  }
}

class _AvailabilityHero extends StatelessWidget {
  const _AvailabilityHero({
    required this.nextOpen,
    required this.onOpenSessions,
  });

  final AvailabilitySlot? nextOpen;
  final VoidCallback onOpenSessions;

  String _formatHeadline(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[local.weekday - 1]} ${local.day} at $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF173D63), Color(0xFF1AA9A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 820;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AvailabilityEyebrow(
                label: 'COUNSELOR AVAILABILITY',
                color: Color(0xFFFDE68A),
                background: Color(0x24FFFFFF),
                border: Color(0x44FFFFFF),
              ),
              const SizedBox(height: 16),
              Text(
                nextOpen == null
                    ? 'No future open slot is published right now.'
                    : 'Next open slot is ${_formatHeadline(nextOpen!.startAt)}.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.04,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Keep your calendar bookable, publish forward coverage, and use the weekly grid for fast slot management.',
                style: TextStyle(
                  color: Color(0xFFD7E5F0),
                  fontSize: 15.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenSessions,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0C2233),
                ),
                icon: const Icon(Icons.arrow_outward_rounded),
                label: const Text('Open Sessions'),
              ),
            ],
          );

          final sideCard = Container(
            width: stacked ? double.infinity : 270,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x55FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Coverage pulse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _AvailabilityMiniSignal(
                  label: 'Forward slot',
                  value: nextOpen == null ? 'missing' : 'live',
                  tone: nextOpen == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF10B981),
                ),
                const SizedBox(height: 10),
                const _AvailabilityMiniSignal(
                  label: 'Calendar mode',
                  value: 'weekly',
                  tone: Color(0xFFFDE68A),
                ),
              ],
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [intro, const SizedBox(height: 18), sideCard],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intro),
              const SizedBox(width: 18),
              sideCard,
            ],
          );
        },
      ),
    );
  }
}

class _AvailabilityStatCard extends StatelessWidget {
  const _AvailabilityStatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
  });

  final String label;
  final String value;
  final String hint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF081A30),
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              color: Color(0xFF7B8CA4),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityEyebrow extends StatelessWidget {
  const _AvailabilityEyebrow({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _AvailabilityMiniSignal extends StatelessWidget {
  const _AvailabilityMiniSignal({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD6E4EE),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotFeedCard extends StatelessWidget {
  const _SlotFeedCard({
    required this.slot,
    required this.formatDateTime,
    required this.onDelete,
  });

  final AvailabilitySlot slot;
  final String Function(DateTime value) formatDateTime;
  final VoidCallback? onDelete;

  Color get _tone {
    switch (slot.status) {
      case AvailabilitySlotStatus.available:
        return const Color(0xFF0E9B90);
      case AvailabilitySlotStatus.booked:
        return const Color(0xFF2563EB);
      case AvailabilitySlotStatus.blocked:
        return const Color(0xFFF97316);
    }
  }

  Color get _background {
    switch (slot.status) {
      case AvailabilitySlotStatus.available:
        return const Color(0xFFE9FBF8);
      case AvailabilitySlotStatus.booked:
        return const Color(0xFFEFF6FF);
      case AvailabilitySlotStatus.blocked:
        return const Color(0xFFFFF7ED);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(slot.startAt),
                  style: const TextStyle(
                    color: Color(0xFF081A30),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ends: ${formatDateTime(slot.endAt)}',
                  style: const TextStyle(
                    color: Color(0xFF5E728D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  slot.status.name,
                  style: TextStyle(color: _tone, fontWeight: FontWeight.w800),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilityEmptyCard extends StatelessWidget {
  const _AvailabilityEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF0C2233),
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.hour});

  final int hour;

  String _label(int h) {
    final suffix = h >= 12 ? 'PM' : 'AM';
    final normalized = h == 0
        ? 12
        : h > 12
        ? h - 12
        : h;
    return '$normalized:00 $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Text(
        _label(hour),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.width,
    required this.color,
    required this.slotCount,
    required this.isBusy,
    required this.onTap,
  });

  final double width;
  final Color color;
  final int slotCount;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: isBusy
                ? Text(
                    '$slotCount slot${slotCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF94A3B8),
                    size: 16,
                  ),
          ),
        ),
      ),
    );
  }
}
