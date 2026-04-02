import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class CounselorAvailabilityScreen extends ConsumerStatefulWidget {
  const CounselorAvailabilityScreen({
    super.key,
    this.embeddedInCounselorShell = false,
  });

  final bool embeddedInCounselorShell;

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
  bool _isFeedCollapsed = false;
  bool _slotTimelineView = true;
  AvailabilitySlotStatus? _slotTimelineFilter;
  AvailabilitySlotStatus? _slotTableFilter;
  int _slotTableRowsPerPage = 6;
  int _slotTablePage = 0;
  String? _expandedSlotDateKey;

  static const double _feedMaxHeight = 360;

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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${local.minute.toString().padLeft(2, '0')} $suffix';
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
      if (handled == true) {
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

  List<AvailabilitySlot> _sortedSlots(List<AvailabilitySlot> source) {
    final sorted = [...source]
      ..sort((a, b) {
        final primary = a.startAt.compareTo(b.startAt);
        if (primary != 0) return primary;
        return a.endAt.compareTo(b.endAt);
      });
    return sorted;
  }

  Color _slotStatusColor(AvailabilitySlotStatus status) {
    switch (status) {
      case AvailabilitySlotStatus.available:
        return const Color(0xFF0E9B90);
      case AvailabilitySlotStatus.booked:
        return const Color(0xFF2563EB);
      case AvailabilitySlotStatus.blocked:
        return const Color(0xFFF97316);
    }
  }

  String _slotStatusLabel(AvailabilitySlotStatus status) {
    switch (status) {
      case AvailabilitySlotStatus.available:
        return 'Available';
      case AvailabilitySlotStatus.booked:
        return 'Booked';
      case AvailabilitySlotStatus.blocked:
        return 'Blocked';
    }
  }

  String _slotDateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
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
      case CounselorWorkspaceNavSection.live:
        context.go(AppRoute.counselorLiveHub);
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
      case CounselorWorkspaceNavSection.counselors:
        context.go(AppRoute.counselorDirectory);
    }
  }

  Widget _buildSlotTimeline(
    BuildContext context,
    List<AvailabilitySlot> slots,
    bool loading,
  ) {
    Widget statusChip({
      required String label,
      required AvailabilitySlotStatus? status,
      required Color color,
    }) {
      final selected = _slotTimelineFilter == status;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _slotTimelineFilter = status;
          _expandedSlotDateKey = null;
        }),
        selectedColor: color.withValues(alpha: 0.12),
        side: BorderSide(
          color: selected ? color : const Color(0xFFD3E0EE),
          width: selected ? 1.2 : 1,
        ),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? color : const Color(0xFF475569),
        ),
      );
    }

    final filtered = _sortedSlots(slots)
        .where(
          (slot) =>
              _slotTimelineFilter == null || slot.status == _slotTimelineFilter,
        )
        .toList(growable: false);

    final filterBar = GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            statusChip(
              label: 'All',
              status: null,
              color: const Color(0xFF0E7490),
            ),
            statusChip(
              label: 'Available',
              status: AvailabilitySlotStatus.available,
              color: _slotStatusColor(AvailabilitySlotStatus.available),
            ),
            statusChip(
              label: 'Booked',
              status: AvailabilitySlotStatus.booked,
              color: _slotStatusColor(AvailabilitySlotStatus.booked),
            ),
            statusChip(
              label: 'Blocked',
              status: AvailabilitySlotStatus.blocked,
              color: _slotStatusColor(AvailabilitySlotStatus.blocked),
            ),
          ],
        ),
      ),
    );

    if (filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterBar,
          const SizedBox(height: 10),
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No slots match the selected filter.'),
            ),
          ),
        ],
      );
    }

    final grouped = <String, List<AvailabilitySlot>>{};
    final dateByKey = <String, DateTime>{};
    for (final slot in filtered) {
      final key = _slotDateKey(slot.startAt);
      grouped.putIfAbsent(key, () => <AvailabilitySlot>[]).add(slot);
      dateByKey.putIfAbsent(key, () {
        final local = slot.startAt.toLocal();
        return DateTime(local.year, local.month, local.day);
      });
    }
    final orderedKeys = grouped.keys.toList(growable: false);
    final todayKey = _slotDateKey(DateTime.now());
    final defaultExpandedKey = grouped.containsKey(todayKey)
        ? todayKey
        : orderedKeys.first;

    Widget dateHeader(DateTime date, int count) {
      return Row(
        children: [
          Text(
            '${_weekdayLabel(date)} ${date.day} ${_monthNames[date.month - 1]}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterBar,
        const SizedBox(height: 10),
        if (_isFeedCollapsed)
          _FeedCollapsedBanner(
            total: filtered.length,
            onExpand: () => setState(() => _isFeedCollapsed = false),
          )
        else
          SizedBox(
            height: _feedMaxHeight,
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.separated(
                primary: false,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemCount: orderedKeys.length,
                itemBuilder: (context, index) {
                  final key = orderedKeys[index];
                  final day = dateByKey[key]!;
                  final events = grouped[key]!;
                  final expandedKey =
                      _expandedSlotDateKey ?? defaultExpandedKey;
                  final expanded = key == expandedKey;
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                if (_expandedSlotDateKey == key) {
                                  _expandedSlotDateKey = null;
                                } else {
                                  _expandedSlotDateKey = key;
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    color: const Color(0xFF334155),
                                  ),
                                  const SizedBox(width: 4),
                                  dateHeader(day, events.length),
                                  const Spacer(),
                                  Text(
                                    'Next at ${_formatTime(events.first.startAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (expanded) ...[
                            const SizedBox(height: 6),
                            ...events.map((slot) {
                              final tone = _slotStatusColor(slot.status);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: tone,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _StatusPill(
                                      label: _slotStatusLabel(slot.status),
                                      color: tone,
                                    ),
                                    const Spacer(),
                                    if (slot.status ==
                                        AvailabilitySlotStatus.available)
                                      TextButton.icon(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(careRepositoryProvider)
                                                .deleteAvailabilitySlot(slot);
                                          } catch (error) {
                                            if (!context.mounted) return;
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
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Delete'),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSlotTable(BuildContext context, List<AvailabilitySlot> slots) {
    final filtered = _sortedSlots(slots)
        .where(
          (slot) => _slotTableFilter == null || slot.status == _slotTableFilter,
        )
        .toList(growable: false);

    final totalRows = filtered.length;
    final totalPages = totalRows == 0
        ? 1
        : ((totalRows + _slotTableRowsPerPage - 1) ~/ _slotTableRowsPerPage);
    final pageIndex = _slotTablePage >= totalPages
        ? totalPages - 1
        : _slotTablePage;
    final rows = filtered
        .skip(pageIndex * _slotTableRowsPerPage)
        .take(_slotTableRowsPerPage)
        .toList(growable: false);

    Widget statusFilterChip({
      required String label,
      required AvailabilitySlotStatus? status,
      required Color color,
    }) {
      final selected = _slotTableFilter == status;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _slotTableFilter = status;
          _slotTablePage = 0;
        }),
        selectedColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: selected ? color : const Color(0xFFD3E0EE)),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? color : const Color(0xFF475569),
        ),
      );
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.table_chart_rounded,
                  size: 18,
                  color: Color(0xFF0E9B90),
                ),
                const SizedBox(width: 8),
                Text(
                  'Slots ($totalRows)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x66FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD0DFEE)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _slotTableRowsPerPage,
                      isDense: true,
                      borderRadius: BorderRadius.circular(10),
                      items: const [
                        DropdownMenuItem(value: 4, child: Text('4 / page')),
                        DropdownMenuItem(value: 6, child: Text('6 / page')),
                        DropdownMenuItem(value: 8, child: Text('8 / page')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _slotTableRowsPerPage = value;
                            _slotTablePage = 0;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                statusFilterChip(
                  label: 'All',
                  status: null,
                  color: const Color(0xFF0E7490),
                ),
                statusFilterChip(
                  label: 'Available',
                  status: AvailabilitySlotStatus.available,
                  color: _slotStatusColor(AvailabilitySlotStatus.available),
                ),
                statusFilterChip(
                  label: 'Booked',
                  status: AvailabilitySlotStatus.booked,
                  color: _slotStatusColor(AvailabilitySlotStatus.booked),
                ),
                statusFilterChip(
                  label: 'Blocked',
                  status: AvailabilitySlotStatus.blocked,
                  color: _slotStatusColor(AvailabilitySlotStatus.blocked),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _feedMaxHeight),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  primary: false,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final slot = rows[index];
                    final tone = _slotStatusColor(slot.status);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatDateTime(slot.startAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatDateTime(slot.endAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _StatusPill(
                              label: _slotStatusLabel(slot.status),
                              color: tone,
                            ),
                          ),
                          if (slot.status == AvailabilitySlotStatus.available)
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(careRepositoryProvider)
                                      .deleteAvailabilitySlot(slot);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Delete'),
                            )
                          else
                            const SizedBox(width: 64),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Page ${pageIndex + 1} of $totalPages',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: pageIndex > 0
                      ? () => setState(() => _slotTablePage = pageIndex - 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: pageIndex < totalPages - 1
                      ? () => setState(() => _slotTablePage = pageIndex + 1)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required UserProfile profile,
    required List<AvailabilitySlot> slots,
    required bool loading,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  'Publish a visible booking window for students. Create a slot here or directly from an empty cell in the weekly calendar below.',
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 540;
                    final feedControls = Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('Table'),
                          selected: !_slotTimelineView,
                          onSelected: (_) => setState(() {
                            _slotTimelineView = false;
                            _isFeedCollapsed = false;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Timeline'),
                          selected: _slotTimelineView,
                          onSelected: (_) => setState(() {
                            _slotTimelineView = true;
                          }),
                        ),
                        if (_slotTimelineView)
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _isFeedCollapsed = !_isFeedCollapsed,
                            ),
                            icon: Icon(
                              _isFeedCollapsed
                                  ? Icons.unfold_more_rounded
                                  : Icons.unfold_less_rounded,
                            ),
                            label: Text(
                              isCompact
                                  ? (_isFeedCollapsed ? 'Expand' : 'Collapse')
                                  : _isFeedCollapsed
                                  ? 'Expand timeline'
                                  : 'Collapse timeline',
                            ),
                          ),
                        if (loading)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                      ],
                    );

                    final feedCopy = Column(
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
                          isCompact ? 'Live slots' : 'Published slots',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF081A30),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isCompact
                              ? 'Edit live slots below.'
                              : 'Review the booking windows that are already live and edit or remove them from the feed below.',
                          style: const TextStyle(
                            color: Color(0xFF6A7C93),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          feedCopy,
                          const SizedBox(height: 14),
                          feedControls,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: feedCopy),
                        const SizedBox(width: 16),
                        feedControls,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (slots.isEmpty)
                  const _AvailabilityEmptyCard(
                    message:
                        'No availability slots are visible yet. Publish your first slot to start taking bookings.',
                  )
                else ...[
                  _slotTimelineView
                      ? _buildSlotTimeline(context, slots, loading)
                      : _buildSlotTable(context, slots),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return content;
        }
        return SingleChildScrollView(
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
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

    final showCounselorDirectory =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile.institutionId ?? ''),
            )
            .valueOrNull
            ?.directoryEnabled ??
        false;

    final availabilityBody = StreamBuilder<List<AvailabilitySlot>>(
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
    );

    if (widget.embeddedInCounselorShell) {
      return availabilityBody;
    }

    final unreadCount =
        ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;

    return CounselorWorkspaceScaffold(
      profile: profile,
      activeSection: CounselorWorkspaceNavSection.availability,
      showCounselorDirectory: showCounselorDirectory,
      unreadNotifications: unreadCount,
      title: 'Availability',
      subtitle:
          'Publish booking windows, manage the weekly grid, and keep your open inventory healthy.',
      onSelectSection: (section) => _navigateSection(context, section),
      onNotifications: () => context.go(AppRoute.notifications),
      onProfile: () => context.go(AppRoute.counselorSettings),
      onLogout: () => confirmAndLogout(context: context, ref: ref),
      child: availabilityBody,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FeedCollapsedBanner extends StatelessWidget {
  const _FeedCollapsedBanner({required this.total, required this.onExpand});

  final int total;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total slots in timeline',
              style: const TextStyle(
                color: Color(0xFF0C2233),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onExpand,
            icon: const Icon(Icons.unfold_more_rounded),
            label: const Text('Expand'),
          ),
        ],
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
