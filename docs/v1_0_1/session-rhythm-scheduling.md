# Session Rhythm Scheduling - v1.0.1

## Summary

Counselor session rhythm now drives real scheduling behavior instead of only saving profile preferences. Availability windows are still stored in `counselor_availability`, but student-facing booking choices are generated from each counselor's session duration, break buffer, active appointments, and the shared 7:00 AM to 8:00 PM working day.

## Before

- Counselor profile saved `defaultSessionMinutes`, `breakBetweenSessionsMins`, `allowDirectBooking`, and `autoApproveFollowUps`.
- Availability creation accepted arbitrary start/end ranges.
- Student booking treated each availability slot as a directly bookable appointment.
- Breaks did not protect time between sessions.
- Direct booking did not affect appointment status.

## After

- Availability windows must stay inside 7:00 AM to 8:00 PM.
- Availability windows must fit at least one counselor session.
- Empty weekly-grid cells quick-add the counselor's default session duration, not a hardcoded one-hour slot.
- Student profile booking generates session-sized options inside availability windows.
- Pending and confirmed appointments block nearby generated options using the counselor break buffer.
- Booking creates `confirmed` appointments when direct booking is enabled.
- Booking creates `pending` appointments when direct booking is disabled, unless auto-approved follow-up logic applies.
- Rescheduling uses the same generated session options and break validation.

## Scheduling Rules

- Shared policy: `CounselorSchedulePolicy`
- Default working day: 7:00 AM to 8:00 PM
- Default session duration fallback: 50 minutes
- Default break fallback: 10 minutes
- Bookable session options are generated as:

```text
availability window - existing pending/confirmed appointments - break buffers
```

Example:

```text
Availability: 9:00 AM - 12:00 PM
Session: 50 min
Break: 10 min

Bookable:
9:00 AM - 9:50 AM
10:00 AM - 10:50 AM
11:00 AM - 11:50 AM
```

## Files Updated

- `lib/features/care/models/counselor_schedule_policy.dart`
- `lib/features/care/models/availability_slot.dart`
- `lib/features/care/models/counselor_profile.dart`
- `lib/features/care/data/care_repository.dart`
- `lib/features/care/presentation/counselor_availability_screen.dart`
- `lib/features/care/presentation/counselor_profile_screen.dart`
- `lib/features/care/presentation/counselor_directory_screen.dart`
- `lib/features/care/presentation/student_appointments_screen.dart`
- `lib/features/counselor/data/counselor_repository.dart`

## Validation

Ran:

```powershell
dart format lib/features/care/models/counselor_schedule_policy.dart lib/features/care/models/availability_slot.dart lib/features/care/models/counselor_profile.dart lib/features/care/data/care_repository.dart lib/features/care/presentation/counselor_profile_screen.dart lib/features/care/presentation/counselor_availability_screen.dart lib/features/care/presentation/counselor_directory_screen.dart lib/features/care/presentation/student_appointments_screen.dart lib/features/counselor/data/counselor_repository.dart
flutter analyze lib/features/care/models/counselor_schedule_policy.dart lib/features/care/models/availability_slot.dart lib/features/care/models/counselor_profile.dart lib/features/care/data/care_repository.dart lib/features/care/presentation/counselor_profile_screen.dart lib/features/care/presentation/counselor_availability_screen.dart lib/features/care/presentation/counselor_directory_screen.dart lib/features/care/presentation/student_appointments_screen.dart lib/features/counselor/data/counselor_repository.dart
```

Result: no analyzer issues.

## Future AI Improvements

- Suggest ideal availability windows based on historical booking demand.
- Warn counselors when a window produces too few bookable sessions.
- Recommend break lengths based on session load and counselor fatigue risk.
- Let students ask the AI assistant for "earliest available counselor this week" using generated session options.
