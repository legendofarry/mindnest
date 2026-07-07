import 'package:mindnest/features/counselor/models/counselor_language_catalog.dart';

class CounselorProfile {
  const CounselorProfile({
    required this.id,
    required this.institutionId,
    required this.displayName,
    required this.title,
    required this.specialization,
    this.gender,
    required this.sessionMode,
    required this.timezone,
    required this.bio,
    required this.yearsExperience,
    required this.languages,
    required this.ratingAverage,
    required this.ratingCount,
    required this.isActive,
    this.defaultSessionMinutes = 50,
    this.breakBetweenSessionsMins = 10,
    this.allowDirectBooking = true,
    this.autoApproveFollowUps = false,
    this.workingWeekdays = const <int>[1, 2, 3, 4, 5],
    this.workingDayStartMinutes = 7 * 60,
    this.workingDayEndMinutes = 20 * 60,
    this.lunchBreakEnabled = false,
    this.lunchBreakStartMinutes = 12 * 60 + 30,
    this.lunchBreakEndMinutes = 13 * 60,
  });

  final String id;
  final String institutionId;
  final String displayName;
  final String title;
  final String specialization;
  final String? gender;
  final String sessionMode;
  final String timezone;
  final String bio;
  final int yearsExperience;
  final List<String> languages;
  final double ratingAverage;
  final int ratingCount;
  final bool isActive;
  final int defaultSessionMinutes;
  final int breakBetweenSessionsMins;
  final bool allowDirectBooking;
  final bool autoApproveFollowUps;
  final List<int> workingWeekdays;
  final int workingDayStartMinutes;
  final int workingDayEndMinutes;
  final bool lunchBreakEnabled;
  final int lunchBreakStartMinutes;
  final int lunchBreakEndMinutes;

  factory CounselorProfile.fromMap(String id, Map<String, dynamic> data) {
    final languagesRaw = data['languages'];
    final languages = switch (languagesRaw) {
      final List<dynamic> values => normalizeCounselorLanguages(values),
      final String value => normalizeCounselorLanguages(value.split(',')),
      _ => const <String>[],
    };

    final ratingRaw = data['ratingAverage'];
    final ratingAverage = ratingRaw is num ? ratingRaw.toDouble() : 0.0;

    final ratingCountRaw = data['ratingCount'];
    final ratingCount = ratingCountRaw is num ? ratingCountRaw.toInt() : 0;

    final rawWorkingWeekdays = data['workingWeekdays'];
    final workingWeekdays = <int>[];
    if (rawWorkingWeekdays is List) {
      for (final value in rawWorkingWeekdays) {
        final parsed = value is num
            ? value.toInt()
            : int.tryParse(value.toString().trim());
        if (parsed != null &&
            parsed >= DateTime.monday &&
            parsed <= DateTime.sunday) {
          workingWeekdays.add(parsed);
        }
      }
    }
    if (workingWeekdays.isEmpty) {
      workingWeekdays.addAll(<int>[1, 2, 3, 4, 5]);
    }

    final workingDayStartMinutes =
        (data['workingDayStartMinutes'] as num?)?.toInt() ?? 7 * 60;
    final workingDayEndMinutes =
        (data['workingDayEndMinutes'] as num?)?.toInt() ?? 20 * 60;
    final lunchBreakEnabled = (data['lunchBreakEnabled'] as bool?) ?? false;
    final lunchBreakStartMinutes =
        (data['lunchBreakStartMinutes'] as num?)?.toInt() ?? (12 * 60 + 30);
    final lunchBreakEndMinutes =
        (data['lunchBreakEndMinutes'] as num?)?.toInt() ?? 13 * 60;

    return CounselorProfile(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Counselor',
      title: (data['title'] as String?) ?? 'Counselor',
      specialization: (data['specialization'] as String?) ?? 'General',
      gender: (data['gender'] as String?)?.trim().isEmpty == true
          ? null
          : (data['gender'] as String?)?.trim(),
      sessionMode: (data['sessionMode'] as String?) ?? '--',
      timezone: (data['timezone'] as String?) ?? 'UTC',
      bio: (data['bio'] as String?) ?? '',
      yearsExperience: (data['yearsExperience'] as num?)?.toInt() ?? 0,
      languages: languages,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      isActive: (data['isActive'] as bool?) ?? true,
      defaultSessionMinutes:
          (data['defaultSessionMinutes'] as num?)?.toInt() ?? 50,
      breakBetweenSessionsMins:
          (data['breakBetweenSessionsMins'] as num?)?.toInt() ?? 10,
      allowDirectBooking: (data['allowDirectBooking'] as bool?) ?? true,
      autoApproveFollowUps: (data['autoApproveFollowUps'] as bool?) ?? false,
      workingWeekdays: workingWeekdays,
      workingDayStartMinutes: workingDayStartMinutes,
      workingDayEndMinutes: workingDayEndMinutes,
      lunchBreakEnabled: lunchBreakEnabled,
      lunchBreakStartMinutes: lunchBreakStartMinutes,
      lunchBreakEndMinutes: lunchBreakEndMinutes,
    );
  }
}
