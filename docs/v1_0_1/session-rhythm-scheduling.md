# Session Rhythm Scheduling - v1.0.1

## Summary

Counselor session rhythm now drives real scheduling behavior instead of only saving profile preferences. Availability windows and temporary blocked windows are still stored in `counselor_availability`, but student-facing booking choices are generated from each counselor's working days, working hours, session duration, break buffer, lunch break, active appointments, and blocked overrides.

## Before

- Counselor profile saved `defaultSessionMinutes`, `breakBetweenSessionsMins`, `allowDirectBooking`, and `autoApproveFollowUps`.
- Availability creation accepted arbitrary start/end ranges.
- Student booking treated each availability slot as a directly bookable appointment.
- Breaks did not protect time between sessions.
- Weekly grid cells did not reflect counselor defaults, lunch breaks, or closed days.
- Counselors had no quick way to fill a default day/week or block a day/week.
- Direct booking did not affect appointment status.

## After

- Counselor profile settings now save working weekdays, daily working hours, optional lunch break, session duration, between-session break, direct booking, and follow-up approval preferences.
- Availability windows must stay inside the counselor's own working days and working hours.
- Availability windows must fit at least one counselor session.
- Empty weekly-grid cells quick-add the counselor's default session duration and refuse cells outside the saved rhythm.
- The counselor weekly grid visually disables closed days, closed hours, past empty cells, and lunch-break cells.
- Quick schedule tools can fill the selected day, fill the visible week, block the selected day, or block the visible week.
- Blocked windows act as temporary overrides and can be removed from the grid/feed/table while booked slots remain protected.
- Student profile booking generates session-sized options inside availability windows.
- Student profile booking, student rescheduling, and counselor directory sorting subtract blocked windows and lunch breaks from generated options.
- Pending and confirmed appointments block nearby generated options using the counselor break buffer.
- Booking creates `confirmed` appointments when direct booking is enabled.
- Booking creates `pending` appointments when direct booking is disabled, unless auto-approved follow-up logic applies.
- Rescheduling uses the same generated session options and break validation.

## Scheduling Rules

- Shared policy: `CounselorSchedulePolicy`
- Default working weekdays fallback: Monday to Friday
- Default working day fallback: 7:00 AM to 8:00 PM
- Default session duration fallback: 50 minutes
- Default break fallback: 10 minutes
- Lunch break fallback: disabled, with 12:30 PM to 1:00 PM stored as the default range if enabled later
- Bookable session options are generated as:

```text
availability window - lunch break - blocked windows - existing pending/confirmed appointments - break buffers
```

Example:

```text
Availability: 9:00 AM - 12:00 PM
Session: 50 min
Break: 10 min
Lunch: disabled

Bookable:
9:00 AM - 9:50 AM
10:00 AM - 10:50 AM
11:00 AM - 11:50 AM
```

Example with lunch and a temporary block:

```text
Availability: 9:00 AM - 5:00 PM
Session: 70 min
Break: 30 min
Lunch: 12:30 PM - 1:00 PM
Blocked override: 3:00 PM - 5:00 PM

Bookable:
9:00 AM - 10:10 AM
10:40 AM - 11:50 AM
1:00 PM - 2:10 PM
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
- `lib/features/counselor/presentation/counselor_profile_settings_screen.dart`

## Validation

Ran:

```powershell
dart format lib/features/care/data/care_repository.dart lib/features/care/presentation/counselor_availability_screen.dart lib/features/care/presentation/counselor_directory_screen.dart lib/features/care/presentation/counselor_profile_screen.dart lib/features/care/presentation/student_appointments_screen.dart lib/features/counselor/presentation/counselor_profile_settings_screen.dart lib/features/counselor/data/counselor_repository.dart lib/features/care/models/counselor_schedule_policy.dart lib/features/care/models/availability_slot.dart lib/features/care/models/counselor_profile.dart
dart analyze lib/features/care/data/care_repository.dart
dart analyze lib/features/care/presentation/counselor_availability_screen.dart
dart analyze lib/features/care/presentation/counselor_directory_screen.dart
dart analyze lib/features/care/presentation/counselor_profile_screen.dart
dart analyze lib/features/care/presentation/student_appointments_screen.dart
dart analyze lib/features/counselor/presentation/counselor_profile_settings_screen.dart
dart analyze lib/features/counselor/data/counselor_repository.dart lib/features/care/models/counselor_schedule_policy.dart lib/features/care/models/availability_slot.dart lib/features/care/models/counselor_profile.dart
```

Result: no analyzer issues.

Note: the wider `flutter analyze` command over the full touched set timed out twice in this workspace before returning diagnostics, so validation used narrower `dart analyze` checks per touched file.

## Future AI Improvements

- Suggest ideal availability windows based on historical booking demand.
- Warn counselors when a window produces too few bookable sessions.
- Recommend break lengths based on session load and counselor fatigue risk.
- Let students ask the AI assistant for "earliest available counselor this week" using generated session options.
