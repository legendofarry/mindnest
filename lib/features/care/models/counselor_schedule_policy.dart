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
  });

  final int dayStartMinutes;
  final int dayEndMinutes;
  final int sessionMinutes;
  final int breakMinutes;
  final bool allowDirectBooking;
  final bool autoApproveFollowUps;

  factory CounselorSchedulePolicy.fromProfile(CounselorProfile profile) {
    return CounselorSchedulePolicy(
      sessionMinutes: _clampInt(profile.defaultSessionMinutes, 15, 120),
      breakMinutes: _clampInt(profile.breakBetweenSessionsMins, 0, 60),
      allowDirectBooking: profile.allowDirectBooking,
      autoApproveFollowUps: profile.autoApproveFollowUps,
    );
  }

  Duration get sessionDuration => Duration(minutes: sessionMinutes);
  Duration get breakDuration => Duration(minutes: breakMinutes);
  Duration get cadence => Duration(minutes: sessionMinutes + breakMinutes);

  bool containsLocalRange(DateTime startLocal, DateTime endLocal) {
    final start = startLocal.hour * 60 + startLocal.minute;
    final end = endLocal.hour * 60 + endLocal.minute;
    return start >= dayStartMinutes &&
        end <= dayEndMinutes &&
        endLocal.isAfter(startLocal);
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
  required List<AppointmentRecord> counselorAppointments,
  required CounselorSchedulePolicy policy,
  DateTime? nowUtc,
}) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final busyAppointments = counselorAppointments.where(_blocksScheduling);
  final options = <AvailabilitySlot>[];

  for (final window in availabilityWindows) {
    if (window.status != AvailabilitySlotStatus.available ||
        !window.endAt.isAfter(now)) {
      continue;
    }

    final windowStartLocal = window.startAt.toLocal();
    final windowEndLocal = window.endAt.toLocal();
    final effectiveStart = _maxDateTime(
      windowStartLocal,
      policy.dayStartFor(windowStartLocal),
    );
    final effectiveEnd = _minDateTime(
      windowEndLocal,
      policy.dayEndFor(windowEndLocal),
    );
    var cursor = _roundUpToFiveMinutes(
      _maxDateTime(effectiveStart, now.toLocal()),
    );

    while (cursor.add(policy.sessionDuration).isBefore(effectiveEnd) ||
        cursor.add(policy.sessionDuration).isAtSameMomentAs(effectiveEnd)) {
      final sessionEnd = cursor.add(policy.sessionDuration);
      final optionStartUtc = cursor.toUtc();
      final optionEndUtc = sessionEnd.toUtc();
      final blocked = busyAppointments.any((appointment) {
        final blockStart = appointment.startAt.toUtc().subtract(
          policy.breakDuration,
        );
        final blockEnd = appointment.endAt.toUtc().add(policy.breakDuration);
        return blockStart.isBefore(optionEndUtc) &&
            blockEnd.isAfter(optionStartUtc);
      });

      if (!blocked) {
        options.add(
          AvailabilitySlot.generated(
            source: window,
            startAt: optionStartUtc,
            endAt: optionEndUtc,
          ),
        );
      }
      cursor = cursor.add(policy.cadence);
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
