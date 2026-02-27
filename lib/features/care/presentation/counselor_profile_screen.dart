import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _SpotPeriod { any, morning, afternoon, evening }

enum _WeeklySlotStatus {
  pending,
  confirmed,
  cancelledByStudent,
  cancelledByCounselor,
  completed,
  noShow,
}

class CounselorProfileScreen extends ConsumerStatefulWidget {
  const CounselorProfileScreen({super.key, required this.counselorId});

  final String counselorId;

  @override
  ConsumerState<CounselorProfileScreen> createState() =>
      _CounselorProfileScreenState();
}

class _CounselorProfileScreenState
    extends ConsumerState<CounselorProfileScreen> {
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

  late DateTime _weekStart;
  DateTime? _selectedDay;
  _SpotPeriod _period = _SpotPeriod.any;
  String? _freezeCacheOwnerUserId;
  bool _freezeCacheReady = false;
  bool _freezeCacheLoading = false;
  final Map<String, String> _frozenStatusByAppointmentId = <String, String>{};
  final Map<String, String> _pendingFreezeWrites = <String, String>{};
  bool _freezeApplyScheduled = false;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
  }

  String _freezeStorageKey(String userId) => 'weekly_status_freeze_$userId';

  _WeeklySlotStatus _statusFromAppointment(AppointmentRecord appointment) {
    switch (appointment.status) {
      case AppointmentStatus.pending:
        return _WeeklySlotStatus.pending;
      case AppointmentStatus.confirmed:
        return _WeeklySlotStatus.confirmed;
      case AppointmentStatus.completed:
        return _WeeklySlotStatus.completed;
      case AppointmentStatus.noShow:
        return _WeeklySlotStatus.noShow;
      case AppointmentStatus.cancelled:
        return appointment.cancelledByRole == 'counselor'
            ? _WeeklySlotStatus.cancelledByCounselor
            : _WeeklySlotStatus.cancelledByStudent;
    }
  }

  String _statusKey(_WeeklySlotStatus status) {
    switch (status) {
      case _WeeklySlotStatus.pending:
        return 'pending';
      case _WeeklySlotStatus.confirmed:
        return 'confirmed';
      case _WeeklySlotStatus.cancelledByStudent:
        return 'cancelledByStudent';
      case _WeeklySlotStatus.cancelledByCounselor:
        return 'cancelledByCounselor';
      case _WeeklySlotStatus.completed:
        return 'completed';
      case _WeeklySlotStatus.noShow:
        return 'noShow';
    }
  }

  _WeeklySlotStatus _statusFromKey(String raw) {
    switch (raw) {
      case 'confirmed':
        return _WeeklySlotStatus.confirmed;
      case 'cancelledByStudent':
        return _WeeklySlotStatus.cancelledByStudent;
      case 'cancelledByCounselor':
        return _WeeklySlotStatus.cancelledByCounselor;
      case 'completed':
        return _WeeklySlotStatus.completed;
      case 'noShow':
        return _WeeklySlotStatus.noShow;
      case 'pending':
      default:
        return _WeeklySlotStatus.pending;
    }
  }

  _WeeklySlotStatus _displayStatusForAppointment(
    AppointmentRecord appointment,
    DateTime nowLocal,
  ) {
    final isPast = !appointment.endAt.toLocal().isAfter(nowLocal);
    if (!isPast) {
      return _statusFromAppointment(appointment);
    }
    final frozen = _frozenStatusByAppointmentId[appointment.id];
    if (frozen != null) {
      return _statusFromKey(frozen);
    }
    return _statusFromAppointment(appointment);
  }

  Future<void> _ensureFreezeCacheLoaded(UserProfile? profile) async {
    final userId = profile?.id ?? '';
    if (userId.isEmpty) {
      return;
    }
    if (_freezeCacheOwnerUserId == userId &&
        (_freezeCacheReady || _freezeCacheLoading)) {
      return;
    }

    _freezeCacheOwnerUserId = userId;
    _freezeCacheReady = false;
    _freezeCacheLoading = true;
    _frozenStatusByAppointmentId.clear();
    _pendingFreezeWrites.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_freezeStorageKey(userId));
      final decoded = <String, String>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map) {
            for (final entry in parsed.entries) {
              final key = entry.key.toString().trim();
              final value = entry.value.toString().trim();
              if (key.isNotEmpty && value.isNotEmpty) {
                decoded[key] = value;
              }
            }
          }
        } catch (_) {}
      }

      if (!mounted || _freezeCacheOwnerUserId != userId) {
        _freezeCacheLoading = false;
        return;
      }
      setState(() {
        _frozenStatusByAppointmentId
          ..clear()
          ..addAll(decoded);
        _freezeCacheReady = true;
        _freezeCacheLoading = false;
      });
    } catch (_) {
      if (!mounted || _freezeCacheOwnerUserId != userId) {
        _freezeCacheLoading = false;
        return;
      }
      setState(() {
        _freezeCacheReady = true;
        _freezeCacheLoading = false;
      });
    }
  }

  Future<void> _persistFreezeCacheIfReady() async {
    final userId = _freezeCacheOwnerUserId;
    if (userId == null || userId.isEmpty || !_freezeCacheReady) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _freezeStorageKey(userId),
      jsonEncode(_frozenStatusByAppointmentId),
    );
  }

  void _queueFreezePastStatuses({
    required List<AppointmentRecord> appointments,
    required DateTime nowLocal,
  }) {
    if (!_freezeCacheReady) {
      return;
    }
    for (final appointment in appointments) {
      final isPast = !appointment.endAt.toLocal().isAfter(nowLocal);
      if (!isPast) {
        continue;
      }
      if (_frozenStatusByAppointmentId.containsKey(appointment.id) ||
          _pendingFreezeWrites.containsKey(appointment.id)) {
        continue;
      }
      _pendingFreezeWrites[appointment.id] = _statusKey(
        _statusFromAppointment(appointment),
      );
    }
    if (_pendingFreezeWrites.isEmpty || _freezeApplyScheduled) {
      return;
    }

    _freezeApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _freezeApplyScheduled = false;
        return;
      }
      if (_pendingFreezeWrites.isEmpty) {
        _freezeApplyScheduled = false;
        return;
      }
      setState(() {
        _frozenStatusByAppointmentId.addAll(_pendingFreezeWrites);
        _pendingFreezeWrites.clear();
      });
      _freezeApplyScheduled = false;
      _persistFreezeCacheIfReady();
    });
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final offset = local.weekday - DateTime.monday;
    return local.subtract(Duration(days: offset));
  }

  List<DateTime> _weekDays() {
    return List<DateTime>.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
      growable: false,
    );
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

  String _shortWeekday(DateTime value) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[value.toLocal().weekday - 1];
  }

  String _friendlyDate(DateTime value) {
    final local = value.toLocal();
    return '${_shortWeekday(local)}, ${_monthNames[local.month - 1]} ${local.day}';
  }

  String _friendlyTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _periodLabel(_SpotPeriod period) {
    switch (period) {
      case _SpotPeriod.any:
        return 'Any time';
      case _SpotPeriod.morning:
        return 'Morning';
      case _SpotPeriod.afternoon:
        return 'Afternoon';
      case _SpotPeriod.evening:
        return 'Evening';
    }
  }

  bool _canCurrentUserBook(UserProfile? profile) {
    if (profile == null) {
      return false;
    }
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.individual;
  }

  bool _matchesSpotFilters(AvailabilitySlot slot) {
    final start = slot.startAt.toLocal();
    if (_selectedDay != null) {
      final day = _selectedDay!;
      if (start.year != day.year ||
          start.month != day.month ||
          start.day != day.day) {
        return false;
      }
    }

    switch (_period) {
      case _SpotPeriod.any:
        return true;
      case _SpotPeriod.morning:
        return start.hour < 12;
      case _SpotPeriod.afternoon:
        return start.hour >= 12 && start.hour < 17;
      case _SpotPeriod.evening:
        return start.hour >= 17;
    }
  }

  List<AvailabilitySlot> _filterAndSortSlots(List<AvailabilitySlot> slots) {
    final filtered = slots
        .where((slot) => _matchesSpotFilters(slot))
        .toList(growable: false);
    filtered.sort((a, b) => a.startAt.compareTo(b.startAt));
    return filtered;
  }

  List<AvailabilitySlot> _weekSlots(List<AvailabilitySlot> slots) {
    final weekEnd = _weekStart.add(const Duration(days: 7));
    return slots
        .where((slot) {
          final local = slot.startAt.toLocal();
          return !local.isBefore(_weekStart) && local.isBefore(weekEnd);
        })
        .toList(growable: false);
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

  List<AppointmentRecord> _weekAppointments(List<AppointmentRecord> entries) {
    final weekEnd = _weekStart.add(const Duration(days: 7));
    return entries
        .where((entry) {
          final start = entry.startAt.toLocal();
          final end = entry.endAt.toLocal();
          return start.isBefore(weekEnd) && end.isAfter(_weekStart);
        })
        .toList(growable: false);
  }

  List<AppointmentRecord> _appointmentsForCell({
    required List<AppointmentRecord> appointments,
    required DateTime day,
    required int hour,
  }) {
    final cellStart = DateTime(day.year, day.month, day.day, hour);
    final cellEnd = cellStart.add(const Duration(hours: 1));
    return appointments
        .where((entry) {
          final start = entry.startAt.toLocal();
          final end = entry.endAt.toLocal();
          return start.isBefore(cellEnd) && end.isAfter(cellStart);
        })
        .toList(growable: false);
  }

  Future<void> _pickSpotDay() async {
    final now = DateTime.now();
    final initial = _selectedDay ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDay = picked);
    }
  }

  Future<void> _bookSlot({
    required CounselorProfile counselor,
    required AvailabilitySlot slot,
    required UserProfile currentProfile,
  }) async {
    final institutionId = currentProfile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join an institution first.')),
      );
      return;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .bookCounselorSlot(
            institutionId: institutionId,
            counselor: counselor,
            slot: slot,
            currentProfile: currentProfile,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session booked successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _showCellSlots({
    required CounselorProfile counselor,
    required UserProfile? currentProfile,
    required List<AvailabilitySlot> cellSlots,
  }) async {
    final canBook = _canCurrentUserBook(currentProfile);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDCE5EF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6E4F2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F3F1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        color: Color(0xFF0E9B90),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Available Spots',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${cellSlots.length} slot${cellSlots.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF516784),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...cellSlots.map((slot) {
                  final dateLabel = _friendlyDate(slot.startAt);
                  final timeLabel =
                      '${_friendlyTime(slot.startAt)} - ${_friendlyTime(slot.endAt)}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFFFF), Color(0xFFF4F9FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDCE5EF)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF516784),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  timeLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: !canBook || currentProfile == null
                                ? null
                                : () async {
                                    Navigator.of(context).pop();
                                    await _bookSlot(
                                      counselor: counselor,
                                      slot: slot,
                                      currentProfile: currentProfile,
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0E9B90),
                              disabledBackgroundColor: const Color(0xFFCBD5E1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 15),
                            label: const Text(
                              'Book',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (!canBook)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Text(
                      'Only students, staff, and individual users can book sessions.',
                      style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyGrid({
    required CounselorProfile counselor,
    required List<AvailabilitySlot> slots,
    required List<AppointmentRecord> appointments,
    required UserProfile? profile,
  }) {
    final weekSlots = _weekSlots(slots);
    final weekAppointments = _weekAppointments(appointments);
    final nowLocal = DateTime.now().toLocal();
    _queueFreezePastStatuses(
      appointments: weekAppointments,
      nowLocal: nowLocal,
    );
    final days = _weekDays();
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 560;
                if (!isMobile) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Counselor Weekly Schedule',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 250, child: weekControls),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Counselor Weekly Schedule',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: weekControls),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap a highlighted cell to view available spots and book.',
            ),
            const SizedBox(height: 12),
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
                              slots: weekSlots,
                              day: day,
                              hour: hour,
                            );
                            final cellAppointments = _appointmentsForCell(
                              appointments: weekAppointments,
                              day: day,
                              hour: hour,
                            );
                            final statusList = cellAppointments
                                .map(
                                  (entry) => _displayStatusForAppointment(
                                    entry,
                                    nowLocal,
                                  ),
                                )
                                .toList(growable: false);
                            return _ScheduleCell(
                              width: 132,
                              slots: cellSlots,
                              statuses: statusList,
                              onTap: cellSlots.isEmpty
                                  ? null
                                  : () => _showCellSlots(
                                      counselor: counselor,
                                      currentProfile: profile,
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

  Widget _buildPendingCounselorHeader({
    required String institutionId,
    required String counselorId,
  }) {
    if (institutionId.isEmpty) {
      return const GlassCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Counselor profile setup is in progress.',
            style: TextStyle(color: Color(0xFF5E728D)),
          ),
        ),
      );
    }

    final firestore = ref.watch(firestoreProvider);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('institution_members')
          .doc('${institutionId}_$counselorId')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final displayName =
            (data?['userName'] as String?) ??
            (data?['name'] as String?) ??
            'Counselor';
        return GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Counselor profile setup in progress'),
                const SizedBox(height: 4),
                const Text(
                  'Basic scheduling is available while this profile is being completed.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroChip({
    required String label,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounselorHeroCard(CounselorProfile counselor) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EBFF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    size: 48,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              counselor.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              counselor.title,
              style: const TextStyle(
                fontSize: 24 / 2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildHeroChip(
                  label: '${counselor.yearsExperience} yrs experience',
                  background: const Color(0xFFEFF6FF),
                  foreground: const Color(0xFF5E728D),
                ),
                _buildHeroChip(
                  label: counselor.sessionMode,
                  background: const Color(0xFFF1F5F9),
                  foreground: const Color(0xFF64748B),
                ),
                _buildHeroChip(
                  label:
                      '${counselor.ratingAverage.toStringAsFixed(1)} (${counselor.ratingCount} ratings)',
                  background: const Color(0xFFFFF7E6),
                  foreground: const Color(0xFFB45309),
                  icon: Icons.star_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              counselor.bio.trim().isNotEmpty
                  ? counselor.bio.trim()
                  : 'Specializing in ${counselor.specialization.toLowerCase()}, helping you navigate life\'s challenges with evidence-based approaches.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF5E728D),
                fontSize: 22 / 2,
                height: 1.45,
              ),
            ),
            if (counselor.languages.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.language_rounded,
                    size: 15,
                    color: Color(0xFF8DA0B7),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      counselor.languages.join(', ').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8DA0B7),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookingPolicyCard() {
    return GlassCard(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7FF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD9E0FF)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.all(Radius.circular(13)),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFFD9E0FF)),
                  ),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF4F46E5),
                  size: 20,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Booking Policy',
                    style: TextStyle(
                      fontSize: 18 / 2,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1B4B),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Please cancel or reschedule at least 24 hours in advance. Counselors aim to confirm sessions within 2 hours of booking.',
                    style: TextStyle(
                      color: Color(0xFF4F46E5),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindSpotSection({
    required CounselorProfile counselor,
    required List<AvailabilitySlot> filteredWeekSlots,
    required UserProfile? profile,
    required bool canBook,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Find a Spot',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedDay = null;
                  _period = _SpotPeriod.any;
                });
              },
              child: const Text('CLEAR FILTERS'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickSpotDay,
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _selectedDay == null
                              ? 'Any day'
                              : '${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PopupMenuButton<_SpotPeriod>(
                        onSelected: (value) => setState(() => _period = value),
                        itemBuilder: (context) => _SpotPeriod.values
                            .map(
                              (period) => PopupMenuItem<_SpotPeriod>(
                                value: period,
                                child: Text(_periodLabel(period)),
                              ),
                            )
                            .toList(growable: false),
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFDCE5EF)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _periodLabel(_period),
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: filteredWeekSlots.isEmpty || !canBook
                      ? null
                      : () => _bookSlot(
                          counselor: counselor,
                          slot: filteredWeekSlots.first,
                          currentProfile: profile!,
                        ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Book next available'),
                ),
                const SizedBox(height: 8),
                Text(
                  '${filteredWeekSlots.length} matching spots in this week.',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                if (!canBook)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Only students, staff, and individual users can book sessions.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
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
    final institutionId = profile?.institutionId ?? '';
    final canBook = _canCurrentUserBook(profile);
    _ensureFreezeCacheLoaded(profile);

    return MindNestShell(
      maxWidth: 1080,
      appBar: null,
      child: StreamBuilder<CounselorProfile?>(
        stream: ref
            .read(careRepositoryProvider)
            .watchCounselorProfile(widget.counselorId),
        builder: (context, counselorSnapshot) {
          final profileReadDenied =
              counselorSnapshot.error is FirebaseException &&
              (counselorSnapshot.error as FirebaseException).code ==
                  'permission-denied';
          if (counselorSnapshot.hasError && !profileReadDenied) {
            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  counselorSnapshot.error.toString().replaceFirst(
                    'Exception: ',
                    '',
                  ),
                ),
              ),
            );
          }
          final counselor = counselorSnapshot.data;
          final effectiveCounselor =
              counselor ??
              CounselorProfile(
                id: widget.counselorId,
                institutionId: institutionId,
                displayName: 'Counselor',
                title: 'Counselor',
                specialization: 'Profile setup in progress',
                sessionMode: '--',
                timezone: 'UTC',
                bio: '',
                yearsExperience: 0,
                languages: const <String>[],
                ratingAverage: 0,
                ratingCount: 0,
                isActive: true,
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              counselor == null
                  ? _buildPendingCounselorHeader(
                      institutionId: institutionId,
                      counselorId: widget.counselorId,
                    )
                  : _buildCounselorHeroCard(counselor),
              const SizedBox(height: 12),
              _buildBookingPolicyCard(),
              const SizedBox(height: 12),
              if (institutionId.isEmpty)
                const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Join an institution to view and book counselor schedules.',
                    ),
                  ),
                )
              else
                StreamBuilder<List<AvailabilitySlot>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchCounselorPublicAvailability(
                        institutionId: institutionId,
                        counselorId: effectiveCounselor.id,
                      ),
                  builder: (context, availabilitySnapshot) {
                    if (availabilitySnapshot.hasError) {
                      return GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            availabilitySnapshot.error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          ),
                        ),
                      );
                    }

                    final slots = availabilitySnapshot.data ?? const [];
                    final weeklyFiltered = _filterAndSortSlots(
                      _weekSlots(slots),
                    );

                    if (availabilitySnapshot.connectionState ==
                            ConnectionState.waiting &&
                        slots.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFindSpotSection(
                          counselor: effectiveCounselor,
                          filteredWeekSlots: weeklyFiltered,
                          profile: profile,
                          canBook: canBook,
                        ),
                        const SizedBox(height: 12),
                        if (profile != null &&
                            institutionId.isNotEmpty &&
                            _canCurrentUserBook(profile))
                          StreamBuilder<List<AppointmentRecord>>(
                            stream: ref
                                .read(careRepositoryProvider)
                                .watchStudentAppointments(
                                  institutionId: institutionId,
                                  studentId: profile.id,
                                ),
                            builder: (context, appointmentSnapshot) {
                              final counselorAppointments =
                                  (appointmentSnapshot.data ?? const [])
                                      .where(
                                        (entry) =>
                                            entry.counselorId ==
                                            effectiveCounselor.id,
                                      )
                                      .toList(growable: false);
                              return _buildWeeklyGrid(
                                counselor: effectiveCounselor,
                                slots: slots,
                                appointments: counselorAppointments,
                                profile: profile,
                              );
                            },
                          )
                        else
                          _buildWeeklyGrid(
                            counselor: effectiveCounselor,
                            slots: slots,
                            appointments: const [],
                            profile: profile,
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        },
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

class _ScheduleCell extends StatelessWidget {
  const _ScheduleCell({
    required this.width,
    required this.slots,
    required this.statuses,
    required this.onTap,
  });

  final double width;
  final List<AvailabilitySlot> slots;
  final List<_WeeklySlotStatus> statuses;
  final VoidCallback? onTap;

  int _priority(_WeeklySlotStatus status) {
    switch (status) {
      case _WeeklySlotStatus.noShow:
        return 6;
      case _WeeklySlotStatus.cancelledByCounselor:
        return 5;
      case _WeeklySlotStatus.cancelledByStudent:
        return 4;
      case _WeeklySlotStatus.confirmed:
        return 3;
      case _WeeklySlotStatus.pending:
        return 2;
      case _WeeklySlotStatus.completed:
        return 1;
    }
  }

  _WeeklySlotStatus? _topStatus() {
    if (statuses.isEmpty) {
      return null;
    }
    final sorted = statuses.toList(growable: false)
      ..sort((a, b) => _priority(b).compareTo(_priority(a)));
    return sorted.first;
  }

  String _statusLabel(_WeeklySlotStatus status) {
    switch (status) {
      case _WeeklySlotStatus.pending:
        return 'Pending';
      case _WeeklySlotStatus.confirmed:
        return 'Confirmed';
      case _WeeklySlotStatus.cancelledByStudent:
        return 'Cancelled';
      case _WeeklySlotStatus.cancelledByCounselor:
        return 'Declined';
      case _WeeklySlotStatus.completed:
        return 'Completed';
      case _WeeklySlotStatus.noShow:
        return 'No-show';
    }
  }

  Color _statusTextColor(_WeeklySlotStatus status) {
    switch (status) {
      case _WeeklySlotStatus.pending:
        return const Color(0xFFB45309);
      case _WeeklySlotStatus.confirmed:
        return const Color(0xFF0F766E);
      case _WeeklySlotStatus.cancelledByStudent:
        return const Color(0xFF475569);
      case _WeeklySlotStatus.cancelledByCounselor:
        return const Color(0xFFB91C1C);
      case _WeeklySlotStatus.completed:
        return const Color(0xFF1D4ED8);
      case _WeeklySlotStatus.noShow:
        return const Color(0xFFB91C1C);
    }
  }

  Color _background() {
    final top = _topStatus();
    if (top != null) {
      switch (top) {
        case _WeeklySlotStatus.pending:
          return const Color(0xFFFFF7E6);
        case _WeeklySlotStatus.confirmed:
          return const Color(0xFFE8FFF6);
        case _WeeklySlotStatus.cancelledByStudent:
          return const Color(0xFFF1F5F9);
        case _WeeklySlotStatus.cancelledByCounselor:
          return const Color(0xFFFFEEF0);
        case _WeeklySlotStatus.completed:
          return const Color(0xFFEFF6FF);
        case _WeeklySlotStatus.noShow:
          return const Color(0xFFFFE8EC);
      }
    }
    if (slots.isEmpty) {
      return Colors.white;
    }
    return const Color(0xFFEFFFFC);
  }

  @override
  Widget build(BuildContext context) {
    final topStatus = _topStatus();
    final count = slots.length;
    final hasStatus = topStatus != null;
    final statusCount = statuses.length;
    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        color: _background(),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: hasStatus
                ? Text(
                    statusCount > 1
                        ? '$statusCount ${_statusLabel(topStatus)}'
                        : _statusLabel(topStatus),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _statusTextColor(topStatus),
                    ),
                  )
                : slots.isEmpty
                ? const Icon(
                    Icons.remove_rounded,
                    color: Color(0xFFB8C3D3),
                    size: 16,
                  )
                : Text(
                    '$count open',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
