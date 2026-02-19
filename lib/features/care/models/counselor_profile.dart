class CounselorProfile {
  const CounselorProfile({
    required this.id,
    required this.institutionId,
    required this.displayName,
    required this.title,
    required this.specialization,
    required this.sessionMode,
    required this.timezone,
    required this.bio,
    required this.yearsExperience,
    required this.languages,
    required this.ratingAverage,
    required this.ratingCount,
    required this.isActive,
  });

  final String id;
  final String institutionId;
  final String displayName;
  final String title;
  final String specialization;
  final String sessionMode;
  final String timezone;
  final String bio;
  final int yearsExperience;
  final List<String> languages;
  final double ratingAverage;
  final int ratingCount;
  final bool isActive;

  factory CounselorProfile.fromMap(String id, Map<String, dynamic> data) {
    final languagesRaw = data['languages'];
    final languages = <String>[];
    if (languagesRaw is List) {
      for (final item in languagesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          languages.add(item.trim());
        }
      }
    }

    final ratingRaw = data['ratingAverage'];
    final ratingAverage = ratingRaw is num ? ratingRaw.toDouble() : 0.0;

    final ratingCountRaw = data['ratingCount'];
    final ratingCount = ratingCountRaw is num ? ratingCountRaw.toInt() : 0;

    return CounselorProfile(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Counselor',
      title: (data['title'] as String?) ?? 'Counselor',
      specialization: (data['specialization'] as String?) ?? 'General',
      sessionMode: (data['sessionMode'] as String?) ?? '--',
      timezone: (data['timezone'] as String?) ?? 'UTC',
      bio: (data['bio'] as String?) ?? '',
      yearsExperience: (data['yearsExperience'] as num?)?.toInt() ?? 0,
      languages: languages,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }
}
