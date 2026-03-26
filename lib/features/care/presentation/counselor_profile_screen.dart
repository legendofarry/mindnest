import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _windowsPollInterval = Duration(seconds: 2);
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
  int? _selectedGridHour;
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
      case CounselorWorkspaceNavSection.counselors:
        context.go(AppRoute.counselorDirectory);
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
    final openCount = weekSlots.length;
    final activeAppointmentCount = weekAppointments
        .where(
          (entry) =>
              entry.status == AppointmentStatus.pending ||
              entry.status == AppointmentStatus.confirmed,
        )
        .length;
    final completedCount = weekAppointments
        .where((entry) => entry.status == AppointmentStatus.completed)
        .length;
    final selectedHourLabel = _selectedGridHour == null
        ? 'No time row focused'
        : 'Focused on ${_TimeCell.labelForHour(_selectedGridHour!)}';
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

    return _ProfileSectionCard(
      eyebrow: 'Weekly calendar',
      title: 'Weekly schedule',
      description: _canCurrentUserBook(profile)
          ? 'Review open cells across the week, inspect session activity, and tap highlighted windows to book available spots.'
          : 'Review the counselor week view, including open windows and current session activity across the schedule.',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFD),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFDCE6F0)),
        ),
        child: SizedBox(width: 250, child: weekControls),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProfileMetaPill(
                label: '$openCount open slot${openCount == 1 ? '' : 's'}',
                icon: Icons.event_available_rounded,
              ),
              _ProfileMetaPill(
                label:
                    '$activeAppointmentCount active session${activeAppointmentCount == 1 ? '' : 's'}',
                icon: Icons.calendar_month_rounded,
              ),
              _ProfileMetaPill(
                label: '$completedCount completed this week',
                icon: Icons.task_alt_rounded,
              ),
              _ProfileMetaPill(
                label: selectedHourLabel,
                icon: Icons.filter_alt_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ScheduleLegendChip(
                label: 'Open',
                background: Color(0xFFE8FFF6),
                foreground: Color(0xFF0E8F61),
              ),
              _ScheduleLegendChip(
                label: 'Pending',
                background: Color(0xFFFFF7E6),
                foreground: Color(0xFFB5690F),
              ),
              _ScheduleLegendChip(
                label: 'Confirmed',
                background: Color(0xFFE8FFF6),
                foreground: Color(0xFF0F766E),
              ),
              _ScheduleLegendChip(
                label: 'Completed',
                background: Color(0xFFEFF6FF),
                foreground: Color(0xFF2457A6),
              ),
              _ScheduleLegendChip(
                label: 'Cancelled or no-show',
                background: Color(0xFFFFEEF0),
                foreground: Color(0xFFB42318),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFD),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDCE6F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      const _HeaderCell(label: 'Time', width: 100),
                      ..._gridHours.map(
                        (hour) => _TimeCell(
                          hour: hour,
                          isRowHighlighted: _selectedGridHour == hour,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: days.length * 132,
                      child: Column(
                        children: [
                          Row(
                            children: days
                                .map(
                                  (day) => _HeaderCell(
                                    label: '${_weekdayLabel(day)} ${day.day}',
                                    width: 132,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          ..._gridHours.map((hour) {
                            final isRowHighlighted = _selectedGridHour == hour;
                            return Row(
                              children: days
                                  .map((day) {
                                    final cellSlots = _slotsForCell(
                                      slots: weekSlots,
                                      day: day,
                                      hour: hour,
                                    );
                                    final cellAppointments =
                                        _appointmentsForCell(
                                          appointments: weekAppointments,
                                          day: day,
                                          hour: hour,
                                        );
                                    final statusList = cellAppointments
                                        .map(
                                          (entry) =>
                                              _displayStatusForAppointment(
                                                entry,
                                                nowLocal,
                                              ),
                                        )
                                        .toList(growable: false);
                                    return _ScheduleCell(
                                      width: 132,
                                      slots: cellSlots,
                                      statuses: statusList,
                                      isRowHighlighted: isRowHighlighted,
                                      onTap: () {
                                        setState(
                                          () => _selectedGridHour = hour,
                                        );
                                        if (cellSlots.isEmpty) {
                                          return;
                                        }
                                        _showCellSlots(
                                          counselor: counselor,
                                          currentProfile: profile,
                                          cellSlots: cellSlots,
                                        );
                                      },
                                    );
                                  })
                                  .toList(growable: false),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCounselorHeader({
    required String institutionId,
    required String counselorId,
  }) {
    if (institutionId.isEmpty) {
      return const _ProfileStateCard(
        icon: Icons.shield_moon_outlined,
        title: 'Profile setup in progress',
        message: 'Counselor profile setup is still underway.',
      );
    }

    final firestore = _useWindowsRestFirestore
        ? null
        : ref.watch(firestoreProvider);
    final windowsRest = ref.watch(windowsFirestoreRestClientProvider);
    final memberStream = _useWindowsRestFirestore
        ? _buildWindowsPollingStream<Map<String, dynamic>?>(
            load: () async => (await windowsRest.getDocument(
              'institution_members/${institutionId}_$counselorId',
            ))?.data,
            signature: (data) => data == null ? 'null' : data.toString(),
          )
        : firestore
              !.collection('institution_members')
              .doc('${institutionId}_$counselorId')
              .snapshots()
              .map((doc) => doc.data());
    return StreamBuilder<Map<String, dynamic>?>(
      stream: memberStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final displayName =
            (data?['userName'] as String?) ??
            (data?['name'] as String?) ??
            'Counselor';
        return _ProfileSectionCard(
          eyebrow: 'Setup status',
          title: displayName,
          description:
              'This counselor is still completing their professional profile. Basic scheduling remains available during setup.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _ProfileMetaPill(
                label: 'Profile still being configured',
                icon: Icons.construction_rounded,
              ),
              _ProfileMetaPill(
                label: 'Basic scheduling available',
                icon: Icons.event_available_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  String _profileInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'CN';
    }
    return parts.map((part) => part[0].toUpperCase()).join();
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
    final summary = counselor.bio.trim().isNotEmpty
        ? counselor.bio.trim()
        : 'Specializing in ${counselor.specialization.toLowerCase()}, helping people navigate life transitions with evidence-based support.';
    return _ProfileSectionCard(
      eyebrow: 'Public profile',
      title: counselor.displayName,
      description: counselor.title,
      trailing: _buildHeroChip(
        label: counselor.isActive ? 'Active profile' : 'Profile paused',
        background: counselor.isActive
            ? const Color(0xFFE9FBF3)
            : const Color(0xFFF1F5F9),
        foreground: counselor.isActive
            ? const Color(0xFF0E8F61)
            : const Color(0xFF64748B),
        icon: counselor.isActive
            ? Icons.verified_rounded
            : Icons.pause_circle_outline_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final header = [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B2A4A), Color(0xFF184E77)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x180B2A4A),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _profileInitials(counselor.displayName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18, height: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildHeroChip(
                            label: counselor.specialization,
                            background: const Color(0xFFEAF2FF),
                            foreground: const Color(0xFF2457A6),
                            icon: Icons.psychology_alt_rounded,
                          ),
                          if ((counselor.gender ?? '').trim().isNotEmpty)
                            _buildHeroChip(
                              label: counselor.gender!.trim(),
                              background: const Color(0xFFF4F1FF),
                              foreground: const Color(0xFF6D4CC3),
                              icon: Icons.diversity_3_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        summary,
                        style: const TextStyle(
                          color: Color(0xFF5F738C),
                          fontSize: 14.5,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ];

              final metrics = Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ProfileMetricTile(
                    label: 'Experience',
                    value: '${counselor.yearsExperience} years',
                    icon: Icons.timeline_rounded,
                    tone: const Color(0xFF2457A6),
                  ),
                  _ProfileMetricTile(
                    label: 'Session mode',
                    value: counselor.sessionMode,
                    icon: Icons.video_call_rounded,
                    tone: const Color(0xFF0E8F61),
                  ),
                  _ProfileMetricTile(
                    label: 'Rating',
                    value: '${counselor.ratingAverage.toStringAsFixed(1)} / 5',
                    supporting:
                        '${counselor.ratingCount} review${counselor.ratingCount == 1 ? '' : 's'}',
                    icon: Icons.star_rounded,
                    tone: const Color(0xFFB5690F),
                  ),
                  _ProfileMetricTile(
                    label: 'Timezone',
                    value: counselor.timezone,
                    icon: Icons.public_rounded,
                    tone: const Color(0xFF6D4CC3),
                  ),
                ],
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: Row(children: header)),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: metrics),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: header,
                  ),
                  const SizedBox(height: 18),
                  metrics,
                ],
              );
            },
          ),
          if (counselor.languages.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCE6F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Communication',
                    style: TextStyle(
                      color: Color(0xFF10233E),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: counselor.languages
                        .map(
                          (language) => _ProfileMetaPill(
                            label: language,
                            icon: Icons.language_rounded,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfessionalSnapshotCard(CounselorProfile counselor) {
    return _ProfileSectionCard(
      eyebrow: 'Professional snapshot',
      title: 'How this counselor practices',
      description:
          'A structured view of the counselor profile students and peers use when reviewing fit, availability, and communication style.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useTwoColumns = constraints.maxWidth >= 860;
          final columnWidth = useTwoColumns
              ? (constraints.maxWidth - 14) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: columnWidth,
                child: _ProfileInfoBlock(
                  title: 'Focus area',
                  icon: Icons.psychology_alt_rounded,
                  accent: const Color(0xFF2457A6),
                  body: counselor.specialization,
                ),
              ),
              SizedBox(
                width: columnWidth,
                child: _ProfileInfoBlock(
                  title: 'Session delivery',
                  icon: Icons.desktop_windows_rounded,
                  accent: const Color(0xFF0E8F61),
                  body:
                      '${counselor.sessionMode} sessions coordinated in ${counselor.timezone}.',
                ),
              ),
              SizedBox(
                width: columnWidth,
                child: _ProfileInfoBlock(
                  title: 'Profile summary',
                  icon: Icons.notes_rounded,
                  accent: const Color(0xFF6D4CC3),
                  body: counselor.bio.trim().isNotEmpty
                      ? counselor.bio.trim()
                      : 'Professional biography has not been added yet.',
                ),
              ),
              SizedBox(
                width: columnWidth,
                child: _ProfileInfoBlock(
                  title: 'Student-facing signals',
                  icon: Icons.visibility_rounded,
                  accent: const Color(0xFFB5690F),
                  body: [
                    '${counselor.yearsExperience} years of experience',
                    if (counselor.languages.isNotEmpty)
                      '${counselor.languages.length} listed language${counselor.languages.length == 1 ? '' : 's'}',
                    if ((counselor.gender ?? '').trim().isNotEmpty)
                      'Gender shared on profile',
                    '${counselor.ratingCount} public rating${counselor.ratingCount == 1 ? '' : 's'}',
                  ].join(' • '),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBookingPolicyCard() {
    return _ProfileSectionCard(
      eyebrow: 'Booking guidance',
      title: 'What happens after a booking request',
      description:
          'Use this section to understand response timing, cancellation expectations, and how the counselor booking workflow is handled.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          if (compact) {
            return const Column(
              children: [
                _ProfileInfoBlock(
                  title: 'Confirmation pace',
                  icon: Icons.schedule_send_rounded,
                  accent: Color(0xFF2457A6),
                  body:
                      'Counselors aim to confirm session requests within 2 hours.',
                ),
                SizedBox(height: 12),
                _ProfileInfoBlock(
                  title: 'Changes and cancellations',
                  icon: Icons.update_rounded,
                  accent: Color(0xFFB5690F),
                  body:
                      'Please cancel or reschedule at least 24 hours before the planned session time.',
                ),
              ],
            );
          }
          return const Row(
            children: [
              Expanded(
                child: _ProfileInfoBlock(
                  title: 'Confirmation pace',
                  icon: Icons.schedule_send_rounded,
                  accent: Color(0xFF2457A6),
                  body:
                      'Counselors aim to confirm session requests within 2 hours.',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ProfileInfoBlock(
                  title: 'Changes and cancellations',
                  icon: Icons.update_rounded,
                  accent: Color(0xFFB5690F),
                  body:
                      'Please cancel or reschedule at least 24 hours before the planned session time.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFindSpotSection({
    required CounselorProfile counselor,
    required List<AvailabilitySlot> filteredWeekSlots,
    required UserProfile? profile,
    required bool canBook,
  }) {
    final previewSlots = filteredWeekSlots.take(3).toList(growable: false);
    return _ProfileSectionCard(
      eyebrow: 'Availability matching',
      title: 'Find a spot',
      description:
          'Filter the current week, preview the next openings, and move directly into the booking flow from one control surface.',
      trailing: TextButton(
        onPressed: () {
          setState(() {
            _selectedDay = null;
            _period = _SpotPeriod.any;
          });
        },
        child: const Text('Clear filters'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 720;
              final controls = [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickSpotDay,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(
                      _selectedDay == null
                          ? 'Any day'
                          : '${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: 10, height: 10),
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
              ];
              return stack
                  ? Column(children: controls)
                  : Row(children: controls);
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDCE6F0)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 760;
                final cta = ElevatedButton.icon(
                  onPressed: filteredWeekSlots.isEmpty || !canBook
                      ? null
                      : () => _bookSlot(
                          counselor: counselor,
                          slot: filteredWeekSlots.first,
                          currentProfile: profile!,
                        ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Book next available'),
                );
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${filteredWeekSlots.length} matching spots in this week',
                      style: const TextStyle(
                        color: Color(0xFF10233E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      previewSlots.isEmpty
                          ? 'No openings match the current filters.'
                          : 'Next opening: ${_friendlyDate(previewSlots.first.startAt)} at ${_friendlyTime(previewSlots.first.startAt)}',
                      style: const TextStyle(
                        color: Color(0xFF5F738C),
                        height: 1.5,
                      ),
                    ),
                  ],
                );
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 12), cta],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    cta,
                  ],
                );
              },
            ),
          ),
          if (previewSlots.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: previewSlots
                  .map(
                    (slot) => _AvailabilityPreviewTile(
                      dateLabel: _friendlyDate(slot.startAt),
                      timeLabel:
                          '${_friendlyTime(slot.startAt)} - ${_friendlyTime(slot.endAt)}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (!canBook)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Only students, staff, and individual users can book sessions.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final showCounselorDirectory =
        ref
            .watch(
              counselorWorkflowSettingsProvider(profile?.institutionId ?? ''),
            )
            .valueOrNull
            ?.directoryEnabled ??
        false;
    final institutionId = profile?.institutionId ?? '';
    final canBook = _canCurrentUserBook(profile);
    final isCounselorWorkspace =
        profile != null && profile.role == UserRole.counselor;
    final isViewingPeerCounselor =
        isCounselorWorkspace && profile.id != widget.counselorId;
    _ensureFreezeCacheLoaded(profile);

    final content = StreamBuilder<CounselorProfile?>(
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
              gender: null,
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
            if (counselorSnapshot.connectionState == ConnectionState.waiting &&
                counselor == null &&
                !profileReadDenied)
              const _ProfileStateCard(
                icon: Icons.person_search_rounded,
                title: 'Loading counselor profile',
                message: 'Fetching the current public profile details.',
                loading: true,
              )
            else
              counselor == null
                  ? _buildPendingCounselorHeader(
                      institutionId: institutionId,
                      counselorId: widget.counselorId,
                    )
                  : _buildCounselorHeroCard(counselor),
            const SizedBox(height: 14),
            _buildProfessionalSnapshotCard(effectiveCounselor),
            if (!isViewingPeerCounselor) ...[
              const SizedBox(height: 14),
              _buildBookingPolicyCard(),
              const SizedBox(height: 14),
              if (institutionId.isEmpty)
                const _ProfileStateCard(
                  icon: Icons.domain_add_outlined,
                  title: 'Institution required',
                  message:
                      'Join an institution first to view counselor availability and book sessions.',
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
                      return _ProfileStateCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'Availability unavailable',
                        message: availabilitySnapshot.error
                            .toString()
                            .replaceFirst('Exception: ', ''),
                      );
                    }

                    final slots = availabilitySnapshot.data ?? const [];
                    final weeklyFiltered = _filterAndSortSlots(
                      _weekSlots(slots),
                    );

                    if (availabilitySnapshot.connectionState ==
                            ConnectionState.waiting &&
                        slots.isEmpty) {
                      return const _ProfileStateCard(
                        icon: Icons.schedule_outlined,
                        title: 'Loading availability',
                        message:
                            'Preparing the counselor schedule and current booking windows.',
                        loading: true,
                      );
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
                        const SizedBox(height: 14),
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
          ],
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
        profileHighlighted: true,
        title: 'Counselor Profile',
        subtitle: isViewingPeerCounselor
            ? 'Review another counselor profile from the same workspace used across your dashboard, sessions, and settings.'
            : 'Review the public-facing counselor profile and availability from the same workspace used across your dashboard, sessions, and settings.',
        onSelectSection: (section) => _navigateSection(context, section),
        onNotifications: () => context.go(AppRoute.notifications),
        onProfile: () => context.go(AppRoute.counselorSettings),
        onLogout: () => confirmAndLogout(context: context, ref: ref),
        child: content,
      );
    }

    return MindNestShell(maxWidth: 1080, appBar: null, child: content);
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 720;
                final headerText = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF7C93AF),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F2037),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF5F738C),
                        fontSize: 14.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );

                if (trailing == null) {
                  return headerText;
                }
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerText,
                      const SizedBox(height: 14),
                      trailing!,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headerText),
                    const SizedBox(width: 18),
                    trailing!,
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileMetaPill extends StatelessWidget {
  const _ProfileMetaPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF59718E)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF48627D),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetricTile extends StatelessWidget {
  const _ProfileMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.supporting,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final String? supporting;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF7C93AF),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (supporting != null) ...[
            const SizedBox(height: 4),
            Text(
              supporting!,
              style: const TextStyle(
                color: Color(0xFF5F738C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileInfoBlock extends StatelessWidget {
  const _ProfileInfoBlock({
    required this.title,
    required this.icon,
    required this.accent,
    required this.body,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF10233E),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF5F738C),
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityPreviewTile extends StatelessWidget {
  const _AvailabilityPreviewTile({
    required this.dateLabel,
    required this.timeLabel,
  });

  final String dateLabel;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF4F8FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEXT OPENING',
            style: TextStyle(
              color: Color(0xFF7C93AF),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            dateLabel,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            style: const TextStyle(
              color: Color(0xFF5F738C),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStateCard extends StatelessWidget {
  const _ProfileStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Icon(icon, color: const Color(0xFF2457A6)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF10233E),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF5F738C),
                      fontSize: 14.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
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
}

class _ScheduleLegendChip extends StatelessWidget {
  const _ScheduleLegendChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
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
        color: const Color(0xFFF2F7FB),
        border: Border.all(color: const Color(0xFFD6E3EE)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF17304D),
        ),
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.hour, required this.isRowHighlighted});

  final int hour;
  final bool isRowHighlighted;

  static String labelForHour(int h) {
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
    final background = isRowHighlighted
        ? const Color(0xFFEAF4FF)
        : const Color(0xFFFCFDFE);
    final borderColor = isRowHighlighted
        ? const Color(0xFF93BEE8)
        : const Color(0xFFD6E3EE);
    return Container(
      width: 100,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
      ),
      child: Text(
        labelForHour(hour),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isRowHighlighted
              ? const Color(0xFF1E3A8A)
              : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _ScheduleCell extends StatelessWidget {
  const _ScheduleCell({
    required this.width,
    required this.slots,
    required this.statuses,
    required this.isRowHighlighted,
    required this.onTap,
  });

  final double width;
  final List<AvailabilitySlot> slots;
  final List<_WeeklySlotStatus> statuses;
  final bool isRowHighlighted;
  final VoidCallback onTap;

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
    Color base;
    if (top != null) {
      switch (top) {
        case _WeeklySlotStatus.pending:
          base = const Color(0xFFFFF7E6);
          break;
        case _WeeklySlotStatus.confirmed:
          base = const Color(0xFFE8FFF6);
          break;
        case _WeeklySlotStatus.cancelledByStudent:
          base = const Color(0xFFF1F5F9);
          break;
        case _WeeklySlotStatus.cancelledByCounselor:
          base = const Color(0xFFFFEEF0);
          break;
        case _WeeklySlotStatus.completed:
          base = const Color(0xFFEFF6FF);
          break;
        case _WeeklySlotStatus.noShow:
          base = const Color(0xFFFFE8EC);
          break;
      }
    } else if (slots.isEmpty) {
      base = Colors.white;
    } else {
      base = const Color(0xFFEFFFFC);
    }
    if (!isRowHighlighted) {
      return base;
    }
    return Color.alphaBlend(const Color(0x180EA5E9), base);
  }

  Color _borderColor() {
    if (isRowHighlighted) {
      return const Color(0xFF93BEE8);
    }
    return const Color(0xFFD6E3EE);
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
        border: Border.all(color: _borderColor()),
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
