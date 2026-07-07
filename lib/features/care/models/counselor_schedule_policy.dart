import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';

class CounselorSchedulePolicy {
  const CounselorSchedulePolicy({
    this.dayStartMinutes = 7 * 60,
    this.dayEndMinutes = 20 * 60,
    this.sessionMinutes = 50,
    this.breakMinutes = 10,
    this.allowDirectBooking = true,
    this.autoApproveFollowUps = false,
    this.workingWeekdays = const <int>[1, 2, 3, 4, 5],
    this.lunchBreakEnabled = false,
    this.lunchBreakStartMinutes = 12 * 60 + 30,
    this.lunchBreakEndMinutes = 13 * 60,
  });

  final int dayStartMinutes;
  final int dayEndMinutes;
  final int sessionMinutes;
  final int breakMinutes;
  final bool allowDirectBooking;
  final bool autoApproveFollowUps;
  final List<int> workingWeekdays;
  final bool lunchBreakEnabled;
  final int lunchBreakStartMinutes;
  final int lunchBreakEndMinutes;

  factory CounselorSchedulePolicy.fromProfile(CounselorProfile profile) {
    final weekdays =
        profile.workingWeekdays
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList(growable: false)
          ..sort();
    return CounselorSchedulePolicy(
      sessionMinutes: _clampInt(profile.defaultSessionMinutes, 15, 120),
      breakMinutes: _clampInt(profile.breakBetweenSessionsMins, 0, 60),
      allowDirectBooking: profile.allowDirectBooking,
      autoApproveFollowUps: profile.autoApproveFollowUps,
      workingWeekdays: weekdays.isEmpty ? const <int>[1, 2, 3, 4, 5] : weekdays,
      dayStartMinutes: _clampInt(
        profile.workingDayStartMinutes,
        0,
        23 * 60 + 59,
      ),
      dayEndMinutes: _clampInt(profile.workingDayEndMinutes, 1, 24 * 60),
      lunchBreakEnabled: profile.lunchBreakEnabled,
      lunchBreakStartMinutes: _clampInt(
        profile.lunchBreakStartMinutes,
        0,
        24 * 60,
      ),
      lunchBreakEndMinutes: _clampInt(profile.lunchBreakEndMinutes, 0, 24 * 60),
    );
  }

  Duration get sessionDuration => Duration(minutes: sessionMinutes);
  Duration get breakDuration => Duration(minutes: breakMinutes);
  Duration get cadence => Duration(minutes: sessionMinutes + breakMinutes);

  bool worksOn(DateTime localDate) {
    return workingWeekdays.contains(localDate.weekday);
  }

  bool containsLocalRange(DateTime startLocal, DateTime endLocal) {
    if (!endLocal.isAfter(startLocal)) {
      return false;
    }
    if (startLocal.year != endLocal.year ||
        startLocal.month != endLocal.month ||
        startLocal.day != endLocal.day) {
      return false;
    }
    if (!worksOn(startLocal)) {
      return false;
    }
    final start = startLocal.hour * 60 + startLocal.minute;
    final end = endLocal.hour * 60 + endLocal.minute;
    return start >= dayStartMinutes && end <= dayEndMinutes && end > start;
  }

  DateTime dayStartFor(DateTime localDay) {
    return DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
      dayStartMinutes ~/ 60,
      dayStartMinutes % 60,
    );
  }

  DateTime dayEndFor(DateTime localDay) {
    return DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
      dayEndMinutes ~/ 60,
      dayEndMinutes % 60,
    );
  }

  List<_TimeRange> _breakRangesFor(DateTime localDay) {
    if (!lunchBreakEnabled) {
      return const <_TimeRange>[];
    }
    if (lunchBreakEndMinutes <= lunchBreakStartMinutes) {
      return const <_TimeRange>[];
    }
    final start = DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
      lunchBreakStartMinutes ~/ 60,
      lunchBreakStartMinutes % 60,
    );
    final end = DateTime(
      localDay.year,
      localDay.month,
      localDay.day,
      lunchBreakEndMinutes ~/ 60,
      lunchBreakEndMinutes % 60,
    );
    if (!end.isAfter(start)) {
      return const <_TimeRange>[];
    }
    return <_TimeRange>[_TimeRange(start: start, end: end)];
  }

  DateTime defaultEndFor(DateTime startLocal) {
    final sessionEnd = startLocal.add(sessionDuration);
    final dayEnd = dayEndFor(startLocal);
    return sessionEnd.isAfter(dayEnd) ? dayEnd : sessionEnd;
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

List<AvailabilitySlot> buildBookableSessionOptions({
  required List<AvailabilitySlot> availabilityWindows,
  List<AvailabilitySlot> blockedWindows = const <AvailabilitySlot>[],
  required List<AppointmentRecord> counselorAppointments,
  required CounselorSchedulePolicy policy,
  DateTime? nowUtc,
}) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final nowLocal = now.toLocal();
  final busyAppointments = counselorAppointments.where(_blocksScheduling);
  final blockedRanges = blockedWindows
      .where((slot) => slot.status == AvailabilitySlotStatus.blocked)
      .map(
        (slot) => _TimeRange(
          start: slot.startAt.toLocal(),
          end: slot.endAt.toLocal(),
        ),
      )
      .toList(growable: false);
  final options = <AvailabilitySlot>[];

  for (final window in availabilityWindows) {
    if (window.status != AvailabilitySlotStatus.available ||
        !window.endAt.isAfter(now)) {
      continue;
    }

    final windowStartLocal = window.startAt.toLocal();
    final windowEndLocal = window.endAt.toLocal();
    if (!policy.worksOn(windowStartLocal)) {
      continue;
    }
    final effectiveStart = _maxDateTime(
      windowStartLocal,
      policy.dayStartFor(windowStartLocal),
    );
    final effectiveEnd = _minDateTime(
      windowEndLocal,
      policy.dayEndFor(windowEndLocal),
    );
    if (!effectiveEnd.isAfter(effectiveStart)) {
      continue;
    }

    final exclusions = <_TimeRange>[
      ...policy._breakRangesFor(windowStartLocal),
      ...blockedRanges.where(
        (blocked) =>
            blocked.end.isAfter(effectiveStart) &&
            blocked.start.isBefore(effectiveEnd),
      ),
      ...busyAppointments
          .map(
            (appointment) => _TimeRange(
              start: appointment.startAt.toLocal().subtract(
                policy.breakDuration,
              ),
              end: appointment.endAt.toLocal().add(policy.breakDuration),
            ),
          )
          .where(
            (range) =>
                range.end.isAfter(effectiveStart) &&
                range.start.isBefore(effectiveEnd),
          ),
    ];

    final candidateRanges = _subtractRanges(<_TimeRange>[
      _TimeRange(start: effectiveStart, end: effectiveEnd),
    ], exclusions);

    for (final range in candidateRanges) {
      var cursor = _roundUpToFiveMinutes(_maxDateTime(range.start, nowLocal));
      while (cursor.add(policy.sessionDuration).isBefore(range.end) ||
          cursor.add(policy.sessionDuration).isAtSameMomentAs(range.end)) {
        final sessionEnd = cursor.add(policy.sessionDuration);
        final optionStartUtc = cursor.toUtc();
        final optionEndUtc = sessionEnd.toUtc();
        options.add(
          AvailabilitySlot.generated(
            source: window,
            startAt: optionStartUtc,
            endAt: optionEndUtc,
          ),
        );
        cursor = cursor.add(policy.cadence);
      }
    }
  }

  options.sort((a, b) => a.startAt.compareTo(b.startAt));
  return options;
}

bool _blocksScheduling(AppointmentRecord appointment) {
  return appointment.status == AppointmentStatus.pending ||
      appointment.status == AppointmentStatus.confirmed;
}

DateTime _minDateTime(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime _maxDateTime(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

List<_TimeRange> _subtractRanges(
  List<_TimeRange> ranges,
  List<_TimeRange> exclusions,
) {
  var current = ranges;
  for (final exclusion in exclusions) {
    final next = <_TimeRange>[];
    for (final range in current) {
      next.addAll(_subtractRange(range, exclusion));
    }
    current = next;
  }
  return current
      .where((range) => range.end.isAfter(range.start))
      .toList(growable: false);
}

List<_TimeRange> _subtractRange(_TimeRange range, _TimeRange exclusion) {
  if (!range.overlaps(exclusion)) {
    return <_TimeRange>[range];
  }
  final result = <_TimeRange>[];
  if (exclusion.start.isAfter(range.start)) {
    result.add(_TimeRange(start: range.start, end: exclusion.start));
  }
  if (exclusion.end.isBefore(range.end)) {
    result.add(_TimeRange(start: exclusion.end, end: range.end));
  }
  return result;
}

DateTime _roundUpToFiveMinutes(DateTime value) {
  final minute = value.minute;
  final remainder = minute % 5;
  if (remainder == 0 && value.second == 0 && value.millisecond == 0) {
    return DateTime(value.year, value.month, value.day, value.hour, minute);
  }
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    minute + (5 - remainder),
  );
}

class _TimeRange {
  const _TimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool overlaps(_TimeRange other) {
    return start.isBefore(other.end) && end.isAfter(other.start);
  }
}
